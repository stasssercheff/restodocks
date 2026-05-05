import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tech_card.dart';
import '../utils/dev_log.dart';

/// Локальное хранение переводов названий ТТК по языкам (после входа и догрузки).
/// При смене языка предыдущие языки не удаляются — только дополняется слой для нового.
class TechCardTranslationCache {
  TechCardTranslationCache._();

  static String _keyOverlays(String dataEstablishmentId) =>
      'ttk_dish_overlay_v2_$dataEstablishmentId';

  static String _keyWarmedLangs(String dataEstablishmentId) =>
      'ttk_overlay_warmed_langs_$dataEstablishmentId';

  /// Загрузить с диска в память [TechCard] (все языки).
  static Future<void> loadForEstablishment(String dataEstablishmentId) async {
    final id = dataEstablishmentId.trim();
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyOverlays(id));
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in decoded.entries) {
        final lang = e.key;
        final inner = e.value;
        if (inner is! Map) continue;
        final map = inner.map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
        // merge: true — иначе повторный load затирает свежий in-memory оверлей
        // (после prefetch, пока save в prefs ещё не выполнился).
        TechCard.setTranslationOverlay(map, languageCode: lang, merge: true);
      }
      final warmedRaw = prefs.getString(_keyWarmedLangs(id));
      if (warmedRaw != null && warmedRaw.isNotEmpty) {
        final list = jsonDecode(warmedRaw) as List<dynamic>;
        TechCard.restoreWarmedLanguages(id, list.map((e) => e.toString()).toSet());
      }
    } catch (e, st) {
      devLog('TechCardTranslationCache.load: $e $st');
    }
  }

  static Future<void> saveForEstablishment(String dataEstablishmentId) async {
    final id = dataEstablishmentId.trim();
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final exported = TechCard.exportTranslationOverlays();
      await prefs.setString(_keyOverlays(id), jsonEncode(exported));
      final warmed = TechCard.exportWarmedLanguages(id);
      await prefs.setString(_keyWarmedLangs(id), jsonEncode(warmed.toList()));
    } catch (e, st) {
      devLog('TechCardTranslationCache.save: $e $st');
    }
  }

  /// Выход из аккаунта / смена заведения.
  static Future<void> clearForEstablishment(String dataEstablishmentId) async {
    final id = dataEstablishmentId.trim();
    if (id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyOverlays(id));
      await prefs.remove(_keyWarmedLangs(id));
    } catch (_) {}
  }
}
