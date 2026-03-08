import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'checklist_submission_service.dart';
import 'supabase_service.dart';

/// Сервис чеклистов-шаблонов (Supabase).
class ChecklistServiceSupabase {
  static final ChecklistServiceSupabase _instance = ChecklistServiceSupabase._internal();
  factory ChecklistServiceSupabase() => _instance;
  ChecklistServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  Future<List<Checklist>> getChecklistsForEstablishment(
    String establishmentId, {
    String department = 'kitchen',
    String? currentEmployeeId,
    /// false = редакторы (шеф, владелец) видят все чеклисты подразделения
    bool applyAssignmentFilter = true,
  }) async {
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
        if (applyAssignmentFilter && currentEmployeeId != null) {
          final ids = c.assignedEmployeeIds;
          final singleId = c.assignedEmployeeId;
          final hasAssignment = (ids != null && ids.isNotEmpty) || (singleId != null && singleId.isNotEmpty);
          if (hasAssignment) {
            final assignedToCurrent = (ids != null && ids.contains(currentEmployeeId)) ||
                (singleId == currentEmployeeId);
            if (!assignedToCurrent) continue;
          }
        }
        final itemsData = await _supabase.client
            .from('checklist_items')
            .select('id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit')
            .eq('checklist_id', c.id)
            .order('sort_order');
        final items = (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
        list.add(c.copyWith(items: items));
      }
      if (kDebugMode) {
        print('ChecklistService: loaded ${list.length} checklists for $establishmentId dept=$department');
      }
      return list;
    } catch (e) {
      print('ChecklistService: Ошибка загрузки чеклистов: $e');
      rethrow;
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
          .select('id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit')
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

  /// Обновление чеклиста с поэтапным retry: при PGRST204 исключаем проблемные колонки.
  Future<void> _updateChecklistWithRetry(String id, Map<String, dynamic> fullUpd) async {
    try {
      await _supabase.updateData('checklists', fullUpd, 'id', id);
      return;
    } catch (e) {
      if (!_isColumnNotFoundError(e)) rethrow;
    }
    const optionalKeys = ['deadline_at', 'scheduled_for_at', 'assigned_section', 'assigned_employee_id', 'assigned_employee_ids', 'additional_name', 'type', 'action_config'];
    final stripped = Map<String, dynamic>.from(fullUpd);
    for (final k in optionalKeys) stripped.remove(k);
    try {
      await _supabase.updateData('checklists', stripped, 'id', id);
      return;
    } catch (e) {
      if (!_isColumnNotFoundError(e)) rethrow;
    }
    final minimal = <String, dynamic>{
      'name': fullUpd['name'],
      'updated_at': fullUpd['updated_at'],
    };
    await _supabase.updateData('checklists', minimal, 'id', id);
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
        await _supabase.insertData('checklist_items', minimal);
      } else {
        rethrow;
      }
    }
  }

  Future<void> saveChecklist(Checklist checklist) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final empIds = checklist.assignedEmployeeIds ?? [];
    final rawEmpId = empIds.isNotEmpty ? empIds.first : checklist.assignedEmployeeId;
    final empId = rawEmpId != null && rawEmpId.trim().isNotEmpty ? rawEmpId : null;
    final itemsPayload = checklist.items
        .map((e) => {
              'title': e.title,
              'sort_order': e.sortOrder,
              'tech_card_id': e.techCardId,
              'target_quantity': e.targetQuantity,
              'target_unit': e.targetUnit,
            })
        .toList();

    try {
      if (kDebugMode) {
        print('ChecklistService: calling RPC save_checklist for ${checklist.id}');
      }
      await _supabase.client.rpc(
        'save_checklist',
        params: {
          'p_checklist_id': checklist.id,
          'p_name': checklist.name,
          'p_updated_at': now,
          'p_action_config': checklist.actionConfig.toJson(),
          'p_assigned_department': checklist.assignedDepartment,
          'p_assigned_section': checklist.assignedSection,
          'p_assigned_employee_id': empId,
          'p_assigned_employee_ids': empIds,
          'p_deadline_at': checklist.deadlineAt?.toUtc().toIso8601String(),
          'p_scheduled_for_at': checklist.scheduledForAt?.toUtc().toIso8601String(),
          'p_additional_name': checklist.additionalName,
          'p_type': checklist.type?.code,
          'p_items': itemsPayload,
        },
      );
      if (kDebugMode) {
        print('ChecklistService: RPC save_checklist OK');
      }
      return;
    } catch (e) {
      print('ChecklistService: RPC save_checklist failed: $e');
      // Fallback: прямой UPDATE + пункты (для legacy/anon когда RPC недоступен)
      try {
        final fullUpd = <String, dynamic>{
          'name': checklist.name,
          'updated_at': now,
          'action_config': checklist.actionConfig.toJson(),
          'assigned_department': checklist.assignedDepartment,
          'assigned_section': checklist.assignedSection,
          'assigned_employee_id': empId,
          'assigned_employee_ids': empIds,
          'deadline_at': checklist.deadlineAt?.toUtc().toIso8601String(),
          'scheduled_for_at': checklist.scheduledForAt?.toUtc().toIso8601String(),
          'additional_name': checklist.additionalName,
          'type': checklist.type?.code,
        };
        await _updateChecklistWithRetry(checklist.id, fullUpd);
        await _supabase.client.from('checklist_items').delete().eq('checklist_id', checklist.id);
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
        if (kDebugMode) print('ChecklistService: fallback save OK');
        return;
      } catch (fallbackErr) {
        print('ChecklistService: fallback save also failed: $fallbackErr');
        rethrow;
      }
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
