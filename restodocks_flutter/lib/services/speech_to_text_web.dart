// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:js_util' as js_util;

String _localeForStt(String languageCode) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return 'en-US';
    case 'es':
      return 'es-ES';
    case 'it':
      return 'it-IT';
    case 'tr':
      return 'tr-TR';
    case 'kk':
      return 'kk-KZ';
    default:
      return 'ru-RU';
  }
}

Future<bool> speechToTextSupported() async {
  final w = html.window;
  return js_util.hasProperty(w, 'webkitSpeechRecognition') ||
      js_util.hasProperty(w, 'SpeechRecognition');
}

Future<String?> speechToTextListenOnce({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final w = html.window;
  final ctor = js_util.getProperty<Object?>(
        w,
        'webkitSpeechRecognition',
      ) ??
      js_util.getProperty<Object?>(w, 'SpeechRecognition');
  if (ctor == null) return null;

  final rec = js_util.callConstructor(ctor as Object, const []);
  final completer = Completer<String?>();

  js_util.setProperty(rec, 'lang', _localeForStt(languageCode));
  js_util.setProperty(rec, 'continuous', false);
  js_util.setProperty(rec, 'interimResults', false);
  js_util.setProperty(rec, 'maxAlternatives', 1);

  js_util.setProperty(
    rec,
    'onresult',
    (dynamic event) {
      try {
        final results = js_util.getProperty(event, 'results');
        final first = js_util.getProperty(results, 0);
        final alt = js_util.getProperty(first, 0);
        final text = js_util.getProperty<String?>(alt, 'transcript')?.trim();
        if (!completer.isCompleted) completer.complete(text);
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    },
  );

  js_util.setProperty(
    rec,
    'onerror',
    (_) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  js_util.setProperty(
    rec,
    'onnomatch',
    (_) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  js_util.setProperty(
    rec,
    'onend',
    (_) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );

  try {
    js_util.callMethod<void>(rec, 'start', const []);
  } catch (_) {
    return null;
  }

  final text = await completer.future.timeout(timeout, onTimeout: () => null);
  try {
    js_util.callMethod<void>(rec, 'stop', const []);
  } catch (_) {}
  return text;
}
