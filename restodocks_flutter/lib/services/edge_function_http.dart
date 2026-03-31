import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;

/// POST к Edge Function с retry при 5xx/сети (proxy/ EarlyDrop).
/// 4xx не retry. Возвращает (status, data).
///
/// [bearerAlwaysAnon] — всегда Bearer = anon (например register-metadata до входа;
/// иначе протухший JWT в сессии даёт 401 на Edge).
Future<({int status, Map<String, dynamic>? data})> postEdgeFunctionWithRetry(
  String functionPath,
  Map<String, dynamic> body, {
  int maxRetries = 3,
  List<int> retryDelays = const [500, 1000],
  bool bearerAlwaysAnon = false,
}) async {
  final url = '${supabase_url.getSupabaseBaseUrl()}/functions/v1/$functionPath';
  final anonKey = supabase_url.getSupabaseAnonKey();
  final sessionToken = Supabase.instance.client.auth.currentSession?.accessToken;
  final authBearer = bearerAlwaysAnon
      ? anonKey
      : ((sessionToken != null && sessionToken.isNotEmpty)
          ? sessionToken
          : anonKey);
  final dio = Dio(BaseOptions(
    headers: {
      'apikey': anonKey,
      'Authorization': 'Bearer $authBearer',
      'Content-Type': 'application/json',
    },
    validateStatus: (_) => true,
  ));

  ({int status, Map<String, dynamic>? data}) lastResult = (status: 0, data: null);

  for (var attempt = 0; attempt < maxRetries; attempt++) {
    if (attempt > 0) {
      await Future<void>.delayed(Duration(milliseconds: retryDelays[attempt - 1]));
      devLog('EdgeFunction retry $attempt/$maxRetries: $functionPath');
    }
    try {
      final resp = await dio.post(url, data: body);
      final data = resp.data is Map<String, dynamic>
          ? resp.data as Map<String, dynamic>
          : (resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null);
      lastResult = (status: resp.statusCode ?? 0, data: data);

      if (resp.statusCode != null && resp.statusCode! >= 200 && resp.statusCode! < 300) {
        return lastResult;
      }
      if (resp.statusCode != null && resp.statusCode! >= 400 && resp.statusCode! < 500) {
        return lastResult; // 4xx — не retry
      }
      // 5xx — retry
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final map = data is Map<String, dynamic>
          ? data
          : (data is Map ? Map<String, dynamic>.from(data as Map) : null);
      lastResult = (status: status, data: map);
      if (status >= 400 && status < 500) return lastResult;
      // сеть/5xx — retry
    }
  }
  return lastResult;
}
