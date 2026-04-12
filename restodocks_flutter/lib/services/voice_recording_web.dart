import 'dart:typed_data';

Future<bool> voiceRecordingSupported() async => false;

Future<bool> voiceHasMicPermission() async => false;

Future<String?> voiceStartRecordingToPath() async => null;

Future<String?> voiceStopRecording() async => null;

Future<Uint8List?> voiceReadFileBytes(String path) async => null;

Future<void> voiceDeleteTempFile(String? path) async {}
