import 'dart:html' as html;

/// Веб: отличаем мобильный браузер от десктопного по User-Agent.
String getRegistrationClientKind() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  if (_isMobileOrTabletBrowserUa(ua)) {
    return 'web_mobile';
  }
  return 'web_desktop';
}

bool _isMobileOrTabletBrowserUa(String ua) {
  if (ua.contains('iphone') || ua.contains('ipod')) return true;
  if (ua.contains('ipad')) return true;
  // iPadOS 13+ может маскироваться под Mac.
  if (ua.contains('macintosh') && ua.contains('mobile')) return true;
  if (ua.contains('android')) return true;
  if (ua.contains('webos') ||
      ua.contains('blackberry') ||
      ua.contains('iemobile') ||
      ua.contains('opera mini')) {
    return true;
  }
  return false;
}
