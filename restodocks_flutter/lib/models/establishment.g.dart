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
      innBin: json['inn_bin'] as String?,
      legalName: json['legal_name'] as String?,
      ogrnOgrnip: json['ogrn_ogrnip'] as String?,
      kpp: json['kpp'] as String?,
      bankRs: json['bank_rs'] as String?,
      bankBik: json['bank_bik'] as String?,
      bankName: json['bank_name'] as String?,
      directorFio: json['director_fio'] as String?,
      directorPosition: json['director_position'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      defaultCurrency: json['default_currency'] as String? ?? 'RUB',
      subscriptionType: json['subscription_type'] as String?,
      parentEstablishmentId: json['parent_establishment_id'] as String?,
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
      'inn_bin': instance.innBin,
      'legal_name': instance.legalName,
      'ogrn_ogrnip': instance.ogrnOgrnip,
      'kpp': instance.kpp,
      'bank_rs': instance.bankRs,
      'bank_bik': instance.bankBik,
      'bank_name': instance.bankName,
      'director_fio': instance.directorFio,
      'director_position': instance.directorPosition,
      'phone': instance.phone,
      'email': instance.email,
      'default_currency': instance.defaultCurrency,
      'subscription_type': instance.subscriptionType,
      'parent_establishment_id': instance.parentEstablishmentId,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
