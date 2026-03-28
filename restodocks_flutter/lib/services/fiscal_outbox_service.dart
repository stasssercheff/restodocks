import 'package:uuid/uuid.dart';

import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Очередь исходящих фискальных операций (до интеграции с ККТ).
class FiscalOutboxService {
  FiscalOutboxService._();
  static final FiscalOutboxService instance = FiscalOutboxService._();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'fiscal_outbox';
  static const _uuid = Uuid();

  /// Идемпотентная постановка: повтор с тем же [clientRequestId] не создаст дубликат (UNIQUE).
  Future<void> enqueueSale({
    required String establishmentId,
    String? posOrderId,
    required Map<String, dynamic> payload,
    String? clientRequestId,
  }) async {
    final cid = clientRequestId ?? _uuid.v4();
    try {
      await _supabase.client.from(_table).insert({
        'establishment_id': establishmentId,
        if (posOrderId != null) 'pos_order_id': posOrderId,
        'operation': 'sale',
        'status': 'pending',
        'client_request_id': cid,
        'payload': payload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e, st) {
      devLog('FiscalOutboxService: enqueueSale $e $st');
      rethrow;
    }
  }

  Future<int> countPending(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from(_table)
          .select('id')
          .eq('establishment_id', establishmentId)
          .eq('status', 'pending');
      return (rows as List).length;
    } catch (e, st) {
      devLog('FiscalOutboxService: countPending $e $st');
      return 0;
    }
  }
}
