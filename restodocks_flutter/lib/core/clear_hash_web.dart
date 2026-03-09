import 'dart:html' as html;

/// Web: убираем токены из адресной строки после восстановления сессии
void clearHashFromUrl() {
  try {
    final uri = Uri.base;
    if (uri.fragment.isNotEmpty) {
      final clean = '${uri.origin}${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}';
      html.window.history.replaceState(null, '', clean);
    }
  } catch (_) {}
}
