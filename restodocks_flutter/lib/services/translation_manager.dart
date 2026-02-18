import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../models/translation.dart';
import 'ai_service_supabase.dart';
import 'translation_service.dart';

/// Универсальный менеджер переводов
class TranslationManager {
  static const List<String> _supportedLanguages = ['ru', 'en', 'de', 'fr', 'es'];

  final AiServiceSupabase _aiService;
  final TranslationService _translationService;

  TranslationManager({
    required AiServiceSupabase aiService,
    required TranslationService translationService,
  }) : _aiService = aiService,
       _translationService = translationService;

  /// Обработать сохранение сущности и выполнить переводы
  Future<void> handleEntitySave({
    required TranslationEntityType entityType,
    required String entityId,
    required Map<String, String> textFields, // fieldName -> text
    required String sourceLanguage,
    String? userId,
  }) async {
    debugPrint('TranslationManager: Processing save for $entityType:$entityId');

    // Определяем язык оригинала если не указан
    final detectedLanguage = sourceLanguage.isNotEmpty
        ? sourceLanguage
        : await _detectLanguage(textFields.values.join(' '));

    debugPrint('TranslationManager: Detected language: $detectedLanguage');

    // Переводим на все поддерживаемые языки
    for (final fieldName in textFields.keys) {
      final sourceText = textFields[fieldName]!;
      if (sourceText.trim().isEmpty) continue;

      for (final targetLang in _supportedLanguages) {
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
          debugPrint('TranslationManager: Failed to translate $fieldName to $targetLang: $e');
        }
      }
    }

    debugPrint('TranslationManager: Translation processing completed');
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
      debugPrint('TranslationManager: Failed to get localized text: $e');
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

  /// Сгенерировать переводы для названия продукта
  Future<Map<String, String>> generateTranslationsForProduct(String productName, String sourceLanguage) async {
    final translations = <String, String>{};
    translations[sourceLanguage] = productName;

    for (final targetLang in _supportedLanguages) {
      if (targetLang == sourceLanguage) continue;

      try {
        final translatedText = await _translationService.translate(
          entityType: TranslationEntityType.product,
          entityId: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          fieldName: 'name',
          text: productName,
          from: sourceLanguage,
          to: targetLang,
          allowOverride: true,
        );

        if (translatedText != null && translatedText != productName) {
          translations[targetLang] = translatedText;
        }
      } catch (e) {
        debugPrint('Translation error for $targetLang: $e');
      }
    }

    return translations;
  }

  /// Определить язык текста через AI
  Future<String> _detectLanguage(String text) async {
    if (text.trim().isEmpty) return 'en';

    try {
      final prompt = '''
Определи язык следующего текста. Верни только код языка (ru, en, de, fr, es, it, zh, ja, ko).
Если текст на нескольких языках, верни основной язык.

Текст: "${text.substring(0, 500)}"

Код языка:
''';

      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });

      final detectedLang = response?['result']?.toString().trim().toLowerCase() ?? 'en';

      // Валидируем
      return _supportedLanguages.contains(detectedLang) ? detectedLang : 'en';
    } catch (e) {
      debugPrint('TranslationManager: Failed to detect language: $e');
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