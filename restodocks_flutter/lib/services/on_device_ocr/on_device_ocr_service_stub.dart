import 'dart:typed_data';

/// Заглушка для веб и неподдерживаемых платформ (без google_mlkit).
class OnDeviceOcrService {
  static bool get isSupported => false;

  Future<String?> extractTextFromImageBytes(Uint8List imageBytes) async => null;
}
