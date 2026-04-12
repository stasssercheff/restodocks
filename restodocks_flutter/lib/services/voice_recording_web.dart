import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:web/web.dart' as web;

final AudioRecorder _recorder = AudioRecorder();

const RecordConfig _kChatVoiceRecordConfig = RecordConfig(
  encoder: AudioEncoder.aacLc,
  bitRate: 48000,
  sampleRate: 22050,
  numChannels: 1,
  noiseSuppress: true,
  echoCancel: true,
);

/// Запасной кодек для браузеров без AAC в MediaRecorder.
const RecordConfig _kChatVoiceOpusFallback = RecordConfig(
  encoder: AudioEncoder.opus,
  bitRate: 64000,
  sampleRate: 48000,
  numChannels: 1,
  noiseSuppress: true,
  echoCancel: true,
);

Future<bool> voiceRecordingSupported() async => true;

Future<bool> voiceHasMicPermission() async => _recorder.hasPermission();

Future<String?> voiceStartRecordingToPath() async {
  if (!await _recorder.hasPermission()) return null;
  final path = 'chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
  try {
    if (!await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      await _recorder.start(_kChatVoiceOpusFallback, path: path);
    } else {
      await _recorder.start(_kChatVoiceRecordConfig, path: path);
    }
  } catch (_) {
    try {
      await _recorder.start(_kChatVoiceOpusFallback, path: path);
    } catch (e) {
      return null;
    }
  }
  return path;
}

Future<String?> voiceStopRecording() async => _recorder.stop();

Future<void> voiceAbortRecording() async {
  try {
    await _recorder.cancel();
  } catch (_) {}
}

Future<Uint8List?> voiceReadFileBytes(String path) async {
  if (path.isEmpty) return null;
  try {
    if (path.startsWith('blob:')) {
      final r = await http.get(Uri.parse(path));
      if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
      return null;
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> voiceDeleteTempFile(String? path) async {
  if (path == null || path.isEmpty) return;
  if (path.startsWith('blob:')) {
    try {
      web.URL.revokeObjectURL(path);
    } catch (_) {}
  }
}
