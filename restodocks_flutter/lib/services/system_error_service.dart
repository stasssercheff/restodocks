import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Запись критических ошибок в `system_errors` (Supabase).
class SystemErrorService {
  SystemErrorService._();
  static final SystemErrorService instance = SystemErrorService._();

  final SupabaseService _supabase = SupabaseService();

  Future<void> insert({
    required String establishmentId,
    required String message,
    String severity = 'error',
    String source = 'client',
    Map<String, dynamic>? context,
    String? employeeId,
    String? posOrderId,
    String? posOrderLineId,
    String? diningTableId,
  }) async {
    try {
      await _supabase.client.from('system_errors').insert({
        'establishment_id': establishmentId,
        'severity': severity,
        'source': source,
        'message': message.length > 8000 ? message.substring(0, 8000) : message,
        'context': context ?? {},
        if (employeeId != null) 'employee_id': employeeId,
        if (posOrderId != null) 'pos_order_id': posOrderId,
        if (posOrderLineId != null) 'pos_order_line_id': posOrderLineId,
        if (diningTableId != null) 'dining_table_id': diningTableId,
      });
    } catch (e, st) {
      devLog('SystemErrorService: insert failed $e $st');
    }
  }

  /// Последние записи журнала по заведению (новые сверху).
  Future<List<Map<String, dynamic>>> listRecent({
    required String establishmentId,
    int limit = 200,
  }) async {
    final rows = await _supabase.client
        .from('system_errors')
        .select()
        .eq('establishment_id', establishmentId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }
}
