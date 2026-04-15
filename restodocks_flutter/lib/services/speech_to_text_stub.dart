Future<bool> speechToTextSupported() async => false;

bool speechToTextIsListening() => false;

Future<bool> speechToTextStart({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async =>
    false;

Future<String?> speechToTextStop() async => null;

Future<String?> speechToTextListenOnce({
  String languageCode = 'ru',
  Duration timeout = const Duration(seconds: 12),
}) async {
  return null;
}
