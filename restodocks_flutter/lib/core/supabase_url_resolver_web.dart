const _defaultSupabaseUrl = 'https://osglfptwbuqqmqunttha.supabase.co';

/// URL Supabase. На restodocks.com и restodocks.pages.dev — через proxy (/supabase-auth),
/// запросы same-origin, как работало на Vercel. На localhost — прямой envUrl.
String resolveSupabaseUrl(String envUrl) {
  final base = Uri.base;
  if (base.host.contains('restodocks.com') || base.host.contains('restodocks.pages.dev')) {
    return '${base.origin}/supabase-auth';
  }
  return envUrl;
}

/// URL для Edge Functions (EmailService, AccountManager и т.д.) — тот же, что у Supabase client.
String getSupabaseBaseUrl() {
  final base = Uri.base;
  if (base.host.contains('restodocks.com') || base.host.contains('restodocks.pages.dev')) {
    return '${base.origin}/supabase-auth';
  }
  return _defaultSupabaseUrl;
}
