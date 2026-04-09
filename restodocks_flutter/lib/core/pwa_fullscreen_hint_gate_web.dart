// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool shouldShowPwaFullscreenHintAfterLogin() {
  try {
    final ua = (html.window.navigator.userAgent).toLowerCase();
    final isMobile = ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod') ||
        ua.contains('android');
    if (!isMobile) return false;

    final displayStandalone =
        html.window.matchMedia('(display-mode: standalone)').matches;
    final displayFullscreen =
        html.window.matchMedia('(display-mode: fullscreen)').matches;
    if (displayStandalone || displayFullscreen) return false;

    if (html.window.sessionStorage['restodocks_pwa_chrome_hint_dismissed'] ==
        '1') {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

void markPwaFullscreenHintDismissed() {
  try {
    html.window.sessionStorage['restodocks_pwa_chrome_hint_dismissed'] = '1';
  } catch (_) {}
}
