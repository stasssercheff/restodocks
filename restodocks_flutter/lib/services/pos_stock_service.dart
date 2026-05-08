import '../models/models.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';
import 'system_error_service.dart';
import 'tech_card_service_supabase.dart';

/// Склад заведения: списание по ТТК при оплате счёта POS.
class PosStockService {
  PosStockService._();
  static final PosStockService instance = PosStockService._();

  final SupabaseService _supabase = SupabaseService();
  final TechCardServiceSupabase _techCards = TechCardServiceSupabase();

  void _applyBarModifiersStockDelta(
    PosOrderLine line,
    Map<String, double> merged,
  ) {
    if (line.barModifiers.isEmpty) return;
    for (final mod in line.barModifiers) {
      final raw = mod['stock_delta'];
      if (raw is! List) continue;
      for (final d in raw) {
        if (d is! Map) continue;
        final item = Map<String, dynamic>.from(d);
        final productId = (item['product_id'] ?? '').toString().trim();
        if (productId.isEmpty) continue;
        final gramsRaw = item['delta_net_grams'];
        if (gramsRaw is! num) continue;
        // delta_net_grams > 0 => дополнительный расход; < 0 => меньше базового расхода.
        final delta = -(gramsRaw.toDouble() * line.quantity);
        if (delta == 0) continue;
        merged[productId] = (merged[productId] ?? 0) + delta;
      }
    }
  }

  /// После закрытия счёта: списываем ингредиенты с привязкой к продукту (`product_id`).
  /// Дельты по одной паре (строка счёта × продукт) суммируются — одна запись в БД.
  Future<void> applySaleDeductionForOrder({
    required String establishmentId,
    required String orderId,
    required List<PosOrderLine> lines,
    String? diningTableId,
    String? closedByEmployeeId,
  }) async {
    if (lines.isEmpty) return;
    for (final line in lines) {
      try {
        final tc = await _techCards.getTechCardById(line.techCardId,
            preferCache: false);
        if (tc == null) {
          await SystemErrorService.instance.insert(
            establishmentId: establishmentId,
            message: 'pos_stock: tech_card missing ${line.techCardId}',
            severity: 'warning',
            source: 'pos_stock',
            context: {
              'orderId': orderId,
              'techCardId': line.techCardId,
              'lineId': line.id
            },
            employeeId: closedByEmployeeId,
            posOrderId: orderId,
            posOrderLineId: line.id,
            diningTableId: diningTableId,
          );
          continue;
        }
        final yieldG = tc.yieldValue;
        if (yieldG <= 0) continue;
        final soldDishGrams = line.quantity * tc.portionWeight;
        if (soldDishGrams <= 0) continue;
        final factor = soldDishGrams / yieldG;
        final merged = <String, double>{};
        for (final ing in tc.ingredients) {
          if (ing.sourceTechCardId != null &&
              ing.sourceTechCardId!.isNotEmpty) {
            continue;
          }
          final pid = ing.productId;
          if (pid == null || pid.isEmpty) continue;
          final delta = -(ing.netWeight * factor);
          if (delta == 0) continue;
          merged[pid] = (merged[pid] ?? 0) + delta;
        }
        _applyBarModifiersStockDelta(line, merged);
        for (final e in merged.entries) {
          final pid = e.key;
          final delta = e.value;
          try {
            await _supabase.client.rpc(
              'apply_establishment_stock_delta',
              params: {
                'p_establishment_id': establishmentId,
                'p_product_id': pid,
                'p_delta_grams': delta,
                'p_reason': 'pos_sale',
                'p_pos_order_id': orderId,
                'p_pos_order_line_id': line.id,
              },
            );
          } catch (err, st) {
            devLog('PosStockService: rpc $err $st');
            await SystemErrorService.instance.insert(
              establishmentId: establishmentId,
              message: 'pos_stock apply_establishment_stock_delta: $err',
              severity: 'error',
              source: 'pos_stock',
              context: {
                'orderId': orderId,
                'lineId': line.id,
                'productId': pid,
                'delta': delta,
              },
              employeeId: closedByEmployeeId,
              posOrderId: orderId,
              posOrderLineId: line.id,
              diningTableId: diningTableId,
            );
          }
        }
      } catch (e, st) {
        devLog('PosStockService: line ${line.id} $e $st');
        await SystemErrorService.instance.insert(
          establishmentId: establishmentId,
          message: 'pos_stock line: $e',
          severity: 'error',
          source: 'pos_stock',
          context: {'orderId': orderId, 'lineId': line.id},
          employeeId: closedByEmployeeId,
          posOrderId: orderId,
          posOrderLineId: line.id,
          diningTableId: diningTableId,
        );
      }
    }
  }

