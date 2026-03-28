import '../models/pos_cash_register_row.dart';
import '../models/pos_dining_table.dart';
import '../models/pos_order.dart';
import '../models/pos_order_line.dart';
import '../utils/dev_log.dart';
import '../utils/pos_order_department.dart';
import 'pos_dining_layout_service.dart';
import 'supabase_service.dart';

/// Правка заказа недоступна (не черновик).
class PosOrderNotEditableException implements Exception {
  PosOrderNotEditableException();
}

/// Отправка заказа без позиций.
class PosOrderSubmitEmptyException implements Exception {
  PosOrderSubmitEmptyException();
}

/// На столе уже есть активный счёт.
class PosOrderTableBusyException implements Exception {
  PosOrderTableBusyException(this.existingOrder);
  final PosOrder existingOrder;
}

/// Отметить «отдано» можно только для отправленного заказа.
class PosOrderLineMarkServedException implements Exception {
  PosOrderLineMarkServedException();
}

/// Заказы подразделения: очередь и уже отданные по строкам.
class PosDepartmentOrderBuckets {
  const PosDepartmentOrderBuckets({
    required this.active,
    required this.served,
    this.menuDueByOrderId = const {},
    this.menuDuePartialOrderIds = const {},
  });

  final List<PosOrder> active;
  final List<PosOrder> served;

  /// Сумма по меню (quantity × selling_price) по id заказа — из того же запроса, что списки.
  final Map<String, double> menuDueByOrderId;

  /// Заказы, где у части строк нет цены в ТТК — сумма приблизительная.
  final Set<String> menuDuePartialOrderIds;
}

/// Заказы зала (pos_orders).
class PosOrderService {
  PosOrderService._();
  static final PosOrderService instance = PosOrderService._();

  final SupabaseService _supabase = SupabaseService();

  static const _lineSelect = 'id, order_id, tech_card_id, quantity, comment, '
      'course_number, guest_number, sort_order, created_at, updated_at, served_at, '
      'tech_cards(dish_name, dish_name_localized, selling_price, department, '
      'category, sections)';

  static const _orderSelectWithTable =
      'id, establishment_id, dining_table_id, status, guest_count, created_at, '
      'updated_at, payment_method, paid_at, '
      'pos_dining_tables(table_number, floor_name, room_name, status)';

