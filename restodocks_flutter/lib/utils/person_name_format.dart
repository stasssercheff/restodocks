/// Имя и фамилия при регистрации: без лишних пробелов, первая буква — заглавная.
String formatPersonNameField(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}
