import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'product.dart';
import 'cooking_process.dart';
import 'culinary_units.dart';

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

  // Вес: брутто (до обработки) и нетто (после обработки). Внутренне храним в граммах.
  @JsonKey(name: 'gross_weight')
  final double grossWeight;

  @JsonKey(name: 'net_weight')
  final double netWeight;

  @JsonKey(name: 'unit')
  final String unit; // г, кг, шт, lb, oz, мл, л и т.д.

  @JsonKey(name: 'primary_waste_pct')
  final double primaryWastePct; // процент отхода при первичной обработке

  @JsonKey(name: 'grams_per_piece')
  final double? gramsPerPiece; // для шт: грамм на штуку

  /// Ручной % ужарки (если задан — используется вместо способа приготовления)
  @JsonKey(name: 'cooking_loss_pct_override')
  final double? cookingLossPctOverride;

  @JsonKey(name: 'is_net_weight_manual')
  final bool isNetWeightManual;

  /// Ручное «нетто» (после отхода, до ужарки). Когда задано — показываем и редактируем его без формул.
  @JsonKey(name: 'manual_effective_gross')
  final double? manualEffectiveGross;

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
    this.unit = 'g',
    this.primaryWastePct = 0,
    this.gramsPerPiece,
    this.cookingLossPctOverride,
    this.isNetWeightManual = false,
    this.manualEffectiveGross,
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
    String unit = 'g',
    double? gramsPerPiece,
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
      unit: unit,
      primaryWastePct: 0,
      gramsPerPiece: gramsPerPiece,
      isNetWeightManual: false,
      finalCalories: totalCalories * factor,
      finalProtein: totalProtein * factor,
      finalFat: totalFat * factor,
      finalCarbs: totalCarbs * factor,
      cost: totalCost * factor,
    );
  }

  static const _undefined = Object();

  /// Создание копии с изменениями
  TTIngredient copyWith({
    Object? id = _undefined,
    Object? productId = _undefined,
    Object? productName = _undefined,
    Object? sourceTechCardId = _undefined,
    Object? sourceTechCardName = _undefined,
    Object? cookingProcessId = _undefined,
    Object? cookingProcessName = _undefined,
    Object? grossWeight = _undefined,
    Object? netWeight = _undefined,
    Object? unit = _undefined,
    Object? primaryWastePct = _undefined,
    Object? gramsPerPiece = _undefined,
    Object? cookingLossPctOverride = _undefined,
    Object? isNetWeightManual = _undefined,
    Object? manualEffectiveGross = _undefined,
    Object? finalCalories = _undefined,
    Object? finalProtein = _undefined,
    Object? finalFat = _undefined,
    Object? finalCarbs = _undefined,
    Object? cost = _undefined,
  }) {
    return TTIngredient(
      id: id == _undefined ? this.id : id as String,
      productId: productId == _undefined ? this.productId : productId as String?,
      productName: productName == _undefined ? this.productName : productName as String,
      sourceTechCardId: sourceTechCardId == _undefined ? this.sourceTechCardId : sourceTechCardId as String?,
      sourceTechCardName: sourceTechCardName == _undefined ? this.sourceTechCardName : sourceTechCardName as String?,
      cookingProcessId: cookingProcessId == _undefined ? this.cookingProcessId : cookingProcessId as String?,
      cookingProcessName: cookingProcessName == _undefined ? this.cookingProcessName : cookingProcessName as String?,
      grossWeight: grossWeight == _undefined ? this.grossWeight : grossWeight as double,
      netWeight: netWeight == _undefined ? this.netWeight : netWeight as double,
      unit: unit == _undefined ? this.unit : unit as String,
      primaryWastePct: primaryWastePct == _undefined ? this.primaryWastePct : primaryWastePct as double,
      gramsPerPiece: gramsPerPiece == _undefined ? this.gramsPerPiece : gramsPerPiece as double?,
      cookingLossPctOverride: cookingLossPctOverride == _undefined ? this.cookingLossPctOverride : cookingLossPctOverride as double?,
      isNetWeightManual: isNetWeightManual == _undefined ? this.isNetWeightManual : isNetWeightManual as bool,
      manualEffectiveGross: manualEffectiveGross == _undefined ? this.manualEffectiveGross : manualEffectiveGross as double?,
      finalCalories: finalCalories == _undefined ? this.finalCalories : finalCalories as double,
      finalProtein: finalProtein == _undefined ? this.finalProtein : finalProtein as double,
      finalFat: finalFat == _undefined ? this.finalFat : finalFat as double,
      finalCarbs: finalCarbs == _undefined ? this.finalCarbs : finalCarbs as double,
      cost: cost == _undefined ? this.cost : cost as double,
    );
  }

  /// Префикс id для пустой строки-заполнителя (не сохраняется в ТТК).
  static const String _placeholderIdPrefix = '_placeholder_';

  bool get isPlaceholder => id.startsWith(_placeholderIdPrefix);

  /// Есть ли хотя бы одно заполненное поле (название или брутто).
  bool get hasData => productName.trim().isNotEmpty || grossWeight > 0;

  /// Заменить placeholder-id на реальный (после ввода данных пользователем).
  TTIngredient withRealId() =>
      copyWith(id: '${DateTime.now().millisecondsSinceEpoch}_${id.hashCode.abs()}');

  /// Пустая строка для ввода в таблице ТТК; при заполнении подменяется на реальный id и добавляется новая пустая.
  factory TTIngredient.emptyPlaceholder() {
    return TTIngredient(
      id: '${_placeholderIdPrefix}${DateTime.now().millisecondsSinceEpoch}',
      productId: null,
      productName: '',
      grossWeight: 0,
      netWeight: 0,
      unit: 'g',
      primaryWastePct: 0,
      isNetWeightManual: false,
      finalCalories: 0,
      finalProtein: 0,
      finalFat: 0,
      finalCarbs: 0,
      cost: 0,
    );
  }

  /// Создание ингредиента из продукта
  /// [primaryWastePct] — процент отхода при первичной обработке, 0–100
  /// [unit] — единица измерения (г, кг, шт и т.д.)
  /// [gramsPerPiece] — для unit=шт: грамм на штуку
  factory TTIngredient.fromProduct({
    required Product? product,
    CookingProcess? cookingProcess,
    required double grossWeight,
    double? netWeight,
    double? primaryWastePct,
    required String defaultCurrency,
    String languageCode = 'ru',
    String unit = 'g',
    double? gramsPerPiece,
    double? cookingLossPctOverride,
  }) {
    final wastePct = primaryWastePct ?? product?.primaryWastePct ?? 0;
    if (product == null) {
      return TTIngredient(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        productId: null,
        productName: '',
        cookingProcessId: null,
        cookingProcessName: null,
        grossWeight: grossWeight,
        netWeight: netWeight ?? grossWeight,
        unit: unit,
        primaryWastePct: wastePct,
        gramsPerPiece: gramsPerPiece,
        isNetWeightManual: netWeight != null,
        finalCalories: 0,
        finalProtein: 0,
        finalFat: 0,
        finalCarbs: 0,
        cost: 0,
      );
    }

    // Конвертируем в граммы для расчётов
    final grossG = CulinaryUnits.toGrams(grossWeight, unit, gramsPerPiece: gramsPerPiece);

    // Эффективный вес после отхода (первичная обработка)
    final waste = wastePct.clamp(0.0, 99.9) / 100.0;
    final effectiveGross = grossG * (1.0 - waste);

    double finalNetWeight = netWeight ?? effectiveGross;
    double finalCalories = 0;
    double finalProtein = 0;
    double finalFat = 0;
    double finalCarbs = 0;

    if (cookingProcess != null) {
      final processed = cookingProcess.applyTo(product, effectiveGross);
      if (netWeight == null) {
        finalNetWeight = processed.finalWeight;
      }
      finalCalories = processed.totalCalories;
      finalProtein = processed.totalProtein;
      finalFat = processed.totalFat;
      finalCarbs = processed.totalCarbs;
    } else {
      final nutrition = product.getNutritionForWeight(finalNetWeight);
      finalCalories = nutrition.calories;
      finalProtein = nutrition.protein;
      finalFat = nutrition.fat;
      finalCarbs = nutrition.carbs;
    }

    // Расчёт стоимости: при unit шт — цена за штуку, иначе — за кг
    double cost;
    if (unit == 'pcs' || unit == 'шт') {
      final pieces = grossG / (gramsPerPiece ?? 50);
      cost = (product.basePrice ?? 0) * pieces;
    } else {
      cost = (product.basePrice ?? 0) * (grossG / 1000.0);
    }

    return TTIngredient(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      productId: product.id,
      productName: product.getLocalizedName(languageCode),
      cookingProcessId: cookingProcess?.id,
      cookingProcessName: cookingProcess?.getLocalizedName(languageCode),
      grossWeight: grossG,
      netWeight: finalNetWeight,
      unit: unit,
      primaryWastePct: wastePct,
      gramsPerPiece: gramsPerPiece,
      cookingLossPctOverride: cookingLossPctOverride,
      isNetWeightManual: netWeight != null,
      finalCalories: finalCalories,
      finalProtein: finalProtein,
      finalFat: finalFat,
      finalCarbs: finalCarbs,
      cost: cost,
    );
  }

  /// Обновить брутто вес и пересчитать значения.
  /// Нетто = брутто × (1 − отход/100). Выход = нетто × (1 − ужарка/100); при ужарке 0 выход = нетто.
  TTIngredient updateGrossWeight(double newGrossWeight, Product? product, CookingProcess? cookingProcess) {
    if (product == null) {
      final net = newGrossWeight * (1.0 - primaryWastePct.clamp(0.0, 99.9) / 100.0);
      final loss = (cookingLossPctOverride ?? 0).clamp(0.0, 99.9) / 100.0;
      final out = net * (1.0 - loss);
      return copyWith(grossWeight: newGrossWeight, netWeight: out, isNetWeightManual: false);
    }

    final effectiveGross = newGrossWeight * (1.0 - primaryWastePct / 100.0);
    double newNetWeight = isNetWeightManual ? netWeight : effectiveGross;
    double newCalories = 0;
    double newProtein = 0;
    double newFat = 0;
    double newCarbs = 0;

    if (cookingProcess != null) {
      final lossPct = cookingLossPctOverride ?? cookingProcess.weightLossPercentage;
      final processed = cookingProcess.applyTo(product, effectiveGross, weightLossOverride: lossPct);
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

  /// Обновить % отхода и пересчитать нетто, КБЖУ, стоимость.
  /// Нетто = брутто × (1 − отход/100). Выход = нетто × (1 − ужарка/100).
  TTIngredient updatePrimaryWastePct(double newWastePct, Product? product, CookingProcess? cookingProcess) {
    final waste = newWastePct.clamp(0.0, 99.9);
    if (product == null) {
      final net = grossWeight * (1.0 - waste / 100.0);
      final loss = (cookingLossPctOverride ?? 0).clamp(0.0, 99.9) / 100.0;
      final out = net * (1.0 - loss);
      return copyWith(primaryWastePct: waste, netWeight: out, isNetWeightManual: false);
    }
    final effectiveGross = grossWeight * (1.0 - waste / 100.0);
    double newNetWeight = effectiveGross;
    double newCalories = 0;
    double newProtein = 0;
    double newFat = 0;
    double newCarbs = 0;

    if (cookingProcess != null) {
      final lossPct = cookingLossPctOverride ?? cookingProcess.weightLossPercentage;
      final processed = cookingProcess.applyTo(product, effectiveGross, weightLossOverride: lossPct);
      if (!isNetWeightManual) newNetWeight = processed.finalWeight;
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

    final newCost = (product.basePrice ?? 0) * (grossWeight / 1000.0);

    return copyWith(
      primaryWastePct: waste,
      netWeight: newNetWeight,
      isNetWeightManual: false,
      finalCalories: newCalories,
      finalProtein: newProtein,
      finalFat: newFat,
      finalCarbs: newCarbs,
      cost: newCost,
    );
  }

  /// Масштабировать ингредиент (для повара: пересчёт под новый выход)
  TTIngredient scaleBy(double factor) {
    if (factor <= 0 || factor == 1.0) return this;
    return copyWith(
      grossWeight: grossWeight * factor,
      netWeight: netWeight * factor,
      cost: cost * factor,
      finalCalories: finalCalories * factor,
      finalProtein: finalProtein * factor,
      finalFat: finalFat * factor,
      finalCarbs: finalCarbs * factor,
    );
  }

  /// Изменить нетто вручную (повар) — пересчёт cost и КБЖУ пропорционально
  TTIngredient updateNetWeightForCook(double newNetWeight) {
    if (netWeight <= 0) return copyWith(netWeight: newNetWeight);
    return scaleBy(newNetWeight / netWeight);
  }

  /// Обновить нетто вес вручную (просто подстановка нетто без пересчёта отхода/ужарки)
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

  /// Пользователь ввёл «нетто» (вес после отхода, до приготовления) → пересчёт % отхода и выхода.
  /// Нетто = брутто × (1 − отход/100). Отсюда отход = (1 − нетто/брутто)×100.
  TTIngredient updateEffectiveGross(double newEffectiveGross, Product? product, CookingProcess? cookingProcess, {String languageCode = 'ru'}) {
    if (grossWeight <= 0) return this;
    final eff = newEffectiveGross.clamp(0.0, grossWeight);
    final wastePct = (1.0 - eff / grossWeight) * 100.0;
    final waste = wastePct.clamp(0.0, 99.9);
    if (product == null) {
      return copyWith(primaryWastePct: waste, netWeight: eff, isNetWeightManual: false);
    }
    return updatePrimaryWastePct(waste, product, cookingProcess);
  }

  /// Пользователь ввёл «выход» (вес после приготовления) → пересчёт % ужарки.
  /// Выход = нетто_после_отхода × (1 − ужарка/100). Отсюда ужарка = (1 − выход/effectiveGross)×100.
  TTIngredient updateOutputWeight(double newOutput, Product? product, CookingProcess? cookingProcess, {String languageCode = 'ru'}) {
    if (product == null || cookingProcess == null) {
      return copyWith(netWeight: newOutput.clamp(0.0, double.infinity), isNetWeightManual: true);
    }
    final effectiveGross = effectiveGrossWeight;
    if (effectiveGross <= 0) return copyWith(netWeight: newOutput.clamp(0.0, double.infinity), isNetWeightManual: true);
    final out = newOutput.clamp(0.0, effectiveGross);
    final lossPct = (1.0 - out / effectiveGross) * 100.0;
    final loss = lossPct.clamp(0.0, 99.9);
    return updateCookingLossPct(loss, product, cookingProcess, languageCode: languageCode);
  }

  /// Обновить технологический процесс
  TTIngredient updateCookingProcess(CookingProcess? newProcess, Product? product, {String languageCode = 'ru'}) {
    if (product == null) {
      return copyWith(
        cookingProcessId: newProcess?.id,
        cookingProcessName: newProcess?.getLocalizedName(languageCode),
      );
    }

    double newNetWeight = isNetWeightManual ? netWeight : grossWeight;
    double newCalories = 0;
    double newProtein = 0;
    double newFat = 0;
    double newCarbs = 0;

    if (newProcess != null) {
      final effectiveGross = grossWeight * (1.0 - primaryWastePct / 100.0);
      final lossPct = cookingLossPctOverride ?? newProcess.weightLossPercentage;
      final processed = newProcess.applyTo(product, effectiveGross, weightLossOverride: lossPct);
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
      cookingProcessName: newProcess?.getLocalizedName(languageCode),
      netWeight: newNetWeight,
      finalCalories: newCalories,
      finalProtein: newProtein,
      finalFat: newFat,
      finalCarbs: newCarbs,
    );
  }

  /// Значение брутто в исходных единицах (для отображения)
  double get grossDisplayValue =>
      CulinaryUnits.fromGrams(grossWeight, unit, gramsPerPiece: gramsPerPiece);

  /// Форматированная строка брутто
  String grossWeightDisplay(String lang) => _formatWithUnit(grossDisplayValue, unit, lang);
  String netWeightDisplay(String lang) => '${netWeight.toStringAsFixed(0)} г';

  String _formatWithUnit(double v, String u, String lang) {
    final label = CulinaryUnits.displayName(u, lang);
    if (u == 'pcs' || u == 'шт') return '${v.toStringAsFixed(v == v.truncateToDouble() ? 0 : 1)} $label';
    if (u == 'g' || u == 'г') return '${v.toStringAsFixed(0)} $label';
    if (u == 'kg' || u == 'кг') return '${v.toStringAsFixed(2)} $label';
    return '${v.toStringAsFixed(1)} $label';
  }

  /// Информация о стоимости
  String get costInfo => '${cost.toStringAsFixed(2)} ₽'; // TODO: использовать текущую валюту

  /// Вес после первичной обработки (нетто до ужарки). При ручном вводе — manualEffectiveGross, иначе формула.
  double get effectiveGrossWeight => manualEffectiveGross ?? (grossWeight * (1.0 - (primaryWastePct.clamp(0.0, 99.9) / 100.0)));

  /// Эффективный процент ужарки: ручная подстановка, иначе из способа, иначе вычисленный
  double get weightLossPercentage {
    if (cookingLossPctOverride != null) return cookingLossPctOverride!;
    if (grossWeight <= 0) return 0;
    return ((grossWeight - netWeight) / grossWeight) * 100.0;
  }

  /// Обновить % ужарки вручную и пересчитать нетто/КБЖУ
  TTIngredient updateCookingLossPct(double? newPct, Product? product, CookingProcess? cookingProcess, {String languageCode = 'ru'}) {
    if (product == null || cookingProcess == null) {
      return copyWith(cookingLossPctOverride: newPct);
    }
    final lossPct = (newPct ?? cookingProcess.weightLossPercentage).clamp(0.0, 99.9);
    final effectiveGross = grossWeight * (1.0 - primaryWastePct / 100.0);
    final newNetWeight = effectiveGross * (1.0 - lossPct / 100.0);
    final processed = cookingProcess.applyTo(product, effectiveGross, weightLossOverride: lossPct);
    return copyWith(
      cookingLossPctOverride: newPct,
      netWeight: newNetWeight,
      isNetWeightManual: newPct != null,
      finalCalories: processed.totalCalories,
      finalProtein: processed.totalProtein,
      finalFat: processed.totalFat,
      finalCarbs: processed.totalCarbs,
    );
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
    unit,
    primaryWastePct,
    gramsPerPiece,
    cookingLossPctOverride,
    isNetWeightManual,
    manualEffectiveGross,
    finalCalories,
    finalProtein,
    finalFat,
    finalCarbs,
    cost,
  ];
}