import 'package:dio/dio.dart';

import '../utils/dev_log.dart';
import 'package:flutter/foundation.dart';
import 'package:restodocks/core/supabase_url_resolver_stub.dart'
    if (dart.library.html) 'package:restodocks/core/supabase_url_resolver_web.dart' as supabase_url;

const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9zZ2xmcHR3YnVxcW1xdW50dGhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUwNTk0MDQsImV4cCI6MjA4MDYzNTQwNH0.Jy7yi2TNdSrmoBdILXBGRYB_vxGtq8scCZ9eCA9vfTE',
);

/// POST к Edge Function с retry при 5xx/сети (proxy/ EarlyDrop).
/// 4xx не retry. Возвращает (status, data).
Future<({int status, Map<String, dynamic>? data})> postEdgeFunctionWithRetry(
  String functionPath,
  Map<String, dynamic> body, {
  int maxRetries = 3,
  List<int> retryDelays = const [500, 1000],
}) async {
  final url = '${supabase_url.getSupabaseBaseUrl()}/functions/v1/$functionPath';
  final dio = Dio(BaseOptions(
    headers: {
      'apikey': _supabaseAnonKey,
      'Authorization': 'Bearer $_supabaseAnonKey',
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
