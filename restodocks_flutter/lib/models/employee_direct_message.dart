/// Сообщение между сотрудниками одного заведения.
class EmployeeDirectMessage {
  final String id;
  final String senderEmployeeId;
  final String recipientEmployeeId;
  final String content;
  final DateTime createdAt;

  const EmployeeDirectMessage({
    required this.id,
    required this.senderEmployeeId,
    required this.recipientEmployeeId,
    required this.content,
    required this.createdAt,
  });

  factory EmployeeDirectMessage.fromJson(Map<String, dynamic> json) {
    return EmployeeDirectMessage(
      id: json['id'] as String,
      senderEmployeeId: json['sender_employee_id'] as String,
      recipientEmployeeId: json['recipient_employee_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
