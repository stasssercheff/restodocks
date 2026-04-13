import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

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

Future<String?> speechToTextListenOnce({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  final stt = SpeechToText();
  final ready = await stt.initialize(
    onStatus: (_) {},
    onError: (_) {},
    debugLogging: false,
  );
  if (!ready) return null;

  final completer = Completer<String?>();
  String latest = '';

  void finish() {
    if (!completer.isCompleted) {
      final text = latest.trim();
      completer.complete(text.isEmpty ? null : text);
    }
  }

  await stt.listen(
    localeId: _localeForStt(languageCode),
    listenMode: ListenMode.confirmation,
    partialResults: false,
    onResult: (SpeechRecognitionResult result) {
      latest = result.recognizedWords;
      if (result.finalResult) finish();
    },
    listenFor: timeout,
    pauseFor: const Duration(seconds: 2),
    cancelOnError: true,
  );

  final text = await completer.future.timeout(timeout, onTimeout: () => null);
  if (stt.isListening) {
    await stt.stop();
  }
  return text;
}
