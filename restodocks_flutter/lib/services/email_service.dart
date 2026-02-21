import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис отправки писем через Edge Functions (Resend).
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  /// Отправить письмо при регистрации (владелец или сотрудник).
  /// Не бросает исключения — ошибки логируются.
  Future<void> sendRegistrationEmail({
    required bool isOwner,
    required String to,
    required String companyName,
    required String email,
    required String password,
    String? pinCode,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'send-registration-email',
        body: {
          'type': isOwner ? 'owner' : 'employee',
          'to': to,
          'companyName': companyName,
          'email': email,
          'password': password,
          if (pinCode != null) 'pinCode': pinCode,
        },
      );
      if (res.status != 200) {
        print('EmailService: send-registration-email failed: ${res.status} ${res.data}');
      }
    } catch (e) {
      print('EmailService: send-registration-email error: $e');
    }
  }

  /// Запросить сброс пароля. Отправляет письмо со ссылкой.
  Future<({bool ok, String? error})> requestPasswordReset(String email) async {
    try {
      final res = await _client.functions.invoke(
        'request-password-reset',
        body: {'email': email.trim()},
      );
      if (res.status == 200) {
        return (ok: true, error: null);
      }
      final msg = (res.data as Map?)?['error']?.toString() ?? 'Unknown error';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Сбросить пароль по токену из письма.
  Future<({bool ok, String? error})> resetPasswordWithToken(String token, String newPassword) async {
    try {
      final res = await _client.functions.invoke(
        'reset-password',
        body: {'token': token, 'password': newPassword},
      );
      if (res.status == 200) {
        return (ok: true, error: null);
      }
      final msg = (res.data as Map?)?['error']?.toString() ?? 'Unknown error';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }
}
