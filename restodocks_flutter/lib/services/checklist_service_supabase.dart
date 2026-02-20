import '../models/models.dart';
import 'supabase_service.dart';

/// Сервис чеклистов-шаблонов (Supabase).
class ChecklistServiceSupabase {
  static final ChecklistServiceSupabase _instance = ChecklistServiceSupabase._internal();
  factory ChecklistServiceSupabase() => _instance;
  ChecklistServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  Future<List<Checklist>> getChecklistsForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select()
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);

      final list = <Checklist>[];
      for (final row in data) {
        final c = Checklist.fromJson(row);
        final itemsData = await _supabase.client
            .from('checklist_items')
            .select()
            .eq('checklist_id', c.id)
            .order('sort_order');
        final items = (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
        list.add(c.copyWith(items: items));
      }
      return list;
    } catch (e) {
      print('Ошибка загрузки чеклистов: $e');
      return [];
    }
  }

  Future<Checklist?> getChecklistById(String id) async {
    try {
      final row = await _supabase.client
          .from('checklists')
          .select()
          .eq('id', id)
          .limit(1)
          .single();
      final c = Checklist.fromJson(row);
      final itemsData = await _supabase.client
          .from('checklist_items')
          .select()
          .eq('checklist_id', c.id)
          .order('sort_order');
      final items = (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
      return c.copyWith(items: items);
    } catch (e) {
      print('Ошибка загрузки чеклиста: $e');
      return null;
    }
  }

  Future<Checklist> createChecklist({
    required String establishmentId,
    required String createdBy,
    required String name,
    List<ChecklistItem> items = const [],
  }) async {
    final now = DateTime.now();
    final data = {
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'name': name,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    final res = await _supabase.insertData('checklists', data);
    final c = Checklist.fromJson(res);

    for (var i = 0; i < items.length; i++) {
      await _supabase.insertData('checklist_items', {
        'checklist_id': c.id,
        'title': items[i].title,
        'sort_order': i,
        'cell_type': items[i].cellType.value,
        'dropdown_options': items[i].dropdownOptions,
      });
    }
    return (await getChecklistById(c.id)) ?? c;
  }

  Future<void> saveChecklist(Checklist checklist) async {
    await _supabase.updateData(
      'checklists',
      {
        'name': checklist.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      'id',
      checklist.id,
    );
    await _supabase.client
        .from('checklist_items')
        .delete()
        .eq('checklist_id', checklist.id);
    for (var i = 0; i < checklist.items.length; i++) {
      await _supabase.insertData('checklist_items', {
        'checklist_id': checklist.id,
        'title': checklist.items[i].title,
        'sort_order': i,
        'cell_type': checklist.items[i].cellType.value,
        'dropdown_options': checklist.items[i].dropdownOptions,
      });
    }
  }

  Future<void> deleteChecklist(String id) async {
    await _supabase.deleteData('checklists', 'id', id);
  }

  /// Создать по аналогии (дубликат шаблона).
  Future<Checklist> duplicateChecklist(Checklist source, String createdBy) async {
    return createChecklist(
      establishmentId: source.establishmentId,
      createdBy: createdBy,
      name: '${source.name} (копия)',
      items: source.items
          .map((e) => ChecklistItem.template(
                title: e.title,
                sortOrder: e.sortOrder,
                cellType: e.cellType,
                dropdownOptions: e.dropdownOptions,
              ))
          .toList(),
    );
  }

  /// Отправить заполненный чеклист шеф-повару.
  Future<ChecklistSubmission?> submitChecklist({
    required String establishmentId,
    required String checklistId,
    required String checklistName,
    required String filledByEmployeeId,
    required String filledByName,
    String? filledByRole,
    required Map<String, dynamic> payload,
    required String recipientChefId,
  }) async {
    try {
      final data = {
        'establishment_id': establishmentId,
        'checklist_id': checklistId,
        'filled_by_employee_id': filledByEmployeeId,
        'recipient_chef_id': recipientChefId,
        'payload': {
          ...payload,
          'checklist_name': checklistName,
          'filled_by_name': filledByName,
          'filled_by_role': filledByRole,
        },
      };
      final res = await _supabase.insertData('checklist_submissions', data);
      return ChecklistSubmission.fromJson(res);
    } catch (e) {
      print('Ошибка отправки чеклиста: $e');
      return null;
    }
  }

  /// Список отправленных чеклистов для шеф-повара.
  Future<List<ChecklistSubmission>> listSubmissionsForChef(String chefId) async {
    try {
      final data = await _supabase.client
          .from('checklist_submissions')
          .select()
          .eq('recipient_chef_id', chefId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => ChecklistSubmission.fromJson(e)).toList();
    } catch (e) {
      print('Ошибка загрузки отправленных чеклистов: $e');
      return [];
    }
  }
}
