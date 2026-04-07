import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Free on-device OCR helper used for beta photo parsing.
class FreeOcrService {
  Future<String?> extractTextFromImage(XFile image) async {
    if (kIsWeb) {
      return _extractTextOnWeb(image);
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(image.path);
      final result = await recognizer.processImage(input);
      final text = result.text.trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  Future<String?> _extractTextOnWeb(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
      // Free OCR.Space public test key (strictly limited). Can be overridden
      // in builds with: --dart-define=OCR_SPACE_API_KEY=...
      const apiKey = String.fromEnvironment(
        'OCR_SPACE_API_KEY',
        defaultValue: 'helloworld',
      );
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.ocr.space/parse/image'),
      );
      req.fields['apikey'] = apiKey;
      req.fields['language'] = 'rus';
      req.fields['isOverlayRequired'] = 'false';
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: image.name.isEmpty ? 'upload.jpg' : image.name,
        ),
      );
      final streamed = await req.send();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) return null;
      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final parsed = json['ParsedResults'];
      if (parsed is! List || parsed.isEmpty) return null;
      final first = parsed.first;
      if (first is! Map<String, dynamic>) return null;
      final text = (first['ParsedText'] as String? ?? '').trim();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }
}
