// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Chrome iOS (CriOS) / Chrome Android: числовые ячейки иногда попадают под UI
/// «Passwords» и полоску автозаполнения (особенно инкогнито). Safari в обычной
/// вкладке не трогаем — отдельная логика сворачивания панели в index.html / nudge.
bool inventoryWebChromeQuantityNoAutofill() {
  try {
    final l = html.window.navigator.userAgent.toLowerCase();
    if (l.contains('edg/')) return false;
    return l.contains('crios/') || l.contains('chrome/');
  } catch (_) {
    return false;
  }
}
