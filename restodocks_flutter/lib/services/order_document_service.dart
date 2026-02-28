import 'supabase_service.dart';

/// Документы заказов продуктов: сохранение во входящие (шефу и собственнику).
class OrderDocumentService {
  static final OrderDocumentService _instance = OrderDocumentService._internal();
  factory OrderDocumentService() => _instance;
  OrderDocumentService._internal();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'order_documents';

  /// Сохранить документ заказа через Edge Function — цены подставляются на сервере из establishment_products/products.
  Future<Map<String, dynamic>?> saveWithServerPrices({
    required String establishmentId,
    required String createdByEmployeeId,
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> items,
    String? comment,
    String? sourceLang,
  }) async {
    try {
      final body = <String, dynamic>{
        'establishmentId': establishmentId,
        'createdByEmployeeId': createdByEmployeeId,
        'header': header,
        'items': items.map((e) => {
          'productId': e['productId'],
          'productName': e['productName'],
          'unit': e['unit'],
          'quantity': e['quantity'],
        }).toList(),
        'comment': comment,
        if (sourceLang != null) 'sourceLang': sourceLang,
      };
      final res = await _supabase.client.functions.invoke('save-order-document', body: body);
      final data = res.data;
      if (res.status != 200 || data == null) {
        final err = data is Map ? (data['error'] ?? res.data) : res.data;
        print('Ошибка Edge Function save-order-document: $err');
        return null;
      }
      final ok = data is Map && data['ok'] == true;
      final id = data is Map ? data['id'] as String? : null;
      if (!ok || id == null) return null;
      return getById(id);
    } catch (e) {
      print('Ошибка сохранения документа заказа (Edge Function): $e');
      return null;
    }
  }

  /// Сохранить документ заказа с готовым payload (legacy, цены считаются на клиенте).
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
