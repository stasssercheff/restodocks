/// Валидация email и телефона для карточек поставщиков.

/// Только цифры (для хранения и tel:).
String supplierPhoneDigitsOnly(String input) =>
    input.replaceAll(RegExp(r'\D'), '');

/// Пусто или корректный email (без «произвольного набора знаков»).
bool isValidSupplierEmail(String text) {
  final s = text.trim();
  if (s.isEmpty) return true;
  return RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(s);
}

/// Пусто или 7–15 цифр (международный номер без + в хранилище).
bool isValidSupplierPhone(String text) {
  final d = supplierPhoneDigitsOnly(text);
  if (d.isEmpty) return true;
  return d.length >= 7 && d.length <= 15;
}

/// null если поле пустое; иначе только цифры.
String? normalizedSupplierPhoneOrNull(String text) {
  final d = supplierPhoneDigitsOnly(text);
  if (d.isEmpty) return null;
  return d;
}

/// null если поле пустое; иначе trim.
String? normalizedSupplierEmailOrNull(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  return s;
}
