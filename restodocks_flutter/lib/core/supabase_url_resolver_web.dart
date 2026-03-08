const _defaultSupabaseUrl = 'https://osglfptwbuqqmqunttha.supabase.co';

/// URL Supabase. Прямой URL — proxy /supabase-auth давал 405 на Cloudflare Pages.
/// Домены restodocks.com, restodocks.pages.dev должны быть в Supabase Auth → Redirect URLs.
String resolveSupabaseUrl(String envUrl) {
  final url = envUrl.trim();
  return url.isNotEmpty ? url : _defaultSupabaseUrl;
}

/// URL для Edge Functions — прямой Supabase, тот же что у client.
String getSupabaseBaseUrl() {
  return _defaultSupabaseUrl;
}
