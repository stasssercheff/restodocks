import 'package:uuid/uuid.dart';

import '../models/fiscal_outbox_entry.dart';
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

  /// Последние записи очереди (новые сверху).
  Future<List<FiscalOutboxEntry>> fetchRecent(
    String establishmentId, {
    int limit = 100,
  }) async {
    try {
      final rows = await _supabase.client
          .from(_table)
          .select(
            'id, pos_order_id, operation, status, error_message, created_at, updated_at, payload',
          )
          .eq('establishment_id', establishmentId)
          .order('created_at', ascending: false)
          .limit(limit.clamp(1, 500));

      final out = <FiscalOutboxEntry>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          out.add(FiscalOutboxEntry.fromJson(Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('FiscalOutboxService: skip row $e');
        }
      }
      return out;
    } catch (e, st) {
      devLog('FiscalOutboxService: fetchRecent $e $st');
      rethrow;
    }
  }

  /// Снять с очереди запись со статусом `failed` (вручную, до появления драйвера ККТ).
  Future<void> markSkipped(String rowId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.client.from(_table).update({
      'status': 'skipped',
      'updated_at': now,
    }).eq('id', rowId).eq('status', 'failed');
  }
}
