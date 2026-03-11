/// Утилиты нормализации названий продуктов (iiko-формат и др.)

/// Убирает префиксы iiko из названия продукта для сопоставления с каталогом и поиска КБЖУ.
/// "Т." — товар, "ТМЦ" — ТМЦ; часть наименования, но при поиске мешает.
String stripIikoPrefix(String name) {
  if (name.isEmpty) return name;
  var s = name.trim();
  // Т. / Т.  / ТМЦ / ТМЦ  в начале
  if (RegExp(r'^Т\.\s*', caseSensitive: false).hasMatch(s)) {
    s = s.replaceFirst(RegExp(r'^Т\.\s*', caseSensitive: false), '');
  } else if (RegExp(r'^ТМЦ\s*', caseSensitive: false).hasMatch(s)) {
    s = s.replaceFirst(RegExp(r'^ТМЦ\s*', caseSensitive: false), '');
  }
  return s.trim();
}
