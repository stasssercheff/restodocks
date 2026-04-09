// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _kPwaHintDismissedKey = 'restodocks_pwa_chrome_hint_dismissed';

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

    final dismissed = html.window.localStorage[_kPwaHintDismissedKey] == '1' ||
        html.window.sessionStorage[_kPwaHintDismissedKey] == '1';
    if (dismissed) {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

void markPwaFullscreenHintDismissed() {
  try {
    // Persist across browser restarts: show only once per device/browser.
    html.window.localStorage[_kPwaHintDismissedKey] = '1';
    // Keep session copy for backwards compatibility with existing checks.
    html.window.sessionStorage[_kPwaHintDismissedKey] = '1';
  } catch (_) {}
}
