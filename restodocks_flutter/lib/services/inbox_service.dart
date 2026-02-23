import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'services.dart';

/// Сервис для работы с документами во входящих
class InboxService {
  final SupabaseService _supabase;

  InboxService(this._supabase);

  /// Получить все документы во входящих для заведения
  Future<List<InboxDocument>> getInboxDocuments(String establishmentId) async {
    final documents = <InboxDocument>[];

    try {
      // Получить инвентаризации
      final inventories = await _getInventoryDocuments(establishmentId);
      documents.addAll(inventories);

      // Получить заказы продуктов
      final productOrders = await _getProductOrderDocuments(establishmentId);
      documents.addAll(productOrders);

      // Получить подтверждения смен
      final shiftConfirmations = await _getShiftConfirmationDocuments(establishmentId);
      documents.addAll(shiftConfirmations);

      // Сортировать по дате (новые сверху)
      documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return documents;
    } catch (e) {
      print('Error loading inbox documents: $e');
      return [];
    }
  }

  /// Получить документы инвентаризации
  Future<List<InboxDocument>> _getInventoryDocuments(String establishmentId) async {
    try {
      final response = await _supabase.client
          .from('inventory_history')
          .select('''
            id,
            created_at,
            employee_id,
            section,
            status,
            employees!inner(full_name),
            establishments!inner(id)
          ''')
          .eq('establishments.id', establishmentId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List).map((item) {
        final data = item as Map<String, dynamic>;
        final employee = data['employees'] as Map<String, dynamic>;
        final section = data['section'] as String? ?? 'general';

        return InboxDocument(
          id: 'inventory_${data['id']}',
          type: DocumentType.inventory,
          title: 'Инвентаризация ${data['created_at']}',
          description: 'Проведена инвентаризация в цехе ${section}',
          createdAt: DateTime.parse(data['created_at']),
          employeeId: data['employee_id'],
          employeeName: employee['full_name'] ?? 'Неизвестный',
          department: _mapSectionToDepartment(section),
          fileUrl: '/api/inventory/${data['id']}/download',
          metadata: {
            'inventoryId': data['id'],
            'section': section,
          },
        );
      }).toList();
    } catch (e) {
      print('Error loading inventory documents: $e');
      return [];
    }
  }

  /// Получить документы заказов продуктов
  Future<List<InboxDocument>> _getProductOrderDocuments(String establishmentId) async {
    try {
      final response = await _supabase.client
          .from('order_history')
          .select('''
            id,
            created_at,
            employee_id,
            supplier_name,
            status,
            total_amount,
            employees!inner(full_name),
            establishments!inner(id)
          ''')
          .eq('establishments.id', establishmentId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List).map((item) {
        final data = item as Map<String, dynamic>;
        final employee = data['employees'] as Map<String, dynamic>;

        return InboxDocument(
          id: 'order_${data['id']}',
          type: DocumentType.productOrder,
          title: 'Заказ от ${data['supplier_name'] ?? 'поставщика'}',
          description: 'Заказ на сумму ${data['total_amount'] ?? 0} ₽',
          createdAt: DateTime.parse(data['created_at']),
          employeeId: data['employee_id'],
          employeeName: employee['full_name'] ?? 'Неизвестный',
          department: 'management', // Заказы обычно делает менеджмент
          fileUrl: '/api/order/${data['id']}/download',
          metadata: {
            'orderId': data['id'],
            'supplierName': data['supplier_name'],
            'totalAmount': data['total_amount'],
          },
        );
      }).toList();
    } catch (e) {
      print('Error loading product order documents: $e');
      return [];
    }
  }

  /// Получить документы подтверждений смен
  Future<List<InboxDocument>> _getShiftConfirmationDocuments(String establishmentId) async {
    try {
      final response = await _supabase.client
          .from('shift_confirmations')
          .select('''
            id,
            created_at,
            employee_id,
            date,
            confirmed,
            employees!inner(full_name, department),
            establishments!inner(id)
          ''')
          .eq('establishments.id', establishmentId)
          .eq('confirmed', true)
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List).map((item) {
        final data = item as Map<String, dynamic>;
        final employee = data['employees'] as Map<String, dynamic>;

        return InboxDocument(
          id: 'shift_${data['id']}',
          type: DocumentType.shiftConfirmation,
          title: 'Подтверждение смены ${data['date']}',
          description: 'Смена подтверждена сотрудником',
          createdAt: DateTime.parse(data['created_at']),
          employeeId: data['employee_id'],
          employeeName: employee['full_name'] ?? 'Неизвестный',
          department: employee['department'] ?? 'general',
          fileUrl: '/api/shift/${data['id']}/download',
          metadata: {
            'shiftId': data['id'],
            'date': data['date'],
            'confirmed': data['confirmed'],
          },
        );
      }).toList();
    } catch (e) {
      print('Error loading shift confirmation documents: $e');
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