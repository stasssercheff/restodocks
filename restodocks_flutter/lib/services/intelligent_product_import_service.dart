import 'dart:convert';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/product_import_result.dart';
import '../models/nomenclature_item.dart';
import '../models/tech_card.dart';
import '../models/translation.dart';
import 'ai_service_supabase.dart';
import 'translation_service.dart';
import 'translation_manager.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';

/// Сервис для интеллектуального импорта продуктов
class IntelligentProductImportService {
  final AiServiceSupabase _aiService;
  final TranslationService _translationService;
  final ProductStoreSupabase _productStore;
  final TechCardServiceSupabase _techCardService;
  late final TranslationManager _translationManager;

  IntelligentProductImportService({
    required AiServiceSupabase aiService,
    required TranslationService translationService,
    required ProductStoreSupabase productStore,
    required TechCardServiceSupabase techCardService,
  }) : _aiService = aiService,
       _translationService = translationService,
       _productStore = productStore,
       _techCardService = techCardService {
    _translationManager = TranslationManager(
      aiService: _aiService,
      translationService: _translationService,
    );
  }

  /// Импортировать продукты из Excel файла с интеллектуальным анализом
  Future<List<ProductImportResult>> importFromExcel(
    Excel excel,
    String fileName,
    String establishmentId,
    String defaultCurrency,
  ) async {
    final results = <ProductImportResult>[];
    final allProducts = _productStore.allProducts;
    final allTechCards = await _techCardService.getAllTechCards();

    // Обрабатываем все листы
    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName]!;
      final language = await _detectLanguage(sheet);

