import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'mobile_browser_chrome_nudge_stub.dart'
    if (dart.library.html) 'mobile_browser_chrome_nudge_web.dart' as chrome_nudge;

/// На web при переходе в альбом на телефоне дергает scroll документа — мобильные браузеры
/// иногда только так начинают сворачивать адресную строку (API «спрятать сразу» нет).
class WebMobileChromeLandscapeWatcher extends StatefulWidget {
  const WebMobileChromeLandscapeWatcher({super.key, required this.child});

  final Widget child;

  @override
  State<WebMobileChromeLandscapeWatcher> createState() =>
      _WebMobileChromeLandscapeWatcherState();
}

class _WebMobileChromeLandscapeWatcherState
    extends State<WebMobileChromeLandscapeWatcher> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) => _nudgeIfLandscapePhone());
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (kIsWeb) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _nudgeIfLandscapePhone());
    }
  }

  void _nudgeIfLandscapePhone() {
    if (!mounted || !kIsWeb) return;
    final mq = MediaQuery.of(context);
    if (mq.orientation != Orientation.landscape) return;
    if (chrome_nudge.mobileBrowserSkipChromeNudgeForWideTablet()) return;
    chrome_nudge.mobileBrowserChromeNudgeOnLandscapeIfPhone();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
