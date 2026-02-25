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
        return documents;
      }

      for (final doc in rawList) {
        final payload = doc['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final dateStr = header['date']?.toString() ?? '';
        final employeeName = header['employeeName']?.toString() ?? '—';
        final createdAt = doc['created_at'] != null
            ? DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now()
            : DateTime.now();

        documents.add(InboxDocument(
          id: doc['id']?.toString() ?? '',
          type: DocumentType.inventory,
          title: 'Инвентаризация $dateStr',
          description: employeeName,
          createdAt: createdAt,
          employeeId: doc['created_by_employee_id']?.toString() ?? '',
          employeeName: employeeName,
          department: _mapSectionToDepartment(currentEmployee.department),
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