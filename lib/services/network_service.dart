import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/peer.dart';
import '../models/message.dart';
import '../models/chat_room.dart';

const int udpPort = 41234;
const int tcpPort = 41235;
const Duration broadcastInterval = Duration(seconds: 2);
const Duration peerTimeout = Duration(seconds: 12);
const Duration scanTimeout = Duration(milliseconds: 500);

class NetworkService {
  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  final Map<String, Socket> _tcpConnections = {};
  final Map<String, DateTime> _lastSeen = {};
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  Timer? _scanTimer;

  String? _myId;
  String? _myName;
  DateTime? _myJoinedAt;
  String? _myAddress;

  final Map<String, Peer> _peers = {};
  final List<ChatRoom> _rooms = [];
  String? _hostId;

  Function(List<Peer>)? onPeersChanged;
  Function(List<ChatRoom>)? onRoomsChanged;
  Function(Message)? onMessageReceived;
  Function(String?)? onHostChanged;
  Function(String)? onLog;

  String? get hostId => _hostId;
  bool get isHost => _hostId == _myId;

  void _log(String msg) {
    onLog?.call('[Network] $msg');
  }

  Future<void> start(String myId, String myName) async {
    _myId = myId;
    _myName = myName;
    _myJoinedAt = DateTime.now();
    _myAddress = await _getLocalAddress();
    _log('My address: $_myAddress');

    _peers[myId] = Peer(
      id: myId,
      name: myName,
      address: _myAddress ?? '',
      port: tcpPort,
      joinedAt: _myJoinedAt!,
    );

    await _startTcpServer();
    await _startUdpDiscovery();
    _startCleanupTimer();
    _startPeriodicScan();
    _electHost();
  }

