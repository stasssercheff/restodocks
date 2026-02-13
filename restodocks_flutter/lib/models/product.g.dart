// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Product _$ProductFromJson(Map<String, dynamic> json) => Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      names: (json['names'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      calories: (json['calories'] as num?)?.toDouble(),
      protein: (json['protein'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      containsGluten: json['contains_gluten'] as bool?,
      containsLactose: json['contains_lactose'] as bool?,
      basePrice: (json['base_price'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      unit: json['unit'] as String?,
      primaryWastePct: (json['primary_waste_pct'] as num?)?.toDouble(),
      supplierIds: (json['supplier_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ProductToJson(Product instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
      'names': instance.names,
      'calories': instance.calories,
      'protein': instance.protein,
      'fat': instance.fat,
      'carbs': instance.carbs,
      'contains_gluten': instance.containsGluten,
      'contains_lactose': instance.containsLactose,
      'base_price': instance.basePrice,
      'currency': instance.currency,
      'unit': instance.unit,
      'primary_waste_pct': instance.primaryWastePct,
      'supplier_ids': instance.supplierIds,
    };
