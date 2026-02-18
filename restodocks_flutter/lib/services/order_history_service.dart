import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис для работы с историей заказов
class OrderHistoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Получить историю заказов для заведения
  Future<List<Map<String, dynamic>>> getOrderHistory(String establishmentId, {
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    var query = _supabase
        .from('order_history')
        .select('*, employees(full_name)')
        .eq('establishment_id', establishmentId);

    if (startDate != null) {
      query = query.filter('created_at', 'gte', startDate.toUtc().toIso8601String());
    }

    if (endDate != null) {
      query = query.filter('created_at', 'lte', endDate.toUtc().toIso8601String());
    }

    if (status != null) {
      query = query.filter('status', 'eq', status);
    }

    query = query.order('created_at', ascending: false);

    final response = await query;
    return List<Map<String, dynamic>>.from(response);
  }

  /// Сохранить заказ в историю
  Future<void> saveOrderToHistory({
    required String establishmentId,
    required String employeeId,
    required Map<String, dynamic> orderData,
  }) async {
    await _supabase.from('order_history').insert({
      'establishment_id': establishmentId,
      'employee_id': employeeId,
      'order_data': orderData,
      'status': 'sent',
    });
  }

  /// Обновить статус заказа
  Future<void> updateOrderStatus(String orderId, String status) async {
    await _supabase
        .from('order_history')
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', orderId);
  }
}