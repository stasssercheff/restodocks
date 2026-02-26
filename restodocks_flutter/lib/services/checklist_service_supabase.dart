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
    String? assignedSection,
    String? assignedEmployeeId,
    String? additionalName,
    ChecklistType? type,
    ChecklistActionConfig? actionConfig,
  }) async {
    final now = DateTime.now();
    final data = <String, dynamic>{
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'name': name,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    if (assignedSection != null) data['assigned_section'] = assignedSection;
    if (assignedEmployeeId != null) data['assigned_employee_id'] = assignedEmployeeId;
    if (additionalName != null) data['additional_name'] = additionalName;
    if (type != null) data['type'] = type.code;
    if (actionConfig != null) data['action_config'] = actionConfig.toJson();
    final res = await _supabase.insertData('checklists', data);
    final c = Checklist.fromJson(res);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final itemData = <String, dynamic>{
        'checklist_id': c.id,
        'title': item.title,
        'sort_order': i,
      };
      if (item.techCardId != null) itemData['tech_card_id'] = item.techCardId;
      await _supabase.insertData('checklist_items', itemData);
    }
    return (await getChecklistById(c.id)) ?? c;
  }

  Future<void> saveChecklist(Checklist checklist) async {
    final upd = <String, dynamic>{
      'name': checklist.name,
      'updated_at': DateTime.now().toIso8601String(),
    };
    upd['assigned_section'] = checklist.assignedSection;
    upd['assigned_employee_id'] = checklist.assignedEmployeeId;
    upd['additional_name'] = checklist.additionalName;
    upd['type'] = checklist.type?.code;
    upd['action_config'] = checklist.actionConfig.toJson();
    await _supabase.updateData('checklists', upd, 'id', checklist.id);
    await _supabase.client
        .from('checklist_items')
        .delete()
        .eq('checklist_id', checklist.id);
    for (var i = 0; i < checklist.items.length; i++) {
      final item = checklist.items[i];
      final itemData = <String, dynamic>{
        'checklist_id': checklist.id,
        'title': item.title,
        'sort_order': i,
      };
      if (item.techCardId != null) itemData['tech_card_id'] = item.techCardId;
      await _supabase.insertData('checklist_items', itemData);
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
      additionalName: source.additionalName,
      type: source.type,
      actionConfig: source.actionConfig,
      items: source.items
          .map((e) => ChecklistItem.template(
                title: e.title,
                sortOrder: e.sortOrder,
                techCardId: e.techCardId,
              ))
          .toList(),
    );
  }
}
