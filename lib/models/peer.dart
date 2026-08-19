class Peer {
  final String id;
  final String name;
  final String address;
  final int port;
  bool isOnline;
  final DateTime joinedAt;

  Peer({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    this.isOnline = true,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'port': port,
        'isOnline': isOnline,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'],
        name: json['name'],
        address: json['address'] ?? '',
        port: json['port'] ?? 0,
        isOnline: json['isOnline'] ?? true,
        joinedAt: DateTime.parse(json['joinedAt']),
      );

  @override
  bool operator ==(Object other) => other is Peer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
