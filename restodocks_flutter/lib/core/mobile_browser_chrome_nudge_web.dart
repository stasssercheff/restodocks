// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

int _lastChromeNudgeMs = 0;

/// Лёгкий сдвиг scroll документа при прокрутке списков во Flutter: мобильные браузеры
/// чаще убирают адресную строку/панель вкладок только при движении страницы, а не канваса.
void mobileBrowserChromeNudgeFromFlutterScroll() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastChromeNudgeMs < 200) return;
    _lastChromeNudgeMs = now;

    final w = html.window;
    final ua = w.navigator.userAgent.toLowerCase();
    if (!ua.contains('android') &&
        !ua.contains('iphone') &&
        !ua.contains('ipad') &&
        !ua.contains('mobile')) {
      return;
    }

    final y = w.scrollY.toDouble();
    final doc = html.document.documentElement;
    final sh = (doc?.scrollHeight ?? 0).toDouble();
    final vh = (w.innerHeight ?? 0).toDouble();
    if (sh <= vh + 4) return;

    final maxY = (sh - vh).clamp(0.0, double.infinity);
    // +1 и возврат в следующем кадре — триггер для Chrome / Safari mobile.
    w.scrollTo(0, (y + 1).clamp(0.0, maxY));
    w.requestAnimationFrame((num _) {
      w.scrollTo(0, y.clamp(0.0, maxY));
    });
  } catch (_) {}
}
