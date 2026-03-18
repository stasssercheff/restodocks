/// Утилиты нормализации названий продуктов (iiko-формат и др.)

/// Добавляет «ПФ » перед названием, если ещё нет (для полуфабрикатов при импорте).
String ensurePfPrefix(String name) {
  if (name.trim().isEmpty) return name.trim();
  final s = name.trim();
  const pfPrefixes = ['пф ', 'п/ф ', 'п.ф. ', 'pf '];
  final sLower = s.toLowerCase();
  for (final p in pfPrefixes) {
    if (sLower.startsWith(p)) return s;
  }
  return 'ПФ $s';
}

/// Убирает "ПФ ", "п/ф " и т.п. из начала названия (для сохранения без дублирования).
/// "ПФ Крем" → "Крем", "п/ф Соус" → "Соус".
String stripPfPrefix(String name) {
  if (name.isEmpty) return name;
  var s = name.trim();
  const pfPrefixes = ['пф ', 'п/ф ', 'п.ф. ', 'pf ', 'prep '];
  final sLower = s.toLowerCase();
  for (final p in pfPrefixes) {
    if (sLower.startsWith(p)) {
      return s.substring(p.length).trim();
    }
  }
  return s;
}

/// Нормализация для сопоставления ПФ: убирает "ПФ ", "п/ф " и т.п. в начале.
/// "ПФ чеснок" и "Чеснок" дают один ключ для матчинга.
String normalizeForPfMatching(String name) {
  if (name.isEmpty) return name;
  var s = stripIikoPrefix(name).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const pfPrefixes = ['пф ', 'п/ф ', 'п.ф. ', 'pf '];
  for (final p in pfPrefixes) {
    if (s.startsWith(p)) {
      s = s.substring(p.length).trim();
      break;
    }
  }
  return s;
}

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
