import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'product.dart';
import 'cooking_process.dart';

part 'tt_ingredient.g.dart';

/// Ингредиент технологической карты
@JsonSerializable()
class TTIngredient extends Equatable {
  @JsonKey(name: 'id')
  final String id;

  @JsonKey(name: 'product_id')
  final String? productId;

  @JsonKey(name: 'product_name')
  final String productName;

  /// Полуфабрикат из другой ТТК: когда задан, product_id пустой.
  @JsonKey(name: 'source_tech_card_id')
  final String? sourceTechCardId;

  @JsonKey(name: 'source_tech_card_name')
  final String? sourceTechCardName;

  // Технологический процесс
  @JsonKey(name: 'cooking_process_id')
  final String? cookingProcessId;

  @JsonKey(name: 'cooking_process_name')
  final String? cookingProcessName;

  // Вес: брутто (до обработки) и нетто (после обработки)
  @JsonKey(name: 'gross_weight')
  final double grossWeight; // брутто в граммах

  @JsonKey(name: 'net_weight')
  final double netWeight; // нетто в граммах

  @JsonKey(name: 'is_net_weight_manual')
  final bool isNetWeightManual; // ручной ввод нетто

  // Итоговые питательные вещества
  @JsonKey(name: 'final_calories')
  final double finalCalories;

  @JsonKey(name: 'final_protein')
  final double finalProtein;

  @JsonKey(name: 'final_fat')
  final double finalFat;

  @JsonKey(name: 'final_carbs')
  final double finalCarbs;

  // Стоимость
  @JsonKey(name: 'cost')
  final double cost;

  const TTIngredient({
    required this.id,
    this.productId,
    required this.productName,
    this.sourceTechCardId,
    this.sourceTechCardName,
    this.cookingProcessId,
    this.cookingProcessName,
    required this.grossWeight,
    required this.netWeight,
    this.isNetWeightManual = false,
    required this.finalCalories,
    required this.finalProtein,
    required this.finalFat,
    required this.finalCarbs,
    required this.cost,
  });

