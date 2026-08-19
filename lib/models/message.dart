class Message {
  final String id;
  final String senderName;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final String roomId;

  Message({
    required this.id,
    required this.senderName,
    required this.senderId,
    required this.content,
    required this.timestamp,
    required this.roomId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderName': senderName,
        'senderId': senderId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'roomId': roomId,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'],
        senderName: json['senderName'],
        senderId: json['senderId'],
        content: json['content'],
        timestamp: DateTime.parse(json['timestamp']),
        roomId: json['roomId'],
      );
}
