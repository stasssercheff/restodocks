import 'dart:html' as html;

/// Web: сохранять при уходе со страницы (вкладка, закрытие, минимизация)
void registerWebLifecycleSaver(void Function() onSave) {
  void handler(html.Event event) {
    onSave();
  }
  html.window.addEventListener('beforeunload', handler);
  html.document.addEventListener('visibilitychange', (html.Event event) {
    if (html.document.visibilityState == 'hidden') onSave();
  });
  html.window.addEventListener('pagehide', handler);
}
