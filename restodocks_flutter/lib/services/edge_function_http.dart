import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;

Dio _buildEdgeDio({
  required String anonKey,
  required bool bearerAlwaysAnon,
}) {
  final sessionToken = Supabase.instance.client.auth.currentSession?.accessToken;
  final authBearer = bearerAlwaysAnon
      ? anonKey
      : ((sessionToken != null && sessionToken.isNotEmpty)
          ? sessionToken
          : anonKey);
  return Dio(
    BaseOptions(
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $authBearer',
        'Content-Type': 'application/json',
      },
      validateStatus: (_) => true,
    ),
  );
}

/// POST к Edge Function с retry при 5xx/сети (proxy/ EarlyDrop).
/// 4xx не retry. Возвращает (status, data).
///
/// [bearerAlwaysAnon] — всегда Bearer = anon (например register-metadata до входа;
/// иначе протухший JWT в сессии даёт 401 на Edge).
///
/// [refreshSessionBeforeFirstPost] — обновить access token перед первым запросом
/// (важно для IAP и долгих сессий без возврата в приложение).
///
/// [retryOnceOn401AfterSessionRefresh] — при 401 один раз вызвать [refreshSession]
/// и повторить POST с новым JWT (типичный случай: истёк access_token во время оплаты).
Future<({int status, Map<String, dynamic>? data})> postEdgeFunctionWithRetry(
  String functionPath,
  Map<String, dynamic> body, {
  int maxRetries = 3,
  List<int> retryDelays = const [500, 1000],
  bool bearerAlwaysAnon = false,
  bool refreshSessionBeforeFirstPost = false,
  bool retryOnceOn401AfterSessionRefresh = false,
}) async {
  final url = '${supabase_url.getSupabaseBaseUrl()}/functions/v1/$functionPath';
  final anonKey = supabase_url.getSupabaseAnonKey().trim();

  Future<void> tryRefresh() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (e, st) {
      devLog('EdgeFunction refreshSession: $e\n$st');
    }
  }

  if (refreshSessionBeforeFirstPost) {
    await tryRefresh();
  }

  ({int status, Map<String, dynamic>? data}) lastResult = (status: 0, data: null);
  var retried401 = false;

  for (var attempt = 0; attempt < maxRetries; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: retryDelays[attempt - 1]));
      devLog('EdgeFunction retry $attempt/$maxRetries: $functionPath');
    }
    try {
      final dio = _buildEdgeDio(anonKey: anonKey, bearerAlwaysAnon: bearerAlwaysAnon);
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
          !retried401 &&
          !bearerAlwaysAnon) {
        retried401 = true;
        devLog('EdgeFunction 401 → refreshSession + retry once: $functionPath');
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
          !retried401 &&
          !bearerAlwaysAnon) {
        retried401 = true;
        devLog('EdgeFunction 401 (Dio) → refreshSession + retry once: $functionPath');
        await tryRefresh();
        attempt--;
        continue;
      }
      if (status >= 400 && status < 500) return lastResult;
    }
  }
  return lastResult;
}
