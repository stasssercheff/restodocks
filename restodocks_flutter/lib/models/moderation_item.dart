import 'package:equatable/equatable.dart';

/// Категория строки на экране модерации импорта
enum ModerationCategory {
  /// ИИ предлагает исправление названия (опечатка, сленг)
  nameFix,
  /// Аномальная цена (запятые, разряды)
  priceAnomaly,
  /// Продукт есть в базе, цена отличается
  priceUpdate,
  /// Новый продукт
  newProduct,
}

/// Элемент буфера модерации (ещё не записан в БД)
class ModerationItem extends Equatable {
  final String name;
  final double? price;
  final String? unit;
  final String? currency;
  final String? normalizedName;
  final double? suggestedPrice;
  final String? existingProductId;
  final String? existingProductName;
  final double? existingPrice;
  /// true = из establishment_products, false = из product.base_price
  final bool existingPriceFromEstablishment;
  final ModerationCategory category;
  final bool approved;
  /// После привязки к существующему продукту сохранить алиас имени из файла (импорт Excel: fuzzy / ambiguous→replace).
  final bool linkAliasFromImportName;

  const ModerationItem({
    required this.name,
    this.price,
    this.unit,
    this.currency,
    this.normalizedName,
    this.suggestedPrice,
    this.existingProductId,
    this.existingProductName,
    this.existingPrice,
    this.existingPriceFromEstablishment = false,
    required this.category,
    this.approved = true,
    this.linkAliasFromImportName = false,
  });

  /// Всегда исходное имя из файла. [normalizedName] не используется для сохранения (политика: не переименовывать автоматически).
  String get displayName => name;
  double? get displayPrice => suggestedPrice ?? price;

  ModerationItem copyWith({
    String? name,
    double? price,
    String? unit,
    String? currency,
    String? normalizedName,
    double? suggestedPrice,
    String? existingProductId,
    String? existingProductName,
    double? existingPrice,
    bool? existingPriceFromEstablishment,
    ModerationCategory? category,
    bool? approved,
    bool? linkAliasFromImportName,
  }) {
    return ModerationItem(
      name: name ?? this.name,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      currency: currency ?? this.currency,
      normalizedName: normalizedName ?? this.normalizedName,
      suggestedPrice: suggestedPrice ?? this.suggestedPrice,
    existingProductId: existingProductId ?? this.existingProductId,
    existingProductName: existingProductName ?? this.existingProductName,
    existingPrice: existingPrice ?? this.existingPrice,
    existingPriceFromEstablishment: existingPriceFromEstablishment ?? this.existingPriceFromEstablishment,
    category: category ?? this.category,
      approved: approved ?? this.approved,
      linkAliasFromImportName:
          linkAliasFromImportName ?? this.linkAliasFromImportName,
    );
  }

  @override
  List<Object?> get props => [
        name,
        price,
        unit,
        currency,
        normalizedName,
        suggestedPrice,
        existingProductId,
        existingProductName,
        existingPrice,
        existingPriceFromEstablishment,
        category,
        approved,
        linkAliasFromImportName,
      ];
}
