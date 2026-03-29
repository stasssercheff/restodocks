import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/translation.dart';
import '../utils/dev_log.dart';
import 'ai_service_supabase.dart';
import 'supabase_service.dart';

/// Сервис для переводов с кешированием.
/// Источники: 1) кеш и БД, 2) Google Cloud Translation API (основной), 3) MyMemory (fallback), 4) ИИ (если включено).
class TranslationService {
  /// Если false — при отсутствии в кеше/БД используется MyMemory API. Если true — вызывается ИИ.
  static bool useAiForTranslation = false;

  /// Если true — при отсутствии в кеше/БД вызывается внешний API (Google Translate или MyMemory). По умолчанию включено.
  static bool useTranslationApi = true;

  /// Если true — в первую очередь используется Google Cloud Translation API. Иначе — MyMemory. По умолчанию true.
  static bool useGoogleTranslate = true;

  final AiServiceSupabase _aiService;
  final SupabaseService _supabase;

  // Локальный кеш переводов
  final Map<String, Translation> _cache = {};

  // Публичный геттер для кеша
  Map<String, Translation> get cache => _cache;

  TranslationService({
    required AiServiceSupabase aiService,
    required SupabaseService supabase,
  }) : _aiService = aiService,
       _supabase = supabase;

  /// Перевести текст с кешированием для сущности
  Future<String?> translate({
    required TranslationEntityType entityType,
    required String entityId,
    required String fieldName,
    required String text,
    required String from,
    required String to,
    String? userId,
    bool allowOverride = true,
  }) async {
    if (text.trim().isEmpty) return text;

    // Сквозной кеш в БД: любая уже сохранённая пара для этой версии исходного текста
    // (не зависит от того, с каким `from` вызвали translate).
    try {
      final bySource = await _getFromDatabaseBySourceTextAndTarget(
        entityType,
        entityId,
        fieldName,
        text.trim(),
        to,
      );
      if (bySource != null) {
        final keyRequested =
            '${entityType}_${entityId}_${fieldName}_${from}_${to}';
        final keyActual =
            '${entityType}_${entityId}_${fieldName}_${bySource.sourceLanguage}_${to}';
        _cache[keyActual] = bySource;
        _cache[keyRequested] = bySource;
        if (bySource.isManualOverride && !allowOverride) {
          return bySource.translatedText;
        }
        return bySource.translatedText;
      }
    } catch (e) {
      devLog('[TranslationService] by-source-text lookup: $e');
    }

    if (from == to) return text;

    final cacheKey = '${entityType}_${entityId}_${fieldName}_${from}_${to}';

    // Проверяем локальный кеш
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      // Если есть manual override и он запрещен, не перезаписываем
      if (cached.isManualOverride && !allowOverride) {
        return cached.translatedText;
      }
      return cached.translatedText;
    }

    // Проверяем базу данных
    try {
      final existing = await _getFromDatabase(entityType, entityId, fieldName, from, to);
      if (existing != null) {
        _cache[cacheKey] = existing;
        // Если есть manual override и он запрещен, не перезаписываем
        if (existing.isManualOverride && !allowOverride) {
          return existing.translatedText;
        }
        return existing.translatedText;
      }
    } catch (e) {
      // Продолжаем без кеша
    }

    // 1. Перевод через внешний API: Google Translate (основной) или MyMemory (fallback)
    if (useTranslationApi && !useAiForTranslation) {
      String? translatedText;
      if (useGoogleTranslate) {
        try {
          translatedText = await _translateWithGoogle(text, from, to);
        } catch (_) {}
      }
      if ((translatedText == null || translatedText.trim().isEmpty) && useTranslationApi) {
        try {
          translatedText = await _translateWithMyMemory(text, from, to);
        } catch (_) {}
      }
      if (translatedText != null && translatedText.trim().isNotEmpty) {
        final translation = Translation(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          entityType: entityType,
          entityId: entityId,
          fieldName: fieldName,
          sourceText: text,
          sourceLanguage: from,
          targetLanguage: to,
          translatedText: translatedText,
          createdAt: DateTime.now(),
          createdBy: userId,
          isManualOverride: false,
        );
        try {
          await saveToDatabase(translation);
        } catch (e) {
          devLog('[TranslationService] saveToDatabase failed: $e');
        }
        _cache[cacheKey] = translation;
        return translatedText;
      }
    }

    // 2. Перевод через AI (только если useAiForTranslation == true)
    if (useAiForTranslation) {
      try {
        final translatedText = await _translateWithAI(text, from, to);

        if (translatedText != null && translatedText.trim().isNotEmpty) {
          final translation = Translation(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            entityType: entityType,
            entityId: entityId,
            fieldName: fieldName,
            sourceText: text,
            sourceLanguage: from,
            targetLanguage: to,
            translatedText: translatedText,
            createdAt: DateTime.now(),
            createdBy: userId,
            isManualOverride: false,
          );
          await saveToDatabase(translation);
          _cache[cacheKey] = translation;
          return translatedText;
        }
      } catch (e) {
        // Возвращаем null в случае ошибки
      }
    }

