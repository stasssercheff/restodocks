import 'supabase_env.dart';

/// URL Supabase. Прямой URL — proxy /supabase-auth давал 405 на Cloudflare Pages.
/// Домены restodocks.com, restodocks.pages.dev должны быть в Supabase Auth → Redirect URLs.
String resolveSupabaseUrl(String envUrl) {
  final url = envUrl.trim();
  return url.isNotEmpty ? url : kSupabaseUrlFromEnvironment;
}

/// URL для Edge Functions — тот же базовый хост, что у клиента.
String getSupabaseBaseUrl() => resolveSupabaseUrl(kSupabaseUrlFromEnvironment);
