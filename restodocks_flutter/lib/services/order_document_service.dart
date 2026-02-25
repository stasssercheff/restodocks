import 'supabase_service.dart';

/// Документы заказов продуктов: сохранение во входящие (шефу и собственнику).
class OrderDocumentService {
  static final OrderDocumentService _instance = OrderDocumentService._internal();
  factory OrderDocumentService() => _instance;
  OrderDocumentService._internal();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'order_documents';

  /// Сохранить документ заказа (после «Сохранить с количествами»).
  Future<Map<String, dynamic>?> save({
    required String establishmentId,
    required String createdByEmployeeId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final data = <String, dynamic>{
        'establishment_id': establishmentId,
        'created_by_employee_id': createdByEmployeeId,
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

  /// Список заказов по заведению (для входящих шефа и собственника), по дате.
  Future<List<Map<String, dynamic>>> listForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false);

      return (data as List).map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Ошибка загрузки документов заказов: $e');
      return [];
    }
  }

  /// Получить документ по id (просмотр во входящих).
  Future<Map<String, dynamic>?> getById(String id) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('id', id)
          .maybeSingle();
      return data != null ? Map<String, dynamic>.from(data as Map<String, dynamic>) : null;
    } catch (e) {
      print('Ошибка загрузки документа заказа: $e');
      return null;
    }
  }
}
