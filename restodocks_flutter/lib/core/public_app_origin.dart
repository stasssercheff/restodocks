import 'package:flutter/foundation.dart' show kIsWeb;

import 'supabase_env.dart';

/// Базовый URL веб-приложения: письма (confirm), ссылки «открыть на сайте».
///
/// Web: `--dart-define=PUBLIC_APP_ORIGIN=...` (см. [kPublicAppOriginFromEnvironment]).
/// Native: опционально `PUBLIC_APP_ORIGIN` в `assets/config.json` — например
/// `https://restodocks.pages.dev`, если в регионе нестабилен `restodocks.com`.
/// Тот же URL должен быть в Supabase Auth → Redirect URLs.
String _nativePublicOrigin = kPublicAppOriginFromEnvironment;

void setNativePublicAppOriginFromConfig(String? url) {
  final u = url?.trim();
  if (u == null || u.isEmpty) return;
  _nativePublicOrigin = u.replaceAll(RegExp(r'/$'), '');
}

/// Без завершающего `/`.
String get publicAppOrigin {
  if (kIsWeb) {
    return kPublicAppOriginFromEnvironment.replaceAll(RegExp(r'/$'), '');
  }
  return _nativePublicOrigin.replaceAll(RegExp(r'/$'), '');
}

/// Deep links / Universal Links с этого хоста обрабатываем как «наши».
bool isPublicAppHost(String host) {
  final h = host.toLowerCase();
  if (h == 'restodocks.com' || h == 'www.restodocks.com') return true;
  if (h == 'restodocks.pages.dev' || h == 'www.restodocks.pages.dev') {
    return true;
  }
  try {
    final configured = Uri.parse(publicAppOrigin).host.toLowerCase();
    if (configured.isNotEmpty && h == configured) return true;
  } catch (_) {}
  return false;
}
