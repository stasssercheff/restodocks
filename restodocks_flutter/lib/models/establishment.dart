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

  @JsonKey(name: 'inn_bin')
  final String? innBin;

  /// Полное юридическое наименование (для приказов/документов)
  @JsonKey(name: 'legal_name')
  final String? legalName;

  /// ОГРН / ОГРНИП
  @JsonKey(name: 'ogrn_ogrnip')
  final String? ogrnOgrnip;

  /// КПП (только для ООО)
  @JsonKey(name: 'kpp')
  final String? kpp;

  /// Банковские реквизиты
  @JsonKey(name: 'bank_rs')
  final String? bankRs;

  @JsonKey(name: 'bank_bik')
  final String? bankBik;

  @JsonKey(name: 'bank_name')
  final String? bankName;

  /// ФИО и должность руководителя (для подписей в документах)
  @JsonKey(name: 'director_fio')
  final String? directorFio;

  @JsonKey(name: 'director_position')
  final String? directorPosition;

  @JsonKey(name: 'phone')
  final String? phone;

  @JsonKey(name: 'email')
  final String? email;

  @JsonKey(name: 'default_currency')
  final String defaultCurrency;

  @JsonKey(name: 'subscription_type')
  final String? subscriptionType;

  /// ID родительского заведения (для филиалов). NULL = основное заведение.
  @JsonKey(name: 'parent_establishment_id')
  final String? parentEstablishmentId;

  // Alias for subscriptionType for backward compatibility
  String? get subscriptionPlan => subscriptionType;

  /// Основное заведение (не филиал)
  bool get isMain => parentEstablishmentId == null || parentEstablishmentId!.isEmpty;

  /// Филиал другого заведения
  bool get isBranch => !isMain;

  /// ID заведения, откуда читаются данные (номенклатура, ТТК). Для филиала — родитель.
  String get dataEstablishmentId => (parentEstablishmentId != null && parentEstablishmentId!.isNotEmpty)
      ? parentEstablishmentId!
      : id;

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
    this.innBin,
    this.legalName,
    this.ogrnOgrnip,
    this.kpp,
    this.bankRs,
    this.bankBik,
    this.bankName,
    this.directorFio,
    this.directorPosition,
    this.phone,
    this.email,
    this.defaultCurrency = 'RUB',
    this.subscriptionType,
    this.parentEstablishmentId,
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
    String? innBin,
    String? legalName,
    String? ogrnOgrnip,
    String? kpp,
    String? bankRs,
    String? bankBik,
    String? bankName,
    String? directorFio,
    String? directorPosition,
    String? phone,
    String? email,
    String? defaultCurrency,
    String? subscriptionType,
    String? parentEstablishmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Establishment(
      id: id ?? this.id,
      name: name ?? this.name,
      pinCode: pinCode ?? this.pinCode,
      ownerId: ownerId ?? this.ownerId,
      address: address ?? this.address,
      innBin: innBin ?? this.innBin,
      legalName: legalName ?? this.legalName,
      ogrnOgrnip: ogrnOgrnip ?? this.ogrnOgrnip,
      kpp: kpp ?? this.kpp,
      bankRs: bankRs ?? this.bankRs,
      bankBik: bankBik ?? this.bankBik,
      bankName: bankName ?? this.bankName,
      directorFio: directorFio ?? this.directorFio,
      directorPosition: directorPosition ?? this.directorPosition,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      parentEstablishmentId: parentEstablishmentId ?? this.parentEstablishmentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Символ валюты
  String get currencySymbol => currencySymbolFor(defaultCurrency);

  /// Статический хелпер — символ для любого кода валюты
  static String currencySymbolFor(String code) {
    switch (code.toUpperCase()) {
      case 'RUB': return '₽';
      case 'USD': return '\$';
      case 'EUR': return '€';
      case 'GBP': return '£';
      case 'VND': return '₫';
      case 'THB': return '฿';
      case 'KZT': return '₸';
      case 'UAH': return '₴';
      case 'JPY': return '¥';
      case 'CNY': return '¥';
      case 'KRW': return '₩';
      case 'INR': return '₹';
      case 'TRY': return '₺';
      case 'PHP': return '₱';
      case 'BYN': return 'Br';
      case 'CHF': return 'Fr';
      case 'PLN': return 'zł';
      case 'SGD': return 'S\$';
      case 'HKD': return 'HK\$';
      case 'CAD': return 'C\$';
      case 'AUD': return 'A\$';
      case 'MXN': return '\$';
      case 'IDR': return 'Rp';
      case 'MYR': return 'RM';
      default: return code;
    }
  }

  /// Проверка PIN-кода (с очисткой пробелов и приведением к верхнему регистру)
  bool verifyPinCode(String inputPin) {
    final cleanInput = inputPin.trim().toUpperCase();
    final cleanStored = pinCode.trim().toUpperCase();
    return cleanInput == cleanStored;
  }

  /// JSON сериализация (защита от null из БД/API на Web)
  factory Establishment.fromJson(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json);
    m['id'] = m['id']?.toString() ?? '';
    m['name'] = m['name']?.toString() ?? '';
    m['pin_code'] = m['pin_code']?.toString() ?? '';
    m['owner_id'] = m['owner_id']?.toString() ?? '';
    m['parent_establishment_id'] = m['parent_establishment_id']?.toString();
    return _$EstablishmentFromJson(m);
  }
  Map<String, dynamic> toJson() => _$EstablishmentToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    pinCode,
    ownerId,
    address,
    innBin,
    legalName,
    ogrnOgrnip,
    kpp,
    bankRs,
    bankBik,
    bankName,
    directorFio,
    directorPosition,
    phone,
    email,
    defaultCurrency,
    parentEstablishmentId,
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