/// Сообщение между сотрудниками одного заведения.
class EmployeeDirectMessage {
  final String id;
  final String senderEmployeeId;
  final String recipientEmployeeId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? readAt;

  const EmployeeDirectMessage({
    required this.id,
    required this.senderEmployeeId,
    required this.recipientEmployeeId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory EmployeeDirectMessage.fromJson(Map<String, dynamic> json) {
    return EmployeeDirectMessage(
      id: json['id'] as String,
      senderEmployeeId: json['sender_employee_id'] as String,
      recipientEmployeeId: json['recipient_employee_id'] as String,
      content: (json['content'] as String?) ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'] as String) : null,
    );
  }
}
