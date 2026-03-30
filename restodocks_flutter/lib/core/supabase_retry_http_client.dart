import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import '../utils/dev_log.dart';

/// HTTP-клиент для [Supabase.initialize]: повтор при кратковременных 5xx/шлюзах и сетевых сбоях.
/// Когда PostgREST/Cloudflare отдаёт 502/503 без CORS, браузер показывает ложный «Origin not allowed» —
/// ретрай часто проходит со второго раза.
http.Client createSupabaseRetryHttpClient() {
  return RetryClient(
    http.Client(),
    retries: 2,
    when: (response) {
      final c = response.statusCode;
      return c == 500 || c == 502 || c == 503 || c == 504;
    },
    whenError: (error, stackTrace) {
      final s = error.toString().toLowerCase();
      return s.contains('clientexception') ||
          s.contains('socket') ||
          s.contains('failed host lookup') ||
          s.contains('connection') ||
          s.contains('timed out') ||
          s.contains('network is unreachable');
    },
    onRetry: (request, response, retryCount) {
      if (kDebugMode) {
        devLog(
          'Supabase HTTP retry #${retryCount + 1} ${request.method} ${request.url} '
          'lastStatus=${response?.statusCode}',
        );
      }
    },
  );
}
