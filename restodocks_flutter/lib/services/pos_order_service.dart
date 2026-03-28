import '../models/pos_order.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Заказы зала (pos_orders).
class PosOrderService {
  PosOrderService._();
  static final PosOrderService instance = PosOrderService._();

  final SupabaseService _supabase = SupabaseService();

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
        } catch (e, st) {
          devLog('PosOrderService: skip row $e $st');
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
