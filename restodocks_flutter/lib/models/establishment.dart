import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'establishment.g.dart';

/// Модель заведения/компании
@JsonSerializable()
class Establishment extends Equatable {
  @JsonKey(name: 'id')
  final String id;

  @JsonKey(name: 'name')
  final String name;

  @JsonKey(name: 'pin_code')
  final String pinCode;

  @JsonKey(name: 'owner_id')
  final String ownerId;

  @JsonKey(name: 'address')
  final String? address;

  @JsonKey(name: 'phone')
  final String? phone;

  @JsonKey(name: 'email')
  final String? email;

  @JsonKey(name: 'default_currency')
  final String defaultCurrency;

  @JsonKey(name: 'subscription_type')
  final String? subscriptionType;

  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const Establishment({
    required this.id,
    required this.name,
    required this.pinCode,
    required this.ownerId,
    this.address,
    this.phone,
    this.email,
    this.defaultCurrency = 'RUB',
    this.subscriptionType,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Создание копии с изменениями
  Establishment copyWith({
    String? id,
    String? name,
    String? pinCode,
    String? ownerId,
    String? address,
    String? phone,
    String? email,
    String? defaultCurrency,
    String? subscriptionType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Establishment(
      id: id ?? this.id,
      name: name ?? this.name,
      pinCode: pinCode ?? this.pinCode,
      ownerId: ownerId ?? this.ownerId,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Символ валюты
  String get currencySymbol {
    switch (defaultCurrency.toUpperCase()) {
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
        return defaultCurrency;
    }
  }

  /// Проверка PIN-кода (с очисткой пробелов и приведением к верхнему регистру)
  bool verifyPinCode(String inputPin) {
    final cleanInput = inputPin.trim().toUpperCase();
    final cleanStored = pinCode.trim().toUpperCase();
    return cleanInput == cleanStored;
  }

  /// JSON сериализация
  factory Establishment.fromJson(Map<String, dynamic> json) => _$EstablishmentFromJson(json);
  Map<String, dynamic> toJson() => _$EstablishmentToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    pinCode,
    ownerId,
    address,
    phone,
    email,
    defaultCurrency,
    createdAt,
    updatedAt,
  ];

  /// Создание нового заведения
  /// [pinCode] — если задан, используется как PIN (иначе генерируется).
  factory Establishment.create({
    required String name,
    required String ownerId,
    String? pinCode,
    String? address,
    String? phone,
    String? email,
    String? defaultCurrency,
  }) {
    final now = DateTime.now();
    return Establishment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      pinCode: pinCode != null && pinCode.length == 8 ? pinCode.trim().toUpperCase() : generatePinCode(),
      ownerId: ownerId,
      address: address,
      phone: phone,
      email: email,
      defaultCurrency: defaultCurrency ?? 'RUB',
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Генерация PIN-кода (8 символов: буквы и цифры). Всегда новый, не дублируется.
  static String generatePinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      buffer.write(chars[r.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  /// Проверка корректности PIN-кода
  static bool isValidPinCode(String pinCode) {
    if (pinCode.length != 8) return false;

    final allowedChars = RegExp(r'^[A-Z0-9]+$');
    return allowedChars.hasMatch(pinCode);
  }
}