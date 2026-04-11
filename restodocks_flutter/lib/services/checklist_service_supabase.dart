import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../utils/dev_log.dart';

import '../models/models.dart';
import 'account_manager_supabase.dart';
import 'checklist_submission_service.dart';
import 'edge_function_http.dart';
import 'local_snapshot_store.dart';
import 'supabase_service.dart';

/// Сервис чеклистов-шаблонов (Supabase).
class ChecklistServiceSupabase {
  static final ChecklistServiceSupabase _instance = ChecklistServiceSupabase._internal();
  factory ChecklistServiceSupabase() => _instance;
  ChecklistServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  static String _checklistsSnapshotKey(String establishmentId) =>
      '${establishmentId.trim()}:checklists_raw';

  Checklist _checklistFromJoinedRow(Map<String, dynamic> row) {
    final map = Map<String, dynamic>.from(row);
    final itemsRaw = map.remove('checklist_items');
    final c = Checklist.fromJson(map);
    final itemsList = itemsRaw is List ? itemsRaw : <dynamic>[];
    final items = <ChecklistItem>[];
    for (final e in itemsList) {
      if (e is! Map) continue;
      try {
        items.add(ChecklistItem.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return c.copyWith(items: items);
  }

  List<Checklist> _filterChecklistsForUi(
    List<Checklist> all, {
    required String department,
    String? currentEmployeeId,
    required bool applyAssignmentFilter,
  }) {
    final list = <Checklist>[];
    for (final c in all) {
      if (c.assignedDepartment != department) continue;
      if (department == 'hall' && c.type?.code == 'prep') continue;
      if (applyAssignmentFilter && currentEmployeeId != null) {
        final ids = c.assignedEmployeeIds;
        final singleId = c.assignedEmployeeId;
        final hasAssignment = (ids != null && ids.isNotEmpty) ||
            (singleId != null && singleId.isNotEmpty);
        if (hasAssignment) {
          final assignedToCurrent = (ids != null &&
                  ids.contains(currentEmployeeId)) ||
              (singleId == currentEmployeeId);
          if (!assignedToCurrent) continue;
        }
      }
      list.add(c);
    }
    return list;
  }

  Future<void> _persistChecklistsRawSnapshot(
    String establishmentId,
    List<dynamic> rows,
  ) async {
    if (kIsWeb) return;
    try {
      await LocalSnapshotStore.instance.put(
        _checklistsSnapshotKey(establishmentId),
        jsonEncode(rows),
      );
    } catch (e) {
      devLog('ChecklistService: persist snapshot $e');
    }
  }

  Future<List<Checklist>?> _loadChecklistsFromSnapshot(
    String establishmentId, {
    required String department,
    String? currentEmployeeId,
    required bool applyAssignmentFilter,
  }) async {
    if (kIsWeb) return null;
    try {
      final raw = await LocalSnapshotStore.instance
          .get(_checklistsSnapshotKey(establishmentId));
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as List<dynamic>;
      final parsed = <Checklist>[];
      for (final row in data) {
        if (row is! Map) continue;
        try {
          parsed.add(
              _checklistFromJoinedRow(Map<String, dynamic>.from(row)));
        } catch (_) {}
      }
      final filtered = _filterChecklistsForUi(
        parsed,
        department: department,
        currentEmployeeId: currentEmployeeId,
        applyAssignmentFilter: applyAssignmentFilter,
      );
      return filtered.isEmpty ? null : filtered;
    } catch (e) {
      devLog('ChecklistService: read snapshot $e');
      return null;
    }
  }

  Future<void> _refreshChecklistsSnapshotInBackground(
    String establishmentId, {
    required String department,
    String? currentEmployeeId,
    required bool applyAssignmentFilter,
  }) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select(
            '*, checklist_items(id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit)',
          )
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);
      final listRaw = List<dynamic>.from(data as List);
      await _persistChecklistsRawSnapshot(establishmentId, listRaw);
    } catch (e) {
      devLog('ChecklistService: background checklist refresh $e');
    }
  }

