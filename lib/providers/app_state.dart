import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/peer.dart';
import '../models/message.dart';
import '../models/chat_room.dart';
import '../services/network_service.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  final NetworkService _network = NetworkService();
  final StorageService _storage = StorageService();
  final Uuid _uuid = const Uuid();

  String? _userId;
  String? _currentUserName;
  List<Peer> _peers = [];
  List<ChatRoom> _rooms = [];
  final Map<String, List<Message>> _messages = {};
  String? _hostId;
  bool _scanning = false;
  final List<String> _logs = [];

  String? get userId => _userId;
  String? get currentUserName => _currentUserName;
  List<Peer> get peers => _peers;
  List<ChatRoom> get rooms => _rooms;
  String? get hostId => _hostId;
  bool get isHost => _hostId == _userId;
  bool get scanning => _scanning;
  List<String> get logs => _logs;

  List<Message> getMessages(String roomId) => _messages[roomId] ?? [];

  AppState() {
    _init();
  }

  Future<void> _init() async {
    await _storage.init();
    _currentUserName = _storage.getSavedName();
    _userId = _storage.getSavedUserId();
    if (_userId == null) {
      _userId = _uuid.v4();
      await _storage.saveUserId(_userId!);
    }

    _network.onPeersChanged = (peers) {
      _peers = peers;
      notifyListeners();
    };
    _network.onRoomsChanged = (rooms) {
      _rooms = rooms;
      notifyListeners();
    };
    _network.onMessageReceived = (msg) {
      _messages.putIfAbsent(msg.roomId, () => []);
      _messages[msg.roomId]!.add(msg);
      _storage.appendMessage(msg.roomId, msg);
      notifyListeners();
    };
    _network.onHostChanged = (hostId) {
      _hostId = hostId;
      notifyListeners();
    };
    _network.onLog = (msg) {
      _logs.add(msg);
      if (_logs.length > 100) _logs.removeAt(0);
      notifyListeners();
    };

    if (_currentUserName != null) {
      await _startNetwork();
    }
    notifyListeners();
  }

  Future<void> setName(String name) async {
    _currentUserName = name;
    await _storage.saveName(name);
    await _startNetwork();
    notifyListeners();
  }

  Future<void> _startNetwork() async {
    if (_userId != null && _currentUserName != null) {
      await _network.start(_userId!, _currentUserName!);
    }
  }

  Future<void> scan() async {
    _scanning = true;
    notifyListeners();
    await _network.scanSubnet();
    _scanning = false;
    notifyListeners();
  }

  void createRoom(String name) {
    final room = ChatRoom(
      id: _uuid.v4(),
      name: name,
      creatorId: _userId!,
      creatorName: _currentUserName!,
      createdAt: DateTime.now(),
      participantIds: [_userId!],
    );
    _rooms.add(room);
    _network.createRoom(room);
    notifyListeners();
  }

  void joinRoom(String roomId) {
    _network.joinRoom(roomId);
    final saved = _storage.getMessages(roomId);
    _messages[roomId] = saved;
    notifyListeners();
  }

  void leaveRoom(String roomId) {
    _network.leaveRoom(roomId);
    notifyListeners();
  }

  void sendMessage(String roomId, String content) {
    final msg = Message(
      id: _uuid.v4(),
      senderName: _currentUserName!,
      senderId: _userId!,
      content: content,
      timestamp: DateTime.now(),
      roomId: roomId,
    );
    _messages.putIfAbsent(roomId, () => []);
    _messages[roomId]!.add(msg);
    _storage.appendMessage(roomId, msg);
    _network.sendMessage(msg);
    notifyListeners();
  }

  @override
  void dispose() {
    _network.stop();
    super.dispose();
  }
}
