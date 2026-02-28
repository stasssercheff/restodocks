import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Отправить обращение в службу поддержки на stassserchef@gmail.com.
  Future<({bool ok, String? error})> sendSupportEmail({
    required String fromEmail,
    required String category,
    required String subject,
    required String message,
  }) async {
    try {
      const supportEmail = 'stassserchef@gmail.com';
      final html = '''
<div style="font-family:sans-serif;max-width:600px;margin:0 auto">
  <h2 style="color:#333">Обращение в поддержку Restodocks</h2>
  <table style="width:100%;border-collapse:collapse">
    <tr><td style="padding:8px;font-weight:bold;width:120px">От:</td><td style="padding:8px">$fromEmail</td></tr>
    <tr style="background:#f9f9f9"><td style="padding:8px;font-weight:bold">Категория:</td><td style="padding:8px">$category</td></tr>
    <tr><td style="padding:8px;font-weight:bold">Тема:</td><td style="padding:8px">$subject</td></tr>
  </table>
  <div style="margin-top:16px;padding:16px;background:#f5f5f5;border-radius:8px;white-space:pre-wrap">$message</div>
</div>
''';
      final res = await _client.functions.invoke('send-email', body: {
        'to': supportEmail,
        'subject': '[Поддержка] $category — $subject',
        'html': html,
      });
      if (res.status == 200) return (ok: true, error: null);
      final msg = (res.data as Map?)?['error']?.toString() ?? 'Unknown error';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Отправить заказ продуктов на email через Resend (с вложением PDF).
  /// [pdfBytes] — сгенерированный PDF заказа (если null, письмо уходит только с html).
  Future<({bool ok, String? error})> sendOrderEmail({
    required String to,
    required String subject,
    required String html,
    List<int>? pdfBytes,
    String pdfFileName = 'order.pdf',
  }) async {
    try {
      final body = <String, dynamic>{
        'to': to.trim(),
        'subject': subject,
        'html': html,
      };
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        final b64 = base64Encode(pdfBytes);
        debugPrint('EmailService: attaching PDF "$pdfFileName", pdfBytes=${pdfBytes.length}, b64len=${b64.length}');
        body['attachments'] = [
          {
            'filename': pdfFileName,
            'content': b64,
          },
        ];
      } else {
        debugPrint('EmailService: no PDF attachment (pdfBytes=${pdfBytes?.length ?? 'null'})');
      }
      debugPrint('EmailService: invoking send-email, body keys=${body.keys.toList()}');
      final res = await _client.functions.invoke('send-email', body: body);
      debugPrint('EmailService: send-email response status=${res.status} data=${res.data}');
      if (res.status == 200) {
        return (ok: true, error: null);
      }
      final msg = (res.data as Map?)?['error']?.toString() ?? 'Unknown error';
      return (ok: false, error: msg);
    } catch (e) {
      debugPrint('EmailService: sendOrderEmail exception: $e');
      return (ok: false, error: e.toString());
    }
  }
}
