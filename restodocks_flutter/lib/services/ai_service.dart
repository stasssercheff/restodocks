import 'dart:typed_data';

import 'nutrition_api_service.dart';

// ---------------------------------------------------------------------------
// Результаты ИИ (для генерации чеклиста, чека, ТТК, продукта, КБЖУ)
// ---------------------------------------------------------------------------

/// Результат генерации чеклиста по текстовому запросу.
class GeneratedChecklist {
  final String name;
  final List<String> itemTitles;

  const GeneratedChecklist({
    required this.name,
    required this.itemTitles,
  });
}

/// Одна строка распознанного чека.
class ReceiptLine {
  final String productName;
  final double quantity;
  final String? unit;
  final double? price;

  const ReceiptLine({
    required this.productName,
    required this.quantity,
    this.unit,
    this.price,
  });
}

/// Результат распознавания чека (фото).
class ReceiptRecognitionResult {
  final List<ReceiptLine> lines;
  final String? rawText;

  const ReceiptRecognitionResult({
    required this.lines,
    this.rawText,
  });
}

/// Один ингредиент, извлечённый из карточки ТТК (фото/Excel).
/// Поля соответствуют ячейкам таблицы ТТК: наименование, брутто, отход %, нетто, способ приготовления, ужарка %, единица.
class TechCardIngredientLine {
  final String productName;
  final double? grossGrams;
  final double? netGrams;
  final String? unit;
  final String? cookingMethod;
  /// Процент отхода при первичной обработке (колонка «Отход %»), 0–100.
  final double? primaryWastePct;
  /// Процент ужарки/усушки (колонка «Ужарка %»), 0–100.
  final double? cookingLossPct;

  const TechCardIngredientLine({
    required this.productName,
    this.grossGrams,
    this.netGrams,
    this.unit,
    this.cookingMethod,
    this.primaryWastePct,
    this.cookingLossPct,
  });
}

/// Результат распознавания ТТК (фото карточки или Excel).
class TechCardRecognitionResult {
  final String? dishName;
  final String? technologyText;
  final List<TechCardIngredientLine> ingredients;
  final bool? isSemiFinished;

  const TechCardRecognitionResult({
    this.dishName,
    this.technologyText,
    this.ingredients = const [],
    this.isSemiFinished,
  });
}

/// Результат распознавания продукта при ручном вводе.
class ProductRecognitionResult {
  final String normalizedName;
  final String? suggestedCategory;
  final String? suggestedUnit;
  /// Предложенный процент отхода при первичной обработке (0–100), для расчёта нетто из брутто.
  final double? suggestedWastePct;

  const ProductRecognitionResult({
    required this.normalizedName,
    this.suggestedCategory,
    this.suggestedUnit,
    this.suggestedWastePct,
  });
}

/// Результат парсинга списка продуктов (файл или текст)
class ParsedProductItem {
  final String name;
  final double? price;
  final String? unit;

  const ParsedProductItem({required this.name, this.price, this.unit});
}

/// Результат верификации продукта ИИ: возможная цена, КБЖУ, исправление названия (для сверки по списку).
class ProductVerificationResult {
  final String? normalizedName;
  final String? suggestedCategory;
  final String? suggestedUnit;
  final double? suggestedPrice;
  final double? suggestedCalories;
  final double? suggestedProtein;
  final double? suggestedFat;
  final double? suggestedCarbs;

  const ProductVerificationResult({
    this.normalizedName,
    this.suggestedCategory,
    this.suggestedUnit,
    this.suggestedPrice,
    this.suggestedCalories,
    this.suggestedProtein,
    this.suggestedFat,
    this.suggestedCarbs,
  });
}

// ---------------------------------------------------------------------------
// Сервис ИИ: интерфейс и заглушка
// ---------------------------------------------------------------------------

/// Единая точка вызова ИИ/OCR. Реальные реализации — через backend (Edge Function),
/// чтобы не хранить API-ключи в приложении. Текущая реализация — заглушка.
abstract class AiService {
  /// Генерация чеклиста по запросу пользователя (название + пункты).
  /// [context] — опционально: продукты, сотрудники, ТТК, график (ИИ учитывает при генерации).
  Future<GeneratedChecklist?> generateChecklistFromPrompt(String prompt, {Map<String, dynamic>? context});

  /// Всеядный парсинг списка продуктов из сырых строк (Excel/CSV/текст).
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text});

  /// Батч-исправление названий продуктов (опечатки, сленг).
  Future<List<String>> normalizeProductNames(List<String> names);

  /// Поиск дубликатов в списке продуктов по названиям.
  Future<List<List<String>>> findDuplicates(List<({String id, String name})> products);

  /// Распознавание чека по фото (OCR + структурирование).
  Future<ReceiptRecognitionResult?> recognizeReceipt(Uint8List imageBytes);

  /// Распознавание ТТК по фото карточки (OCR + извлечение полей).
  Future<TechCardRecognitionResult?> recognizeTechCardFromImage(Uint8List imageBytes);

  /// Парсинг ТТК из Excel (байты .xlsx) — одна карточка.
  Future<TechCardRecognitionResult?> parseTechCardFromExcel(Uint8List xlsxBytes);

  /// Парсинг всех ТТК из одного документа Excel (несколько карточек в одном файле).
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes);

  /// Распознавание продукта по введённому тексту (нормализация, категория, единица).
  Future<ProductRecognitionResult?> recognizeProduct(String userInput);

  /// Уточнение или получение КБЖУ по названию (fallback/дополнение к Open Food Facts).
  Future<NutritionResult?> refineOrGetNutrition(String productName, NutritionResult? existing);

  /// Верификация продукта для сверки по списку: возможная цена (если не указана), КБЖУ, исправление названия.
  Future<ProductVerificationResult?> verifyProduct(
    String productName, {
    double? currentPrice,
    NutritionResult? currentNutrition,
  });
}

/// Заглушка: все методы возвращают null / пустые данные. Замените на реализацию,
/// вызывающую ваши backend endpoints (Supabase Edge Functions или отдельный API).
class AiServiceStub implements AiService {
  @override
  Future<GeneratedChecklist?> generateChecklistFromPrompt(String prompt, {Map<String, dynamic>? context}) async =>
      null;

  @override
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text}) async => [];

  @override
  Future<List<String>> normalizeProductNames(List<String> names) async => names;

  @override
  Future<List<List<String>>> findDuplicates(List<({String id, String name})> products) async => [];

  @override
  Future<ReceiptRecognitionResult?> recognizeReceipt(Uint8List imageBytes) async =>
      null;

  @override
  Future<TechCardRecognitionResult?> recognizeTechCardFromImage(Uint8List imageBytes) async =>
      null;

  @override
  Future<TechCardRecognitionResult?> parseTechCardFromExcel(Uint8List xlsxBytes) async =>
      null;

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes) async =>
      [];

  @override
  Future<ProductRecognitionResult?> recognizeProduct(String userInput) async =>
      null;

  @override
  Future<NutritionResult?> refineOrGetNutrition(String productName, NutritionResult? existing) async =>
      null;

  @override
  Future<ProductVerificationResult?> verifyProduct(
    String productName, {
    double? currentPrice,
    NutritionResult? currentNutrition,
  }) async =>
      null;
}
