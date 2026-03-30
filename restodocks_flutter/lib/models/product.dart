import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

import 'establishment.dart';

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

  /// Пользователь подтвердил КБЖУ (в т.ч. нули); не дозаполнять автоматикой и не считать неполными.
  @JsonKey(name: 'kbju_manually_confirmed')
  final bool kbjuManuallyConfirmed;

  // Аллергены
  @JsonKey(name: 'contains_gluten')
  final bool? containsGluten;

  @JsonKey(name: 'contains_lactose')
  final bool? containsLactose;

  // Ценообразование
  @JsonKey(name: 'base_price')
  final double? basePrice; // базовая цена за единицу (кг / шт)

  @JsonKey(name: 'currency')
  final String? currency;

  // Упаковка: цена за упаковку и вес (граммы) одной упаковки
  @JsonKey(name: 'package_price')
  final double? packagePrice; // цена за 1 упаковку

  @JsonKey(name: 'package_weight_grams')
  final double? packageWeightGrams; // вес упаковки в граммах

  @JsonKey(name: 'grams_per_piece')
  final double? gramsPerPiece; // вес 1 шт в граммах (для unit=шт/pcs)

  // Единица измерения
  @JsonKey(name: 'unit')
  final String? unit;

  /// Процент отхода при первичной обработке (0–100), для ТТК
  @JsonKey(name: 'primary_waste_pct')
  final double? primaryWastePct;

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
    this.kbjuManuallyConfirmed = false,
    this.containsGluten,
    this.containsLactose,
    this.basePrice,
    this.currency,
    this.packagePrice,
    this.packageWeightGrams,
    this.gramsPerPiece,
    this.unit,
    this.primaryWastePct,
    this.supplierIds,
  });

  /// Цена за кг, рассчитанная из упаковки (если заданы packagePrice и packageWeightGrams)
  double? get computedPricePerKg {
    if (packagePrice != null && packageWeightGrams != null && packageWeightGrams! > 0) {
      return packagePrice! / packageWeightGrams! * 1000.0;
    }
    return null;
  }

  /// Эффективная цена за единицу: если задана цена упаковки — считаем через неё, иначе basePrice
  double? get effectiveBasePrice => computedPricePerKg ?? basePrice;

  /// Создание копии с изменениями.
  /// Для сброса nullable полей используй Object() sentinel: copyWith(packagePrice: null) не сбросит поле,
  /// передай clearPackagePrice: true.
  Product copyWith({
    String? id,
    String? name,
    String? category,
    Map<String, String>? names,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
    bool? kbjuManuallyConfirmed,
    bool? containsGluten,
    bool? containsLactose,
    double? basePrice,
    String? currency,
    double? packagePrice,
    double? packageWeightGrams,
    bool clearPackagePrice = false,
    bool clearPackageWeight = false,
    double? gramsPerPiece,
    bool clearGramsPerPiece = false,
    String? unit,
    double? primaryWastePct,
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
      kbjuManuallyConfirmed:
          kbjuManuallyConfirmed ?? this.kbjuManuallyConfirmed,
      containsGluten: containsGluten ?? this.containsGluten,
      containsLactose: containsLactose ?? this.containsLactose,
      basePrice: basePrice ?? this.basePrice,
      currency: currency ?? this.currency,
      packagePrice: clearPackagePrice ? null : (packagePrice ?? this.packagePrice),
      packageWeightGrams: clearPackageWeight ? null : (packageWeightGrams ?? this.packageWeightGrams),
      gramsPerPiece: clearGramsPerPiece ? null : (gramsPerPiece ?? this.gramsPerPiece),
      unit: unit ?? this.unit,
      primaryWastePct: primaryWastePct ?? this.primaryWastePct,
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

  /// Безглютеновый продукт (явно помечен как без глютена)
  bool get isGlutenFree => containsGluten == false;

  /// Безлактозный продукт (явно помечен как без лактозы)
  bool get isLactoseFree => containsLactose == false;

  /// Подходит под фильтр «без глютена»: не помечен как содержащий глютен (null = не исключаем).
  bool get suitableForGlutenFreeFilter => containsGluten != true;

  /// Подходит под фильтр «без лактозы»: не помечен как содержащий лактозу (null = не исключаем).
  bool get suitableForLactoseFreeFilter => containsLactose != true;

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

    final currencySymbol = Establishment.currencySymbolFor(currency ?? 'RUB');
    return '$basePrice $currencySymbol';
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
    kbjuManuallyConfirmed,
    containsGluten,
    containsLactose,
    basePrice,
    currency,
    packagePrice,
    packageWeightGrams,
    gramsPerPiece,
    unit,
    primaryWastePct,
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
    bool kbjuManuallyConfirmed = false,
    bool? containsGluten,
    bool? containsLactose,
    double? basePrice,
    String? currency,
    double? packagePrice,
    double? packageWeightGrams,
    double? gramsPerPiece,
    String? unit,
    List<String>? supplierIds,
  }) {
    return Product(
      id: const Uuid().v4(),
      name: name,
      category: category,
      names: names,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kbjuManuallyConfirmed: kbjuManuallyConfirmed,
      containsGluten: containsGluten,
      containsLactose: containsLactose,
      basePrice: basePrice,
      currency: currency,
      packagePrice: packagePrice,
      packageWeightGrams: packageWeightGrams,
      gramsPerPiece: gramsPerPiece,
      unit: unit,
      primaryWastePct: null,
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