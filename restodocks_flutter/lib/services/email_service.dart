import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE',
);

/// Сервис отправки писем через Edge Functions (Resend).
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  /// Прямой HTTP POST к Edge Function send-email (обходит 403 от functions.invoke на web).
  Future<({int status, Map<String, dynamic>? data})> _invokeSendEmailHttp(Map<String, dynamic> body) async {
    final dio = Dio(BaseOptions(
      headers: {
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $_supabaseAnonKey',
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true,
    ));
    try {
      final resp = await dio.post('${supabase_url.getSupabaseBaseUrl()}/functions/v1/send-email', data: body);
      final data = resp.data is Map<String, dynamic>
          ? resp.data as Map<String, dynamic>
          : (resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null);
      return (status: resp.statusCode ?? 0, data: data);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data as Map) : null);
      return (status: status, data: map);
    }
  }

  /// Отправить письмо при регистрации (владелец или сотрудник).
  /// Прямой HTTP (как sendOrderEmail) — обход 403 от functions.invoke на web.
  Future<void> sendRegistrationEmail({
    required bool isOwner,
    required String to,
    required String companyName,
    required String email,
    String? pinCode,
  }) async {
    try {
      final dio = Dio(BaseOptions(
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Content-Type': 'application/json',
        },
        validateStatus: (_) => true,
      ));
      final body = {
        'type': isOwner ? 'owner' : 'employee',
        'to': to.trim(),
        'companyName': companyName,
        'email': email,
        if (pinCode != null) 'pinCode': pinCode,
      };
      final resp = await dio.post(
        '${supabase_url.getSupabaseBaseUrl()}/functions/v1/send-registration-email',
        data: body,
      );
      if (resp.statusCode != 200) {
        debugPrint('EmailService: send-registration-email HTTP ${resp.statusCode} ${resp.data}');
      }
    } catch (e) {
      debugPrint('EmailService: send-registration-email error: $e');
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
      debugPrint('EmailService: invoking send-email (HTTP), body keys=${body.keys.toList()}');
      final res = await _invokeSendEmailHttp(body);
      debugPrint('EmailService: send-email response status=${res.status} data=${res.data}');
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
      debugPrint('EmailService: sendOrderEmail exception: $e');
      return (ok: false, error: e.toString());
    }
  }
}