  Future<void> _touchOrderUpdated(String orderId) async {
    await _supabase.client.from('pos_orders').update({
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  Future<void> _requireDraft(String orderId) async {
    final o = await fetchById(orderId);
    if (o == null) throw StateError('pos_order_missing');
    if (o.status != PosOrderStatus.draft) {
      throw PosOrderNotEditableException();
    }
  }

  Future<List<PosOrderLine>> fetchLines(String orderId) async {
    try {
      final rows = await _supabase.client
          .from('pos_order_lines')
          .select(_lineSelect)
          .eq('order_id', orderId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);

      final list = <PosOrderLine>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          list.add(PosOrderLine.fromJson(Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('PosOrderService: skip line $e');
        }
      }
      return list;
    } catch (e, st) {
      devLog('PosOrderService: fetchLines $e $st');
      rethrow;
    }
  }

  Future<PosOrderLine> addLine({
    required String orderId,
    required String techCardId,
    double quantity = 1,
    String? comment,
    int courseNumber = 1,
    int? guestNumber,
  }) async {
    if (quantity <= 0) throw ArgumentError.value(quantity, 'quantity');
    await _requireDraft(orderId);
    final maxRows = await _supabase.client
        .from('pos_order_lines')
        .select('sort_order')
        .eq('order_id', orderId)
        .order('sort_order', ascending: false)
        .limit(1);
    var nextSort = 0;
    final mr = maxRows as List<dynamic>;
    if (mr.isNotEmpty) {
      final m = mr.first as Map;
      nextSort = ((m['sort_order'] as num?)?.toInt() ?? 0) + 1;
    }
    final row = await _supabase.client.from('pos_order_lines').insert({
      'order_id': orderId,
      'tech_card_id': techCardId,
      'quantity': quantity,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      'course_number': courseNumber,
      if (guestNumber != null) 'guest_number': guestNumber,
      'sort_order': nextSort,
    }).select(_lineSelect).single();
    await _touchOrderUpdated(orderId);
    return PosOrderLine.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateLineQuantity(String lineId, String orderId, double quantity) async {
    if (quantity <= 0) return;
    await _requireDraft(orderId);
    await _supabase.client.from('pos_order_lines').update({
      'quantity': quantity,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lineId);
    await _touchOrderUpdated(orderId);
  }

  Future<void> updateLineComment(String lineId, String orderId, String? comment) async {
    await _requireDraft(orderId);
    await _supabase.client.from('pos_order_lines').update({
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lineId);
    await _touchOrderUpdated(orderId);
  }

  Future<void> updateLineCourseAndGuest(
    String lineId,
    String orderId, {
    required int courseNumber,
    int? guestNumber,
  }) async {
    if (courseNumber < 1) throw ArgumentError.value(courseNumber, 'courseNumber');
    await _requireDraft(orderId);
    await _supabase.client.from('pos_order_lines').update({
      'course_number': courseNumber,
      'guest_number': guestNumber,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lineId);
    await _touchOrderUpdated(orderId);
  }

  Future<void> deleteLine(String lineId, String orderId) async {
    await _requireDraft(orderId);
    await _supabase.client.from('pos_order_lines').delete().eq('id', lineId);
    await _touchOrderUpdated(orderId);
  }

  /// Отметить позицию отданной гостю (после отправки заказа на кухню/бар).
  Future<void> markLineServed(String lineId, String orderId) async {
    final o = await fetchById(orderId);
    if (o == null) throw StateError('pos_order_missing');
    if (o.status != PosOrderStatus.sent) {
      throw PosOrderLineMarkServedException();
    }
    await _supabase.client.from('pos_order_lines').update({
      'served_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', lineId).eq('order_id', orderId);
    await _touchOrderUpdated(orderId);
  }

  /// Черновик → отправлен (кухня/бар увидят по статусу и строкам). Без строк — ошибка.
  Future<void> submitOrder(String orderId) async {
    await _requireDraft(orderId);
    final lines = await fetchLines(orderId);
    if (lines.isEmpty) throw PosOrderSubmitEmptyException();
    await _supabase.client.from('pos_orders').update({
      'status': PosOrderStatus.sent.toApi(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Незакрытые заказы для экрана подразделения, разбитые на очередь и отданные.
  /// [routeDepartment] = kitchen | bar | hall.
  Future<PosDepartmentOrderBuckets> fetchDepartmentOrderBuckets(
    String establishmentId,
    String routeDepartment,
  ) async {
    var dept = routeDepartment;
    if (dept != 'kitchen' && dept != 'bar' && dept != 'hall') {
      dept = 'kitchen';
    }
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            '$_orderSelectWithTable, pos_order_lines(quantity, served_at, tech_cards(category, sections, selling_price))',
          )
          .eq('establishment_id', establishmentId)
          .neq('status', 'closed')
          .order('created_at', ascending: false);

      final active = <PosOrder>[];
      final served = <PosOrder>[];
      final menuDue = <String, double>{};
      final partialIds = <String>{};
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          final m = Map<String, dynamic>.from(row);
          final linesRaw = m['pos_order_lines'];
          m.remove('pos_order_lines');
          if (!_orderMatchesDepartment(linesRaw, dept)) continue;
          final o = PosOrder.fromJson(m);
          final (due, partial) = _menuDueFromLinesRaw(linesRaw);
          menuDue[o.id] = due;
          if (partial) partialIds.add(o.id);
          if (_allRelevantLinesServed(linesRaw, dept)) {
            served.add(o);
          } else {
            active.add(o);
          }
        } catch (e) {
          devLog('PosOrderService: skip order row $e');
        }
      }
      return PosDepartmentOrderBuckets(
        active: active,
        served: served,
        menuDueByOrderId: menuDue,
        menuDuePartialOrderIds: partialIds,
      );
    } catch (e, st) {
      devLog('PosOrderService: fetchDepartmentOrderBuckets $e $st');
      rethrow;
    }
  }

  bool _orderMatchesDepartment(dynamic linesRaw, String routeDepartment) {
    if (routeDepartment == 'hall') return true;
    final summaries = _parseLineCategorySections(linesRaw);
    if (summaries.isEmpty) return false;
    var hasBar = false;
    var hasKitchen = false;
    for (final s in summaries) {
      if (posLineIsBarDish(s.$1, s.$2)) {
        hasBar = true;
      } else {
        hasKitchen = true;
      }
    }
    if (routeDepartment == 'bar') return hasBar;
    if (routeDepartment == 'kitchen') return hasKitchen;
    return true;
  }

  List<(String, List<String>)> _parseLineCategorySections(dynamic linesRaw) {
    if (linesRaw is! List) return [];
    final out = <(String, List<String>)>[];
    for (final item in linesRaw) {
      if (item is! Map) continue;
      final line = Map<String, dynamic>.from(item);
      final tc = line['tech_cards'];
      Map<String, dynamic>? t;
      if (tc is Map<String, dynamic>) {
        t = tc;
      } else if (tc is List && tc.isNotEmpty && tc.first is Map) {
        t = Map<String, dynamic>.from(tc.first as Map);
      }
      if (t == null) continue;
      final cat = t['category'] as String? ?? '';
      final secRaw = t['sections'];
      final sections = secRaw is List
          ? secRaw.map((e) => e.toString()).toList()
          : <String>[];
      out.add((cat, sections));
    }
    return out;
  }

  /// По строкам подразделения: все отмечены «отдано».
  bool _allRelevantLinesServed(dynamic linesRaw, String routeDepartment) {
    final infos = _parseLineServeInfos(linesRaw);
    if (infos.isEmpty) return false;
    final relevant = infos.where((e) {
      final (isBar, _) = e;
      if (routeDepartment == 'hall') return true;
      if (routeDepartment == 'bar') return isBar;
      return !isBar;
    }).toList();
    if (relevant.isEmpty) return false;
    return relevant.every((e) => e.$2 != null);
  }

  List<(bool, DateTime?)> _parseLineServeInfos(dynamic linesRaw) {
    if (linesRaw is! List) return [];
    final out = <(bool, DateTime?)>[];
    for (final item in linesRaw) {
      if (item is! Map) continue;
      final line = Map<String, dynamic>.from(item);
      DateTime? servedAt;
      final servedRaw = line['served_at'];
      if (servedRaw != null) {
        servedAt = DateTime.tryParse(servedRaw.toString());
      }
      final tc = line['tech_cards'];
      Map<String, dynamic>? t;
      if (tc is Map<String, dynamic>) {
        t = tc;
      } else if (tc is List && tc.isNotEmpty && tc.first is Map) {
        t = Map<String, dynamic>.from(tc.first as Map);
      }
      if (t == null) continue;
      final cat = t['category'] as String? ?? '';
      final secRaw = t['sections'];
      final sections = secRaw is List
          ? secRaw.map((e) => e.toString()).toList()
          : <String>[];
      out.add((posLineIsBarDish(cat, sections), servedAt));
    }
    return out;
  }

  Future<List<PosOrder>> fetchActiveOrders(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            _orderSelectWithTable,
          )
          .eq('establishment_id', establishmentId)
          .neq('status', 'closed')
          .order('created_at', ascending: false);

      final list = <PosOrder>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          list.add(PosOrder.fromJson(Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('PosOrderService: skip row $e');
        }
      }
      return list;
    } catch (e, st) {
      devLog('PosOrderService: fetchActiveOrders $e $st');
      rethrow;
    }
  }

  /// Столы со статусом «счёт» — для экрана кассы (сумма по позициям × цена ТТК).
  Future<List<PosCashRegisterRow>> fetchCashRegisterRows(
    String establishmentId,
  ) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            '$_orderSelectWithTable, pos_order_lines(quantity, tech_cards(selling_price))',
          )
          .eq('establishment_id', establishmentId)
          .neq('status', 'closed')
          .order('updated_at', ascending: false);

      final out = <PosCashRegisterRow>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          final m = Map<String, dynamic>.from(row);
          final linesRaw = m['pos_order_lines'];
          m.remove('pos_order_lines');
          final o = PosOrder.fromJson(m);
          if (o.tableStatus != PosTableStatus.billRequested) continue;
          out.add(PosCashRegisterRow(
            order: o,
            totalDue: _sumLineTotals(linesRaw),
          ));
        } catch (e) {
          devLog('PosOrderService: skip cash row $e');
        }
      }
      return out;
    } catch (e, st) {
      devLog('PosOrderService: fetchCashRegisterRows $e $st');
      rethrow;
    }
  }

  double _sumLineTotals(dynamic linesRaw) {
    final (s, _) = _menuDueFromLinesRaw(linesRaw);
    return s;
  }

  /// Сумма по строкам; [partial] — есть строка без selling_price в ТТК.
  (double sum, bool partial) _menuDueFromLinesRaw(dynamic linesRaw) {
    if (linesRaw is! List) return (0.0, false);
    var s = 0.0;
    var partial = false;
    for (final item in linesRaw) {
      if (item is! Map) continue;
      final line = Map<String, dynamic>.from(item);
      final q = (line['quantity'] as num?)?.toDouble() ?? 0;
      final tc = line['tech_cards'];
      Map<String, dynamic>? t;
      if (tc is Map<String, dynamic>) {
        t = tc;
      } else if (tc is List && tc.isNotEmpty && tc.first is Map) {
        t = Map<String, dynamic>.from(tc.first as Map);
      }
      final priceRaw = t?['selling_price'];
      if (priceRaw == null) {
        partial = true;
        continue;
      }
      final price = (priceRaw as num).toDouble();
      s += q * price;
    }
    return (s, partial);
  }

  /// Один активный (не закрытый) заказ по столу, если есть.
  Future<PosOrder?> fetchActiveOrderForTable(
    String establishmentId,
    String diningTableId,
  ) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            _orderSelectWithTable,
          )
          .eq('establishment_id', establishmentId)
          .eq('dining_table_id', diningTableId)
          .neq('status', 'closed')
          .order('created_at', ascending: false)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      return PosOrder.fromJson(Map<String, dynamic>.from(list.first as Map));
    } catch (e, st) {
      devLog('PosOrderService: fetchActiveOrderForTable $e $st');
      rethrow;
    }
  }

  Future<PosOrder?> fetchById(String orderId) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            _orderSelectWithTable,
          )
          .eq('id', orderId)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      return PosOrder.fromJson(Map<String, dynamic>.from(list.first as Map));
    } catch (e, st) {
      devLog('PosOrderService: fetchById $e $st');
      rethrow;
    }
  }

  Future<PosOrder> createDraft({
    required String establishmentId,
    required String diningTableId,
    int guestCount = 1,
  }) async {
    final existing = await fetchActiveOrderForTable(establishmentId, diningTableId);
    if (existing != null) {
      throw PosOrderTableBusyException(existing);
    }
    final row = await _supabase.client
        .from('pos_orders')
        .insert({
          'establishment_id': establishmentId,
          'dining_table_id': diningTableId,
          'guest_count': guestCount,
          'status': PosOrderStatus.draft.toApi(),
        })
        .select(
          _orderSelectWithTable,
        )
        .single();
    try {
      await PosDiningLayoutService.instance
          .updateTableStatus(diningTableId, PosTableStatus.occupied);
    } catch (e, st) {
      devLog('PosOrderService: createDraft table status $e $st');
    }
    return PosOrder.fromJson(Map<String, dynamic>.from(row));
  }

  /// Гости просят счёт: стол в статусе «счёт» (касса / официант видят на плане).
  Future<void> markTableBillRequested(String orderId) async {
    final o = await fetchById(orderId);
    if (o == null) throw StateError('pos_order_missing');
    if (o.status == PosOrderStatus.closed) return;
    await PosDiningLayoutService.instance
        .updateTableStatus(o.diningTableId, PosTableStatus.billRequested);
  }

  /// Закрыть счёт: заказ закрыт, стол свободен; фиксируется способ оплаты и время.
  Future<void> closeOrder(
    String orderId, {
    required PosPaymentMethod paymentMethod,
  }) async {
    final o = await fetchById(orderId);
    if (o == null) throw StateError('pos_order_missing');
    if (o.status == PosOrderStatus.closed) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.client.from('pos_orders').update({
      'status': PosOrderStatus.closed.toApi(),
      'payment_method': paymentMethod.toApi(),
      'paid_at': now,
      'updated_at': now,
    }).eq('id', orderId);
    try {
      await PosDiningLayoutService.instance
          .updateTableStatus(o.diningTableId, PosTableStatus.free);
    } catch (e, st) {
      devLog('PosOrderService: closeOrder table free $e $st');
    }
  }

  Future<void> updateGuestCount(String orderId, int guestCount) async {
    if (guestCount < 1) return;
    await _supabase.client.from('pos_orders').update({
      'guest_count': guestCount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }
}
