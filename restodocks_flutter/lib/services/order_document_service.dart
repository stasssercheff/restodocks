import 'supabase_service.dart';

/// Сервис документов заказов продуктов: сохранение в БД, кабинет шеф-повара.
class OrderDocumentService {
  static final OrderDocumentService _instance = OrderDocumentService._internal();
  factory OrderDocumentService() => _instance;
  OrderDocumentService._internal();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'order_documents';

  /// Сохранить документ заказа (после «Сохранить на устройство» / «Отправить»).
  Future<Map<String, dynamic>?> save({
    required String establishmentId,
    required String createdByEmployeeId,
    required String recipientChefId,
    required String recipientEmail,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final data = <String, dynamic>{
        'establishment_id': establishmentId,
        'created_by_employee_id': createdByEmployeeId,
        'recipient_chef_id': recipientChefId,
        'recipient_email': recipientEmail,
        'payload': payload,
      };
      final raw = await _supabase.client.from(_table).insert(data).select();
      final list = raw as List;
      if (list.isEmpty) return null;
      return Map<String, dynamic>.from(list.first as Map<String, dynamic>);
    } catch (e) {
      print('Ошибка сохранения документа заказа: $e');
      return null;
    }
  }

  /// Список документов заказов для кабинета шеф-повара.
  Future<List<Map<String, dynamic>>> listForChef(String recipientChefId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('recipient_chef_id', recipientChefId)
          .order('created_at', ascending: false);

      return (data as List).map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Ошибка загрузки документов заказов: $e');
      return [];
    }
  }
}
