import '../models/employee.dart';
import '../models/translation.dart';
import '../services/translation_service.dart';
import 'employee_display_utils.dart';
import 'translit_utils.dart';

/// Эвристика исходного языка имени для вызова перевода (не «транслит»).
String guessSourceLangForPersonName(String text) {
  final t = text.trim();
  if (t.isEmpty) return 'ru';
  if (RegExp(r'[\u0400-\u04FF]').hasMatch(t)) return 'ru';
  if (RegExp(r'[àáạảãâăèéẹẻẽêìíịỉĩòóọỏõôơùúụủũưỳýỵỷỹđ]')
      .hasMatch(t.toLowerCase())) {
    return 'vi';
  }
  return 'en';
}

/// Перевод ФИО для отображения или экспорта; при ошибке API — транслит с кириллицы.
Future<String> translatePersonName(
  TranslationService ts,
  Employee e,
  String targetLang,
) async {
  final raw = employeeFullNameRaw(e);
  if (raw.isEmpty) return raw;
  if (targetLang == 'ru') return raw;
  final from = guessSourceLangForPersonName(raw);
  if (from == targetLang) return raw;
  try {
    final out = await ts.translate(
      entityType: TranslationEntityType.ui,
      entityId: 'employee_name_${e.id}',
      fieldName: 'full_name',
      text: raw,
      from: from,
      to: targetLang,
    );
    if (out != null && out.trim().isNotEmpty && out != raw) return out.trim();
  } catch (_) {}
  return RegExp(r'[\u0400-\u04FF]').hasMatch(raw) ? cyrillicToLatin(raw) : raw;
}

/// Параллельный перевод имён сотрудников (кеш TranslationService снимает дубли).
Future<Map<String, String>> translatePersonNamesForEmployees(
  TranslationService ts,
  List<Employee> employees,
  String targetLang,
) async {
  if (targetLang == 'ru') {
    return {for (final e in employees) e.id: employeeFullNameRaw(e)};
  }
  final entries = await Future.wait(
    employees.map((e) async {
      final s = await translatePersonName(ts, e, targetLang);
      return MapEntry(e.id, s);
    }),
  );
  return Map<String, String>.fromEntries(entries);
}

/// Перевод произвольной строки ФИО (нет [Employee] в БД), кеш по хешу текста.
Future<String> translateAdHocPersonName(
  TranslationService ts,
  String raw,
  String targetLang,
) async {
  final t = raw.trim();
  if (t.isEmpty || t == '—') return t;
  if (targetLang == 'ru') return t;
  final from = guessSourceLangForPersonName(t);
  if (from == targetLang) return t;
  final id = 'adhoc_${t.hashCode}';
  try {
    final out = await ts.translate(
      entityType: TranslationEntityType.ui,
      entityId: id,
      fieldName: 'person_name',
      text: t,
      from: from,
      to: targetLang,
    );
    if (out != null && out.trim().isNotEmpty && out != t) return out.trim();
  } catch (_) {}
  return RegExp(r'[\u0400-\u04FF]').hasMatch(t) ? cyrillicToLatin(t) : t;
}
