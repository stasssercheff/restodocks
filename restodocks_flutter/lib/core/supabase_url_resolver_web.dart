import 'dart:html' as html;

/// На restodocks.com Supabase Auth отклоняет origin — используем прокси через тот же домен.
String resolveSupabaseUrl(String envUrl) {
  try {
    final host = html.window.location.hostname.toLowerCase();
    if (host == 'restodocks.com' || host == 'www.restodocks.com') {
      final origin = '${html.window.location.protocol}//${html.window.location.host}';
      return '$origin/supabase-auth';
    }
  } catch (_) {}
  return envUrl;
}
