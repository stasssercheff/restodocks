import 'dart:html' as html;

/// Читает путь из адресной строки (pathname, href, hash). Нужно для F5.
String _pathFromWindow() {
  try {
    String path = html.window.location.pathname ?? '';
    path = path.trim();
    if (path.endsWith('/') && path.length > 1) path = path.substring(0, path.length - 1);
    final search = html.window.location.search ?? '';
    if (path.isNotEmpty && path != '/') {
      return search.isNotEmpty ? '$path$search' : path;
    }
    final hash = html.window.location.hash ?? '';
    if (hash.isNotEmpty) {
      String h = hash.startsWith('#') ? hash.substring(1) : hash;
      if (h.startsWith('/')) {
        final q = h.contains('?') ? h.substring(h.indexOf('?')) : '';
        final p = h.contains('?') ? h.substring(0, h.indexOf('?')) : h;
        if (p != '/' && p.isNotEmpty) return q.isNotEmpty ? '$p$q' : p;
      }
    }
    final href = html.window.location.href ?? '';
    if (href.isNotEmpty) {
      final uri = Uri.tryParse(href);
      if (uri != null && uri.path.isNotEmpty && uri.path != '/') {
        final p = uri.path.endsWith('/') && uri.path.length > 1
            ? uri.path.substring(0, uri.path.length - 1) : uri.path;
        return uri.hasQuery ? '$p?${uri.query}' : p;
      }
    }
  } catch (_) {}
  return '/';
}

/// Web: при F5 сохраняем текущую страницу из URL (path или hash)
String getInitialLocation() => _pathFromWindow();

/// Текущий путь из адресной строки (для коррекции в redirect). Возвращает null если корень.
String? getCurrentBrowserPath() {
  try {
    final loc = _pathFromWindow();
    if (loc.isNotEmpty && loc != '/') return loc;
  } catch (_) {}
  return null;
}
