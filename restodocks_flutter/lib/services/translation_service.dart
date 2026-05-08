import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tech_card.dart';
import '../models/translation.dart';
import '../utils/dev_log.dart';
import 'ai_service_supabase.dart';
import 'supabase_service.dart';

/// Сервис для переводов с кешированием.
/// Источники: 1) кеш и БД, 2) DeepL через Edge Function `translate-text` (основной),
/// 3) MyMemory (резерв), 4) ИИ (если включено).
class TranslationService {
  /// Если false — при отсутствии в кеше/БД используется MyMemory API. Если true — вызывается ИИ.
  static bool useAiForTranslation = false;

  /// Если true — при отсутствии в кеше/БД вызывается внешний API (Google Translate или MyMemory). По умолчанию включено.
  static bool useTranslationApi = true;

  /// Legacy flag name kept for compatibility.
  /// Если true — в первую очередь используется Edge Function `translate-text` (DeepL).
  /// Иначе — сразу MyMemory.
  static bool useGoogleTranslate = true;

  final AiServiceSupabase _aiService;
  final SupabaseService _supabase;

  static final RegExp _sfPrefixRe =
      RegExp(r'^\s*(пф|п/ф|п\.ф\.|pf|prep|sf|hf)\s+', caseSensitive: false);

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
        final processed = await _postProcessTranslatedText(
          translatedText: bySource.translatedText,
          sourceText: text,
          sourceLanguage: bySource.sourceLanguage,
          targetLanguage: to,
          fieldName: fieldName,
        );
        final adapted = processed == bySource.translatedText
            ? bySource
            : Translation(
                id: bySource.id,
                entityType: bySource.entityType,
                entityId: bySource.entityId,
                fieldName: bySource.fieldName,
                sourceText: bySource.sourceText,
                sourceLanguage: bySource.sourceLanguage,
                targetLanguage: bySource.targetLanguage,
                translatedText: processed,
                createdAt: bySource.createdAt,
                createdBy: bySource.createdBy,
                isManualOverride: bySource.isManualOverride,
              );
        _cache[keyActual] = adapted;
        _cache[keyRequested] = adapted;
        if (bySource.isManualOverride && !allowOverride) {
          return adapted.translatedText;
        }
        return adapted.translatedText;
      }
    } catch (e) {
      devLog('[TranslationService] by-source-text lookup: $e');
    }

    if (from == to) return text;

    final cacheKey = '${entityType}_${entityId}_${fieldName}_${from}_${to}';

    // Проверяем локальный кеш
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      final processed = await _postProcessTranslatedText(
        translatedText: cached.translatedText,
        sourceText: text,
        sourceLanguage: from,
        targetLanguage: to,
        fieldName: fieldName,
      );
      final adapted = processed == cached.translatedText
          ? cached
          : Translation(
              id: cached.id,
              entityType: cached.entityType,
              entityId: cached.entityId,
              fieldName: cached.fieldName,
              sourceText: cached.sourceText,
              sourceLanguage: cached.sourceLanguage,
              targetLanguage: cached.targetLanguage,
              translatedText: processed,
              createdAt: cached.createdAt,
              createdBy: cached.createdBy,
              isManualOverride: cached.isManualOverride,
            );
      _cache[cacheKey] = adapted;
      // Если есть manual override и он запрещен, не перезаписываем
      if (cached.isManualOverride && !allowOverride) {
        return adapted.translatedText;
      }
      return adapted.translatedText;
    }

    // Проверяем базу данных
    try {
      final existing = await _getFromDatabase(entityType, entityId, fieldName, from, to);
      if (existing != null) {
        final processed = await _postProcessTranslatedText(
          translatedText: existing.translatedText,
          sourceText: text,
          sourceLanguage: from,
          targetLanguage: to,
          fieldName: fieldName,
        );
        final adapted = processed == existing.translatedText
            ? existing
            : Translation(
                id: existing.id,
                entityType: existing.entityType,
                entityId: existing.entityId,
                fieldName: existing.fieldName,
                sourceText: existing.sourceText,
                sourceLanguage: existing.sourceLanguage,
                targetLanguage: existing.targetLanguage,
                translatedText: processed,
                createdAt: existing.createdAt,
                createdBy: existing.createdBy,
                isManualOverride: existing.isManualOverride,
              );
        _cache[cacheKey] = adapted;
        // Если есть manual override и он запрещен, не перезаписываем
        if (existing.isManualOverride && !allowOverride) {
          return adapted.translatedText;
        }
        return adapted.translatedText;
      }
    } catch (e) {
      // Продолжаем без кеша
    }

    // 1. Перевод через внешний API: DeepL (основной, через Edge) или MyMemory (резерв).
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
        translatedText = await _postProcessTranslatedText(
          translatedText: translatedText,
          sourceText: text,
          sourceLanguage: from,
          targetLanguage: to,
          fieldName: fieldName,
        );
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
        var translatedText = await _translateWithAI(text, from, to);

        if (translatedText != null && translatedText.trim().isNotEmpty) {
          translatedText = await _postProcessTranslatedText(
            translatedText: translatedText,
            sourceText: text,
            sourceLanguage: from,
            targetLanguage: to,
            fieldName: fieldName,
          );
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

  /// Перевести через Edge Function `translate-text` (DeepL).
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
      final isFallback = data['fallback'] == true;
      final translated = data['translatedText']?.toString().trim();
      if (translated == null || translated.isEmpty) return null;
      // DeepL fallback in Edge can intentionally return original text.
      // Treat this as a miss so reserve provider can try translating.
      if (isFallback) return null;
      if (from.trim().toLowerCase() != to.trim().toLowerCase() &&
          translated.trim() == text.trim()) {
        return null;
      }
      return translated;
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

  String _semiFinishedPrefixForLanguage(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return 'ПФ';
      case 'en':
      case 'it':
      case 'de':
        return 'Prep';
      case 'es':
      case 'fr':
      case 'tr':
      case 'vi':
      case 'kk':
      default:
        return 'SF';
    }
  }

  String _normalizeSemiFinishedPrefix(
    String translatedText, {
    required String sourceText,
    required String targetLanguage,
  }) {
    final src = sourceText.trim();
    final out = translatedText.trim();
    if (src.isEmpty || out.isEmpty) return translatedText;
    final sourceLooksSemiFinished = _sfPrefixRe.hasMatch(src);
    final translatedHasPrefix = _sfPrefixRe.hasMatch(out);
    if (!sourceLooksSemiFinished && !translatedHasPrefix) return translatedText;

    final withoutPrefix = out.replaceFirst(_sfPrefixRe, '').trim();
    if (withoutPrefix.isEmpty) return translatedText;
    final prefix = _semiFinishedPrefixForLanguage(targetLanguage.toLowerCase());
    return '$prefix $withoutPrefix';
  }

  String _normalizeDishNameTranslation(
    String translatedText, {
    required String sourceText,
    required String targetLanguage,
    required String fieldName,
  }) {
    if (fieldName != 'dish_name') return translatedText;
    final src = sourceText.trim().toLowerCase();
    final to = targetLanguage.trim().toLowerCase();
    if (src.isEmpty || to.isEmpty) return translatedText;

    final enIdioms = <String, String>{
      'селедка под шубой': 'Dressed Herring Salad',
      'сельдь под шубой': 'Dressed Herring Salad',
      'оливье': 'Russian Potato Salad (Olivier)',
      'винегрет': 'Russian Beetroot Vinaigrette',
      'борщ': 'Borscht',
      'щи': 'Cabbage Soup (Shchi)',
      'пельмени': 'Pelmeni Dumplings',
      'блины': 'Blini',
    };

    if (to == 'en') {
      final idiom = enIdioms[src];
      if (idiom != null && idiom.isNotEmpty) {
        return idiom;
      }
    }
    return translatedText;
  }

  Future<String> _postProcessTranslatedText({
    required String translatedText,
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
    required String fieldName,
  }) async {
    var out = _normalizeSemiFinishedPrefix(
      translatedText,
      sourceText: sourceText,
      targetLanguage: targetLanguage,
    );
    out = _normalizeDishNameTranslation(
      out,
      sourceText: sourceText,
      targetLanguage: targetLanguage,
      fieldName: fieldName,
    );
    out = await _refineDishNameForCuisineContext(
      out,
      sourceText: sourceText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      fieldName: fieldName,
    );
    return out;
  }

  Future<String> _refineDishNameForCuisineContext(
    String translatedText, {
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
    required String fieldName,
  }) async {
    if (fieldName != 'dish_name') return translatedText;
    final source = sourceText.trim();
    final translated = translatedText.trim();
    final from = sourceLanguage.trim().toLowerCase();
    final to = targetLanguage.trim().toLowerCase();
    if (source.isEmpty || translated.isEmpty) return translatedText;
    if (from == to) return translatedText;
    if (source.length > 120 || translated.length > 140) return translatedText;

    final prompt = '''
Ты шеф-переводчик меню.
Сделай название блюда естественным для носителя языка "$to", а не дословным переводом.
Сохраняй кулинарный смысл, стиль карточки блюда и узнаваемость национального блюда.
Если есть устойчивое кулинарное название — используй его.
Верни ТОЛЬКО итоговое название без пояснений и кавычек.

Исходный язык: $from
Исходное название: "$source"
Черновой перевод: "$translated"
''';

    try {
      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });
      final refined = response?['result']?.toString().trim() ?? '';
      if (refined.isEmpty) return translatedText;
      // Защита: ИИ иногда возвращает фразы вроде "Here is..." — такие ответы игнорируем.
      if (refined.length > 140 || refined.contains('\n')) return translatedText;
      final lower = refined.toLowerCase();
      if (lower.startsWith('here is') ||
          lower.startsWith('translation:') ||
          lower.startsWith('перевод:')) {
        return translatedText;
      }
      return refined;
    } catch (_) {
      return translatedText;
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


  /// Сколько ТТК потребуют вызова [translate] в [ensureMissingTechCardDishNameTranslations]
  /// (после учёта строк из БД в [existingFromDatabase]).
  static int countTechCardsNeedingDishNameTranslation({
    required List<TechCard> techCards,
    required String targetLanguage,
    required Map<String, String> existingFromDatabase,
  }) {
    if (techCards.isEmpty) return 0;
    final out = existingFromDatabase;
    var n = 0;
    for (final tc in techCards) {
      if (_needsDishNameFill(tc, targetLanguage, out)) n++;
    }
    return n;
  }

  static bool _needsDishNameFill(
    TechCard tc,
    String targetLanguage,
    Map<String, String> out,
  ) {
    final loc = tc.dishNameLocalized;
    if (loc != null) {
      final direct = loc[targetLanguage]?.trim();
      if (direct != null && direct.isNotEmpty) return false;
    }
    final o = out[tc.id]?.trim();
    if (o != null && o.isNotEmpty) return false;
    return true;
  }

  /// Переводы названий ТТК из таблицы [translations] для целевого языка (пакетно, без N+1).
  /// При нескольких строках на один [entity_id] берётся первая непустая [translated_text].
  Future<Map<String, String>> fetchTechCardDishNameTranslationsForTargetLanguage({
    required List<String> techCardIds,
    required String targetLanguage,
    void Function(int doneChunks, int totalChunks)? onChunkProgress,
  }) async {
    final out = <String, String>{};
    if (techCardIds.isEmpty) return out;
    const chunkSize = 28;
    final totalChunks = (techCardIds.length + chunkSize - 1) ~/ chunkSize;
    var chunkIndex = 0;
    for (var i = 0; i < techCardIds.length; i += chunkSize) {
      chunkIndex++;
      onChunkProgress?.call(chunkIndex, totalChunks);
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

  /// Карточки без строки в [translations] и без [TechCard.dishNameLocalized] для целевого языка —
  /// переводим через [translate] (тот же Google/MyMemory/ИИ), результат попадает в БД и в возвращаемую карту.
  ///
  /// Без этого в UI с языком en остаётся русский `dish_name`, а префикс ПФ («Prep») уже на английском — смешение языков.
  ///
  /// Поддерживается любой `targetLanguage` (в т.ч. ru, es, de…): нельзя было
  /// ранее выходить при `ru` — тогда не догонялись подписи в overlay для «чужого» `dishName`.
  Future<Map<String, String>> ensureMissingTechCardDishNameTranslations({
    required List<TechCard> techCards,
    required String targetLanguage,
    required Map<String, String> existingFromDatabase,
    void Function(int done, int total)? onProgress,
  }) async {
    final out = Map<String, String>.from(existingFromDatabase);
    if (techCards.isEmpty) return out;

    bool needsFill(TechCard tc) => _needsDishNameFill(tc, targetLanguage, out);

    String inferSourceLang(String text) {
      final t = text.trim();
      if (t.isEmpty) return 'ru';
      if (RegExp(r'[\u0400-\u04FF]').hasMatch(t)) return 'ru';
      return 'en';
    }

    final byId = <String, TechCard>{};
    for (final tc in techCards) {
      if (!needsFill(tc)) continue;
      byId[tc.id] = tc;
    }
    if (byId.isEmpty) return out;

    final todo = byId.values.toList();
    final totalTodo = todo.length;
    var done = 0;
    void bump() {
      done++;
      onProgress?.call(done, totalTodo);
    }

    const batch = 5;
    for (var i = 0; i < todo.length; i += batch) {
      final end = (i + batch > todo.length) ? todo.length : i + batch;
      final chunk = todo.sublist(i, end);
      await Future.wait(chunk.map((tc) async {
        try {
          final rawRu = tc.dishNameLocalized?['ru']?.trim();
          final source = (rawRu != null && rawRu.isNotEmpty)
              ? rawRu
              : tc.dishName.trim();
          if (source.isEmpty) {
            return;
          }
          final from = inferSourceLang(source);
          if (from == targetLanguage) {
            out[tc.id] = source;
            return;
          }
          final translated = await translate(
            entityType: TranslationEntityType.techCard,
            entityId: tc.id,
            fieldName: 'dish_name',
            text: source,
            from: from,
            to: targetLanguage,
            userId: null,
          );
          if (translated != null && translated.trim().isNotEmpty) {
            out[tc.id] = translated.trim();
          }
        } catch (e) {
          devLog('[TranslationService] ensureMissing TTK ${tc.id}: $e');
        } finally {
          bump();
        }
      }));
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
    try {
      await _supabase.insertData('translations', data);
    } catch (e) {
      // Duplicate translation row race (409) is benign.
      final msg = e.toString().toLowerCase();
      if (msg.contains('translations') && msg.contains('409')) return;
      rethrow;
    }
  }
}