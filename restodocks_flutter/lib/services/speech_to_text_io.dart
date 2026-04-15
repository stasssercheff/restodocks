import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

SpeechToText? _activeStt;
Completer<String?>? _activeCompleter;
String _latestText = '';
bool _listening = false;

String _localeForStt(String languageCode) {
  switch (languageCode.trim().toLowerCase()) {
    case 'en':
      return 'en_US';
    case 'es':
      return 'es_ES';
    case 'it':
      return 'it_IT';
    case 'tr':
      return 'tr_TR';
    case 'kk':
      return 'kk_KZ';
    default:
      return 'ru_RU';
  }
}

Future<bool> speechToTextSupported() async {
  final stt = SpeechToText();
  return stt.initialize(
    onStatus: (_) {},
    onError: (_) {},
    debugLogging: false,
  );
}

bool speechToTextIsListening() => _listening;

Future<bool> speechToTextStart({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (_listening) return true;
  final stt = SpeechToText();
  final ready = await stt.initialize(
    onStatus: (status) {
      if ((status == 'done' || status == 'notListening') && _listening) {
        if (!_activeCompleter!.isCompleted) {
          final text = _latestText.trim();
          _activeCompleter!.complete(text.isEmpty ? null : text);
        }
        _listening = false;
      }
    },
    onError: (_) {
      if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
        _activeCompleter!.complete(null);
      }
      _listening = false;
    },
    debugLogging: false,
  );
  if (!ready) return false;

  _activeStt = stt;
  _activeCompleter = Completer<String?>();
  _latestText = '';
  _listening = true;

  await stt.listen(
    localeId: _localeForStt(languageCode),
    listenMode: ListenMode.confirmation,
    partialResults: true,
    onResult: (SpeechRecognitionResult result) {
      _latestText = result.recognizedWords;
      if (result.finalResult && _activeCompleter != null && !_activeCompleter!.isCompleted) {
        final text = _latestText.trim();
        _activeCompleter!.complete(text.isEmpty ? null : text);
      }
    },
    listenFor: timeout,
    pauseFor: const Duration(seconds: 2),
    cancelOnError: true,
  );
  return true;
}

Future<String?> speechToTextStop() async {
  if (!_listening || _activeCompleter == null || _activeStt == null) {
    return null;
  }
  try {
    if (_activeStt!.isListening) {
      await _activeStt!.stop();
    }
  } catch (_) {}
  if (!_activeCompleter!.isCompleted) {
    final text = _latestText.trim();
    _activeCompleter!.complete(text.isEmpty ? null : text);
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
