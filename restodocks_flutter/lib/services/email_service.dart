import 'dart:convert';

import '../core/public_app_origin.dart';
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

  /// Разбор ответа Edge `send-email`: успех только если Resend вернул [id] (иначе был бы ложный «успех»).
  static ({bool ok, String? resendId, String? error}) _parseSendEmailResponse(
    int status,
    Map<String, dynamic>? data,
  ) {
    if (status != 200) {
      return (
        ok: false,
        resendId: null,
        error: data?['error']?.toString() ?? 'HTTP $status',
      );
    }
    final topErr = data?['error']?.toString();
    if (topErr != null && topErr.isNotEmpty) {
      return (ok: false, resendId: null, error: topErr);
    }
    final inner = data?['data'];
    if (inner is Map) {
      final id = inner['id'];
      if (id is String && id.isNotEmpty) {
        return (ok: true, resendId: id, error: null);
      }
    }
    final directId = data?['id'];
    if (directId is String && directId.isNotEmpty) {
      return (ok: true, resendId: directId, error: null);
    }
    return (
      ok: false,
      resendId: null,
      error:
          'Почтовый сервер не подтвердил отправку (нет id в ответе Resend). Смотрите логи Edge send-email и RESEND_API_KEY.',
    );
  }

  /// send-registration-email: прямой POST через Dio ([postEdgeFunctionWithRetry]), не [FunctionsClient] + [AuthHttpClient].
  /// [bearerAlwaysAnon: true] — после signUp сессия иначе подставляет user JWT; Edge ждёт anon или валидный user JWT.
  Future<({int status, Map<String, dynamic>? data})> _invokeSendRegistrationEmail(
    Map<String, dynamic> body,
  ) async {
    return postEdgeFunctionWithRetry(
      'send-registration-email',
      body,
      bearerAlwaysAnon: true,
    );
  }

  /// Если Edge (Resend) недоступен или отвечает 401 — стандартное письмо подтверждения через Auth API (тот же anon).
  Future<({bool ok, String? error})> _tryAuthResendSignupConfirmation(
    String email,
    String? languageCode,
  ) async {
    try {
      final lang = (languageCode ?? 'en').trim().toLowerCase();
      final redirect =
          '$publicAppOriginForEmailRedirect/auth/confirm?lang=${Uri.encodeComponent(lang)}';
      await _client.auth.resend(
        email: email.trim(),
        type: OtpType.signup,
        emailRedirectTo: redirect,
      );
      devLog('EmailService: auth.resend(signup) ok fallback for ${email.trim()}');
      return (ok: true, error: null);
    } catch (e, st) {
      devLog('EmailService: auth.resend(signup) fallback failed: $e\n$st');
      return (ok: false, error: e.toString());
    }
  }

  static bool _edgeRegistrationMailOk(int status, Map<String, dynamic>? data) {
    if (status != 200) return false;
    final id = data?['id']?.toString();
    return id != null && id.isNotEmpty;
  }

  /// Отправить письмо при регистрации (владелец или сотрудник).
  /// [passwordForConfirmation] — если передан и Confirm Email включён, в письмо добавляется ссылка подтверждения.
  Future<({bool ok, String? error})> sendRegistrationEmail({
    required bool isOwner,
    bool isCoOwner = false,
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
        'type': isCoOwner ? 'co_owner' : (isOwner ? 'owner' : 'employee'),
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
      final res = await _invokeSendRegistrationEmail(body);
      if (_edgeRegistrationMailOk(res.status, res.data)) return (ok: true, error: null);
      if (res.status == 200 && res.data != null) {
        return (
          ok: false,
          error:
              'Ответ send-registration-email без id письма (Resend). Проверьте логи Edge и ключ API.',
        );
      }
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
  /// Сначала Edge [send-registration-email] → **Resend** (как приглашение; письмо видно в Resend).
  /// Если Edge не сработал — запасной [auth.resend] (GoTrue / SMTP Supabase, в Resend не отображается).
  Future<({bool ok, String? error})> sendConfirmationLinkRequest(
    String to, {
    String? languageCode,
    String? password,
  }) async {
    try {
      final res = await _invokeSendRegistrationEmail({
        'type': 'confirmation_only',
        'to': to.trim(),
        if (languageCode != null && languageCode.trim().isNotEmpty)
          'language': languageCode.trim().toLowerCase(),
        if (password != null && password.isNotEmpty) 'password': password,
      });
      if (_edgeRegistrationMailOk(res.status, res.data)) {
        devLog('EmailService: confirmation_only via Resend/Edge ok');
        return (ok: true, error: null);
      }

      final viaAuth = await _tryAuthResendSignupConfirmation(to, languageCode);
      if (viaAuth.ok) {
        devLog('EmailService: confirmation fallback via auth.resend (не в списке Resend)');
        return viaAuth;
      }

      if (res.status == 0) {
        return (
          ok: false,
          error: viaAuth.error ??
              'Сеть или CORS: send-registration-email не дошёл; auth.resend тоже не удался.',
        );
      }
      final msg = res.data is Map
          ? (res.data!['error'] ?? res.data!['message'] ?? res.status)
          : res.status;
      return (
        ok: false,
        error: 'Edge: $msg. Auth: ${viaAuth.error ?? "—"}',
      );
    } catch (e) {
      return (ok: false, error: e.toString());
    }
  }

  /// Отправить только письмо с ссылкой подтверждения (для co-owner и др.).
  /// Порядок как в [sendConfirmationLinkRequest]: сначала Resend (Edge), потом auth.resend.
  Future<({bool ok, String? error})> sendConfirmationEmail({
    required String to,
    required String password,
    String? languageCode,
  }) async {
    try {
      final res = await _invokeSendRegistrationEmail({
        'type': 'confirmation_only',
        'to': to.trim(),
        'password': password,
        if (languageCode != null && languageCode.trim().isNotEmpty)
          'language': languageCode.trim().toLowerCase(),
      });
      if (_edgeRegistrationMailOk(res.status, res.data)) {
        devLog('EmailService: sendConfirmationEmail via Resend/Edge ok');
        return (ok: true, error: null);
      }

      final viaAuth = await _tryAuthResendSignupConfirmation(to, null);
      if (viaAuth.ok) {
        devLog('EmailService: sendConfirmationEmail fallback auth.resend');
        return viaAuth;
      }

      if (res.status == 0) {
        return (
          ok: false,
          error: viaAuth.error ??
              'Сеть или CORS: send-registration-email; auth.resend тоже не удался.',
        );
      }
      final msg = res.data is Map
          ? (res.data!['error'] ?? res.data!['message'] ?? res.status)
          : res.status;
      return (ok: false, error: 'Edge: $msg. Auth: ${viaAuth.error ?? "—"}');
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
      final parsed = EmailService._parseSendEmailResponse(res.status, res.data);
      if (parsed.ok) return (ok: true, error: null);
      return (ok: false, error: parsed.error);
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
      // Plain text + HTML снижает риск «спама» у части фильтров; основная доставляемость — DNS (SPF/DKIM/DMARC) в Resend.
      final text = 'Приглашение соучредителя Restodocks\n\n'
          'Вас пригласили стать соучредителем заведения «$displayName».\n\n'
          'Открыть приглашение: $invitationLink\n';
      final res = await _invokeSendEmailHttp({
        'to': to.trim(),
        'subject': 'Restodocks: приглашение соучредителя — $displayName',
        'html': html,
        'text': text,
      });
      final parsed = EmailService._parseSendEmailResponse(res.status, res.data);
      if (parsed.ok) {
        devLog('EmailService: invitation sent, resend_id=${parsed.resendId}');
        return (ok: true, error: null);
      }
      return (ok: false, error: parsed.error);
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
      final parsed = EmailService._parseSendEmailResponse(res.status, res.data);
      if (parsed.ok) {
        devLog('EmailService: send-email ok resend_id=${parsed.resendId}');
        return (ok: true, error: null);
      }
      return (ok: false, error: parsed.error);
    } catch (e) {
      devLog('EmailService: sendOrderEmail exception: $e');
      return (ok: false, error: e.toString());
    }
  }
}
