/// Web/Android/macOS: подстановка email из Apple не используется.
class AppleEmailPrefill {
  static bool get isSupported => false;

  static Future<String?> requestEmailFromApple() async => null;
}
