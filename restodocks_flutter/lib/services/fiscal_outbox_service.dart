import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

  /// После первой ошибки «таблицы нет / не в schema cache» не дёргаем [fiscal_outbox] до перезагрузки
  /// (иначе повторяющиеся 404 в консоли браузера на окружениях без миграции).
  bool _outboxUnavailable = false;

  static bool _looksLikeFiscalOutboxUnavailable(Object e) {
    if (e is PostgrestException) {
      final blob =
          '${e.code ?? ''} ${e.message} ${e.details ?? ''} ${e.hint ?? ''}'
              .toLowerCase();
      if (blob.contains('fiscal_outbox')) return true;
      final code = e.code ?? '';
      if (code == 'PGRST205' || code == '42P01') {
        if (blob.contains('schema cache') ||
            blob.contains('does not exist') ||
            blob.contains('could not find the table')) {
          return true;
        }
      }
    }
    final s = e.toString().toLowerCase();
    return s.contains('fiscal_outbox') &&
        (s.contains('404') ||
            s.contains('not found') ||
            s.contains('does not exist') ||
            s.contains('schema cache') ||
            s.contains('pgrst205'));
  }

  void _rememberOutboxUnavailable(Object e) {
    if (_looksLikeFiscalOutboxUnavailable(e)) {
      _outboxUnavailable = true;
    }
  }

  /// Идемпотентная постановка: повтор с тем же [clientRequestId] не создаст дубликат (UNIQUE).
  Future<void> enqueueSale({
    required String establishmentId,
    String? posOrderId,
    required Map<String, dynamic> payload,
    String? clientRequestId,
  }) async {
    if (_outboxUnavailable) return;
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
      _rememberOutboxUnavailable(e);
      if (_outboxUnavailable) return;
      devLog('FiscalOutboxService: enqueueSale $e $st');
      rethrow;
    }
  }

  Future<int> countPending(String establishmentId) async {
    if (_outboxUnavailable) return 0;
    try {
      final rows = await _supabase.client
          .from(_table)
          .select('id')
          .eq('establishment_id', establishmentId)
          .eq('status', 'pending');
      return (rows as List).length;
    } catch (e, st) {
      _rememberOutboxUnavailable(e);
      if (!_outboxUnavailable) {
        devLog('FiscalOutboxService: countPending $e $st');
      }
      return 0;
    }
  }

  /// Последние записи очереди (новые сверху).
  Future<List<FiscalOutboxEntry>> fetchRecent(
    String establishmentId, {
    int limit = 100,
  }) async {
    if (_outboxUnavailable) return [];
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
      _rememberOutboxUnavailable(e);
      if (_outboxUnavailable) return [];
      devLog('FiscalOutboxService: fetchRecent $e $st');
      rethrow;
    }
  }

  /// Снять с очереди запись со статусом `failed` (вручную, до появления драйвера ККТ).
  Future<void> markSkipped(String rowId) async {
    if (_outboxUnavailable) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.client.from(_table).update({
      'status': 'skipped',
      'updated_at': now,
    }).eq('id', rowId).eq('status', 'failed');
  }
}
