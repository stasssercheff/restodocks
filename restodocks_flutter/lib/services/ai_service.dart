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

/// Один ингредиент, извлечённый из карточки ТТК (фото/Excel/PDF).
/// Поля соответствуют ячейкам таблицы ТТК: наименование, брутто, отход %, нетто и т.д.
/// [ingredientType]: "product" = покупное сырьё (смесь РИКО, мука, масло), "semi_finished" = ПФ (крем, бисквит).
class TechCardIngredientLine {
  final String productName;
  final double? grossGrams;
  final double? netGrams;
  /// Вес готового продукта (выход после ужарки), г.
  final double? outputGrams;
  final String? unit;
  final String? cookingMethod;
  /// Процент отхода при первичной обработке (колонка «Отход %»), 0–100.
  final double? primaryWastePct;
  /// Процент ужарки/усушки (колонка «Ужарка %»), 0–100.
  final double? cookingLossPct;
  /// "product" = покупное сырьё, "semi_finished" = полуфабрикат (ПФ). Для маппинга в номенклатуру.
  final String? ingredientType;
  /// Цена за кг/л из документа (КК). При создании продукта в номенклатуру — подставить в цену.
  final double? pricePerKg;

  const TechCardIngredientLine({
    required this.productName,
    this.grossGrams,
    this.netGrams,
    this.outputGrams,
    this.unit,
    this.cookingMethod,
    this.primaryWastePct,
    this.cookingLossPct,
    this.ingredientType,
    this.pricePerKg,
  });
}

/// Результат распознавания ТТК (фото карточки или Excel).
class TechCardRecognitionResult {
  final String? dishName;
  final String? technologyText;
  final List<TechCardIngredientLine> ingredients;
  final bool? isSemiFinished;
  /// Выход готового продукта (г), если задан в файле (строка «Выход»).
  final double? yieldGrams;

  const TechCardRecognitionResult({
    this.dishName,
    this.technologyText,
    this.ingredients = const [],
    this.isSemiFinished,
    this.yieldGrams,
  });

  TechCardRecognitionResult copyWith({
    String? dishName,
    String? technologyText,
    List<TechCardIngredientLine>? ingredients,
    bool? isSemiFinished,
    double? yieldGrams,
  }) {
    return TechCardRecognitionResult(
      dishName: dishName ?? this.dishName,
      technologyText: technologyText ?? this.technologyText,
      ingredients: ingredients ?? this.ingredients,
      isSemiFinished: isSemiFinished ?? this.isSemiFinished,
      yieldGrams: yieldGrams ?? this.yieldGrams,
    );
  }
}

/// Ошибка парсинга одной карточки (битая/пропущенная).
class TtkParseError {
  final String? dishName;
  final String error;

  const TtkParseError({this.dishName, required this.error});
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
  final String? currency;

  const ParsedProductItem({required this.name, this.price, this.unit, this.currency});
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

  /// Всеядный парсинг списка продуктов из сырых строк (Excel/CSV/Numbers/RTF/текст).
  /// [source] — подсказка для ИИ: "numbers", "rtf", "text", "csv" и т.п.
  /// [userLocale] — локаль для подсказки валюты (ru_RU, en_US и т.д.)
  /// [mode] — режим парсинга: null/обычный или "inventory" для инвентаризационных бланков.
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text, String? source, String? userLocale, String? mode});

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
  /// [establishmentId] — для учёта лимита AI (3/день). Шаблонный парсинг без лимита.
  /// [sheetIndex] — для .xlsx с несколькими листами: парсить только этот лист (0-based). null = все листы или первый.
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes, {String? establishmentId, int? sheetIndex});

  /// Парсинг ТТК из PDF (извлечение текста + ИИ).
  /// [establishmentId] — для учёта лимита AI (3/день). Шаблонный парсинг без лимита.
  Future<List<TechCardRecognitionResult>> parseTechCardsFromPdf(Uint8List pdfBytes, {String? establishmentId});

  /// Парсинг ТТК из вставленного текста (табуляции, как продукты).
  /// Формат: название блюда → заголовок (наименование, Ед.изм, Норма закладки…) → строки ингредиентов → Выход.
  Future<List<TechCardRecognitionResult>> parseTechCardsFromText(String text, {String? establishmentId});

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
  Future<List<ParsedProductItem>> parseProductList({List<String>? rows, String? text, String? source, String? userLocale, String? mode}) async => [];

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
  Future<List<TechCardRecognitionResult>> parseTechCardsFromExcel(Uint8List xlsxBytes, {String? establishmentId, int? sheetIndex}) async =>
      [];

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromPdf(Uint8List pdfBytes, {String? establishmentId}) async =>
      [];

  @override
  Future<List<TechCardRecognitionResult>> parseTechCardsFromText(String text, {String? establishmentId}) async =>
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
