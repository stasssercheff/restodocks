import 'package:flutter/foundation.dart';

import '../haccp/haccp_country_profile.dart';
import '../models/establishment.dart';
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
  final Map<String, String?> _countryProfileCache = {};

  /// Получить включённые типы журналов для заведения.
  Set<String> getEnabledLogTypes(String establishmentId) {
    return Set<String>.from(_cache[establishmentId] ?? {});
  }

  String? getHaccpCountryCode(String establishmentId) {
    final v = _countryProfileCache[establishmentId];
    if (v == null || v.trim().isEmpty) return null;
    return v.trim().toUpperCase();
  }

  /// Проверить, включён ли журнал.
  bool isEnabled(String establishmentId, HaccpLogType logType) {
    return getEnabledLogTypes(establishmentId).contains(logType.code);
  }

  /// Загрузить настройки из Supabase.
  /// [notify] — false при фоновой гидратации, чтобы не дёргать перерисовку всего дерева.
  Future<void> load(String establishmentId, {bool notify = true}) async {
    try {
      Map<String, dynamic>? row;
      try {
        row = await _supabase.client
            .from('establishment_haccp_config')
            .select('*')
            .eq('establishment_id', establishmentId)
            .maybeSingle();
      } catch (_) {
        // Fallback для окружений, где миграция country_code ещё не применена.
        row = await _supabase.client
            .from('establishment_haccp_config')
            .select('enabled_log_types')
            .eq('establishment_id', establishmentId)
            .maybeSingle();
      }

      if (row != null && row['enabled_log_types'] != null) {
        final list = row['enabled_log_types'] as List<dynamic>?;
        _cache[establishmentId] =
            list?.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet() ??
                {};
      } else {
        _cache[establishmentId] = {};
      }
      _countryProfileCache[establishmentId] =
          row?['haccp_country_code']?.toString();
      if (notify) notifyListeners();
    } catch (_) {
      _cache[establishmentId] = {};
      _countryProfileCache.remove(establishmentId);
      if (notify) notifyListeners();
    }
  }

  /// Сохранить настройки (массив кодов). Сохраняются только коды поддерживаемых журналов (СанПиН 1–5 + фритюрные жиры).
  Future<void> save(
    String establishmentId,
    Set<String> enabledLogTypes, {
    String? countryCode,
  }) async {
    final supportedCodes = supportedCodesForCountry(countryCode);
    final list = enabledLogTypes
        .where((code) => supportedCodes.contains(code))
        .toList()
      ..sort();
    final payload = {
      'establishment_id': establishmentId,
      'enabled_log_types': list,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final normalizedCountry = countryCode?.trim().toUpperCase();
    try {
      await _supabase.client.from('establishment_haccp_config').upsert(
        {
          ...payload,
          if (normalizedCountry != null && normalizedCountry.isNotEmpty)
            'haccp_country_code': normalizedCountry,
        },
        onConflict: 'establishment_id',
      );
    } catch (_) {
      await _supabase.client
          .from('establishment_haccp_config')
          .upsert(payload, onConflict: 'establishment_id');
    }
    _cache[establishmentId] = Set.from(list);
    if (normalizedCountry != null && normalizedCountry.isNotEmpty) {
      _countryProfileCache[establishmentId] = normalizedCountry;
    }
    notifyListeners();
  }

  /// Включить/выключить журнал.
  Future<void> setEnabled(
    String establishmentId,
    HaccpLogType logType,
    bool enabled, {
    String? countryCode,
  }) async {
    final current = getEnabledLogTypes(establishmentId);
    if (enabled) {
      current.add(logType.code);
    } else {
      current.remove(logType.code);
    }
    await save(establishmentId, current, countryCode: countryCode);
  }

  Future<void> setHaccpCountryCode(
    String establishmentId,
    String countryCode,
  ) async {
    final enabled = getEnabledLogTypes(establishmentId);
    await save(establishmentId, enabled, countryCode: countryCode);
  }

  Future<void> clearHaccpCountryCode(String establishmentId) async {
    try {
      final enabled = getEnabledLogTypes(establishmentId).toList()..sort();
      await _supabase.client.from('establishment_haccp_config').upsert(
        {
          'establishment_id': establishmentId,
          'enabled_log_types': enabled,
          'haccp_country_code': null,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'establishment_id',
      );
      _countryProfileCache.remove(establishmentId);
      notifyListeners();
    } catch (_) {
      // Fallback для старой схемы без country_code.
      _countryProfileCache.remove(establishmentId);
      notifyListeners();
    }
  }

  /// Список включённых журналов (СанПиН 1–5 + фритюрные жиры) в порядке для UI.
  List<HaccpLogType> getEnabledJournalsOrdered(
    String establishmentId, {
    String? countryCode,
  }) {
    final enabled = getEnabledLogTypes(establishmentId);
    final supported = supportedCodesForCountry(countryCode);
    return HaccpLogType.supportedInApp
        .where((t) => supported.contains(t.code) && enabled.contains(t.code))
        .toList()
      ..sort((a, b) {
        final g = a.group.compareTo(b.group);
        if (g != 0) return g;
        return a.displayNameRu.compareTo(b.displayNameRu);
      });
  }

  Set<String> supportedCodesForCountry(String? countryCode) {
    final profile = HaccpCountryProfiles.byCountryCode(countryCode);
    return profile.supportedLogTypes.map((t) => t.code).toSet();
  }

  String resolveCountryCodeForEstablishment(Establishment est) {
    return HaccpCountryProfiles.effectiveCountryCodeForEstablishment(
      est,
      overrideCountryCode: getHaccpCountryCode(est.id),
    );
  }

  HaccpCountryProfile resolveCountryProfileForEstablishment(Establishment est) {
    final code = resolveCountryCodeForEstablishment(est);
    return HaccpCountryProfiles.byCountryCode(code);
  }

  bool hasExplicitCountryOverride(String establishmentId) {
    final c = getHaccpCountryCode(establishmentId);
    return c != null && c.isNotEmpty;
  }
}
