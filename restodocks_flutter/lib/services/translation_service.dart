import 'dart:convert';

import 'package:http/http.dart' as http;

/// Сервис перевода названий продуктов (MyMemory API, бесплатно, без ключа)
class TranslationService {
  static const _baseUrl = 'https://api.mymemory.translated.net/get';
  static const _timeout = Duration(seconds: 5);

  /// Перевести текст с fromLang на toLang
  static Future<String?> translate(String text, String fromLang, String toLang) async {
    if (text.trim().isEmpty || fromLang == toLang) return text;
    final q = Uri.encodeQueryComponent(text.trim());
    final url = Uri.parse('$_baseUrl?q=$q&langpair=$fromLang|$toLang');
    try {
      final resp = await http.get(url).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>?;
      final status = json?['responseStatus'] as int? ?? 0;
      if (status != 200) return null;
      final tr = json?['responseData'] as Map<String, dynamic>?;
      final translated = tr?['translatedText'] as String?;
      return (translated != null && translated.trim().isNotEmpty) ? translated.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Заполнить переводы для всех языков (sourceLang — язык исходного текста)
  static Future<Map<String, String>> translateToAll(
    String text,
    String sourceLang,
    List<String> targetLangs,
  ) async {
    final result = <String, String>{};
    result[sourceLang] = text;
    for (final target in targetLangs) {
      if (target == sourceLang) continue;
      final tr = await translate(text, sourceLang, target);
      if (tr != null) result[target] = tr;
      // Небольшая задержка, чтобы не перегружать API
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return result;
  }
}
