// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'establishment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Establishment _$EstablishmentFromJson(Map<String, dynamic> json) =>
    Establishment(
      id: json['id'] as String,
      name: json['name'] as String,
      pinCode: json['pin_code'] as String,
      ownerId: json['owner_id'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      defaultCurrency: json['default_currency'] as String? ?? 'RUB',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$EstablishmentToJson(Establishment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'pin_code': instance.pinCode,
      'owner_id': instance.ownerId,
      'address': instance.address,
      'phone': instance.phone,
      'email': instance.email,
      'default_currency': instance.defaultCurrency,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
