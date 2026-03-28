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
        } catch (e, st) {
          devLog('PosDiningLayoutService: skip row $e $st');
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
}
