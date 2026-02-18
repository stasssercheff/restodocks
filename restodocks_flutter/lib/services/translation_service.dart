import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/translation.dart';
import 'ai_service_supabase.dart';
import 'supabase_service.dart';

/// Сервис для переводов с кешированием
class TranslationService {
  final AiServiceSupabase _aiService;
  final SupabaseService _supabase;

  // Локальный кеш переводов
  final Map<String, Translation> _cache = {};

  TranslationService({
    required AiServiceSupabase aiService,
    required SupabaseService supabase,
  }) : _aiService = aiService,
       _supabase = supabase;

  /// Перевести текст с кешированием
  Future<String?> translate({
    required String text,
    required String from,
    required String to,
    String? userId,
  }) async {
    if (text.trim().isEmpty) return text;
    if (from == to) return text;

    final cacheKey = '${text}_${from}_${to}';

    // Проверяем локальный кеш
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!.translatedText;
    }

    // Проверяем базу данных
    try {
      final existing = await _getFromDatabase(text, from, to);
      if (existing != null) {
        _cache[cacheKey] = existing;
        return existing.translatedText;
      }
    } catch (e) {
      // Продолжаем без кеша
    }

    // Выполняем перевод через AI
    try {
      final translatedText = await _translateWithAI(text, from, to);

      if (translatedText != null && translatedText.trim().isNotEmpty) {
        // Сохраняем в базу данных
        final translation = Translation.create(
          sourceText: text,
          sourceLanguage: from,
          targetLanguage: to,
          translatedText: translatedText,
          createdBy: userId,
        );

        await _saveToDatabase(translation);
        _cache[cacheKey] = translation;

        return translatedText;
      }
    } catch (e) {
      // Возвращаем null в случае ошибки
    }

    return null;
  }

  /// Перевести через AI
  Future<String?> _translateWithAI(String text, String from, String to) async {
    final prompt = '''
Переведи следующий текст с языка $from на язык $to.
Сохрани стиль и терминологию, особенно если это название продукта.

Текст: "$text"

Верни только переведенный текст без дополнительных комментариев.
''';

    try {
      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });

      return response?['result']?.toString().trim();
    } catch (e) {
      return null;
    }
  }

  /// Получить перевод из базы данных
  Future<Translation?> _getFromDatabase(String text, String from, String to) async {
    final response = await _supabase.client
        .from('translations')
        .select()
        .eq('source_text', text)
        .eq('source_language', from)
        .eq('target_language', to)
        .maybeSingle();

    if (response != null) {
      return Translation.fromJson(response);
    }

    return null;
  }

  /// Сохранить перевод в базу данных
  Future<void> _saveToDatabase(Translation translation) async {
    await _supabase.insertData('translations', translation.toJson());
  }

  /// Очистить кеш
  void clearCache() {
    _cache.clear();
  }

  /// Получить статистику переводов
  Future<Map<String, int>> getTranslationStats() async {
    final stats = <String, int>{};

    try {
      final response = await _supabase.client
          .from('translations')
          .select('source_language, target_language')
          .limit(1000);

      for (final row in response) {
        final source = row['source_language'] as String;
        final target = row['target_language'] as String;
        final key = '$source->$target';

        stats[key] = (stats[key] ?? 0) + 1;
      }
    } catch (e) {
      // Игнорируем ошибки статистики
    }

    return stats;
  }
}