  /// Ингредиент из полуфабриката (другой ТТК). КБЖУ и стоимость масштабируются по весу.
  factory TTIngredient.fromTechCardData({
    required String techCardId,
    required String techCardName,
    required double totalNetWeight,
    required double totalCalories,
    required double totalProtein,
    required double totalFat,
    required double totalCarbs,
    required double totalCost,
    required double grossWeight,
  }) {
    final factor = totalNetWeight > 0 ? grossWeight / totalNetWeight : 0.0;
    return TTIngredient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      productId: null,
      productName: techCardName,
      sourceTechCardId: techCardId,
      sourceTechCardName: techCardName,
      cookingProcessId: null,
      cookingProcessName: null,
      grossWeight: grossWeight,
      netWeight: grossWeight,
      isNetWeightManual: false,
      finalCalories: totalCalories * factor,
      finalProtein: totalProtein * factor,
      finalFat: totalFat * factor,
      finalCarbs: totalCarbs * factor,
      cost: totalCost * factor,
    );
  }

  /// Создание копии с изменениями
  TTIngredient copyWith({
    String? id,
    String? productId,
    String? productName,
    String? sourceTechCardId,
    String? sourceTechCardName,
    String? cookingProcessId,
    String? cookingProcessName,
    double? grossWeight,
    double? netWeight,
    bool? isNetWeightManual,
    double? finalCalories,
    double? finalProtein,
    double? finalFat,
    double? finalCarbs,
    double? cost,
  }) {
    return TTIngredient(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      sourceTechCardId: sourceTechCardId ?? this.sourceTechCardId,
      sourceTechCardName: sourceTechCardName ?? this.sourceTechCardName,
      cookingProcessId: cookingProcessId ?? this.cookingProcessId,
      cookingProcessName: cookingProcessName ?? this.cookingProcessName,
      grossWeight: grossWeight ?? this.grossWeight,
      netWeight: netWeight ?? this.netWeight,
      isNetWeightManual: isNetWeightManual ?? this.isNetWeightManual,
      finalCalories: finalCalories ?? this.finalCalories,
      finalProtein: finalProtein ?? this.finalProtein,
      finalFat: finalFat ?? this.finalFat,
      finalCarbs: finalCarbs ?? this.finalCarbs,
      cost: cost ?? this.cost,
    );
  }

  /// Создание ингредиента из продукта
  factory TTIngredient.fromProduct({
    required Product? product,
    CookingProcess? cookingProcess,
    required double grossWeight,
    double? netWeight,
    required String defaultCurrency,
  }) {
    if (product == null) {
      return TTIngredient(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        productId: null,
        productName: '',
        cookingProcessId: null,
        cookingProcessName: null,
        grossWeight: grossWeight,
        netWeight: netWeight ?? grossWeight,
        isNetWeightManual: netWeight != null,
        finalCalories: 0,
        finalProtein: 0,
        finalFat: 0,
        finalCarbs: 0,
        cost: 0,
      );
    }

    double finalNetWeight = netWeight ?? grossWeight;
    double finalCalories = 0;
    double finalProtein = 0;
    double finalFat = 0;
    double finalCarbs = 0;

    if (cookingProcess != null) {
      // Применяем технологический процесс
      final processed = cookingProcess.applyTo(product, grossWeight);
      if (netWeight == null) {
        finalNetWeight = processed.finalWeight;
      }
      finalCalories = processed.totalCalories;
      finalProtein = processed.totalProtein;
      finalFat = processed.totalFat;
      finalCarbs = processed.totalCarbs;
    } else {
      // Сырой продукт
      final nutrition = product.getNutritionForWeight(finalNetWeight);
      finalCalories = nutrition.calories;
      finalProtein = nutrition.protein;
      finalFat = nutrition.fat;
      finalCarbs = nutrition.carbs;
    }

    // Расчет стоимости
    final cost = (product.basePrice ?? 0) * (grossWeight / 1000.0);

    return TTIngredient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      productId: product.id,
      productName: product.getLocalizedName('ru'), // TODO: использовать текущий язык
      cookingProcessId: cookingProcess?.id,
      cookingProcessName: cookingProcess?.getLocalizedName('ru'),
      grossWeight: grossWeight,
      netWeight: finalNetWeight,
      isNetWeightManual: netWeight != null,
      finalCalories: finalCalories,
      finalProtein: finalProtein,
      finalFat: finalFat,
      finalCarbs: finalCarbs,
      cost: cost,
    );
  }

  /// Обновить брутто вес и пересчитать значения
  TTIngredient updateGrossWeight(double newGrossWeight, Product? product, CookingProcess? cookingProcess) {
    if (product == null) {
      return copyWith(grossWeight: newGrossWeight);
    }

    double newNetWeight = isNetWeightManual ? netWeight : newGrossWeight;
    double newCalories = 0;
    double newProtein = 0;
    double newFat = 0;
    double newCarbs = 0;

    if (cookingProcess != null) {
      final processed = cookingProcess.applyTo(product, newGrossWeight);
      if (!isNetWeightManual) {
        newNetWeight = processed.finalWeight;
      }
      newCalories = processed.totalCalories;
      newProtein = processed.totalProtein;
      newFat = processed.totalFat;
      newCarbs = processed.totalCarbs;
    } else {
      final nutrition = product.getNutritionForWeight(newNetWeight);
      newCalories = nutrition.calories;
      newProtein = nutrition.protein;
      newFat = nutrition.fat;
      newCarbs = nutrition.carbs;
    }

    final newCost = (product.basePrice ?? 0) * (newGrossWeight / 1000.0);

    return copyWith(
      grossWeight: newGrossWeight,
      netWeight: newNetWeight,
      finalCalories: newCalories,
      finalProtein: newProtein,
      finalFat: newFat,
      finalCarbs: newCarbs,
      cost: newCost,
    );
  }

  /// Обновить нетто вес вручную
  TTIngredient updateNetWeight(double newNetWeight, Product? product) {
    if (product == null) {
      return copyWith(netWeight: newNetWeight, isNetWeightManual: true);
    }

    // Пересчитываем КБЖУ пропорционально весу
    final ratio = newNetWeight / grossWeight;
    final baseCalories = (product.calories ?? 0) * grossWeight / 100.0;
    final baseProtein = (product.protein ?? 0) * grossWeight / 100.0;
    final baseFat = (product.fat ?? 0) * grossWeight / 100.0;
    final baseCarbs = (product.carbs ?? 0) * grossWeight / 100.0;

    return copyWith(
      netWeight: newNetWeight,
      isNetWeightManual: true,
      finalCalories: baseCalories * ratio,
      finalProtein: baseProtein * ratio,
      finalFat: baseFat * ratio,
      finalCarbs: baseCarbs * ratio,
    );
  }

  /// Обновить технологический процесс
  TTIngredient updateCookingProcess(CookingProcess? newProcess, Product? product) {
    if (product == null) {
      return copyWith(
        cookingProcessId: newProcess?.id,
        cookingProcessName: newProcess?.getLocalizedName('ru'),
      );
    }

    double newNetWeight = isNetWeightManual ? netWeight : grossWeight;
    double newCalories = 0;
    double newProtein = 0;
    double newFat = 0;
    double newCarbs = 0;

    if (newProcess != null) {
      final processed = newProcess.applyTo(product, grossWeight);
      if (!isNetWeightManual) {
        newNetWeight = processed.finalWeight;
      }
      newCalories = processed.totalCalories;
      newProtein = processed.totalProtein;
      newFat = processed.totalFat;
      newCarbs = processed.totalCarbs;
    } else {
      final nutrition = product.getNutritionForWeight(newNetWeight);
      newCalories = nutrition.calories;
      newProtein = nutrition.protein;
      newFat = nutrition.fat;
      newCarbs = nutrition.carbs;
    }

    return copyWith(
      cookingProcessId: newProcess?.id,
      cookingProcessName: newProcess?.getLocalizedName('ru'),
      netWeight: newNetWeight,
      finalCalories: newCalories,
      finalProtein: newProtein,
      finalFat: newFat,
      finalCarbs: newCarbs,
    );
  }

  /// Информация о весе
  String get grossWeightInfo => '${grossWeight.toStringAsFixed(1)} г';
  String get netWeightInfo => '${netWeight.toStringAsFixed(1)} г';

  /// Информация о стоимости
  String get costInfo => '${cost.toStringAsFixed(2)} ₽'; // TODO: использовать текущую валюту

  /// Процент ужарки/упарки
  double get weightLossPercentage {
    if (grossWeight <= 0) return 0;
    return ((grossWeight - netWeight) / grossWeight) * 100.0;
  }

  /// JSON сериализация
  factory TTIngredient.fromJson(Map<String, dynamic> json) => _$TTIngredientFromJson(json);
  Map<String, dynamic> toJson() => _$TTIngredientToJson(this);

  bool get isFromTechCard => sourceTechCardId != null && sourceTechCardId!.isNotEmpty;

  @override
  List<Object?> get props => [
    id,
    productId,
    productName,
    sourceTechCardId,
    sourceTechCardName,
    cookingProcessId,
    cookingProcessName,
    grossWeight,
    netWeight,
    isNetWeightManual,
    finalCalories,
    finalProtein,
    finalFat,
    finalCarbs,
    cost,
  ];
}