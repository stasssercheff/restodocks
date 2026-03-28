import '../models/pos_order.dart';
import '../models/pos_order_line.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Правка заказа недоступна (не черновик).
class PosOrderNotEditableException implements Exception {
  PosOrderNotEditableException();
}

/// Заказы зала (pos_orders).
class PosOrderService {
  PosOrderService._();
  static final PosOrderService instance = PosOrderService._();

  final SupabaseService _supabase = SupabaseService();

  static const _lineSelect = 'id, order_id, tech_card_id, quantity, comment, '
      'course_number, guest_number, sort_order, created_at, updated_at, '
      'tech_cards(dish_name, dish_name_localized, selling_price, department)';

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

  Future<void> deleteLine(String lineId, String orderId) async {
    await _requireDraft(orderId);
    await _supabase.client.from('pos_order_lines').delete().eq('id', lineId);
    await _touchOrderUpdated(orderId);
  }

  Future<List<PosOrder>> fetchActiveOrders(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            'id, establishment_id, dining_table_id, status, guest_count, created_at, updated_at, pos_dining_tables(table_number, floor_name, room_name)',
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

  Future<PosOrder?> fetchById(String orderId) async {
    try {
      final rows = await _supabase.client
          .from('pos_orders')
          .select(
            'id, establishment_id, dining_table_id, status, guest_count, created_at, updated_at, pos_dining_tables(table_number, floor_name, room_name)',
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
    final row = await _supabase.client
        .from('pos_orders')
        .insert({
          'establishment_id': establishmentId,
          'dining_table_id': diningTableId,
          'guest_count': guestCount,
          'status': PosOrderStatus.draft.toApi(),
        })
        .select(
          'id, establishment_id, dining_table_id, status, guest_count, created_at, updated_at, pos_dining_tables(table_number, floor_name, room_name)',
        )
        .single();
    return PosOrder.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateGuestCount(String orderId, int guestCount) async {
    if (guestCount < 1) return;
    await _supabase.client.from('pos_orders').update({
      'guest_count': guestCount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', orderId);
  }
}
