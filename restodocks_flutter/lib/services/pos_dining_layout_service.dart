import '../models/pos_dining_table.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Загрузка раскладки столов зала (pos_dining_tables).
class PosDiningLayoutService {
  PosDiningLayoutService._();
  static final PosDiningLayoutService instance = PosDiningLayoutService._();

  final SupabaseService _supabase = SupabaseService();

  Future<List<PosDiningTable>> fetchTables(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('pos_dining_tables')
          .select()
          .eq('establishment_id', establishmentId);

      final list = <PosDiningTable>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map<String, dynamic>) continue;
        try {
          list.add(PosDiningTable.fromJson(Map<String, dynamic>.from(row)));
        } catch (e) {
          devLog('PosDiningLayoutService: skip row $e');
        }
      }
      list.sort((a, b) {
        final s = a.sortOrder.compareTo(b.sortOrder);
        if (s != 0) return s;
        return a.tableNumber.compareTo(b.tableNumber);
      });
      return list;
    } catch (e, st) {
      devLog('PosDiningLayoutService: fetchTables $e $st');
      rethrow;
    }
  }

  String? _nullIfEmpty(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<PosDiningTable> insertTable({
    required String establishmentId,
    String? floorName,
    String? roomName,
    required int tableNumber,
    int sortOrder = 0,
    PosTableStatus status = PosTableStatus.free,
  }) async {
    final payload = <String, dynamic>{
      'establishment_id': establishmentId,
      'floor_name': _nullIfEmpty(floorName),
      'room_name': _nullIfEmpty(roomName),
      'table_number': tableNumber,
      'sort_order': sortOrder,
      'status': status.toApi(),
    };
    final row = await _supabase.client
        .from('pos_dining_tables')
        .insert(payload)
        .select()
        .single();
    return PosDiningTable.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateTable(PosDiningTable table) async {
    await _supabase.client.from('pos_dining_tables').update({
      'floor_name': _nullIfEmpty(table.floorName),
      'room_name': _nullIfEmpty(table.roomName),
      'table_number': table.tableNumber,
      'sort_order': table.sortOrder,
      'status': table.status.toApi(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', table.id);
  }

  Future<void> updateTableStatus(String tableId, PosTableStatus status) async {
    await _supabase.client.from('pos_dining_tables').update({
      'status': status.toApi(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', tableId);
  }

  Future<void> deleteTable(String id) async {
    await _supabase.client.from('pos_dining_tables').delete().eq('id', id);
  }
}
