// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
Object? _activeRec;
Completer<String?>? _activeCompleter;
String _latestText = '';
bool _listening = false;

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
  final w = html.window as dynamic;
  return (w.webkitSpeechRecognition != null) || (w.SpeechRecognition != null);
}

bool speechToTextIsListening() => _listening;

Future<bool> speechToTextStart({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (_listening) return true;
  final w = html.window;
  final dynamic wd = w as dynamic;
  final ctor = wd.webkitSpeechRecognition ?? wd.SpeechRecognition;
  if (ctor == null) return false;

  final dynamic rec = ctor();
  final completer = Completer<String?>();
  _activeRec = rec;
  _activeCompleter = completer;
  _latestText = '';
  _listening = true;

  rec.lang = _localeForStt(languageCode);
  rec.continuous = false;
  rec.interimResults = true;
  rec.maxAlternatives = 1;

  rec.onresult = (dynamic event) {
      try {
        final results = event.results;
        final first = results[0];
        final alt = first[0];
        final text = (alt.transcript as String?)?.trim();
        if (text != null) _latestText = text;
      } catch (_) {}
    };

  rec.onerror = (_) {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        _activeCompleter!.complete(null);
      }
      _listening = false;
    };

  rec.onnomatch = (_) {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        _activeCompleter!.complete(null);
      }
      _listening = false;
    };

  rec.onend = (_) {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        final t = _latestText.trim();
        _activeCompleter!.complete(t.isEmpty ? null : t);
      }
      _listening = false;
    };

  try {
    rec.start();
  } catch (_) {
    _activeRec = null;
    _activeCompleter = null;
    _listening = false;
    return false;
  }

  unawaited(Future<void>.delayed(timeout).then((_) async {
    if (_listening) {
      await speechToTextStop();
    }
  }));
  return true;
}

Future<String?> speechToTextStop() async {
  if (!_listening || _activeRec == null || _activeCompleter == null) {
    return null;
  }
  try {
    (_activeRec as dynamic).stop();
  } catch (_) {}
  if (!_activeCompleter!.isCompleted) {
    final t = _latestText.trim();
    _activeCompleter!.complete(t.isEmpty ? null : t);
  }
  _listening = false;
  return _activeCompleter!.future;
}

Future<String?> speechToTextListenOnce({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final ok = await speechToTextStart(
    languageCode: languageCode,
    timeout: timeout,
  );
  if (!ok || _activeCompleter == null) return null;
  final text =
      await _activeCompleter!.future.timeout(timeout, onTimeout: () => null);
  await speechToTextStop();
  return text;
}
