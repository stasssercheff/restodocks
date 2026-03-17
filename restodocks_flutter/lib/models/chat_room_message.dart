/// Сообщение в групповом чате.
class ChatRoomMessage {
  final String id;
  final String chatRoomId;
  final String senderEmployeeId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  const ChatRoomMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderEmployeeId,
    required this.content,
    this.imageUrl,
    required this.createdAt,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory ChatRoomMessage.fromJson(Map<String, dynamic> json) {
    return ChatRoomMessage(
      id: json['id'] as String,
      chatRoomId: json['chat_room_id'] as String,
      senderEmployeeId: json['sender_employee_id'] as String,
      content: (json['content'] as String?) ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
