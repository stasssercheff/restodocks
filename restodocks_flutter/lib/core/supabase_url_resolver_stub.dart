import 'supabase_env.dart';

String? _nativeUrl;
String? _nativeAnon;

/// Вызвать из [main] до [Supabase.initialize] после чтения `assets/config.json` (iOS/Android/macOS).
void setNativeSupabaseRuntimeConfig({
  required String url,
  required String anonKey,
}) {
  _nativeUrl = url.trim().isNotEmpty ? url.trim() : null;
  _nativeAnon = anonKey.trim().isNotEmpty ? anonKey.trim() : null;
}

/// Не-web: тот же базовый URL, что и у [Supabase.initialize].
String resolveSupabaseUrl(String envUrl) {
  final u = envUrl.trim();
  return u.isNotEmpty ? u : kSupabaseUrlFromEnvironment;
}

/// База для `.../functions/v1/...` — совпадает с URL клиента.
String getSupabaseBaseUrl() {
  final r = _nativeUrl;
  if (r != null && r.isNotEmpty) return r;
  return resolveSupabaseUrl(kSupabaseUrlFromEnvironment);
}

String getSupabaseAnonKey() {
  final r = _nativeAnon;
  if (r != null && r.isNotEmpty) return r;
  return kSupabaseAnonKeyFromEnvironment;
}
