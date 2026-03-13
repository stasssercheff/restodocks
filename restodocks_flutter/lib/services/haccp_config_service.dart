import 'package:flutter/foundation.dart';

import '../models/haccp_log_type.dart';
import 'supabase_service.dart';

/// Сервис настроек журналов ХАССП для заведения.
/// Владелец/управление выбирают галочками, какие журналы включены.
class HaccpConfigService extends ChangeNotifier {
  static final HaccpConfigService _instance = HaccpConfigService._internal();
  factory HaccpConfigService() => _instance;
  HaccpConfigService._internal();

  final SupabaseService _supabase = SupabaseService();

  /// Кэш: establishmentId -> Set<logType.code>
  final Map<String, Set<String>> _cache = {};

  /// Получить включённые типы журналов для заведения.
  Set<String> getEnabledLogTypes(String establishmentId) {
    return Set<String>.from(_cache[establishmentId] ?? {});
  }

  /// Проверить, включён ли журнал.
  bool isEnabled(String establishmentId, HaccpLogType logType) {
    return getEnabledLogTypes(establishmentId).contains(logType.code);
  }

  /// Загрузить настройки из Supabase.
  Future<void> load(String establishmentId) async {
    try {
      final row = await _supabase.client
          .from('establishment_haccp_config')
          .select('enabled_log_types')
          .eq('establishment_id', establishmentId)
          .maybeSingle();

      if (row != null && row['enabled_log_types'] != null) {
        final list = row['enabled_log_types'] as List<dynamic>?;
        _cache[establishmentId] = list
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toSet() ??
            {};
      } else {
        _cache[establishmentId] = {};
      }
      notifyListeners();
    } catch (_) {
      _cache[establishmentId] = {};
      notifyListeners();
    }
  }

  /// Сохранить настройки (массив кодов).
  Future<void> save(String establishmentId, Set<String> enabledLogTypes) async {
    final list = enabledLogTypes.toList()..sort();
    await _supabase.client.from('establishment_haccp_config').upsert(
          {
            'establishment_id': establishmentId,
            'enabled_log_types': list,
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'establishment_id',
        );
    _cache[establishmentId] = Set.from(list);
    notifyListeners();
  }

  /// Включить/выключить журнал.
  Future<void> setEnabled(String establishmentId, HaccpLogType logType, bool enabled) async {
    final current = getEnabledLogTypes(establishmentId);
    if (enabled) {
      current.add(logType.code);
    } else {
      current.remove(logType.code);
    }
    await save(establishmentId, current);
  }

  /// Список включённых журналов в порядке групп.
  List<HaccpLogType> getEnabledJournalsOrdered(String establishmentId) {
    final enabled = getEnabledLogTypes(establishmentId);
    return HaccpLogType.values.where((t) => enabled.contains(t.code)).toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        if (g != 0) return g;
        return a.displayNameRu.compareTo(b.displayNameRu);
      });
  }
}
