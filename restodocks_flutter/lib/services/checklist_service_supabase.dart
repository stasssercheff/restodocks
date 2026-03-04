import '../models/models.dart';
import 'checklist_submission_service.dart';
import 'supabase_service.dart';

/// Сервис чеклистов-шаблонов (Supabase).
class ChecklistServiceSupabase {
  static final ChecklistServiceSupabase _instance = ChecklistServiceSupabase._internal();
  factory ChecklistServiceSupabase() => _instance;
  ChecklistServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  Future<List<Checklist>> getChecklistsForEstablishment(String establishmentId, {String department = 'kitchen'}) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select()
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);

      final list = <Checklist>[];
      for (final row in data) {
        final c = Checklist.fromJson(row);
        if (c.assignedDepartment != department) continue;
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
    List<String>? assignedEmployeeIds,
    DateTime? deadlineAt,
    DateTime? scheduledForAt,
    String? additionalName,
    ChecklistType? type,
    ChecklistActionConfig? actionConfig,
    String assignedDepartment = 'kitchen',
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
    if (deadlineAt != null) data['deadline_at'] = deadlineAt.toIso8601String();
    if (scheduledForAt != null) data['scheduled_for_at'] = scheduledForAt.toIso8601String();
    if (additionalName != null) data['additional_name'] = additionalName;
    data['assigned_department'] = assignedDepartment;
    if (type != null) data['type'] = type.code;
    if (actionConfig != null) data['action_config'] = actionConfig.toJson();
    Map<String, dynamic> res;
    try {
      res = await _supabase.insertData('checklists', data);
    } catch (e) {
      if (_isColumnNotFoundError(e)) {
        // Без assigned_department — колонка может отсутствовать или schema cache не обновлён
        final minimal = <String, dynamic>{
          'establishment_id': establishmentId,
          'created_by': createdBy,
          'name': name,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        };
        res = await _supabase.insertData('checklists', minimal);
      } else {
        rethrow;
      }
    }
    final c = Checklist.fromJson(res);

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final itemData = <String, dynamic>{
        'checklist_id': c.id,
        'title': item.title,
        'sort_order': i,
      };
      if (item.techCardId != null) itemData['tech_card_id'] = item.techCardId;
      if (item.targetQuantity != null) itemData['target_quantity'] = item.targetQuantity;
      if (item.targetUnit != null) itemData['target_unit'] = item.targetUnit;
      await _insertChecklistItem(itemData);
    }
    return (await getChecklistById(c.id)) ?? c;
  }

  /// Чеклисты с пропущенным дедлайном (deadline_at в прошлом и нет отправки по этому чеклисту).
  Future<List<Checklist>> getChecklistsWithMissedDeadline(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select()
          .eq('establishment_id', establishmentId);
      final now = DateTime.now();
      final submissions = await ChecklistSubmissionService().listForEstablishment(establishmentId);
      final submittedChecklistIds = submissions.map((s) => s.checklistId).toSet();

      final list = <Checklist>[];
      for (final row in data) {
        final c = Checklist.fromJson(row);
        if (c.deadlineAt == null || !c.deadlineAt!.isBefore(now)) continue;
        if (submittedChecklistIds.contains(c.id)) continue;
        list.add(c);
      }
      list.sort((a, b) => (b.deadlineAt ?? DateTime(0)).compareTo(a.deadlineAt ?? DateTime(0)));
      return list;
    } catch (e) {
      print('Ошибка загрузки чеклистов с пропущенным дедлайном: $e');
      return [];
    }
  }

  bool _isColumnNotFoundError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('pgrst204') ||
        (msg.contains('column') && (msg.contains('find') || msg.contains('found') || msg.contains('exist')));
  }

  /// Вставка одного пункта; при ошибке схемы (PGRST204) повтор без опциональных колонок.
  Future<void> _insertChecklistItem(Map<String, dynamic> itemData) async {
    try {
      await _supabase.insertData('checklist_items', itemData);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('pgrst204') || (msg.contains('column') && (msg.contains('find') || msg.contains('found') || msg.contains('exist')))) {
        final minimal = <String, dynamic>{
          'checklist_id': itemData['checklist_id'],
          'title': itemData['title'],
          'sort_order': itemData['sort_order'],
        };
        if (itemData.containsKey('tech_card_id') && itemData['tech_card_id'] != null) {
          minimal['tech_card_id'] = itemData['tech_card_id'];
        }
        await _supabase.insertData('checklist_items', minimal);
      } else {
        rethrow;
      }
    }
  }

  Future<void> saveChecklist(Checklist checklist) async {
    final upd = <String, dynamic>{
      'name': checklist.name,
      'updated_at': DateTime.now().toIso8601String(),
    };
    upd['assigned_section'] = checklist.assignedSection;
    upd['assigned_employee_id'] = checklist.assignedEmployeeIds?.isNotEmpty == true
        ? checklist.assignedEmployeeIds!.first
        : checklist.assignedEmployeeId;
    if (checklist.deadlineAt != null) upd['deadline_at'] = checklist.deadlineAt!.toIso8601String();
    if (checklist.scheduledForAt != null) upd['scheduled_for_at'] = checklist.scheduledForAt!.toIso8601String();
    upd['additional_name'] = checklist.additionalName;
    upd['type'] = checklist.type?.code;
    upd['action_config'] = checklist.actionConfig.toJson();
    try {
      await _supabase.updateData('checklists', upd, 'id', checklist.id);
    } catch (e) {
      if (_isColumnNotFoundError(e)) {
        // Только колонки, гарантированно существующие — schema cache может не видеть deadline_at и др.
        final minimal = <String, dynamic>{
          'name': checklist.name,
          'updated_at': DateTime.now().toIso8601String(),
        };
        await _supabase.updateData('checklists', minimal, 'id', checklist.id);
      } else {
        rethrow;
      }
    }
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
      if (item.targetQuantity != null) itemData['target_quantity'] = item.targetQuantity;
      if (item.targetUnit != null) itemData['target_unit'] = item.targetUnit;
      await _insertChecklistItem(itemData);
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
      assignedDepartment: source.assignedDepartment,
      assignedSection: source.assignedSection,
      assignedEmployeeId: source.assignedEmployeeId,
      assignedEmployeeIds: source.assignedEmployeeIds,
      deadlineAt: source.deadlineAt,
      scheduledForAt: source.scheduledForAt,
      items: source.items
          .map((e) => ChecklistItem.template(
                title: e.title,
                sortOrder: e.sortOrder,
                techCardId: e.techCardId,
                targetQuantity: e.targetQuantity,
                targetUnit: e.targetUnit,
              ))
          .toList(),
    );
  }
}
