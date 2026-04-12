import 'employee_message_system_link.dart';

/// Сообщение между сотрудниками одного заведения.
class EmployeeDirectMessage {
  final String id;
  final String senderEmployeeId;
  final String recipientEmployeeId;
  final String content;
  final String? imageUrl;
  final String? audioUrl;
  final int? audioDurationSeconds;
  final List<EmployeeMessageSystemLink> systemLinks;
  final DateTime createdAt;
  final DateTime? readAt;

  const EmployeeDirectMessage({
    required this.id,
    required this.senderEmployeeId,
    required this.recipientEmployeeId,
    required this.content,
    this.imageUrl,
    this.audioUrl,
    this.audioDurationSeconds,
    this.systemLinks = const [],
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get hasSystemLinks => systemLinks.isNotEmpty;

  factory EmployeeDirectMessage.fromJson(Map<String, dynamic> json) {
    return EmployeeDirectMessage(
      id: json['id'] as String,
      senderEmployeeId: json['sender_employee_id'] as String,
      recipientEmployeeId: json['recipient_employee_id'] as String,
      content: (json['content'] as String?) ?? '',
      imageUrl: json['image_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      audioDurationSeconds: (json['audio_duration_seconds'] as num?)?.toInt(),
      systemLinks: _parseSystemLinks(json['system_links']),
      createdAt: DateTime.parse(json['created_at'] as String),
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at'] as String) : null,
    );
  }

  static List<EmployeeMessageSystemLink> _parseSystemLinks(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    final out = <EmployeeMessageSystemLink>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        final link = EmployeeMessageSystemLink.fromJson(e);
        if (link.path.isNotEmpty && link.label.isNotEmpty) out.add(link);
      }
    }
    return out;
  }
}
