import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../models/translation.dart';
import '../utils/dev_log.dart';
import 'ai_service_supabase.dart';
import 'translation_service.dart';

/// Универсальный менеджер переводов. supportedLanguageCodes — из LocalizationService.productLanguageCodes.
class TranslationManager {
  final AiServiceSupabase _aiService;
  final TranslationService _translationService;
  final List<String> Function() _getSupportedLanguages;

  TranslationManager({
    required AiServiceSupabase aiService,
    required TranslationService translationService,
    required List<String> Function() getSupportedLanguages,
  })  : _aiService = aiService,
        _translationService = translationService,
        _getSupportedLanguages = getSupportedLanguages;

  /// Обработать сохранение сущности и выполнить переводы
  Future<void> handleEntitySave({
    required TranslationEntityType entityType,
    required String entityId,
    required Map<String, String> textFields, // fieldName -> text
    required String sourceLanguage,
    String? userId,
    List<String>? targetLanguages,
  }) async {
    devLog('TranslationManager: Processing save for $entityType:$entityId');

    // Определяем язык оригинала если не указан
    final detectedLanguage = sourceLanguage.isNotEmpty
        ? sourceLanguage
        : await _detectLanguage(textFields.values.join(' '));

    devLog('TranslationManager: Detected language: $detectedLanguage');

    // Переводим на все поддерживаемые языки
    for (final fieldName in textFields.keys) {
      final sourceText = textFields[fieldName]!;
      if (sourceText.trim().isEmpty) continue;

      final targets = targetLanguages ?? _getSupportedLanguages();
      for (final targetLang in targets) {
        if (targetLang == detectedLanguage) continue;

        try {
          await _translationService.translate(
            entityType: entityType,
            entityId: entityId,
            fieldName: fieldName,
            text: sourceText,
            from: detectedLanguage,
            to: targetLang,
            userId: userId,
            allowOverride: false, // Не перезаписывать manual overrides
          );
        } catch (e) {
          devLog(
              'TranslationManager: Failed to translate $fieldName to $targetLang: $e');
        }
      }
    }

    devLog('TranslationManager: Translation processing completed');
  }

  /// Собирает [Product.names]-совместимую карту для всех [productLanguageCodes]
  /// (после [handleEntitySave] повторный вызов [TranslationService.translate] в основном бьёт в кеш).
  ///
  /// Если задан [mergeExisting], непустые значения из него сохраняются; переводятся только пустые коды.
  Future<Map<String, String>> materializeProductNames({
    required String productId,
    required String sourceLanguage,
    required String sourceText,
    Map<String, String>? mergeExisting,
  }) async {
    final text = sourceText.trim();
    final codes = _getSupportedLanguages();
    if (codes.isEmpty) {
      return {sourceLanguage: text};
    }
    final from = codes.contains(sourceLanguage) ? sourceLanguage : codes.first;

    final names = <String, String>{};
    for (final c in codes) {
      final merged = mergeExisting?[c]?.trim();
      if (merged != null && merged.isNotEmpty) {
        names[c] = merged;
      } else {
        names[c] = text;
      }
    }
    names[from] = text;

    for (final lang in codes) {
      if (lang == from) continue;
      final keep = mergeExisting?[lang]?.trim();
      if (keep != null && keep.isNotEmpty) continue;
      try {
        final t = await _translationService.translate(
          entityType: TranslationEntityType.product,
          entityId: productId,
          fieldName: 'name',
          text: text,
          from: from,
          to: lang,
          allowOverride: false,
        );
        if (t != null && t.trim().isNotEmpty) {
          names[lang] = t.trim();
        }
      } catch (e) {
        devLog('TranslationManager: materializeProductNames $lang: $e');
      }
    }

    return names;
  }

  /// Получить локализованный текст для сущности
  Future<String> getLocalizedText({
    required TranslationEntityType entityType,
    required String entityId,
    required String fieldName,
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (targetLanguage == sourceLanguage) return sourceText;

    try {
      final translation = await _translationService.translate(
        entityType: entityType,
        entityId: entityId,
        fieldName: fieldName,
        text: sourceText,
        from: sourceLanguage,
        to: targetLanguage,
        allowOverride: true, // Позволяем получать даже manual overrides
      );

      return translation ?? sourceText; // Fallback на оригинал
    } catch (e) {
      devLog('TranslationManager: Failed to get localized text: $e');
      return sourceText;
    }
  }

  /// Отметить перевод как manual override
  Future<void> markAsManualOverride({
    required TranslationEntityType entityType,
    required String entityId,
    required String fieldName,
    required String sourceLanguage,
    required String targetLanguage,
    required String manualTranslation,
    String? userId,
  }) async {
    // Создаем или обновляем перевод с флагом manual override
    final translation = Translation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      sourceText: '', // Не важен для manual override
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      translatedText: manualTranslation,
      createdAt: DateTime.now(),
      createdBy: userId,
      isManualOverride: true,
    );

    // Сохраняем в кеш и БД
    await _translationService.saveToDatabase(translation);
    _translationService.cache[translation.cacheKey] = translation;
  }

  /// Определить язык текста через AI
  Future<String> _detectLanguage(String text) async {
    if (text.trim().isEmpty) return 'en';

    try {
      final prompt = '''
Определи язык следующего текста. Верни только код языка (ru, en, es, kk, de, fr, it, tr, vi, zh, ja, ko).
Если текст на нескольких языках, верни основной язык.

Текст: "${text.substring(0, 500)}"

Код языка:
''';

      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });

      final detectedLang =
          response?['result']?.toString().trim().toLowerCase() ?? 'en';

      // Валидируем
      final codes = _getSupportedLanguages();
      return codes.contains(detectedLang) ? detectedLang : 'en';
    } catch (e) {
      devLog('TranslationManager: Failed to detect language: $e');
      return 'en'; // fallback
    }
  }

  /// Очистить кеш переводов
  void clearCache() {
    _translationService.clearCache();
  }

  /// Получить статистику переводов
  Future<Map<String, int>> getTranslationStats() async {
    return await _translationService.getTranslationStats();
  }
}