    return null;
  }

  /// Перевести через Google Cloud Translation API (Edge Function translate-text)
  Future<String?> _translateWithGoogle(String text, String from, String to) async {
    if (text.trim().isEmpty) return null;
    try {
      final res = await _supabase.client.functions.invoke(
        'translate-text',
        body: {'text': text, 'from': from, 'to': to},
      );
      if (res.status != 200) return null;
      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      if (data.containsKey('error')) return null;
      final translated = data['translatedText']?.toString().trim();
      if (translated != null && translated.isNotEmpty) return translated;
    } catch (_) {}
    return null;
  }

  /// Перевести через MyMemory API (бесплатно, ~5000 символов/день анонимно) — fallback
  Future<String?> _translateWithMyMemory(String text, String from, String to) async {
    if (text.trim().isEmpty) return null;
    // MyMemory лимит ~500 байт на запрос; для длинных текстов режем
    final trimmed = text.length > 450 ? text.substring(0, 450) : text;
    final langPair = '$from|$to';
    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get'
      '?q=${Uri.encodeComponent(trimmed)}'
      '&langpair=$langPair',
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      final respData = json?['responseData'] as Map<String, dynamic>?;
      final translated = respData?['translatedText']?.toString().trim();
      if (translated != null && translated.isNotEmpty && translated != trimmed) {
        return translated;
      }
    } catch (_) {}
    return null;
  }

  /// Перевести через AI
  Future<String?> _translateWithAI(String text, String from, String to) async {
    final prompt = '''
Ты профессиональный шеф-переводчик. Переведи кулинарный текст с языка $from на язык $to, сохраняя терминологию и структуру. Не переводи бренды и названия в кавычках.

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

  /// Перевод для данной версии source_text и целевого языка (любой source_language в строке).
  Future<Translation?> _getFromDatabaseBySourceTextAndTarget(
    TranslationEntityType entityType,
    String entityId,
    String fieldName,
    String sourceText,
    String targetLanguage,
  ) async {
    final rows = await _supabase.client
        .from('translations')
        .select()
        .eq('entity_type', entityType.name)
        .eq('entity_id', entityId)
        .eq('field_name', fieldName)
        .eq('source_text', sourceText)
        .eq('target_language', targetLanguage)
        .limit(1);
    if (rows is List && rows.isNotEmpty) {
      return Translation.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
      );
    }
    return null;
  }

  /// Получить перевод из базы данных
  Future<Translation?> _getFromDatabase(
    TranslationEntityType entityType,
    String entityId,
    String fieldName,
    String from,
    String to,
  ) async {
    final response = await _supabase.client
        .from('translations')
        .select()
        .eq('entity_type', entityType.name)
        .eq('entity_id', entityId)
        .eq('field_name', fieldName)
        .eq('source_language', from)
        .eq('target_language', to)
        .maybeSingle();

    if (response != null) {
      return Translation.fromJson(Map<String, dynamic>.from(response as Map));
    }

    return null;
  }


  /// Переводы названий ТТК из таблицы [translations] для целевого языка (пакетно, без N+1).
  /// При нескольких строках на один [entity_id] берётся первая непустая [translated_text].
  Future<Map<String, String>> fetchTechCardDishNameTranslationsForTargetLanguage({
    required List<String> techCardIds,
    required String targetLanguage,
  }) async {
    final out = <String, String>{};
    if (techCardIds.isEmpty) return out;
    const chunkSize = 90;
    for (var i = 0; i < techCardIds.length; i += chunkSize) {
      final end = (i + chunkSize > techCardIds.length)
          ? techCardIds.length
          : i + chunkSize;
      final chunk = techCardIds.sublist(i, end);
      try {
        final rows = await _supabase.client
            .from('translations')
            .select('entity_id, translated_text')
            .eq('entity_type', TranslationEntityType.techCard.name)
            .eq('field_name', 'dish_name')
            .eq('target_language', targetLanguage)
            .inFilter('entity_id', chunk);
        if (rows is! List) continue;
        for (final raw in rows) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final id = m['entity_id']?.toString();
          final text = m['translated_text']?.toString().trim();
          if (id == null || id.isEmpty) continue;
          if (text == null || text.isEmpty) continue;
          out.putIfAbsent(id, () => text);
        }
      } catch (e) {
        devLog('[TranslationService] batch tech_card dish_name: $e');
      }
    }
    return out;
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

  /// Сохранить перевод в базу данных (public для TranslationManager)
  Future<void> saveToDatabase(Translation translation) async {
    final data = translation.toJson();
    data.remove('id'); // Убираем id для insert

    await _supabase.insertData('translations', data);
  }
}