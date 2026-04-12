import 'dart:io' show File;

import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

final AudioRecorder _recorder = AudioRecorder();

/// Речь: моно, AAC-LC, пониженный битрейт и частота — меньше объём без серверного перекодирования.
const RecordConfig _kChatVoiceRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 48000,
  sampleRate: 22050,
  numChannels: 1,
  noiseSuppress: true,
  echoCancel: true,
);

Future<bool> voiceRecordingSupported() async => true;

Future<bool> voiceHasMicPermission() async => _recorder.hasPermission();

Future<String?> voiceStartRecordingToPath() async {
  if (!await _recorder.hasPermission()) return null;
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  await _recorder.start(
    _kChatVoiceRecordConfig,
    path: path,
  );
  return path;
}

Future<String?> voiceStopRecording() async => _recorder.stop();

Future<void> voiceAbortRecording() async {
  try {
    await _recorder.cancel();
  } catch (_) {}
}

Future<Uint8List?> voiceReadFileBytes(String path) async {
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> voiceDeleteTempFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
