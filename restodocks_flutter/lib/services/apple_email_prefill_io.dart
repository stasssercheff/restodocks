import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Опционально подставить в форму **только email** из Sign in with Apple.
/// Имя, фамилию и прочее Apple не используем — пользователь заполняет вручную (часто данные Apple неточны).
class AppleEmailPrefill {
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Email при первой авторизации; при повторных вызовах часто `null` — тогда ввод вручную.
  static Future<String?> requestEmailFromApple() async {
    if (!isSupported) return null;
    try {
      if (!await SignInWithApple.isAvailable()) return null;
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
      );
      final email = credential.email?.trim();
      if (email == null || email.isEmpty) return null;
      return email;
    } catch (_) {
      return null;
    }
  }
}
