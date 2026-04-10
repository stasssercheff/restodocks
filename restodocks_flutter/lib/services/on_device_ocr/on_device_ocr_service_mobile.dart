import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vision_text_recognition/vision_text_recognition.dart';

import 'ocr_reading_order.dart';

/// Распознавание текста на устройстве без вызова облачных LLM.
///
/// iOS: Apple Vision с приоритетом [ru-RU] (кириллица), затем упорядочивание блоков.
/// Android: Google ML Kit (латиница + частично кириллица) и тот же порядок строк.
class OnDeviceOcrService {
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Возвращает сырой текст или null при ошибке / пустом результате.
  Future<String?> extractTextFromImageBytes(Uint8List imageBytes) async {
    if (!isSupported || imageBytes.isEmpty) return null;
    if (Platform.isIOS) {
      final fromVision = await _extractWithAppleVision(imageBytes);
      if (fromVision != null && fromVision.isNotEmpty) return fromVision;
    }
    return _extractWithMlKit(imageBytes);
  }

  Future<String?> _extractWithAppleVision(Uint8List imageBytes) async {
    try {
      final available = await VisionTextRecognition.isAvailable();
      if (!available) return null;
      const config = TextRecognitionConfig(
        recognitionLevel: RecognitionLevel.accurate,
        usesLanguageCorrection: true,
        preferredLanguages: ['ru-RU', 'en-US'],
        automaticallyDetectsLanguage: false,
      );
      final result = await VisionTextRecognition.recognizeTextWithConfig(
        imageBytes,
        config,
      );
      if (result.textBlocks.isNotEmpty) {
        final laidOut = layoutFromVisionBlocks(result.textBlocks).trim();
        if (laidOut.isNotEmpty) return laidOut;
      }
      final plain = result.fullText.trim();
      return plain.isEmpty ? null : plain;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _extractWithMlKit(Uint8List imageBytes) async {
    File? file;
    TextRecognizer? recognizer;
    try {
      final dir = await getTemporaryDirectory();
      file = File(
          '${dir.path}/mlkit_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(imageBytes, flush: true);
      final inputImage = InputImage.fromFilePath(file.path);
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      final laidOut = layoutFromMlKitRecognizedText(recognized).trim();
      return laidOut.isEmpty ? null : laidOut;
    } catch (_) {
      return null;
    } finally {
      try {
        await recognizer?.close();
      } catch (_) {}
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
