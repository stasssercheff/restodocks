/// Список заказа продуктов: шаблон (название, поставщик, контакты, позиции) или сохранённый экземпляр с количествами и датой.
class OrderList {
  final String id;
  /// Название списка (для сохранённого с количествами — с датой в названии).
  final String name;
  /// Наименование поставщика.
  final String supplierName;
  final String? email;
  final String? phone;
  final String? telegram;
  final String? zalo;
  final String? whatsapp;
  /// Позиции списка (продукт, единица, количество при сохранении).
  final List<OrderListItem> items;
  /// Комментарий к списку.
  final String comment;
  /// Дата сохранения списка с количествами (null = шаблон).
  final DateTime? savedAt;

  const OrderList({
    required this.id,
    required this.name,
    required this.supplierName,
    this.email,
    this.phone,
    this.telegram,
    this.zalo,
    this.whatsapp,
    this.items = const [],
    this.comment = '',
    this.savedAt,
  });

  bool get isSavedWithQuantities => savedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'supplierName': supplierName,
        'email': email,
        'phone': phone,
        'telegram': telegram,
        'zalo': zalo,
        'whatsapp': whatsapp,
        'items': items.map((e) => e.toJson()).toList(),
        'comment': comment,
        'savedAt': savedAt?.toIso8601String(),
      };

  factory OrderList.fromJson(Map<String, dynamic> json) {
    final savedAtStr = json['savedAt'] as String?;
    return OrderList(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      supplierName: json['supplierName'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      telegram: json['telegram'] as String?,
      zalo: json['zalo'] as String?,
      whatsapp: json['whatsapp'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => OrderListItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      comment: json['comment'] as String? ?? '',
      savedAt: savedAtStr != null ? DateTime.tryParse(savedAtStr) : null,
    );
  }

  OrderList copyWith({
    String? id,
    String? name,
    String? supplierName,
    String? email,
    String? phone,
    String? telegram,
    String? zalo,
    String? whatsapp,
    List<OrderListItem>? items,
    String? comment,
    DateTime? savedAt,
  }) =>
      OrderList(
        id: id ?? this.id,
        name: name ?? this.name,
        supplierName: supplierName ?? this.supplierName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        telegram: telegram ?? this.telegram,
        zalo: zalo ?? this.zalo,
        whatsapp: whatsapp ?? this.whatsapp,
        items: items ?? this.items,
        comment: comment ?? this.comment,
        savedAt: savedAt ?? this.savedAt,
      );
}

/// Позиция в списке заказа: продукт (id + название для отображения), единица измерения, количество.
class OrderListItem {
  /// id продукта из номенклатуры (может быть пустым для ручного ввода).
  final String? productId;
  /// Название для отображения (из продукта или вручную).
  final String productName;
  /// Единица измерения (г, кг, л, пачка, коробка и т.д.) — задаётся при создании, можно менять в списке.
  final String unit;
  /// Количество (заполняется при открытии списка / сохранении).
  final double quantity;

  const OrderListItem({
    this.productId,
    required this.productName,
    required this.unit,
    this.quantity = 0,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'unit': unit,
        'quantity': quantity,
      };

  factory OrderListItem.fromJson(Map<String, dynamic> json) => OrderListItem(
        productId: json['productId'] as String?,
        productName: json['productName'] as String? ?? '',
        unit: json['unit'] as String? ?? 'g',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      );

  OrderListItem copyWith({
    String? productId,
    String? productName,
    String? unit,
    double? quantity,
  }) =>
      OrderListItem(
        productId: productId ?? this.productId,
        productName: productName ?? this.productName,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
      );
}
