import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import 'chat_screen.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final onlinePeers = state.peers.where((p) => p.isOnline && p.id != state.userId).toList();
    final offlinePeers = state.peers.where((p) => !p.isOnline).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PlaneChat'),
        actions: [
          if (state.scanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            onPressed: state.scanning ? null : () => state.scan(),
            icon: const Icon(Icons.radar),
            tooltip: '네트워크 스캔',
          ),
          IconButton(
            onPressed: () => _showLogDialog(context, state),
            icon: const Icon(Icons.bug_report),
            tooltip: '디버그 로그',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16),
                  const SizedBox(width: 4),
                  Text(state.currentUserName ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: _PeerPanel(onlinePeers: onlinePeers, offlinePeers: offlinePeers, hostId: state.hostId, myId: state.userId),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _RoomPanel(rooms: state.rooms),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRoomDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('채팅방 만들기'),
      ),
    );
  }

  void _showLogDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('네트워크 로그'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.builder(
            reverse: true,
            itemCount: state.logs.length,
            itemBuilder: (_, i) => Text(
              state.logs[state.logs.length - 1 - i],
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('새 채팅방'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '채팅방 이름',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              context.read<AppState>().createRoom(value.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context.read<AppState>().createRoom(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('만들기'),
          ),
        ],
      ),
    );
  }
}

class _PeerPanel extends StatelessWidget {
  final List<dynamic> onlinePeers;
  final List<dynamic> offlinePeers;
  final String? hostId;
  final String? myId;

  const _PeerPanel({required this.onlinePeers, required this.offlinePeers, required this.hostId, required this.myId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('접속자 (${onlinePeers.length}명)', style: Theme.of(context).textTheme.titleMedium),
              if (context.watch<AppState>().isHost) ...[
                const SizedBox(width: 8),
                const Chip(label: Text('나=호스트', style: TextStyle(fontSize: 10))),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final peer in onlinePeers)
                ListTile(
                  leading: const Icon(Icons.circle, color: Colors.green, size: 12),
                  title: Text(peer.name),
                  subtitle: Text(peer.address, style: const TextStyle(fontSize: 10)),
                  trailing: peer.id == hostId ? const Chip(label: Text('호스트', style: TextStyle(fontSize: 11))) : null,
                  dense: true,
                ),
              if (offlinePeers.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('오프라인', style: Theme.of(context).textTheme.bodySmall),
                ),
                for (final peer in offlinePeers)
                  ListTile(
                    leading: const Icon(Icons.circle, color: Colors.grey, size: 12),
                    title: Text(peer.name, style: const TextStyle(color: Colors.grey)),
                    dense: true,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomPanel extends StatelessWidget {
  final List rooms;

  const _RoomPanel({required this.rooms});

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('아직 열린 채팅방이 없습니다', style: TextStyle(color: Colors.grey)),
            Text('채팅방을 만들어보세요!', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('채팅방 (${rooms.length}개)', style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rooms.length,
            itemBuilder: (ctx, i) {
              final room = rooms[i];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  title: Text(room.name),
                  subtitle: Text('${room.creatorName} · 참여자 ${room.participantIds.length}명'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    context.read<AppState>().joinRoom(room.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatScreen(roomId: room.id, roomName: room.name)),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
