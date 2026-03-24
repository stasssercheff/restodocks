// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void registerFlutterNav(void Function(dynamic) callback) {
  try {
    js.context['_flutterNav'] = callback;
  } catch (_) {}
}

void unregisterFlutterNav() {
  try {
    js.context.deleteProperty('_flutterNav');
  } catch (_) {}
}
