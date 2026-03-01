/// Продукт из iiko-бланка инвентаризации.
/// Хранится в таблице iiko_products, не связан с основным каталогом products.
class IikoProduct {
  final String id;
  final String establishmentId;
  final String? code;
  final String name;
  final String? unit;
  final String? groupName;
  final int sortOrder;

  const IikoProduct({
    required this.id,
    required this.establishmentId,
    this.code,
    required this.name,
    this.unit,
    this.groupName,
    this.sortOrder = 0,
  });

  factory IikoProduct.fromJson(Map<String, dynamic> json) => IikoProduct(
        id: json['id'] as String,
        establishmentId: json['establishment_id'] as String,
        code: json['code'] as String?,
        name: json['name'] as String,
        unit: json['unit'] as String?,
        groupName: json['group_name'] as String?,
        sortOrder: (json['sort_order'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'code': code,
        'name': name,
        'unit': unit,
        'group_name': groupName,
        'sort_order': sortOrder,
      };

  IikoProduct copyWith({
    String? code,
    String? name,
    String? unit,
    String? groupName,
    int? sortOrder,
  }) =>
      IikoProduct(
        id: id,
        establishmentId: establishmentId,
        code: code ?? this.code,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        groupName: groupName ?? this.groupName,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
