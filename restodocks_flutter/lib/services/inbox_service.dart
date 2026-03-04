import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'services.dart';

/// Сервис для работы с документами во входящих (инвентаризации — шефу и собственнику).
class InboxService {
  final SupabaseService _supabase;

  InboxService(this._supabase);

  /// Получить документы во входящих: для шефа — полученные им инвентаризации, для собственника/управления — все по заведению.
  Future<List<InboxDocument>> getInboxDocuments(String establishmentId, Employee? currentEmployee) async {
    final documents = <InboxDocument>[];

    if (currentEmployee == null) return documents;

    try {
      final docService = InventoryDocumentService();
      List<Map<String, dynamic>> rawList;

      if (currentEmployee.hasRole('owner') || currentEmployee.department == 'management') {
        rawList = await docService.listForEstablishment(establishmentId);
      } else if (currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef')) {
        rawList = await docService.listForChef(currentEmployee.id);
      } else {
        rawList = [];
      }

      for (final doc in rawList) {
        final payload = doc['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final dateStr = header['date']?.toString() ?? '';
        final employeeName = header['employeeName']?.toString() ?? '—';
        final createdAt = doc['created_at'] != null
            ? (DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now()).toLocal()
            : DateTime.now();

        // Различаем обычную инвентаризацию и iiko по полю payload['type']
        final isIiko = payload['type'] == 'iiko_inventory';
        // iiko — всегда данные кухни, не показывать в баре/зале
        final docDept = isIiko ? 'kitchen' : (header['department']?.toString() ?? _mapSectionToDepartment(currentEmployee.department));
        documents.add(InboxDocument(
          id: doc['id']?.toString() ?? '',
          type: isIiko ? DocumentType.iikoInventory : DocumentType.inventory,
          title: isIiko ? 'Инвентаризация iiko $dateStr' : 'Инвентаризация $dateStr',
          description: employeeName,
          createdAt: createdAt,
          employeeId: doc['created_by_employee_id']?.toString() ?? '',
          employeeName: employeeName,
          department: docDept,
          fileUrl: null,
          metadata: payload,
        ));
      }

      // Отправленные чеклисты — для шефа и су-шефа
      if (currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef') ||
          currentEmployee.hasRole('owner') || currentEmployee.department == 'management') {
        final subSvc = ChecklistSubmissionService();
        final subList = currentEmployee.hasRole('owner') || currentEmployee.department == 'management'
            ? await subSvc.listForEstablishment(establishmentId)
            : await subSvc.listForChef(currentEmployee.id);
        for (final sub in subList) {
          final submittedName = sub.submittedByName.isNotEmpty ? sub.submittedByName : '—';
          final subDept = sub.payload['department']?.toString() ?? 'kitchen';
          documents.add(InboxDocument(
            id: sub.id,
            type: DocumentType.checklistSubmission,
            title: 'Чеклист: ${sub.checklistName}',
            description: '$submittedName${sub.section != null ? ' • ${sub.section}' : ''}',
            createdAt: sub.createdAt,
            employeeId: sub.submittedByEmployeeId ?? '',
            employeeName: submittedName,
            department: subDept,
            fileUrl: null,
            metadata: {'submission': sub.payload, 'checklistId': sub.checklistId},
          ));
        }
      }

      // Чеклисты с пропущенным дедлайном — для шефа, су-шефа и собственника
      if (currentEmployee.hasRole('executive_chef') || currentEmployee.hasRole('sous_chef') ||
          currentEmployee.hasRole('owner') || currentEmployee.department == 'management') {
        final checklistSvc = ChecklistServiceSupabase();
        final missed = await checklistSvc.getChecklistsWithMissedDeadline(establishmentId);
        for (final c in missed) {
          final deadlineStr = c.deadlineAt != null
              ? DateTime(c.deadlineAt!.year, c.deadlineAt!.month, c.deadlineAt!.day)
                  .toIso8601String()
              : '';
          documents.add(InboxDocument(
            id: c.id,
            type: DocumentType.checklistMissedDeadline,
            title: 'Чеклист не выполнен: ${c.name}',
            description: deadlineStr.isNotEmpty ? 'Срок: $deadlineStr' : '',
            createdAt: c.deadlineAt ?? c.updatedAt,
            employeeId: '',
            employeeName: '',
            department: c.assignedDepartment,
            fileUrl: null,
            metadata: {'checklistId': c.id, 'checklistName': c.name},
          ));
        }
      }

      // Заказы продуктов — для шефа и собственника по заведению
      final orderDocs = await OrderDocumentService().listForEstablishment(establishmentId);
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

      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return documents;
    } catch (e) {
      print('Error loading inbox documents: $e');
      return [];
    }
  }

  /// Маппинг секции на отдел
  String _mapSectionToDepartment(String section) {
    switch (section.toLowerCase()) {
      case 'hot_kitchen':
      case 'cold_kitchen':
      case 'confectionery':
        return 'kitchen';
      case 'bar':
        return 'bar';
      case 'hall':
      case 'service':
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
      print('Downloading document: ${document.title}');
      print('File URL: ${document.fileUrl}');

      // Можно добавить логику сохранения файла на устройство
      // используя packages как path_provider и http

    } catch (e) {
      print('Error downloading document: $e');
      rethrow;
    }
  }

  /// Получить документы по отделу
  List<InboxDocument> filterByDepartment(List<InboxDocument> documents, String department) {
    if (department == 'all') return documents;
    return documents.where((doc) => doc.department == department).toList();
  }
}