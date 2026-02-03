import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'product.g.dart';

/// Модель продукта с питательной ценностью и характеристиками
@JsonSerializable()
class Product extends Equatable {
  @JsonKey(name: 'id')
  final String id;

  @JsonKey(name: 'name')
  final String name;

  @JsonKey(name: 'category')
  final String category;

  // Многоязычные названия
  @JsonKey(name: 'names')
  final Map<String, String>? names;

  // Питательная ценность на 100г
  @JsonKey(name: 'calories')
  final double? calories; // ккал

  @JsonKey(name: 'protein')
  final double? protein; // граммы

  @JsonKey(name: 'fat')
  final double? fat; // граммы

  @JsonKey(name: 'carbs')
  final double? carbs; // граммы

  // Аллергены
  @JsonKey(name: 'contains_gluten')
  final bool? containsGluten;

  @JsonKey(name: 'contains_lactose')
  final bool? containsLactose;

  // Ценообразование
  @JsonKey(name: 'base_price')
  final double? basePrice; // базовая цена

  @JsonKey(name: 'currency')
  final String? currency;

  // Единица измерения
  @JsonKey(name: 'unit')
  final String? unit;

  // Поставщики
  @JsonKey(name: 'supplier_ids')
  final List<String>? supplierIds;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    this.names,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.containsGluten,
    this.containsLactose,
    this.basePrice,
    this.currency,
    this.unit,
    this.supplierIds,
  });

  /// Создание копии с изменениями
  Product copyWith({
    String? id,
    String? name,
    String? category,
    Map<String, String>? names,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    bool? containsGluten,
    bool? containsLactose,
    double? basePrice,
    String? currency,
    String? unit,
    List<String>? supplierIds,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      names: names ?? this.names,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
      containsGluten: containsGluten ?? this.containsGluten,
      containsLactose: containsLactose ?? this.containsLactose,
      basePrice: basePrice ?? this.basePrice,
      currency: currency ?? this.currency,
      unit: unit ?? this.unit,
      supplierIds: supplierIds ?? this.supplierIds,
    );
  }

  /// Локализованное название продукта (fallback: lang → ru → en → любой → name)
  String getLocalizedName(String languageCode) {
    final n = names;
    if (n == null || n.isEmpty) return name;
    final v = n[languageCode];
    if (v != null && v.trim().isNotEmpty) return v;
    final ru = n['ru'];
    if (ru != null && ru.trim().isNotEmpty) return ru;
    final en = n['en'];
    if (en != null && en.trim().isNotEmpty) return en;
    final any = n.values.where((s) => s.trim().isNotEmpty).firstOrNull;
    return any ?? name;
  }

  /// Безглютеновый продукт
  bool get isGlutenFree => containsGluten == false;

  /// Безлактозный продукт
  bool get isLactoseFree => containsLactose == false;

  /// Информация о питательной ценности
  String get nutritionInfo {
    final List<String> parts = [];

    if (calories != null) {
      parts.add('${calories!.round()} ккал');
    }
    if (protein != null) {
      parts.add('Б:${protein!.toStringAsFixed(1)}г');
    }
    if (fat != null) {
      parts.add('Ж:${fat!.toStringAsFixed(1)}г');
    }
    if (carbs != null) {
      parts.add('У:${carbs!.toStringAsFixed(1)}г');
    }

    return parts.join(' ');
  }

  /// Информация об аллергенах
  String get allergensInfo {
    final List<String> allergens = [];

    if (containsGluten == true) {
      allergens.add('глютен');
    }
    if (containsLactose == true) {
      allergens.add('лактоза');
    }

    return allergens.join(', ');
  }

  /// Информация о цене
  String get priceInfo {
    if (basePrice == null) return '';

    final currencySymbol = _getCurrencySymbol(currency ?? 'RUB');
    return '$basePrice $currencySymbol';
  }

  String _getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'RUB':
        return '₽';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'VND':
        return '₫';
      default:
        return currency;
    }
  }

  /// Проверка на наличие аллергенов
  bool containsAllergen(String allergen) {
    switch (allergen.toLowerCase()) {
      case 'gluten':
      case 'глютен':
        return containsGluten == true;
      case 'lactose':
      case 'лактоза':
        return containsLactose == true;
      default:
        return false;
    }
  }

  /// Питательная ценность на указанный вес (в граммах)
  NutritionInfo getNutritionForWeight(double weightInGrams) {
    if (weightInGrams <= 0) {
      return NutritionInfo.zero();
    }

    final multiplier = weightInGrams / 100.0;

    return NutritionInfo(
      calories: (calories ?? 0) * multiplier,
      protein: (protein ?? 0) * multiplier,
      fat: (fat ?? 0) * multiplier,
      carbs: (carbs ?? 0) * multiplier,
    );
  }

  /// JSON сериализация
  factory Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);
  Map<String, dynamic> toJson() => _$ProductToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    category,
    names,
    calories,
    protein,
    fat,
    carbs,
    containsGluten,
    containsLactose,
    basePrice,
    currency,
    unit,
    supplierIds,
  ];

  /// Создание продукта с автогенерированным ID
  factory Product.create({
    required String name,
    required String category,
    Map<String, String>? names,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    bool? containsGluten,
    bool? containsLactose,
    double? basePrice,
    String? currency,
    String? unit,
    List<String>? supplierIds,
  }) {
    return Product(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: category,
      names: names,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      containsGluten: containsGluten,
      containsLactose: containsLactose,
      basePrice: basePrice,
      currency: currency,
      unit: unit,
      supplierIds: supplierIds,
    );
  }
}

/// Класс для питательной ценности
class NutritionInfo {
  final double calories;
  final double protein;
  final double fat;
  final double carbs;

  const NutritionInfo({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
  });

  factory NutritionInfo.zero() {
    return const NutritionInfo(
      calories: 0,
      protein: 0,
      fat: 0,
      carbs: 0,
    );
  }

  NutritionInfo operator +(NutritionInfo other) {
    return NutritionInfo(
      calories: calories + other.calories,
      protein: protein + other.protein,
      fat: fat + other.fat,
      carbs: carbs + other.carbs,
    );
  }

  NutritionInfo operator *(double multiplier) {
    return NutritionInfo(
      calories: calories * multiplier,
      protein: protein * multiplier,
      fat: fat * multiplier,
      carbs: carbs * multiplier,
    );
  }

  @override
  String toString() {
    return '${calories.round()} ккал, Б:${protein.toStringAsFixed(1)}г, Ж:${fat.toStringAsFixed(1)}г, У:${carbs.toStringAsFixed(1)}г';
  }
}