  Future<List<Checklist>> getChecklistsForEstablishment(
    String establishmentId, {
    String department = 'kitchen',
    String? currentEmployeeId,
    /// false = редакторы (шеф, владелец) видят все чеклисты подразделения
    bool applyAssignmentFilter = true,
  }) async {
    if (!kIsWeb) {
      final offline = await _loadChecklistsFromSnapshot(
        establishmentId,
        department: department,
        currentEmployeeId: currentEmployeeId,
        applyAssignmentFilter: applyAssignmentFilter,
      );
      if (offline != null && offline.isNotEmpty) {
        unawaited(_refreshChecklistsSnapshotInBackground(
          establishmentId,
          department: department,
          currentEmployeeId: currentEmployeeId,
          applyAssignmentFilter: applyAssignmentFilter,
        ));
        if (kDebugMode) {
          devLog(
              'ChecklistService: ${offline.length} from snapshot, bg refresh');
        }
        return offline;
      }
    }

    try {
      final data = await _supabase.client
          .from('checklists')
          .select(
              '*, checklist_items(id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit)')
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);

      final listRaw = List<dynamic>.from(data as List);
      if (!kIsWeb) {
        await _persistChecklistsRawSnapshot(establishmentId, listRaw);
      }
      final parsed = <Checklist>[];
      for (final row in listRaw) {
        if (row is! Map) continue;
        try {
          parsed.add(
              _checklistFromJoinedRow(Map<String, dynamic>.from(row)));
        } catch (_) {}
      }
      final list = _filterChecklistsForUi(
        parsed,
        department: department,
        currentEmployeeId: currentEmployeeId,
        applyAssignmentFilter: applyAssignmentFilter,
      );
      if (kDebugMode) {
        devLog(
            'ChecklistService: loaded ${list.length} checklists for $establishmentId dept=$department');
      }
      return list;
    } catch (e) {
      devLog('ChecklistService: Ошибка загрузки чеклистов: $e');
      if (!kIsWeb) {
        final fallback = await _loadChecklistsFromSnapshot(
          establishmentId,
          department: department,
          currentEmployeeId: currentEmployeeId,
          applyAssignmentFilter: applyAssignmentFilter,
        );
        if (fallback != null && fallback.isNotEmpty) return fallback;
      }
      rethrow;
    }
  }

  Future<Checklist?> getChecklistById(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    final snapshotEstId =
        !kIsWeb ? AccountManagerSupabase().establishment?.id : null;
    if (snapshotEstId != null) {
      try {
        final raw = await LocalSnapshotStore.instance
            .get(_checklistsSnapshotKey(snapshotEstId));
        if (raw != null && raw.isNotEmpty) {
          final data = jsonDecode(raw) as List<dynamic>;
          for (final row in data) {
            if (row is! Map) continue;
            final m = Map<String, dynamic>.from(row);
            if (m['id']?.toString() != trimmed) continue;
            return _checklistFromJoinedRow(m);
          }
        }
      } catch (_) {}
    }

    try {
      final row = await _supabase.client
          .from('checklists')
          .select()
          .eq('id', trimmed)
          .limit(1)
          .single();
      final c = Checklist.fromJson(Map<String, dynamic>.from(row as Map));
      final itemsData = await _supabase.client
          .from('checklist_items')
          .select(
              'id, checklist_id, title, sort_order, tech_card_id, target_quantity, target_unit')
          .eq('checklist_id', c.id)
          .order('sort_order');
      final items =
          (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
      final result = c.copyWith(items: items);
      if (snapshotEstId != null) {
        unawaited(_refreshChecklistsSnapshotInBackground(
          snapshotEstId,
          department: c.assignedDepartment,
          currentEmployeeId: null,
          applyAssignmentFilter: false,
        ));
      }
      return result;
    } catch (e) {
      devLog('Ошибка загрузки чеклиста: $e');
      return null;
    }
  }

  Future<Checklist> createChecklist({
    required String establishmentId,
    required String createdBy,
    required String name,
    List<ChecklistItem> items = const [],
    String? assignedSection,
    List<String> assignedSectionIds = const [],
    String? assignedEmployeeId,
    List<String>? assignedEmployeeIds,
    DateTime? deadlineAt,
    DateTime? scheduledForAt,
    ChecklistReminderConfig? reminderConfig,
    String? additionalName,
    ChecklistType? type,
    ChecklistActionConfig? actionConfig,
    String assignedDepartment = 'kitchen',
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('createChecklist: name не может быть пустым. Сначала заполните форму и нажмите Сохранить.');
    }
    final now = DateTime.now();
    final data = <String, dynamic>{
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'name': name,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    final secIds = assignedSectionIds.isNotEmpty
        ? List<String>.from(assignedSectionIds)
        : (assignedSection != null && assignedSection.trim().isNotEmpty ? [assignedSection.trim()] : <String>[]);
    data['assigned_section_ids'] = secIds;
    if (secIds.isNotEmpty) data['assigned_section'] = secIds.first;
    if (assignedEmployeeId != null) data['assigned_employee_id'] = assignedEmployeeId;
    if (deadlineAt != null) data['deadline_at'] = deadlineAt.toIso8601String();
    if (scheduledForAt != null) data['scheduled_for_at'] = scheduledForAt.toIso8601String();
    if (reminderConfig != null && reminderConfig.hasAny) {
      data['reminder_config'] = reminderConfig.toJson();
    }
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
      devLog('Ошибка загрузки чеклистов с пропущенным дедлайном: $e');
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
    const optionalKeys = [
      'deadline_at',
      'scheduled_for_at',
      'assigned_section',
      'assigned_section_ids',
      'assigned_employee_id',
      'assigned_employee_ids',
      'additional_name',
      'type',
      'action_config',
      'reminder_config',
    ];
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
    final sectionIds = checklist.assignedSectionIds.isNotEmpty
        ? List<String>.from(checklist.assignedSectionIds)
        : checklist.effectiveSectionIds;
    final sectionFirst = sectionIds.isEmpty ? null : sectionIds.first;
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

    final body = <String, dynamic>{
      'checklist_id': checklist.id,
      'name': checklist.name,
      'updated_at': now,
      'action_config': checklist.actionConfig.toJson(),
      'assigned_department': checklist.assignedDepartment,
      'assigned_section': sectionFirst,
      'assigned_section_ids': sectionIds,
      'assigned_employee_id': empId,
      'assigned_employee_ids': empIds,
      'deadline_at': checklist.deadlineAt?.toUtc().toIso8601String(),
      'scheduled_for_at': checklist.scheduledForAt?.toUtc().toIso8601String(),
      'additional_name': checklist.additionalName,
      'type': checklist.type?.code,
      'items': itemsPayload,
      'reminder_config': checklist.reminderConfig != null && checklist.reminderConfig!.hasAny
          ? checklist.reminderConfig!.toJson()
          : null,
    };

    // 1. Пробуем Edge Function (с retry при 5xx/сети)
    try {
      final res = await postEdgeFunctionWithRetry('save-checklist', body);
      if (res.status == 200 && res.data?['ok'] == true) return;
    } catch (_) { /* пробуем RPC */ }

    // 2. Fallback: RPC save_checklist (anon grant)
    try {
      await _supabase.client.rpc('save_checklist', params: {
        'p_checklist_id': checklist.id,
        'p_name': checklist.name,
        'p_updated_at': now,
        'p_action_config': checklist.actionConfig.toJson(),
        'p_assigned_department': checklist.assignedDepartment,
        'p_assigned_section': sectionFirst,
        'p_assigned_section_ids': sectionIds,
        'p_assigned_employee_id': empId,
        'p_assigned_employee_ids': empIds,
        'p_deadline_at': checklist.deadlineAt?.toUtc().toIso8601String(),
        'p_scheduled_for_at': checklist.scheduledForAt?.toUtc().toIso8601String(),
        'p_additional_name': checklist.additionalName,
        'p_type': checklist.type?.code,
        'p_items': itemsPayload,
        'p_reminder_config': checklist.reminderConfig != null && checklist.reminderConfig!.hasAny
            ? checklist.reminderConfig!.toJson()
            : null,
      });
      return;
    } catch (_) { /* пробуем прямой UPDATE */ }

    // 3. Fallback: прямой UPDATE + INSERT (anon policies)
    final fullUpd = <String, dynamic>{
      'name': checklist.name,
      'updated_at': now,
      'action_config': checklist.actionConfig.toJson(),
      'assigned_department': checklist.assignedDepartment,
      'assigned_section': sectionFirst,
      'assigned_section_ids': sectionIds,
      'assigned_employee_id': empId,
      'assigned_employee_ids': empIds,
      'deadline_at': checklist.deadlineAt?.toUtc().toIso8601String(),
      'scheduled_for_at': checklist.scheduledForAt?.toUtc().toIso8601String(),
      'additional_name': checklist.additionalName,
      'type': checklist.type?.code,
      'reminder_config': checklist.reminderConfig != null && checklist.reminderConfig!.hasAny
          ? checklist.reminderConfig!.toJson()
          : null,
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
      assignedSectionIds: source.assignedSectionIds,
      assignedEmployeeId: source.assignedEmployeeId,
      assignedEmployeeIds: source.assignedEmployeeIds,
      deadlineAt: source.deadlineAt,
      scheduledForAt: null,
      reminderConfig: source.reminderConfig,
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
