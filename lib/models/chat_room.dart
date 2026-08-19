class ChatRoom {
  final String id;
  final String name;
  final String creatorId;
  final String creatorName;
  final DateTime createdAt;
  final List<String> participantIds;

  ChatRoom({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.creatorName,
    required this.createdAt,
    List<String>? participantIds,
  }) : participantIds = participantIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'createdAt': createdAt.toIso8601String(),
        'participantIds': participantIds,
      };

  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
        id: json['id'],
        name: json['name'],
        creatorId: json['creatorId'],
        creatorName: json['creatorName'],
        createdAt: DateTime.parse(json['createdAt']),
        participantIds: List<String>.from(json['participantIds'] ?? []),
      );
}
