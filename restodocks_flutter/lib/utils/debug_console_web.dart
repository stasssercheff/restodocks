// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Выводит сообщение в консоль браузера (работает в release-сборке Flutter Web).
void debugLogToConsole(String message) {
  html.window.console.log(message);
}
