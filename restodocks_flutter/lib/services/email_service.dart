import 'dart:convert';

import '../utils/dev_log.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'edge_function_http.dart';

/// Сервис отправки писем через Edge Functions (Resend).
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  /// Прямой HTTP POST к Edge Function send-email (retry при 5xx/сети).
  Future<({int status, Map<String, dynamic>? data})> _invokeSendEmailHttp(Map<String, dynamic> body) async {
    return postEdgeFunctionWithRetry('send-email', body);
  }

  /// Отправить письмо при регистрации (владелец или сотрудник).
  /// [passwordForConfirmation] — если передан и Confirm Email включён, в письмо добавляется ссылка подтверждения.
  Future<({bool ok, String? error})> sendRegistrationEmail({
    required bool isOwner,
    required String to,
    required String companyName,
    required String email,
    String? fullName,
    String? registeredAtLocal,
    String? pinCode,
    String? passwordForConfirmation,
    String? languageCode,
  }) async {
    try {
      final body = {
        'type': isOwner ? 'owner' : 'employee',
        'to': to.trim(),
        'companyName': companyName,
        'email': email,
        if (fullName != null && fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
        if (registeredAtLocal != null && registeredAtLocal.trim().isNotEmpty)
          'registeredAtLocal': registeredAtLocal.trim(),
        if (pinCode != null) 'pinCode': pinCode,
        if (passwordForConfirmation != null && passwordForConfirmation.isNotEmpty)
          'password': passwordForConfirmation,
        if (languageCode != null && languageCode.trim().isNotEmpty)
          'language': languageCode.trim().toLowerCase(),
      };
      final res = await postEdgeFunctionWithRetry('send-registration-email', body);
      if (res.status == 200) return (ok: true, error: null);
      if (res.status == 0) {
        return (
          ok: false,
          error:
              'Сеть или CORS: запрос к send-registration-email не дошёл (проверьте сайт и Edge Functions).',
        );
      }
      final msg = res.data is Map
          ? (res.data!['error'] ?? res.data!['message'] ?? res.status)
          : res.status;
      return (ok: false, error: msg.toString());
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Запросить ссылку подтверждения (по кнопке «Отправить ссылку»).
  /// Не требует пароль — использует magiclink.
  Future<({bool ok, String? error})> sendConfirmationLinkRequest(
    String to, {
    String? languageCode,
  }) async {
    try {
      final res = await postEdgeFunctionWithRetry(
        'send-registration-email',
        {
          'type': 'confirmation_only',
          'to': to.trim(),
          if (languageCode != null && languageCode.trim().isNotEmpty)
            'language': languageCode.trim().toLowerCase(),
        },
      );
      if (res.status == 200) return (ok: true, error: null);
      if (res.status == 0) {
        return (
          ok: false,
          error:
              'Сеть или CORS: запрос к send-registration-email не дошёл (проверьте сайт и Edge Functions).',
        );
      }
      final msg = res.data is Map
          ? (res.data!['error'] ?? res.data!['message'] ?? res.status)
          : res.status;
      return (ok: false, error: msg.toString());
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Отправить только письмо с ссылкой подтверждения (для co-owner и др.).
  Future<({bool ok, String? error})> sendConfirmationEmail({
    required String to,
    required String password,
  }) async {
    try {
      final res = await postEdgeFunctionWithRetry(
        'send-registration-email',
        {'type': 'confirmation_only', 'to': to.trim(), 'password': password},
      );
      if (res.status == 200) return (ok: true, error: null);
      if (res.status == 0) {
        return (
          ok: false,
          error:
              'Сеть или CORS: запрос к send-registration-email не дошёл (проверьте сайт и Edge Functions).',
        );
      }
      final msg = res.data is Map
          ? (res.data!['error'] ?? res.data!['message'] ?? res.status)
          : res.status;
      return (ok: false, error: msg.toString());
    } catch (e) {
      return (ok: false, error: e.toString());
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

  /// Запросить смену пароля из личного кабинета (старый + новый).
  /// Требует авторизации. Отправляет письмо со ссылкой, по ссылке — страница смены пароля.
  Future<({bool ok, String? error})> requestChangePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'request-change-password',
        body: {
          'old_password': oldPassword,
          'new_password': newPassword,
        },
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
      final res = await _invokeSendEmailHttp({
        'to': supportEmail,
        'subject': '[Поддержка] $category — $subject',
        'html': html,
      });
      if (res.status == 200) return (ok: true, error: null);
      final msg = res.data?['error']?.toString() ?? 'Unknown error';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Приглашение соучредителя: ссылка на accept-co-owner-invitation.
  Future<({bool ok, String? error})> sendCoOwnerInvitationEmail({
    required String to,
    required String invitationLink,
    String? establishmentName,
  }) async {
    try {
      final displayName =
          (establishmentName != null && establishmentName.trim().isNotEmpty)
              ? establishmentName.trim()
              : 'Restodocks';
      final safeName = _escapeHtml(displayName);
      final safeLink = _escapeHtml(invitationLink);
      final html = '''
<div style="font-family:sans-serif;max-width:600px;margin:0 auto">
  <h2 style="color:#333">Приглашение соучредителя</h2>
  <p>Вас пригласили стать соучредителем заведения <strong>$safeName</strong> в Restodocks.</p>
  <p><a href="$safeLink" style="display:inline-block;padding:12px 24px;background:#1976d2;color:#fff;text-decoration:none;border-radius:8px">Принять приглашение</a></p>
  <p style="color:#666;font-size:14px">Если кнопка не открывается, скопируйте ссылку в браузер:</p>
  <p style="word-break:break-all;font-size:13px;color:#333">$safeLink</p>
</div>
''';
      final res = await _invokeSendEmailHttp({
        'to': to.trim(),
        'subject': 'Приглашение соучредителя Restodocks — $displayName',
        'html': html,
      });
      if (res.status == 200) {
        final bodyError = res.data?['error']?.toString();
        if (bodyError != null && bodyError.isNotEmpty) {
          return (ok: false, error: bodyError);
        }
        return (ok: true, error: null);
      }
      final msg = res.data?['error']?.toString() ?? 'HTTP ${res.status}';
      return (ok: false, error: msg);
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  static String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
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
        devLog('EmailService: attaching PDF "$pdfFileName", pdfBytes=${pdfBytes.length}, b64len=${b64.length}');
        body['attachments'] = [
          {
            'filename': pdfFileName,
            'content': b64,
          },
        ];
      } else {
        devLog('EmailService: no PDF attachment (pdfBytes=${pdfBytes?.length ?? 'null'})');
      }
      devLog('EmailService: invoking send-email (HTTP), body keys=${body.keys.toList()}');
      final res = await _invokeSendEmailHttp(body);
      devLog('EmailService: send-email response status=${res.status} data=${res.data}');
      if (res.status != 200) {
        final msg = res.data?['error']?.toString() ?? 'HTTP ${res.status}';
        return (ok: false, error: msg);
      }
      // Даже при 200 проверяем body — функция может вернуть { error: '...' }
      final bodyError = res.data?['error']?.toString();
      if (bodyError != null && bodyError.isNotEmpty) {
        return (ok: false, error: bodyError);
      }
      return (ok: true, error: null);
    } catch (e) {
      devLog('EmailService: sendOrderEmail exception: $e');
      return (ok: false, error: e.toString());
    }
  }
}
