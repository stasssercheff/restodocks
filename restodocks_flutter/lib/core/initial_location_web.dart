import 'dart:html' as html;

const String _sessionStorageKey = 'restodocks_last_path';

/// Сохраняет путь в sessionStorage для fallback при F5 (pathname иногда приходит как /).
void savePathForRefresh(String path) {
  try {
    if (path.isNotEmpty && path != '/' && path != '/splash') {
      html.window.sessionStorage[_sessionStorageKey] = path;
    }
  } catch (_) {}
}

/// Читает путь из sessionStorage (fallback при pathname == '/' на момент загрузки).
String? _pathFromSessionStorage() {
  try {
    final s = html.window.sessionStorage[_sessionStorageKey];
    if (s != null && s.isNotEmpty && s != '/' && s != '/splash') return s;
  } catch (_) {}
  return null;
}

/// Читает путь из адресной строки (pathname, hash). HashUrlStrategy: путь в #.
String _pathFromWindow() {
  try {
    // HashUrlStrategy: путь в # (site.com/#/schedule)
    final hash = html.window.location.hash ?? '';
    if (hash.isNotEmpty) {
      String h = hash.startsWith('#') ? hash.substring(1) : hash;
      if (h.startsWith('/')) {
        final q = h.contains('?') ? h.substring(h.indexOf('?')) : '';
        final p = h.contains('?') ? h.substring(0, h.indexOf('?')) : h;
        if (p != '/' && p.isNotEmpty) return q.isNotEmpty ? '$p$q' : p;
      }
    }
    // pathname (если hash пуст — первая загрузка на корень)
    String path = html.window.location.pathname ?? '';
    path = path.trim();
    if (path.endsWith('/') && path.length > 1) path = path.substring(0, path.length - 1);
    final search = html.window.location.search ?? '';
    if (path.isNotEmpty && path != '/') {
      return search.isNotEmpty ? '$path$search' : path;
    }
  } catch (_) {}
  return '/';
}

/// Путь на момент первой загрузки (до любых переходов). Не меняется.
String? _cachedInitialPath;

/// Web: при F5 сохраняем текущую страницу из URL (path или hash). Кэшируем при первом вызове.
/// Fallback: sessionStorage, если pathname пришёл как / (SW/race на загрузке).
String getInitialLocation() {
  if (_cachedInitialPath == null) {
    final fromWindow = _pathFromWindow();
    _cachedInitialPath = (fromWindow.isNotEmpty && fromWindow != '/')
        ? fromWindow
        : _pathFromSessionStorage() ?? '/';
  }
  return _cachedInitialPath!;
}

/// Исходный путь до любых redirect — использовать при F5, когда текущий URL уже /splash.
String? getCachedInitialPath() => _cachedInitialPath;

/// Текущий путь из адресной строки (для коррекции в redirect). Возвращает null если корень.
String? getCurrentBrowserPath() {
  try {
    final loc = _pathFromWindow();
    if (loc.isNotEmpty && loc != '/') return loc;
  } catch (_) {}
  return null;
}
