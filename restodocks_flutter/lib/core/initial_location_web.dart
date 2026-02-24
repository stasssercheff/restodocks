import 'dart:html' as html;

/// Web: берём путь из window.location для надёжного сохранения при F5
String getInitialLocation() {
  try {
    final path = html.window.location.pathname ?? '';
    final search = html.window.location.search ?? '';
    if (path.isNotEmpty && path != '/') {
      return search.isNotEmpty ? '$path$search' : path;
    }
  } catch (_) {}
  return '/';
}
