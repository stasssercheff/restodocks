// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cooking_process.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CookingProcess _$CookingProcessFromJson(Map<String, dynamic> json) =>
    CookingProcess(
      id: json['id'] as String,
      name: json['name'] as String,
      localizedNames: Map<String, String>.from(json['localized_names'] as Map),
      calorieMultiplier: (json['calorie_multiplier'] as num).toDouble(),
      proteinMultiplier: (json['protein_multiplier'] as num).toDouble(),
      fatMultiplier: (json['fat_multiplier'] as num).toDouble(),
      carbsMultiplier: (json['carbs_multiplier'] as num).toDouble(),
      weightLossPercentage: (json['weight_loss_percentage'] as num).toDouble(),
      applicableCategories: (json['applicable_categories'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$CookingProcessToJson(CookingProcess instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'localized_names': instance.localizedNames,
      'calorie_multiplier': instance.calorieMultiplier,
      'protein_multiplier': instance.proteinMultiplier,
      'fat_multiplier': instance.fatMultiplier,
      'carbs_multiplier': instance.carbsMultiplier,
      'weight_loss_percentage': instance.weightLossPercentage,
      'applicable_categories': instance.applicableCategories,
    };
