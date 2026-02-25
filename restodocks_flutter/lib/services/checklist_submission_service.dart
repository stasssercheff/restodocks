import '../models/checklist_submission.dart';
import 'supabase_service.dart';

/// Сервис отправленных заполненных чеклистов.
class ChecklistSubmissionService {
  static final ChecklistSubmissionService _instance = ChecklistSubmissionService._internal();
  factory ChecklistSubmissionService() => _instance;
  ChecklistSubmissionService._internal();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'checklist_submissions';

  /// Отправить заполненный чеклист шефу и су-шефу (по одному ряду на получателя).
  Future<void> submit({
    required String establishmentId,
    required String checklistId,
    required String submittedByEmployeeId,
    required String submittedByName,
    required String checklistName,
    String? section,
    required List<({String title, bool done})> items,
    required List<String> recipientChefIds,
  }) async {
    final payload = <String, dynamic>{
      'submittedByName': submittedByName,
      'items': items.map((e) => {'title': e.title, 'done': e.done}).toList(),
    };
    for (final rid in recipientChefIds) {
      await _supabase.client.from(_table).insert({
        'establishment_id': establishmentId,
        'checklist_id': checklistId,
        'submitted_by_employee_id': submittedByEmployeeId,
        'recipient_chef_id': rid,
        'checklist_name': checklistName,
        'section': section,
        'payload': payload,
      });
    }
  }

  /// Список отправленных чеклистов для шефа/су-шефа.
  Future<List<ChecklistSubmission>> listForChef(String recipientChefId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('recipient_chef_id', recipientChefId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => ChecklistSubmission.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      print('Ошибка загрузки checklist_submissions: $e');
      return [];
    }
  }

  /// Список по заведению (для собственника/управления).
  Future<List<ChecklistSubmission>> listForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => ChecklistSubmission.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      print('Ошибка загрузки checklist_submissions: $e');
      return [];
    }
  }

  /// Получить по id.
  Future<ChecklistSubmission?> getById(String id) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      return data != null ? ChecklistSubmission.fromJson(Map<String, dynamic>.from(data as Map)) : null;
    } catch (e) {
      print('Ошибка загрузки checklist_submission: $e');
      return null;
    }
  }
}
