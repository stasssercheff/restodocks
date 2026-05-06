import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'supabase_service.dart';

/// Снимок заказов для гостевого KDS (anon + RPC по токену).
@immutable
class KdsGuestOrderRow {
  const KdsGuestOrderRow({
    required this.order,
    required this.lines,
    required this.bucket,
    required this.grandDue,
    required this.menuDuePartial,
    required this.menuSubtotalRaw,
  });

  final PosOrder order;
  final List<PosOrderLine> lines;
  final String bucket;
  final double grandDue;
  final bool menuDuePartial;
  final double menuSubtotalRaw;

  static KdsGuestOrderRow fromRpcJson(Map<String, dynamic> m) {
    final om = Map<String, dynamic>.from(m['order'] as Map);
    final order = PosOrder.fromJson(om);
    final linesRaw = m['lines'] as List<dynamic>? ?? const [];
    final lines = linesRaw
        .map((e) => PosOrderLine.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return KdsGuestOrderRow(
      order: order,
      lines: lines,
      bucket: (m['bucket'] as String?) ?? 'active',
      grandDue: (m['grand_due'] as num?)?.toDouble() ?? 0,
      menuDuePartial: m['menu_due_partial'] == true,
      menuSubtotalRaw: (m['menu_subtotal_raw'] as num?)?.toDouble() ?? 0,
    );
  }
}

@immutable
class KdsGuestSnapshot {
  const KdsGuestSnapshot({
    required this.ok,
    this.errorCode,
    required this.shiftRequired,
    required this.shiftOpen,
    required this.department,
    required this.rows,
  });

  final bool ok;
  final String? errorCode;
  final bool shiftRequired;
  final bool shiftOpen;
  final String department;
  final List<KdsGuestOrderRow> rows;

  List<KdsGuestOrderRow> sortedForList() {
    final a = rows.where((r) => r.bucket == 'active').toList();
    final s = rows.where((r) => r.bucket == 'served').toList();
    return [...a, ...s];
  }
}

/// Вызовы `pos_kds_*` без авторизации сотрудника.
class PosKdsGuestService {
  PosKdsGuestService._();
  static final PosKdsGuestService instance = PosKdsGuestService._();

  final SupabaseService _sb = SupabaseService();

  Future<KdsGuestSnapshot> fetchOrders({
    required String token,
    required String department,
  }) async {
    final d = department.trim().toLowerCase();
    final raw = await _sb.client.rpc(
      'pos_kds_fetch_orders',
      params: {'p_token': token, 'p_department': d},
    );
    if (raw is! Map<String, dynamic>) {
      return KdsGuestSnapshot(
        ok: false,
        errorCode: 'rpc_format',
        shiftRequired: true,
        shiftOpen: false,
        department: d,
        rows: const [],
      );
    }
    final m = Map<String, dynamic>.from(raw);
    final ok = m['ok'] == true;
    if (!ok) {
      return KdsGuestSnapshot(
        ok: false,
        errorCode: m['error'] as String? ?? 'unknown',
        shiftRequired: false,
        shiftOpen: false,
        department: d,
        rows: const [],
      );
    }
    final ordRaw = m['orders'];
    final list = ordRaw is List<dynamic> ? ordRaw : const <dynamic>[];
    final rows = <KdsGuestOrderRow>[];
    for (final item in list) {
      if (item is! Map) continue;
      rows.add(KdsGuestOrderRow.fromRpcJson(Map<String, dynamic>.from(item)));
    }
    return KdsGuestSnapshot(
      ok: true,
      shiftRequired: m['shift_required'] == true,
      shiftOpen: m['shift_open'] == true,
      department: (m['department'] as String?) ?? d,
      rows: rows,
    );
  }

  Future<bool> markLineServed({
    required String token,
    required String department,
    required String orderId,
    required String lineId,
  }) async {
    final d = department.trim().toLowerCase();
    final raw = await _sb.client.rpc(
      'pos_kds_mark_line_served',
      params: {
        'p_token': token,
        'p_department': d,
        'p_order_id': orderId,
        'p_line_id': lineId,
      },
    );
    if (raw is! Map) return false;
    return Map<String, dynamic>.from(raw)['ok'] == true;
  }

  Future<Map<String, dynamic>?> techCardPreview({
    required String token,
    required String department,
    required String techCardId,
  }) async {
    final d = department.trim().toLowerCase();
    final raw = await _sb.client.rpc(
      'pos_kds_tech_card_preview',
      params: {
        'p_token': token,
        'p_department': d,
        'p_tech_card_id': techCardId,
      },
    );
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if (m['ok'] != true) return null;
    final tc = m['tech_card'];
    if (tc is Map<String, dynamic>) return tc;
    if (tc is Map) return Map<String, dynamic>.from(tc);
    return null;
  }
}
