import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис для работы с историей инвентаризаций
class InventoryHistoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Получить историю инвентаризаций для заведения
  Future<List<Map<String, dynamic>>> getInventoryHistory(String establishmentId, {
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    var query = _supabase
        .from('inventory_history')
        .select('*, employees(full_name)')
        .eq('establishment_id', establishmentId)
        .order('created_at', ascending: false);

    if (startDate != null) {
      query = query.gte('date', startDate.toIso8601String().split('T')[0]);
    }

    if (endDate != null) {
      query = query.lte('date', endDate.toIso8601String().split('T')[0]);
    }

    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query;
    return List<Map<String, dynamic>>.from(response);
  }

  /// Сохранить инвентаризацию в историю
  Future<void> saveInventoryToHistory({
    required String establishmentId,
    required String employeeId,
    required Map<String, dynamic> inventoryData,
    required DateTime date,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? notes,
  }) async {
    await _supabase.from('inventory_history').insert({
      'establishment_id': establishmentId,
      'employee_id': employeeId,
      'inventory_data': inventoryData,
      'date': date.toIso8601String().split('T')[0],
      'start_time': startTime != null ? '${startTime.hour}:${startTime.minute}' : null,
      'end_time': endTime != null ? '${endTime.hour}:${endTime.minute}' : null,
      'total_items': inventoryData['rows']?.length ?? 0,
      'notes': notes,
      'status': 'completed',
    });
  }

  /// Получить детали инвентаризации
  Future<Map<String, dynamic>?> getInventoryDetails(String inventoryId) async {
    final response = await _supabase
        .from('inventory_history')
        .select('*, employees(full_name)')
        .eq('id', inventoryId)
        .single();

    return response;
  }
}