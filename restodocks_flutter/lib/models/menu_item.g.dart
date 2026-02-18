// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MenuItem _$MenuItemFromJson(Map<String, dynamic> json) => MenuItem(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      establishmentId: json['establishmentId'] as String,
      techCardId: json['techCardId'] as String?,
      calories: (json['calories'] as num?)?.toDouble(),
      protein: (json['protein'] as num?)?.toDouble(),
      fat: (json['fat'] as num?)?.toDouble(),
      carbs: (json['carbs'] as num?)?.toDouble(),
      portionWeight: (json['portionWeight'] as num?)?.toDouble() ?? 100,
    );

Map<String, dynamic> _$MenuItemToJson(MenuItem instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
      'price': instance.price,
      'currency': instance.currency,
      'establishmentId': instance.establishmentId,
      'techCardId': instance.techCardId,
      'calories': instance.calories,
      'protein': instance.protein,
      'fat': instance.fat,
      'carbs': instance.carbs,
      'portionWeight': instance.portionWeight,
    };
