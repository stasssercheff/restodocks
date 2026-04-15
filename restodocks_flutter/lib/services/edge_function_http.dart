import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;

bool _isPublishableKey(String? v) =>
    v != null && v.trim().startsWith('sb_publishable_');

Dio _buildEdgeDio({
  required String anonKey,
  required String authorizationBearer,
}) {
  return Dio(
    BaseOptions(
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $authorizationBearer',
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true,
    ),
  );
}

/// POST к Edge Function с retry при 5xx/сети (proxy/ EarlyDrop).
/// 4xx не retry. Возвращает (status, data).
///
/// [bearerAlwaysAnon] — всегда Bearer = anon (например register-metadata до входа).
///
/// Если [bearerAlwaysAnon] == false и JWT пользователя нет даже после [refreshSession],
/// **не** подставляем anon в Authorization — иначе Edge даёт 401 «как будто сессия протухла»,
/// хотя реально пользователь не аутентифицирован для этого запроса.
///
/// [refreshSessionBeforeFirstPost] — обновить access token перед первым запросом
/// (важно для IAP и долгих сессий без возврата в приложение).
///
/// [retryOnceOn401AfterSessionRefresh] — при 401 вызывать [refreshSession] и повторить POST
/// (до [max401RecoveryAttempts] раз — во время IAP окно Apple может «съесть» несколько минут).
Future<({int status, Map<String, dynamic>? data})> postEdgeFunctionWithRetry(
  String functionPath,
  Map<String, dynamic> body, {
  int maxRetries = 3,
  List<int> retryDelays = const [500, 1000],
  bool bearerAlwaysAnon = false,
  bool refreshSessionBeforeFirstPost = false,
  bool retryOnceOn401AfterSessionRefresh = false,
  int max401RecoveryAttempts = 1,
}) async {
  var resolvedAnonKey = supabase_url.getSupabaseAnonKey().trim();
  var resolvedBaseUrl = supabase_url.getSupabaseBaseUrl().trim().replaceAll(RegExp(r'/+$'), '');
  try {
    if (Supabase.instance.isInitialized) {
      final client = Supabase.instance.client;
      final fromRest = client.rest.headers['apikey']?.trim();
      if (fromRest != null && fromRest.isNotEmpty) {
        // Предпочитаем publishable ключ из конфигурации приложения.
        // Старый JWT из rest.headers может приводить к 401 в Edge.
        if (_isPublishableKey(resolvedAnonKey) && !_isPublishableKey(fromRest)) {
          devLog('EdgeFunction: keeping publishable apikey from app config');
        } else {
          resolvedAnonKey = fromRest;
        }
      }
      final restUrl = client.rest.url.trim();
      if (restUrl.isNotEmpty) {
        resolvedBaseUrl = Uri.parse(restUrl).origin;
      }
    }
  } catch (e, st) {
    devLog('EdgeFunction: resolve URL/anon from Supabase client skipped: $e\n$st');
  }
  final url = '$resolvedBaseUrl/functions/v1/$functionPath';

  Future<void> tryRefresh() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (e, st) {
      devLog('EdgeFunction refreshSession: $e\n$st');
    }
  }

  Future<String?> userJwtAfterRefresh() async {
    var t = Supabase.instance.client.auth.currentSession?.accessToken;
    if (t != null && t.isNotEmpty) return t;
    await tryRefresh();
    t = Supabase.instance.client.auth.currentSession?.accessToken;
    if (t != null && t.isNotEmpty) return t;
    return null;
  }

  if (refreshSessionBeforeFirstPost) {
    await tryRefresh();
  }

  ({int status, Map<String, dynamic>? data}) lastResult = (status: 0, data: null);
  var recovery401Count = 0;

  for (var attempt = 0; attempt < maxRetries; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: retryDelays[attempt - 1]));
      devLog('EdgeFunction retry $attempt/$maxRetries: $functionPath');
    }

    final String authBearer;
    if (bearerAlwaysAnon) {
      authBearer = resolvedAnonKey;
    } else {
      final jwt = await userJwtAfterRefresh();
      if (jwt == null || jwt.isEmpty) {
        devLog('EdgeFunction: no user JWT for $functionPath — not sending anon as Bearer');
        return (
          status: 401,
          data: <String, dynamic>{
            'error': 'missing_user_jwt',
          },
        );
      }
      authBearer = jwt;
    }

    try {
      final dio = _buildEdgeDio(anonKey: resolvedAnonKey, authorizationBearer: authBearer);
      final resp = await dio.post<dynamic>(url, data: body);
      final data = resp.data is Map<String, dynamic>
          ? resp.data as Map<String, dynamic>
          : (resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null);
      lastResult = (status: resp.statusCode ?? 0, data: data);

      final code = resp.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        return lastResult;
      }
      if (code == 401 &&
          retryOnceOn401AfterSessionRefresh &&
          recovery401Count < max401RecoveryAttempts &&
          !bearerAlwaysAnon) {
        recovery401Count++;
        devLog(
          'EdgeFunction 401 → refreshSession ($recovery401Count/$max401RecoveryAttempts): $functionPath',
        );
        await tryRefresh();
        attempt--;
        continue;
      }
      if (code >= 400 && code < 500) {
        return lastResult;
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data) : null);
      lastResult = (status: status, data: map);

      if (status == 401 &&
          retryOnceOn401AfterSessionRefresh &&
          recovery401Count < max401RecoveryAttempts &&
          !bearerAlwaysAnon) {
        recovery401Count++;
        devLog(
          'EdgeFunction 401 (Dio) → refreshSession ($recovery401Count/$max401RecoveryAttempts): $functionPath',
        );
        await tryRefresh();
        attempt--;
        continue;
      }
      if (status >= 400 && status < 500) return lastResult;
    }
  }
  return lastResult;
}
