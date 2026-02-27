import 'package:equatable/equatable.dart';

/// Отправленный заполненный чеклист.
class ChecklistSubmission extends Equatable {
  final String id;
  final String establishmentId;
  final String checklistId;
  final String? submittedByEmployeeId;
  final String? recipientChefId;
  final String checklistName;
  final String? section;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const ChecklistSubmission({
    required this.id,
    required this.establishmentId,
    required this.checklistId,
    this.submittedByEmployeeId,
    this.recipientChefId,
    required this.checklistName,
    this.section,
    required this.payload,
    required this.createdAt,
  });

  factory ChecklistSubmission.fromJson(Map<String, dynamic> json) {
    return ChecklistSubmission(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      checklistId: json['checklist_id'] as String,
      submittedByEmployeeId: json['submitted_by_employee_id'] as String?,
      recipientChefId: json['recipient_chef_id'] as String?,
      checklistName: (json['checklist_name'] as String?) ?? '',
      section: json['section'] as String?,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  List<({String title, bool done})> get items {
    final list = payload['items'] as List<dynamic>? ?? [];
    return list.map((e) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        return (
          title: (m['title'] as String?) ?? '',
          done: m['done'] == true,
        );
      }
      return (title: '', done: false);
    }).toList();
  }

  String get submittedByName => payload['submittedByName'] as String? ?? '';

  @override
  List<Object?> get props => [id];
}