  Future<List<({String productId, double quantityGrams, DateTime updatedAt})>>
      fetchBalances(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('establishment_stock_balances')
          .select('product_id, quantity_grams, updated_at')
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);
      final out =
          <({String productId, double quantityGrams, DateTime updatedAt})>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        final pid = row['product_id'] as String?;
        if (pid == null) continue;
        out.add((
          productId: pid,
          quantityGrams: (row['quantity_grams'] as num).toDouble(),
          updatedAt: DateTime.parse(row['updated_at'] as String),
        ));
      }
      return out;
    } catch (e, st) {
      devLog('PosStockService: fetchBalances $e $st');
      rethrow;
    }
  }

  Future<
      List<
          ({
            DateTime createdAt,
            String productId,
            double deltaGrams,
            String reason
          })>> fetchMovements({
    required String establishmentId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 500,
  }) async {
    try {
      final rows = await _supabase.client
          .from('establishment_stock_movements')
          .select('product_id, delta_grams, reason, created_at')
          .eq('establishment_id', establishmentId)
          .gte('created_at', fromUtc.toUtc().toIso8601String())
          .lte('created_at', toUtc.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);
      final out = <({
        DateTime createdAt,
        String productId,
        double deltaGrams,
        String reason
      })>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        out.add((
          createdAt: DateTime.parse(row['created_at'] as String),
          productId: row['product_id'] as String,
          deltaGrams: (row['delta_grams'] as num).toDouble(),
          reason: row['reason'] as String? ?? '',
        ));
      }
      return out;
    } catch (e, st) {
      devLog('PosStockService: fetchMovements $e $st');
      rethrow;
    }
  }

  /// Сверка: сумма движений vs остаток по каждому продукту (расхождения — дрейф данных).
  Future<List<Map<String, dynamic>>> runWarehouseHealthCheck(
      String establishmentId) async {
    final raw = await _supabase.client.rpc('warehouse_health_check',
        params: {'p_establishment_id': establishmentId});
    if (raw == null) return [];
    final list = raw as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Приход на склад по факту получения из списка заказа (`reason` = import).
  Future<void> applyImportDelta({
    required String establishmentId,
    required String productId,
    required double deltaGrams,
  }) async {
    if (deltaGrams == 0) return;
    try {
      await _supabase.client.rpc(
        'apply_establishment_stock_delta',
        params: {
          'p_establishment_id': establishmentId,
          'p_product_id': productId,
          'p_delta_grams': deltaGrams,
          'p_reason': 'import',
          'p_pos_order_id': null,
          'p_pos_order_line_id': null,
        },
      );
    } catch (err, st) {
      devLog('PosStockService: import rpc $err $st');
      await SystemErrorService.instance.insert(
        establishmentId: establishmentId,
        message: 'pos_stock import apply_establishment_stock_delta: $err',
        severity: 'error',
        source: 'pos_stock',
        context: {'productId': productId, 'deltaGrams': deltaGrams},
      );
      rethrow;
    }
  }

  /// Ручная корректировка остатка (инвентаризация, порча, пересорт).
  Future<void> applyAdjustmentDelta({
    required String establishmentId,
    required String productId,
    required double deltaGrams,
  }) async {
    if (deltaGrams == 0) return;
    try {
      await _supabase.client.rpc(
        'apply_establishment_stock_delta',
        params: {
          'p_establishment_id': establishmentId,
          'p_product_id': productId,
          'p_delta_grams': deltaGrams,
          'p_reason': 'adjustment',
          'p_pos_order_id': null,
          'p_pos_order_line_id': null,
        },
      );
    } catch (err, st) {
      devLog('PosStockService: adjustment rpc $err $st');
      await SystemErrorService.instance.insert(
        establishmentId: establishmentId,
        message: 'pos_stock adjustment apply_establishment_stock_delta: $err',
        severity: 'error',
        source: 'pos_stock',
        context: {'productId': productId, 'deltaGrams': deltaGrams},
      );
      rethrow;
    }
  }

  /// Сводка за период: приход, расход POS, ручные корректировки (все в граммах; расход — модуль).
  Future<
      Map<
          String,
          ({
            double importGrams,
            double saleGrams,
            double adjustmentGrams,
          })>> aggregateStockReconciliation({
    required String establishmentId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    final movements = await fetchMovements(
      establishmentId: establishmentId,
      fromUtc: fromUtc,
      toUtc: toUtc,
      limit: 20000,
    );
    final acc = <String, ({double i, double s, double a})>{};
    for (final m in movements) {
      final cur = acc[m.productId] ?? (i: 0, s: 0, a: 0);
      if (m.reason == 'import') {
        acc[m.productId] = (i: cur.i + m.deltaGrams, s: cur.s, a: cur.a);
      } else if (m.reason == 'pos_sale') {
        acc[m.productId] = (
          i: cur.i,
          s: cur.s + m.deltaGrams.abs(),
          a: cur.a,
        );
      } else if (m.reason == 'adjustment') {
        acc[m.productId] = (
          i: cur.i,
          s: cur.s,
          a: cur.a + m.deltaGrams,
        );
      }
    }
    return acc.map(
      (k, v) => MapEntry(
        k,
        (
          importGrams: v.i,
          saleGrams: v.s,
          adjustmentGrams: v.a,
        ),
      ),
    );
  }
}
