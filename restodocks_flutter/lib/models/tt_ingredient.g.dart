// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tt_ingredient.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TTIngredient _$TTIngredientFromJson(Map<String, dynamic> json) => TTIngredient(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String,
      sourceTechCardId: json['source_tech_card_id'] as String?,
      sourceTechCardName: json['source_tech_card_name'] as String?,
      cookingProcessId: json['cooking_process_id'] as String?,
      cookingProcessName: json['cooking_process_name'] as String?,
      grossWeight: (json['gross_weight'] as num).toDouble(),
      netWeight: (json['net_weight'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'g',
      primaryWastePct: (json['primary_waste_pct'] as num?)?.toDouble() ?? 0,
      gramsPerPiece: (json['gramsPerPiece'] as num?)?.toDouble(),
      cookingLossPctOverride:
          (json['cooking_loss_pct_override'] as num?)?.toDouble(),
      isNetWeightManual: json['is_net_weight_manual'] as bool? ?? false,
      manualEffectiveGross:
          (json['manual_effective_gross'] as num?)?.toDouble(),
      outputWeight: (json['output_weight'] as num?)?.toDouble() ?? 0,
      finalCalories: (json['final_calories'] as num).toDouble(),
      finalProtein: (json['final_protein'] as num).toDouble(),
      finalFat: (json['final_fat'] as num).toDouble(),
      finalCarbs: (json['final_carbs'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      pricePerKg: (json['price_per_kg'] as num?)?.toDouble(),
      costCurrency: json['cost_currency'] as String?,
    );

Map<String, dynamic> _$TTIngredientToJson(TTIngredient instance) =>
    <String, dynamic>{
      'id': instance.id,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'source_tech_card_id': instance.sourceTechCardId,
      'source_tech_card_name': instance.sourceTechCardName,
      'cooking_process_id': instance.cookingProcessId,
      'cooking_process_name': instance.cookingProcessName,
      'gross_weight': instance.grossWeight,
      'net_weight': instance.netWeight,
      'unit': instance.unit,
      'primary_waste_pct': instance.primaryWastePct,
      'gramsPerPiece': instance.gramsPerPiece,
      'cooking_loss_pct_override': instance.cookingLossPctOverride,
      'is_net_weight_manual': instance.isNetWeightManual,
      'manual_effective_gross': instance.manualEffectiveGross,
      'output_weight': instance.outputWeight,
      'final_calories': instance.finalCalories,
      'final_protein': instance.finalProtein,
      'final_fat': instance.finalFat,
      'final_carbs': instance.finalCarbs,
      'cost': instance.cost,
      'price_per_kg': instance.pricePerKg,
      'cost_currency': instance.costCurrency,
    };
