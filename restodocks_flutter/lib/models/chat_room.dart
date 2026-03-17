/// Групповой чат заведения.
class ChatRoom {
  final String id;
  final String establishmentId;
  final String? name;
  final DateTime createdAt;
  final String? createdByEmployeeId;

  const ChatRoom({
    required this.id,
    required this.establishmentId,
    this.name,
    required this.createdAt,
    this.createdByEmployeeId,
  });

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : '';

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      name: json['name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdByEmployeeId: json['created_by_employee_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'name': name,
        'created_at': createdAt.toUtc().toIso8601String(),
        'created_by_employee_id': createdByEmployeeId,
      };
}
