// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:math' as math;

int _lastChromeNudgeMs = 0;
int _lastLandscapeNudgeMs = 0;

bool _targetMobileBrowser(html.Window w) {
  final ua = w.navigator.userAgent.toLowerCase();
  return ua.contains('android') ||
      ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('mobile');
}

/// Лёгкий сдвиг scroll документа при прокрутке списков во Flutter: мобильные браузеры
/// чаще убирают адресную строку/панель вкладок только при движении страницы, а не канваса.
void mobileBrowserChromeNudgeFromFlutterScroll() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastChromeNudgeMs < 200) return;
    _lastChromeNudgeMs = now;

    final w = html.window;
    if (!_targetMobileBrowser(w)) return;

    final y = w.scrollY.toDouble();
    final doc = html.document.documentElement;
    final sh = (doc?.scrollHeight ?? 0).toDouble();
    final vh = (w.innerHeight ?? 0).toDouble();
    if (sh <= vh + 4) return;

    final maxY = (sh - vh).clamp(0.0, double.infinity);
    w.scrollTo(0, (y + 1).clamp(0.0, maxY));
    w.requestAnimationFrame((num _) {
      w.scrollTo(0, y.clamp(0.0, maxY));
    });
  } catch (_) {}
}

/// Сразу после смены ориентации в альбом на узком экране — несколько кадров подряд.
/// Браузер не даёт API «убрать строку мгновенно»; это максимум без поломки вёрстки.
void mobileBrowserChromeNudgeOnLandscapeIfPhone() {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastLandscapeNudgeMs < 900) return;
    _lastLandscapeNudgeMs = now;

    final w = html.window;
    if (!_targetMobileBrowser(w)) return;

    final iw = (w.innerWidth ?? 0).toDouble();
    final ih = (w.innerHeight ?? 0).toDouble();
    if (iw <= ih) return;
    if (math.min(iw, ih) >= 600) return;

    final doc = html.document.documentElement;
    final sh = (doc?.scrollHeight ?? 0).toDouble();
    final vh = (w.innerHeight ?? 0).toDouble();
    if (sh <= vh + 4) return;

    final maxY = (sh - vh).clamp(0.0, double.infinity);
    final y0 = w.scrollY.toDouble();

    void step(int i) {
      if (i > 4) {
        w.scrollTo(0, y0.clamp(0.0, maxY));
        return;
      }
      final bump = (i.isOdd ? 2.0 : 3.0);
      w.scrollTo(0, (y0 + bump).clamp(0.0, maxY));
      w.requestAnimationFrame((num _) {
        w.scrollTo(0, y0.clamp(0.0, maxY));
        w.requestAnimationFrame((num _) => step(i + 1));
      });
    }

    step(0);
  } catch (_) {}
}
