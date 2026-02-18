import 'package:equatable/equatable.dart';

/// Результат импорта продукта
class ProductImportResult extends Equatable {
  final String fileName;
  final double? filePrice;
  final String? detectedLanguage;
  final ProductMatchResult matchResult;
  final String? error;

  const ProductImportResult({
    required this.fileName,
    this.filePrice,
    this.detectedLanguage,
    required this.matchResult,
    this.error,
  });

  @override
  List<Object?> get props => [fileName, filePrice, detectedLanguage, matchResult, error];
}

/// Результат сопоставления продукта
class ProductMatchResult extends Equatable {
  final MatchType type;
  final String? existingProductId;
  final String? existingProductName;
  final String? suggestedName;
  final Map<String, String>? translations;

  const ProductMatchResult({
    required this.type,
    this.existingProductId,
    this.existingProductName,
    this.suggestedName,
    this.translations,
  });

  @override
  List<Object?> get props => [type, existingProductId, existingProductName, suggestedName, translations];
}

/// Тип сопоставления
enum MatchType {
  exact,      // Точное совпадение - обновить цену
  fuzzy,      // Нечеткое совпадение - предложить выбор
  ambiguous,  // Неоднозначное совпадение - показать модальное окно
  create,     // Новый продукт - создать с переводом
  error,      // Ошибка обработки
}

/// Запрос на разрешение неоднозначного сопоставления
class ProductMatchResolution {
  final String fileName;
  final double? filePrice;
  final List<ProductMatchOption> options;

  const ProductMatchResolution({
    required this.fileName,
    this.filePrice,
    required this.options,
  });
}

/// Вариант разрешения неоднозначного сопоставления
class ProductMatchOption {
  final String action; // 'replace', 'create'
  final String? existingProductId;
  final String? existingProductName;
  final String description;

  const ProductMatchOption({
    required this.action,
    this.existingProductId,
    this.existingProductName,
    required this.description,
  });
}