import 'supabase_env.dart';

/// Не-web: тот же базовый URL, что и у [Supabase.initialize] (см. [kSupabaseUrlFromEnvironment]).
String resolveSupabaseUrl(String envUrl) {
  final u = envUrl.trim();
  return u.isNotEmpty ? u : kSupabaseUrlFromEnvironment;
}

/// База для `.../functions/v1/...` — совпадает с URL клиента.
String getSupabaseBaseUrl() => resolveSupabaseUrl(kSupabaseUrlFromEnvironment);
