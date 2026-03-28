import 'moderation_item.dart';

/// Параметры перехода на экран модерации импорта (GoRouter `extra`).
class ImportReviewPayload {
  const ImportReviewPayload({
    required this.items,
    this.generateTranslationsForNewProducts = false,
    this.importSourceLanguage,
  });

  final List<ModerationItem> items;
  /// Как при интеллектуальном импорте Excel: после создания продукта — `TranslationManager`.
  final bool generateTranslationsForNewProducts;
  /// Язык исходных названий (код листа Excel и т.п.), по умолчанию в экране — `en`.
  final String? importSourceLanguage;
}
