/// Прямой URL Supabase для всех доменов.
/// restodocks.com должен быть в Supabase: Authentication → URL Configuration → Redirect URLs
/// и в Supabase: Project Settings → API → CORS Allowed Origins (если есть).
String resolveSupabaseUrl(String envUrl) {
  return envUrl;
}
