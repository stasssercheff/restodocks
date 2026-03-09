import 'supabase_service.dart';

/// Stop-list / Go-list: статус блюд в меню кухни и бара.
/// Ключ: 'techCardId_department' (например 'uuid_kitchen'), значение: 'stop' | 'go'.
class MenuStopGoService {
  static final MenuStopGoService _instance = MenuStopGoService._internal();
  factory MenuStopGoService() => _instance;
  MenuStopGoService._internal();

  final SupabaseService _supabase = SupabaseService();

  static String _key(String techCardId, String department) => '${techCardId}_$department';

  /// Загрузить все статусы stop/go для заведения.
  /// Возвращает Map: ключ 'techCardId_department', значение 'stop' | 'go'.
  Future<Map<String, String>> loadStopGoMap(String establishmentId) async {
    try {
      final res = await _supabase.client
          .from('menu_stop_go')
          .select('tech_card_id, department, status')
          .eq('establishment_id', establishmentId);
      final list = res as List<dynamic>;
      final map = <String, String>{};
      for (final row in list) {
        final m = row as Map<String, dynamic>;
        final tcId = m['tech_card_id'] as String?;
        final dept = m['department'] as String?;
        final status = m['status'] as String?;
        if (tcId != null && dept != null && status != null) {
          map[_key(tcId, dept)] = status;
        }
      }
      return map;
    } catch (e) {
      // Таблица может отсутствовать до применения миграции
      return {};
    }
  }

  /// Получить статус для блюда и подразделения.
  String? getStatus(Map<String, String> stopGoMap, String techCardId, String department) {
    return stopGoMap[_key(techCardId, department)];
  }

  /// Установить или сбросить статус.
  /// [status] = 'stop' | 'go' | null (null = удалить запись).
  Future<void> setStatus({
    required String establishmentId,
    required String techCardId,
    required String department,
    String? status,
  }) async {
    if (department != 'kitchen' && department != 'bar') return;
    try {
      if (status == null || status.isEmpty) {
        await _supabase.client
            .from('menu_stop_go')
            .delete()
            .eq('establishment_id', establishmentId)
            .eq('tech_card_id', techCardId)
            .eq('department', department);
      } else if (status == 'stop' || status == 'go') {
        await _supabase.client.from('menu_stop_go').upsert({
          'establishment_id': establishmentId,
          'tech_card_id': techCardId,
          'department': department,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'establishment_id,tech_card_id,department');
      }
    } catch (e) {
      rethrow;
    }
  }
}