      for (final row in sheet.rows.skip(1)) { // Пропускаем заголовок
        if (row.isEmpty || row.length < 2) continue;

        final name = row[0]?.value?.toString().trim();
        final priceStr = row.length > 1 ? row[1]?.value?.toString().trim() : null;

        if (name == null || name.isEmpty) continue;

        final price = _parsePrice(priceStr);

        try {
          final matchResult = await _findProductMatch(
            name,
            language,
            allProducts,
            establishmentId,
          );

          results.add(ProductImportResult(
            fileName: name,
            filePrice: price,
            detectedLanguage: language,
            matchResult: matchResult,
          ));
        } catch (e) {
          results.add(ProductImportResult(
            fileName: name,
            filePrice: price,
            detectedLanguage: language,
            matchResult: const ProductMatchResult(type: MatchType.error),
            error: e.toString(),
          ));
        }
      }
    }

    return results;
  }

  /// Обработать результаты импорта с пользовательскими решениями
  Future<List<Product>> processImportResults(
    List<ProductImportResult> results,
    Map<String, String> resolutions, // fileName -> resolutionAction
    String establishmentId,
    String defaultCurrency,
  ) async {
    final createdProducts = <Product>[];
    final updatedProducts = <Product>[];

    for (final result in results) {
      if (result.error != null) continue;

      switch (result.matchResult.type) {
        case MatchType.exact:
          // Обновляем цену существующего продукта
          if (result.matchResult.existingProductId != null && result.filePrice != null) {
            await _productStore.setEstablishmentPrice(
              establishmentId,
              result.matchResult.existingProductId!,
              result.filePrice,
              defaultCurrency,
            );
          }
          break;

        case MatchType.create:
          // Создаем новый продукт с переводами
          final productName = result.matchResult.suggestedName ?? result.fileName;
          final product = Product.create(
            name: productName,
            category: 'imported',
            basePrice: result.filePrice ?? 0.0,
            currency: result.filePrice != null ? defaultCurrency : null,
          );

          await _productStore.addProduct(product);
          createdProducts.add(product);

          // Генерируем и сохраняем переводы
          await _generateAndSaveTranslations(
            product.id,
            productName,
            result.detectedLanguage ?? 'en',
          );
          break;

        case MatchType.fuzzy:
        case MatchType.ambiguous:
          // Используем решение пользователя
          final resolution = resolutions[result.fileName];
          if (resolution == 'replace' && result.matchResult.existingProductId != null) {
            // Обновляем существующий продукт
            if (result.filePrice != null) {
              await _productStore.setEstablishmentPrice(
                establishmentId,
                result.matchResult.existingProductId!,
                result.filePrice,
                defaultCurrency,
              );
            }
          } else if (resolution == 'create') {
            // Создаем новый продукт
            final translations = await _translationManager.generateTranslationsForProduct(
              result.fileName,
              result.detectedLanguage ?? 'en',
            );

            final product = Product.create(
              name: result.fileName,
              category: 'imported',
              names: translations,
              basePrice: result.filePrice ?? 0.0,
              currency: result.filePrice != null ? defaultCurrency : null,
            );

            await _productStore.addProduct(product);
            createdProducts.add(product);
          }
          break;

        case MatchType.error:
          // Пропускаем с ошибкой
          break;
      }
    }

    return createdProducts;
  }

  /// Определить язык содержимого листа Excel
  Future<String> _detectLanguage(Sheet sheet) async {
    final sampleTexts = <String>[];

    // Собираем образцы текста из первых 10 строк
    for (final row in sheet.rows.take(10)) {
      if (row.isNotEmpty) {
        final text = row.map((cell) => cell?.value?.toString() ?? '').join(' ');
        if (text.trim().isNotEmpty) {
          sampleTexts.add(text);
        }
      }
    }

    if (sampleTexts.isEmpty) return 'en';

    try {
      final prompt = '''
Определи язык следующих текстов и верни код языка (ru, en, de, fr, es, it, zh, ja, ko).
Если тексты на разных языках, верни наиболее вероятный основной язык.

Тексты:
${sampleTexts.take(5).join('\n')}

Верни только код языка в нижнем регистре.
''';

      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });

      final languageCode = response?['result']?.toString().trim().toLowerCase() ?? 'en';

      // Валидируем код языка
      const validCodes = ['ru', 'en', 'de', 'fr', 'es', 'it', 'zh', 'ja', 'ko'];
      return validCodes.contains(languageCode) ? languageCode : 'en';
    } catch (e) {
      return 'en'; // fallback
    }
  }

  /// Найти соответствие продукта в базе данных
  Future<ProductMatchResult> _findProductMatch(
    String fileName,
    String language,
    List<Product> allProducts,
    String establishmentId,
  ) async {
    final normalizedFileName = _normalizeText(fileName);

    // Ищем точные совпадения
    final exactMatches = allProducts.where((product) {
      final productNames = [product.name, ...(product.names?.values ?? [])];
      return productNames.any((name) => _normalizeText(name) == normalizedFileName);
    }).toList();

    if (exactMatches.isNotEmpty) {
      return ProductMatchResult(
        type: MatchType.exact,
        existingProductId: exactMatches.first.id,
        existingProductName: exactMatches.first.name,
      );
    }

    // Ищем нечеткие совпадения
    final fuzzyMatches = <Product>[];
    for (final product in allProducts) {
      final productNames = [product.name, ...(product.names?.values ?? [])];
      for (final productName in productNames) {
        if (_calculateSimilarity(normalizedFileName, _normalizeText(productName)) > 0.8) {
          fuzzyMatches.add(product);
          break; // Нашли соответствие для этого продукта
        }
      }
    }

    if (fuzzyMatches.length == 1) {
      return ProductMatchResult(
        type: MatchType.fuzzy,
        existingProductId: fuzzyMatches.first.id,
        existingProductName: fuzzyMatches.first.name,
      );
    }

    if (fuzzyMatches.length > 1) {
      return ProductMatchResult(
        type: MatchType.ambiguous,
        existingProductId: fuzzyMatches.first.id,
        existingProductName: fuzzyMatches.first.name,
      );
    }

    // Новый продукт - генерируем нормализованное имя
    final suggestedName = await _normalizeProductName(fileName, language);

    return ProductMatchResult(
      type: MatchType.create,
      suggestedName: suggestedName,
    );
  }

  /// Нормализовать текст для сравнения
  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Удаляем пунктуацию
        .replaceAll(RegExp(r'\s+'), ' ') // Нормализуем пробелы
        .trim();
  }

  /// Вычислить схожесть строк (простая реализация)
  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;

    final longer = a.length > b.length ? a : b;
    final shorter = a.length > b.length ? b : a;

    if (longer.isEmpty) return 1.0;

    final distance = _levenshteinDistance(longer, shorter);
    return (longer.length - distance) / longer.length.toDouble();
  }

  /// Расстояние Левенштейна
  int _levenshteinDistance(String a, String b) {
    final matrix = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => 0),
    );

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }

    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[a.length][b.length];
  }

  /// Нормализовать название продукта
  Future<String> _normalizeProductName(String name, String language) async {
    try {
      final prompt = '''
Нормализуй название продукта для использования в базе данных.
Убери лишние слова, исправь опечатки, приведи к стандартному виду.

Оригинал: "$name"
Язык: $language

Верни только нормализованное название на английском языке.
''';

      final response = await _aiService.invoke('ai-generate-checklist', {
        'prompt': prompt,
      });

      return response?['result']?.toString().trim() ?? name;
    } catch (e) {
      return name; // fallback
    }
  }

  /// Сгенерировать переводы продукта (сохранение в БД)
  Future<void> _generateAndSaveTranslations(String productId, String name, String sourceLanguage) async {
    // Создаем TranslationManager для сохранения переводов
    final translationManager = TranslationManager(
      aiService: _aiService,
      translationService: _translationService,
    );

    // Сохраняем переводы через TranslationManager
    await translationManager.handleEntitySave(
      entityType: TranslationEntityType.product,
      entityId: productId,
      textFields: {'name': name},
      sourceLanguage: sourceLanguage,
    );
  }

  /// Разобрать цену из строки
  double? _parsePrice(String? priceStr) {
    if (priceStr == null || priceStr.trim().isEmpty) {
      return null;
    }

    // Удаляем валютные символы и пробелы
    final cleanPrice = priceStr
        .replaceAll(RegExp(r'[^\d.,]'), '') // Оставляем только цифры, точки и запятые
        .replaceAll(',', '.'); // Заменяем запятые на точки

    return double.tryParse(cleanPrice);
  }

  /// Проверить, используется ли продукт в рецептах
  Future<bool> _isProductUsedInRecipes(String productId) async {
    try {
      final techCards = await _techCardService.getAllTechCards();
      return techCards.any((card) =>
          card.ingredients.any((ing) => ing.productId == productId));
    } catch (e) {
      return true; // В случае ошибки считаем, что используется
    }
  }
}