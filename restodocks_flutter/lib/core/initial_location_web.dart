import 'dart:html' as html;

const String _sessionStorageKey = 'restodocks_last_path';
const String _localStorageKey   = 'restodocks_last_path_persist';

bool _beforeUnloadRegistered = false;

void _registerBeforeUnload() {
  if (_beforeUnloadRegistered) return;
  _beforeUnloadRegistered = true;
  try {
    html.window.addEventListener('beforeunload', (e) {
      String p = '';
      final hash = html.window.location.hash ?? '';
      if (hash.isNotEmpty && hash.startsWith('#/')) {
        p = hash.substring(2).trim();
      } else {
        p = (html.window.location.pathname ?? '').trim();
      }
      if (p.isNotEmpty && p != '/' && p != '/splash') {
        var path = p;
        if (path.endsWith('/') && path.length > 1) path = path.substring(0, path.length - 1);
        final search = html.window.location.search ?? '';
        if (search.isNotEmpty) path = '$path$search';
        html.window.sessionStorage[_sessionStorageKey] = path;
        html.window.localStorage[_localStorageKey] = path; // persist через hard refresh
      }
    });
  } catch (_) {}
}

/// Сохраняет путь в sessionStorage + localStorage для fallback при F5.
void savePathForRefresh(String path) {
  try {
    if (path.isNotEmpty && path != '/' && path != '/splash') {
      html.window.sessionStorage[_sessionStorageKey] = path;
      html.window.localStorage[_localStorageKey] = path;
    }
  } catch (_) {}
}

/// Читает путь из sessionStorage (fallback при pathname == '/' на момент загрузки).
String? _pathFromSessionStorage() {
  try {
    final s = html.window.sessionStorage[_sessionStorageKey];
    if (s != null && s.isNotEmpty && s != '/' && s != '/splash') return s;
  } catch (_) {}
  // Fallback: localStorage (переживает hard refresh когда pathname == '/')
  try {
    final s = html.window.localStorage[_localStorageKey];
    if (s != null && s.isNotEmpty && s != '/' && s != '/splash') return s;
  } catch (_) {}
  return null;
}

/// Читает путь из data-initial-path (inline script в head).
String? _pathFromDataset() {
  try {
    final s = html.document.documentElement?.dataset['initialPath'];
    if (s != null && s.isNotEmpty && s != '/' && s != '/splash') return s;
  } catch (_) {}
  return null;
}

/// Читает путь из адресной строки. PathUrlStrategy: путь в pathname (site.com/schedule).
String _pathFromWindow() {
  try {
    // PathUrlStrategy: путь в pathname. Hash — fallback для старых закладок.
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

/// Путь на момент первой загрузки (до любых переходов). Не меняется.
String? _cachedInitialPath;

/// Web: при F5 сохраняем текущую страницу из URL. Кэшируем при первом вызове.
/// Приоритет: pathname → dataset (head script) → sessionStorage.
String getInitialLocation() {
  _registerBeforeUnload();
  if (_cachedInitialPath == null) {
    final fromWindow = _pathFromWindow();
    _cachedInitialPath = (fromWindow.isNotEmpty && fromWindow != '/')
        ? fromWindow
        : _pathFromDataset() ?? _pathFromSessionStorage() ?? '/';
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
