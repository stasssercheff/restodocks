import '../models/models.dart';
import '../utils/dev_log.dart';
import 'services.dart';

/// Сервис для работы с документами во входящих (инвентаризации — шефу и собственнику).
class InboxService {
  final SupabaseService _supabase;

  InboxService(this._supabase);

  bool _isAuthLikeError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('401') ||
        s.contains('403') ||
        s.contains('42501') ||
        s.contains('jwt') ||
        s.contains('not authorized') ||
        s.contains('permission denied');
  }

  Future<void> _refreshSessionQuietly() async {
    try {
      if (_supabase.client.auth.currentSession != null) {
        await _supabase.client.auth.refreshSession();
      }
    } catch (_) {}
  }

  Future<T> _withAuthRetry<T>(String tag, Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      if (!_isAuthLikeError(e)) rethrow;
      devLog('InboxService: $tag auth-like error, retry after refresh');
      await _refreshSessionQuietly();
      return await run();
    }
  }

  Future<T> _safe<T>(String tag, Future<T> Function() run, T fallback) async {
    try {
      return await _withAuthRetry(tag, run);
    } catch (e) {
      devLog('InboxService: $tag failed: $e');
      return fallback;
    }
  }

  /// Получить документы во входящих: для шефа — полученные им инвентаризации, для собственника/управления — все по заведению.
  Future<List<InboxDocument>> getInboxDocuments(String establishmentId, Employee? currentEmployee) async {
    final documents = <InboxDocument>[];

    if (currentEmployee == null) return documents;

    try {
      final docService = InventoryDocumentService();
      final isOwnerOrMgmt = currentEmployee.hasRole('owner') || currentEmployee.department == 'management';
      final isChefOrOwner = currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef') || isOwnerOrMgmt;

      // Параллельная загрузка: инвентаризации, чеклисты, просрочки, заказы.
      // Важно: падение одного источника не должно обнулять все входящие.
      final inventoryFuture = () async {
        List<Map<String, dynamic>> rawList;
        if (isOwnerOrMgmt) {
          rawList = await docService.listForEstablishment(establishmentId);
        } else if (currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef')) {
          rawList = await docService.listForChef(currentEmployee.id);
        } else if (currentEmployee.hasRole('bar_manager')) {
          rawList = await docService.listForEstablishment(establishmentId);
          rawList = rawList.where((d) {
            final p = d['payload'] as Map<String, dynamic>?;
            final h = p?['header'] as Map<String, dynamic>?;
            final dept = (h?['department'] ?? '').toString();
            final isBar = dept == 'bar' || dept == 'Bar';
            final isIiko = p?['type'] == 'iiko_inventory';
            if (isIiko) return isBar; // инвентаризация iiko бара — показываем барменеджеру
            return isBar;
          }).toList();
        } else if (currentEmployee.hasRole('floor_manager')) {
          rawList = await docService.listForEstablishment(establishmentId);
          rawList = rawList.where((d) {
            final p = d['payload'] as Map<String, dynamic>?;
            final h = p?['header'] as Map<String, dynamic>?;
            final isIiko = p?['type'] == 'iiko_inventory';
            if (isIiko) return false;
            final dept = (h?['department'] ?? '').toString().toLowerCase();
            return dept == 'hall' || dept == 'dining_room' || dept == 'зал';
          }).toList();
        } else {
          rawList = [];
        }
        return rawList;
      }();

      final checklistFuture = isChefOrOwner
          ? (currentEmployee.hasRole('owner') || currentEmployee.department == 'management'
              ? ChecklistSubmissionService().listForEstablishment(establishmentId)
              : ChecklistSubmissionService().listForChef(currentEmployee.id))
          : Future<List<dynamic>>.value([]);

      final missedFuture = isChefOrOwner
          ? ChecklistServiceSupabase().getChecklistsWithMissedDeadline(establishmentId)
          : Future<List<dynamic>>.value([]);

      final ordersFuture = OrderDocumentService().listForEstablishment(establishmentId);
      final receiptsFuture =
          ProcurementReceiptService.instance.listDeduped(establishmentId);
      final priceApprovalFuture =
          ProcurementPriceApprovalService.instance.listPending(establishmentId);

      final results = await Future.wait([
        _safe<List<Map<String, dynamic>>>(
            'inventory', () async => await inventoryFuture, <Map<String, dynamic>>[]),
        _safe<List<dynamic>>(
            'checklist_submissions', () async => await checklistFuture, <dynamic>[]),
        _safe<List<dynamic>>(
            'checklist_missed', () async => await missedFuture, <dynamic>[]),
        _safe<List<Map<String, dynamic>>>(
            'orders', () async => await ordersFuture, <Map<String, dynamic>>[]),
        _safe<List<Map<String, dynamic>>>(
            'procurement_receipts', () async => await receiptsFuture, <Map<String, dynamic>>[]),
        _safe<List<Map<String, dynamic>>>(
            'price_approvals', () async => await priceApprovalFuture, <Map<String, dynamic>>[]),
      ]);
      final rawList = results[0] as List<Map<String, dynamic>>;
      final subList = results[1] as List<dynamic>;
      final missed = results[2] as List<dynamic>;
      final orderDocs = results[3] as List<Map<String, dynamic>>;
      final receiptDocs = results[4] as List<Map<String, dynamic>>;
      final priceApprovalRows = results[5] as List<Map<String, dynamic>>;

      for (final doc in rawList) {
        final payload = doc['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final dateStr = header['date']?.toString() ?? '';
        final employeeName = header['employeeName']?.toString() ?? '—';
        final createdAt = doc['created_at'] != null
            ? (DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now()).toLocal()
            : DateTime.now();

        final payloadType = payload['type']?.toString() ?? '';
        final isIiko = payloadType == 'iiko_inventory';
        final isWriteoff = payloadType == 'writeoff';
        var docDept = header['department']?.toString() ?? _mapSectionToDepartment(currentEmployee.department);
        docDept = _mapSectionToDepartment(docDept);
        // Документы инвентаризаций/списаний с "management" (или пустым отделом)
        // должны быть видимы во входящих у владельца/менеджмента, поэтому
        // маппим их в "kitchen" (вкладки owner не содержат "management").
        if ((isWriteoff || isIiko || payloadType == 'selective_inventory' || payloadType.isEmpty) &&
            docDept == 'management') {
          docDept = 'kitchen';
        }

        DocumentType docType;
        String docTitle;
        if (isWriteoff) {
          docType = DocumentType.writeoff;
          docTitle = 'Списания $dateStr';
        } else if (isIiko) {
          docType = DocumentType.iikoInventory;
          docTitle = 'Инвентаризация iiko $dateStr';
        } else {
          docType = DocumentType.inventory;
          if (payloadType == 'selective_inventory') {
            docTitle = 'Выборочная инвентаризация $dateStr';
          } else {
            docTitle = 'Инвентаризация $dateStr';
          }
        }

        documents.add(InboxDocument(
          id: doc['id']?.toString() ?? '',
          type: docType,
          title: docTitle,
          description: employeeName,
          createdAt: createdAt,
          employeeId: doc['created_by_employee_id']?.toString() ?? '',
          employeeName: employeeName,
          department: docDept,
          fileUrl: null,
          metadata: payload,
        ));
      }

      // Отправленные чеклисты — для шефа и су-шефа (данные уже загружены параллельно выше)
      for (final sub in subList) {
        final s = sub as ChecklistSubmission;
        final submittedName = s.submittedByName.isNotEmpty ? s.submittedByName : '—';
        var subDept = _mapSectionToDepartment(
          s.payload['department']?.toString() ?? '',
        );
        // Для management-подразделения показываем во вкладке «Кухня»,
        // иначе карточки чеклистов не видны в фильтре цехов.
        if (subDept == 'management') subDept = 'kitchen';
        documents.add(InboxDocument(
          id: s.id,
          type: DocumentType.checklistSubmission,
          title: 'Чеклист: ${s.checklistName}',
          description: '$submittedName${s.section != null ? ' • ${s.section}' : ''}',
          createdAt: s.createdAt,
          employeeId: s.submittedByEmployeeId ?? '',
          employeeName: submittedName,
          department: subDept,
          fileUrl: null,
          metadata: {'submission': s.payload, 'checklistId': s.checklistId},
        ));
      }

      // Чеклисты с пропущенным дедлайном (данные уже загружены параллельно выше)
      for (final c in missed) {
        final ch = c as Checklist;
        final deadlineStr = ch.deadlineAt != null
            ? DateTime(ch.deadlineAt!.year, ch.deadlineAt!.month, ch.deadlineAt!.day)
                .toIso8601String()
            : '';
        documents.add(InboxDocument(
          id: ch.id,
          type: DocumentType.checklistMissedDeadline,
          title: 'Чеклист не выполнен: ${ch.name}',
          description: deadlineStr.isNotEmpty ? 'Срок: $deadlineStr' : '',
          createdAt: ch.deadlineAt ?? ch.updatedAt,
          employeeId: '',
          employeeName: '',
          department: ch.assignedDepartment,
          fileUrl: null,
          metadata: {'checklistId': ch.id, 'checklistName': ch.name},
        ));
      }

      // Заявки на изменение ТТК — владелец и генеральный директор
      if (currentEmployee.hasRole('owner') ||
          currentEmployee.hasRole('general_manager')) {
        try {
          final ttkRows =
              await TechCardChangeRequestService.instance.listPending(establishmentId);
          for (final row in ttkRows) {
            final payload = row['proposed_payload'];
            var dish = 'ТТК';
            var dept = 'kitchen';
            if (payload is Map<String, dynamic>) {
              final card = payload['card'];
              if (card is Map<String, dynamic>) {
                dish = card['dish_name']?.toString() ?? dish;
                dept = card['department']?.toString() ?? 'kitchen';
              }
            }
            documents.add(InboxDocument(
              id: row['id']?.toString() ?? '',
              type: DocumentType.techCardChangeRequest,
              title: dish,
              description: 'ТТК',
              createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
              employeeId: row['author_employee_id']?.toString() ?? '',
              employeeName: '—',
              department: _mapSectionToDepartment(dept),
              fileUrl: null,
              metadata: Map<String, dynamic>.from(row),
            ));
          }
        } catch (e) {
          devLog('InboxService: ttk change requests $e');
        }
      }

      // Заказы продуктов (данные уже загружены параллельно выше)
      for (final doc in orderDocs) {
        final payload = doc['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final supplierName = header['supplierName']?.toString() ?? '—';
        final employeeName = header['employeeName']?.toString() ?? '—';
        final docDept = header['department']?.toString() ?? _mapSectionToDepartment(currentEmployee.department);
        final createdAt = doc['created_at'] != null
            ? (DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now()).toLocal()
            : DateTime.now();

        documents.add(InboxDocument(
          id: doc['id']?.toString() ?? '',
          type: DocumentType.productOrder,
          title: 'Заказ $supplierName',
          description: employeeName,
          createdAt: createdAt,
          employeeId: doc['created_by_employee_id']?.toString() ?? '',
          employeeName: employeeName,
          department: docDept,
          fileUrl: null,
          metadata: payload,
        ));
      }

      for (final doc in receiptDocs) {
        final payload = doc['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        if (header['receipt'] != true) continue;
        final supplierName = header['supplierName']?.toString() ?? '—';
        final employeeName = header['employeeName']?.toString() ?? '—';
        final docDept = header['department']?.toString() ??
            _mapSectionToDepartment(currentEmployee.department);
        final createdAt = doc['created_at'] != null
            ? (DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now())
                .toLocal()
            : DateTime.now();

        documents.add(InboxDocument(
          id: doc['id']?.toString() ?? '',
          type: DocumentType.procurementGoodsReceipt,
          title: 'Приёмка $supplierName',
          description: employeeName,
          createdAt: createdAt,
          employeeId: doc['created_by_employee_id']?.toString() ?? '',
          employeeName: employeeName,
          department: docDept,
          fileUrl: null,
          metadata: payload,
        ));
      }

      if (priceApprovalRows.isNotEmpty) {
        final receiptIds = priceApprovalRows
            .map((r) => r['receipt_document_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        final receiptById = <String, Map<String, dynamic>>{};
        if (receiptIds.isNotEmpty) {
          try {
            final recData = await _supabase.client
                .from('procurement_receipt_documents')
                .select('id, payload')
                .inFilter('id', receiptIds);
            for (final r in (recData as List? ?? [])) {
              if (r is Map) {
                final m = Map<String, dynamic>.from(r);
                final id = m['id']?.toString();
                if (id != null) receiptById[id] = m;
              }
            }
          } catch (e) {
            devLog('InboxService: procurement receipts for price approval $e');
          }
        }
        final authorIds = priceApprovalRows
            .map((r) => r['created_by_employee_id']?.toString())
            .whereType<String>()
            .toSet()
            .toList();
        final nameByEmp = <String, String>{};
        if (authorIds.isNotEmpty) {
          try {
            final empData = await _supabase.client
                .from('employees')
                .select('id, full_name, surname')
                .inFilter('id', authorIds);
            for (final e in (empData as List? ?? [])) {
              if (e is Map) {
                final m = Map<String, dynamic>.from(e);
                final id = m['id']?.toString();
                if (id == null) continue;
                final fn = m['full_name']?.toString() ?? '';
                final sn = m['surname']?.toString() ?? '';
                nameByEmp[id] = fn.trim().isNotEmpty ? fn : sn;
              }
            }
          } catch (e) {
            devLog('InboxService: employees for price approval $e');
          }
        }

        for (final row in priceApprovalRows) {
          final recId = row['receipt_document_id']?.toString();
          final rec =
              recId != null ? receiptById[recId] : null;
          final p = rec?['payload'] as Map<String, dynamic>?;
          final header = p?['header'] as Map<String, dynamic>? ?? {};
          final docDept = _mapSectionToDepartment(
            header['department']?.toString() ?? 'kitchen',
          );
          if (!ProcurementPriceApprovalService.canSeePriceApproval(
              currentEmployee, docDept)) {
            continue;
          }
          final supplier = header['supplierName']?.toString() ?? '—';
          final createdBy = row['created_by_employee_id']?.toString() ?? '';
          final authorName = nameByEmp[createdBy] ?? '—';
          final createdAt = row['created_at'] != null
              ? (DateTime.tryParse(row['created_at'].toString()) ??
                      DateTime.now())
                  .toLocal()
              : DateTime.now();
          final meta = Map<String, dynamic>.from(row);
          meta['receiptSupplier'] = supplier;
          documents.add(InboxDocument(
            id: row['id']?.toString() ?? '',
            type: DocumentType.procurementPriceApproval,
            title: supplier,
            description: authorName,
            createdAt: createdAt,
            employeeId: createdBy,
            employeeName: authorName,
            department: docDept,
            fileUrl: null,
            metadata: meta,
          ));
        }
      }

      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (e) {
      devLog('Error loading inbox documents: $e');
      return [];
    }
  }

  /// Маппинг секции на отдел (kitchen, bar, hall — для фильтра входящих; management — скрыт)
  String _mapSectionToDepartment(String section) {
    switch (section.toLowerCase()) {
      case 'kitchen':
      case 'hot_kitchen':
      case 'cold_kitchen':
      case 'confectionery':
        return 'kitchen';
      case 'bar':
        return 'bar';
      case 'hall':
      case 'service':
      case 'dining_room':
        return 'hall';
      default:
        return 'management';
    }
  }

  /// Скачать документ
  Future<void> downloadDocument(InboxDocument document) async {
    if (document.fileUrl == null) return;

    try {
      // В реальном приложении здесь будет логика скачивания файла
      // Пока просто имитируем скачивание
      devLog('Downloading document: ${document.title}');
      devLog('File URL: ${document.fileUrl}');

      // Можно добавить логику сохранения файла на устройство
      // используя packages как path_provider и http

    } catch (e) {
      devLog('Error downloading document: $e');
      rethrow;
    }
  }

  /// Получить документы по отделу
  List<InboxDocument> filterByDepartment(List<InboxDocument> documents, String department) {
    if (department == 'all') return documents;
    return documents.where((doc) => doc.department == department).toList();
  }

  /// Создать уведомление об изменении дня рождения (вызывается при сохранении профиля сотрудником).
  Future<void> insertBirthdayChangeNotification({
    required String establishmentId,
    required String employeeId,
    required String employeeName,
    required DateTime? newBirthday,
    DateTime? previousBirthday,
  }) async {
    try {
      await _supabase.client.from('employee_birthday_change_notifications').insert({
        'establishment_id': establishmentId,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'previous_birthday': previousBirthday != null ? _dateOnly(previousBirthday) : null,
        'new_birthday': newBirthday != null ? _dateOnly(newBirthday) : null,
        'changed_by_employee_id': employeeId,
      });
    } catch (e) {
      devLog('Error inserting birthday change notification: $e');
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Уведомления об изменении дня рождения (видят owner, executive_chef, sous_chef, bar_manager, floor_manager)
  Future<List<EmployeeBirthdayChangeNotification>> getBirthdayChangeNotifications(String establishmentId) async {
    try {
      final res = await _supabase.client
          .from('employee_birthday_change_notifications')
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false)
          .limit(100);
      final list = res as List<dynamic>? ?? [];
      return list.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return EmployeeBirthdayChangeNotification(
          id: m['id']?.toString() ?? '',
          employeeName: m['employee_name']?.toString() ?? '—',
          previousBirthday: _parseDate(m['previous_birthday']?.toString()),
          newBirthday: _parseDate(m['new_birthday']?.toString()) ?? DateTime.now(),
          createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      devLog('Error loading birthday change notifications: $e');
      return [];
    }
  }

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Уведомления об удалении сотрудников (видят owner, executive_chef, sous_chef, bar_manager, floor_manager)
  Future<List<EmployeeDeletionNotification>> getDeletionNotifications(String establishmentId) async {
    try {
      final res = await _supabase.client
          .from('employee_deletion_notifications')
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false)
          .limit(100);
      final list = res as List<dynamic>? ?? [];
      return list.map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        return EmployeeDeletionNotification(
          id: m['id']?.toString() ?? '',
          deletedEmployeeName: m['deleted_employee_name']?.toString() ?? '—',
          deletedEmployeeEmail: m['deleted_employee_email']?.toString(),
          deletedByName: m['deleted_by_name']?.toString() ?? '—',
          isSelfDeletion: m['is_self_deletion'] == true,
          createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      devLog('Error loading deletion notifications: $e');
      return [];
    }
  }
}

/// Уведомление об изменении дня рождения сотрудника
class EmployeeBirthdayChangeNotification {
  final String id;
  final String employeeName;
  final DateTime? previousBirthday;
  final DateTime newBirthday;
  final DateTime createdAt;

  EmployeeBirthdayChangeNotification({
    required this.id,
    required this.employeeName,
    this.previousBirthday,
    required this.newBirthday,
    required this.createdAt,
  });
}

/// Уведомление об удалении сотрудника
class EmployeeDeletionNotification {
  final String id;
  final String deletedEmployeeName;
  final String? deletedEmployeeEmail;
  final String deletedByName;
  final bool isSelfDeletion;
  final DateTime createdAt;

  EmployeeDeletionNotification({
    required this.id,
    required this.deletedEmployeeName,
    this.deletedEmployeeEmail,
    required this.deletedByName,
    required this.isSelfDeletion,
    required this.createdAt,
  });
}