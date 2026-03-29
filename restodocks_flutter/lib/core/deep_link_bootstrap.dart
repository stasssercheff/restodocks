import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Cold start и поток ссылок с https-хоста приложения (Universal Links / App Links).
class DeepLinkBootstrap {
  DeepLinkBootstrap._();

  static Uri? initialUri;
  /// Последняя ссылка на /auth/confirm (с фрагментом #access_token=...), если приложение уже было открыто.
  static Uri? lastAuthConfirmUri;

  static AppLinks? _appLinks;

  static bool _isOurHost(String host) {
    final h = host.toLowerCase();
    return h == 'restodocks.com' || h == 'www.restodocks.com';
  }

  static bool isOurHttpsLink(Uri? u) {
    if (u == null) return false;
    if (u.scheme != 'https' && u.scheme != 'http') return false;
    return _isOurHost(u.host);
  }

  /// Путь + query для [GoRouter.initialLocation] (фрагмент отдельно остаётся в [authCallbackUri]).
  static String? get initialLocationPath {
    final u = initialUri;
    if (u == null || !isOurHttpsLink(u)) return null;
    return pathAndQuery(u);
  }

  static String pathAndQuery(Uri u) {
    var path = u.path.isEmpty ? '/' : u.path;
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return u.hasQuery ? '$path?${u.query}' : path;
  }

  /// URI для [AuthConfirmScreen]: на вебе — [Uri.base], на iOS/Android — входящая https-ссылка.
  static Uri authCallbackUri({required bool isWeb}) {
    if (isWeb) return Uri.base;
    return lastAuthConfirmUri ?? initialUri ?? Uri();
  }

  static void rememberAuthConfirmUri(Uri u) {
    final p = u.path;
    if (p == '/auth/confirm' || p.endsWith('/auth/confirm')) {
      lastAuthConfirmUri = u;
    }
  }

  static Future<void> captureInitial() async {
    if (kIsWeb) return;
    try {
      _appLinks ??= AppLinks();
      final uri = await _appLinks!.getInitialLink();
      if (uri != null && isOurHttpsLink(uri)) {
        initialUri = uri;
        rememberAuthConfirmUri(uri);
      }
    } catch (_) {}
  }

  static Stream<Uri> uriLinkStream() {
    _appLinks ??= AppLinks();
    return _appLinks!.uriLinkStream;
  }

  static bool shouldDispatchPath(String pathAndQ) {
    return pathAndQ.startsWith('/auth/') ||
        pathAndQ.startsWith('/accept-co-owner-invitation') ||
        pathAndQ.startsWith('/register-co-owner');
  }
}