  Future<String?> _getLocalAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (iface.name.contains('lo')) continue;
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      _log('Error getting local address: $e');
    }
    return null;
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _scanTimer?.cancel();
    _udpSocket?.close();
    _udpSocket = null;
    await _tcpServer?.close();
    _tcpServer = null;
    for (final socket in _tcpConnections.values) {
      try { socket.destroy(); } catch (_) {}
    }
    _tcpConnections.clear();
    _peers.clear();
    _rooms.clear();
  }

  // --- UDP Discovery ---

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) _handleUdpMessage(datagram);
        }
      });

      _broadcastTimer = Timer.periodic(broadcastInterval, (_) => _sendDiscovery());
      _sendDiscovery();
      _log('UDP discovery started on port $udpPort');
    } catch (e) {
      _log('UDP bind failed: $e - will rely on TCP scan');
    }
  }

  void _sendDiscovery() {
    if (_myId == null || _myName == null || _udpSocket == null) return;
    final data = jsonEncode({
      'type': 'discovery',
      'peerId': _myId,
      'peerName': _myName,
      'tcpPort': tcpPort,
      'joinedAt': _myJoinedAt?.toIso8601String(),
    });
    final bytes = utf8.encode(data);

    // 서브넷 브로드캐스트
    if (_myAddress != null) {
      final parts = _myAddress!.split('.');
      if (parts.length == 4) {
        final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
        try {
          _udpSocket!.send(bytes, InternetAddress(subnetBroadcast), udpPort);
        } catch (_) {}
      }
    }

    // 글로벌 브로드캐스트
    try {
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), udpPort);
    } catch (_) {}
  }

  void _handleUdpMessage(Datagram datagram) {
    try {
      final data = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (data['type'] != 'discovery') return;

      final peerId = data['peerId'] as String;
      if (peerId == _myId) return;

      final peerAddress = datagram.address.address;
      _log('UDP discovered: ${data['peerName']} at $peerAddress');

      final peer = Peer(
        id: peerId,
        name: data['peerName'] as String,
        address: peerAddress,
        port: data['tcpPort'] as int? ?? tcpPort,
        joinedAt: DateTime.parse(data['joinedAt'] as String),
      );

      _lastSeen[peerId] = DateTime.now();
      final isNew = !_peers.containsKey(peerId) || !_peers[peerId]!.isOnline;
      _peers[peerId] = peer;

      if (isNew) {
        onPeersChanged?.call(_peers.values.toList());
        _connectToPeer(peer);
        _electHost();
      }
    } catch (e) {
      _log('UDP parse error: $e');
    }
  }

  // --- TCP Server ---

  Future<void> _startTcpServer() async {
    try {
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort, shared: true);
      _tcpServer!.listen(_handleIncomingConnection);
      _log('TCP server started on port $tcpPort');
    } catch (e) {
      _log('TCP server bind failed: $e');
    }
  }

  void _handleIncomingConnection(Socket socket) {
    _log('TCP incoming from ${socket.remoteAddress.address}');
    _setupSocketListener(socket);
  }

  void _setupSocketListener(Socket socket) {
    String buffer = '';
    socket.listen(
      (data) {
        buffer += utf8.decode(data);
        while (buffer.contains('\n')) {
          final idx = buffer.indexOf('\n');
          final line = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 1);
          if (line.isNotEmpty) _handleTcpMessage(line, socket);
        }
      },
      onDone: () => _handleDisconnect(socket),
      onError: (_) => _handleDisconnect(socket),
    );
  }

  void _handleDisconnect(Socket socket) {
    String? disconnectedId;
    _tcpConnections.forEach((id, s) {
      if (s == socket) disconnectedId = id;
    });

    if (disconnectedId != null) {
      _tcpConnections.remove(disconnectedId);
      final peer = _peers[disconnectedId];
      if (peer != null) {
        peer.isOnline = false;
        _rooms.removeWhere((r) => r.creatorId == disconnectedId);
        _log('Peer disconnected: ${peer.name}');
      }
      onPeersChanged?.call(_peers.values.toList());
      onRoomsChanged?.call(List.from(_rooms));
      _electHost();
    }

    try { socket.destroy(); } catch (_) {}
  }

  // --- TCP Connect to Peer ---

  Future<bool> _connectToPeer(Peer peer) async {
    if (_tcpConnections.containsKey(peer.id)) return true;
    try {
      final socket = await Socket.connect(
        peer.address,
        peer.port,
        timeout: const Duration(seconds: 3),
      );
      _tcpConnections[peer.id] = socket;
      _setupSocketListener(socket);
      _log('TCP connected to ${peer.name} at ${peer.address}');

      _sendTcp(socket, {
        'type': 'join',
        'peerId': _myId,
        'peerName': _myName,
        'joinedAt': _myJoinedAt?.toIso8601String(),
        'address': _myAddress,
      });

      return true;
    } catch (e) {
      _log('TCP connect failed to ${peer.address}: $e');
      return false;
    }
  }

  // --- Subnet TCP Scan ---

  void _startPeriodicScan() {
    scanSubnet();
    _scanTimer = Timer.periodic(const Duration(seconds: 10), (_) => scanSubnet());
  }

  Future<void> scanSubnet() async {
    if (_myAddress == null) {
      _myAddress = await _getLocalAddress();
      if (_myAddress == null) return;
    }

    final parts = _myAddress!.split('.');
    if (parts.length != 4) return;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
    final myLastOctet = int.tryParse(parts[3]) ?? 0;

    _log('Scanning subnet $subnet.0/24...');

    final futures = <Future>[];
    for (int i = 1; i < 255; i++) {
      if (i == myLastOctet) continue;
      final ip = '$subnet.$i';
      final alreadyConnected = _peers.values.any((p) => p.address == ip && p.isOnline);
      if (alreadyConnected) continue;
      futures.add(_tryConnect(ip));
    }

    await Future.wait(futures);
    _log('Scan complete. Peers: ${_peers.values.where((p) => p.isOnline).length}');
  }

  Future<void> _tryConnect(String ip) async {
    try {
      final socket = await Socket.connect(ip, tcpPort, timeout: scanTimeout);
      _log('Scan found device at $ip');
      _setupSocketListener(socket);

      _sendTcp(socket, {
        'type': 'join',
        'peerId': _myId,
        'peerName': _myName,
        'joinedAt': _myJoinedAt?.toIso8601String(),
        'address': _myAddress,
      });

      // 상대가 join 응답을 보내면 거기서 등록됨
    } catch (_) {
      // 연결 안됨 - 정상 (PlaneChat 앱이 없는 기기)
    }
  }

  // --- TCP Message Handler ---

  void _handleTcpMessage(String raw, Socket socket) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'join':
          final peerId = data['peerId'] as String;
          final peerName = data['peerName'] as String;
          final joinedAt = DateTime.parse(data['joinedAt'] as String);
          String addr;
          try { addr = socket.remoteAddress.address; } catch (_) { addr = data['address'] ?? ''; }

          _peers[peerId] = Peer(
            id: peerId, name: peerName, address: addr,
            port: tcpPort, joinedAt: joinedAt,
          );
          _tcpConnections[peerId] = socket;
          _lastSeen[peerId] = DateTime.now();
          _log('Peer joined: $peerName ($addr)');

          onPeersChanged?.call(_peers.values.toList());
          _electHost();

          // 응답으로 내 정보 전송
          _sendTcp(socket, {
            'type': 'join_ack',
            'peerId': _myId,
            'peerName': _myName,
            'joinedAt': _myJoinedAt?.toIso8601String(),
            'address': _myAddress,
          });

          if (isHost) {
            Future.delayed(const Duration(milliseconds: 200), () {
              _broadcastPeerList();
              _broadcastRoomList();
            });
          }
          break;

        case 'join_ack':
          final peerId = data['peerId'] as String;
          final peerName = data['peerName'] as String;
          final joinedAt = DateTime.parse(data['joinedAt'] as String);
          String addr;
          try { addr = socket.remoteAddress.address; } catch (_) { addr = data['address'] ?? ''; }

          _peers[peerId] = Peer(
            id: peerId, name: peerName, address: addr,
            port: tcpPort, joinedAt: joinedAt,
          );
          _tcpConnections[peerId] = socket;
          _lastSeen[peerId] = DateTime.now();
          _log('Peer ack: $peerName ($addr)');

          onPeersChanged?.call(_peers.values.toList());
          _electHost();

          if (isHost) {
            Future.delayed(const Duration(milliseconds: 200), () {
              _broadcastPeerList();
              _broadcastRoomList();
            });
          }
          break;

        case 'peer_list':
          final list = (data['peers'] as List).map((e) => Peer.fromJson(e as Map<String, dynamic>)).toList();
          for (final p in list) {
            if (p.id != _myId) {
              _peers[p.id] = p;
              _lastSeen[p.id] = DateTime.now();
            }
          }
          onPeersChanged?.call(_peers.values.toList());
          break;

        case 'room_list':
          _rooms.clear();
          _rooms.addAll((data['rooms'] as List).map((e) => ChatRoom.fromJson(e as Map<String, dynamic>)));
          onRoomsChanged?.call(List.from(_rooms));
          break;

        case 'create_room':
          final room = ChatRoom.fromJson(data['room'] as Map<String, dynamic>);
          if (!_rooms.any((r) => r.id == room.id)) {
            _rooms.add(room);
            onRoomsChanged?.call(List.from(_rooms));
            if (isHost) _broadcastRoomList();
          }
          break;

        case 'join_room':
          final roomId = data['roomId'] as String;
          final peerId = data['peerId'] as String;
          final room = _rooms.where((r) => r.id == roomId).firstOrNull;
          if (room != null && !room.participantIds.contains(peerId)) {
            room.participantIds.add(peerId);
            onRoomsChanged?.call(List.from(_rooms));
            if (isHost) _broadcastRoomList();
          }
          break;

        case 'leave_room':
          final roomId = data['roomId'] as String;
          final peerId = data['peerId'] as String;
          final room = _rooms.where((r) => r.id == roomId).firstOrNull;
          if (room != null) {
            room.participantIds.remove(peerId);
            onRoomsChanged?.call(List.from(_rooms));
            if (isHost) _broadcastRoomList();
          }
          break;

        case 'chat_message':
          final msg = Message.fromJson(data['message'] as Map<String, dynamic>);
          onMessageReceived?.call(msg);
          if (isHost) {
            _broadcastToRoom(data['roomId'] as String, raw, excludeId: msg.senderId);
          }
          break;

        case 'host_election':
          _hostId = data['newHostId'] as String?;
          onHostChanged?.call(_hostId);
          break;
      }
    } catch (e) {
      _log('TCP message error: $e');
    }
  }

  // --- Host Election ---

  void _electHost() {
    final onlinePeers = _peers.values.where((p) => p.isOnline).toList();
    if (onlinePeers.isEmpty) return;
    onlinePeers.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    final newHost = onlinePeers.first.id;
    if (newHost != _hostId) {
      _hostId = newHost;
      onHostChanged?.call(_hostId);
      if (isHost) {
        _broadcastMessage({'type': 'host_election', 'newHostId': _hostId});
        _broadcastPeerList();
        _broadcastRoomList();
      }
    }
  }

  // --- Cleanup Timer ---

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(peerTimeout, (_) {
      bool changed = false;
      final now = DateTime.now();
      for (final entry in _peers.entries) {
        if (entry.key == _myId) continue;
        final lastSeen = _lastSeen[entry.key];
        final hasConnection = _tcpConnections.containsKey(entry.key);
        if (!hasConnection && entry.value.isOnline) {
          if (lastSeen == null || now.difference(lastSeen) > peerTimeout) {
            entry.value.isOnline = false;
            _rooms.removeWhere((r) => r.creatorId == entry.key);
            changed = true;
          }
        }
      }
      if (changed) {
        onPeersChanged?.call(_peers.values.toList());
        onRoomsChanged?.call(List.from(_rooms));
        _electHost();
      }
    });
  }

  // --- Public API ---

  void createRoom(ChatRoom room) {
    if (!_rooms.any((r) => r.id == room.id)) {
      _rooms.add(room);
    }
    onRoomsChanged?.call(List.from(_rooms));
    _broadcastMessage({'type': 'create_room', 'room': room.toJson()});
  }

  void joinRoom(String roomId) {
    final room = _rooms.where((r) => r.id == roomId).firstOrNull;
    if (room != null && !room.participantIds.contains(_myId)) {
      room.participantIds.add(_myId!);
      onRoomsChanged?.call(List.from(_rooms));
    }
    _broadcastMessage({'type': 'join_room', 'roomId': roomId, 'peerId': _myId, 'peerName': _myName});
  }

  void leaveRoom(String roomId) {
    final room = _rooms.where((r) => r.id == roomId).firstOrNull;
    if (room != null) {
      room.participantIds.remove(_myId);
      onRoomsChanged?.call(List.from(_rooms));
    }
    _broadcastMessage({'type': 'leave_room', 'roomId': roomId, 'peerId': _myId});
  }

  void sendMessage(Message message) {
    final data = {'type': 'chat_message', 'roomId': message.roomId, 'message': message.toJson()};
    if (isHost) {
      _broadcastToRoom(message.roomId, jsonEncode(data), excludeId: _myId);
    } else {
      _broadcastMessage(data);
    }
  }

  // --- Internal Broadcast ---

  void _broadcastPeerList() {
    final data = {'type': 'peer_list', 'peers': _peers.values.map((p) => p.toJson()).toList()};
    _broadcastMessage(data);
  }

  void _broadcastRoomList() {
    final data = {'type': 'room_list', 'rooms': _rooms.map((r) => r.toJson()).toList()};
    _broadcastMessage(data);
  }

  void _broadcastMessage(Map<String, dynamic> data) {
    final raw = '${jsonEncode(data)}\n';
    for (final entry in _tcpConnections.entries) {
      if (entry.key == _myId) continue;
      try {
        entry.value.write(raw);
      } catch (_) {}
    }
  }

  void _broadcastToRoom(String roomId, String raw, {String? excludeId}) {
    final room = _rooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null) return;
    final line = raw.endsWith('\n') ? raw : '$raw\n';
    for (final pid in room.participantIds) {
      if (pid == excludeId || pid == _myId) continue;
      final socket = _tcpConnections[pid];
      if (socket != null) {
        try { socket.write(line); } catch (_) {}
      }
    }
  }

  void _sendTcp(Socket socket, Map<String, dynamic> data) {
    try {
      socket.write('${jsonEncode(data)}\n');
    } catch (_) {}
  }
}
