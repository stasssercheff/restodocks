import 'package:shared_preferences/shared_preferences.dart';

/// Локально сохраняемые варианты для полей HACCP-форм.
/// Храним отдельно по заведению, чтобы на следующих записях можно было выбирать из списка.
class HaccpFormPresetService {
  static const _prefix = 'haccp_form_presets';

  String _storageKey(String establishmentId, String fieldKey) =>
      '$_prefix:${establishmentId.trim()}:$fieldKey';

  List<String> _normalize(Iterable<String> values) {
    final unique = <String, String>{};
    for (final raw in values) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      unique.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }
    final result = unique.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<List<String>> getOptions({
    required String establishmentId,
    required String fieldKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_storageKey(establishmentId, fieldKey)) ?? const [];
    return _normalize(list);
  }

  Future<List<String>> addOption({
    required String establishmentId,
    required String fieldKey,
    required String value,
  }) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return getOptions(establishmentId: establishmentId, fieldKey: fieldKey);
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKey(establishmentId, fieldKey);
    final existing = prefs.getStringList(key) ?? const [];
    final updated = _normalize([...existing, trimmed]);
    await prefs.setStringList(key, updated);
    return updated;
  }
}
