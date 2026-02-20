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
  final String? normalizedName;
  final double? suggestedPrice;
  final String? existingProductId;
  final String? existingProductName;
  final double? existingPrice;
  /// true = из establishment_products, false = из product.base_price
  final bool existingPriceFromEstablishment;
  final ModerationCategory category;
  final bool approved;

  const ModerationItem({
    required this.name,
    this.price,
    this.unit,
    this.normalizedName,
    this.suggestedPrice,
    this.existingProductId,
    this.existingProductName,
    this.existingPrice,
    this.existingPriceFromEstablishment = false,
    required this.category,
    this.approved = true,
  });

  String get displayName => normalizedName ?? name;
  double? get displayPrice => suggestedPrice ?? price;

  ModerationItem copyWith({
    String? name,
    double? price,
    String? unit,
    String? normalizedName,
    double? suggestedPrice,
    String? existingProductId,
    String? existingProductName,
    double? existingPrice,
    bool? existingPriceFromEstablishment,
    ModerationCategory? category,
    bool? approved,
  }) {
    return ModerationItem(
      name: name ?? this.name,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      normalizedName: normalizedName ?? this.normalizedName,
      suggestedPrice: suggestedPrice ?? this.suggestedPrice,
    existingProductId: existingProductId ?? this.existingProductId,
    existingProductName: existingProductName ?? this.existingProductName,
    existingPrice: existingPrice ?? this.existingPrice,
    existingPriceFromEstablishment: existingPriceFromEstablishment ?? this.existingPriceFromEstablishment,
    category: category ?? this.category,
      approved: approved ?? this.approved,
    );
  }

  @override
  List<Object?> get props => [
        name,
        price,
        unit,
        normalizedName,
        suggestedPrice,
        existingProductId,
        existingProductName,
        existingPrice,
        existingPriceFromEstablishment,
        category,
        approved,
      ];
}
