/// Продукт из iiko-бланка инвентаризации.
/// Хранится в таблице iiko_products, не связан с основным каталогом products.
class IikoProduct {
  final String id;
  final String establishmentId;
  final String? code;
  /// Отображаемое название (без префикса «Т.»)
  final String name;
  /// Оригинальное название из бланка (с «Т.», как в файле) — для экспорта
  final String? nameOriginal;
  /// Единица измерения как в бланке (кг, л, шт — оригинал)
  final String? unit;
  /// Оригинальное значение группы из бланка (с «Т.») — для экспорта
  final String? groupNameOriginal;
  final String? groupName;
  final int sortOrder;

  const IikoProduct({
    required this.id,
    required this.establishmentId,
    this.code,
    required this.name,
    this.nameOriginal,
    this.unit,
    this.groupName,
    this.groupNameOriginal,
    this.sortOrder = 0,
  });

  factory IikoProduct.fromJson(Map<String, dynamic> json) => IikoProduct(
        id: json['id'] as String,
        establishmentId: json['establishment_id'] as String,
        code: json['code'] as String?,
        name: json['name'] as String,
        nameOriginal: json['name_original'] as String?,
        unit: json['unit'] as String?,
        groupName: json['group_name'] as String?,
        groupNameOriginal: json['group_name_original'] as String?,
        sortOrder: (json['sort_order'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'code': code,
        'name': name,
        'name_original': nameOriginal ?? name,
        'unit': unit,
        'group_name': groupName,
        'group_name_original': groupNameOriginal ?? groupName,
        'sort_order': sortOrder,
      };

  IikoProduct copyWith({
    String? code,
    String? name,
    String? nameOriginal,
    String? unit,
    String? groupName,
    String? groupNameOriginal,
    int? sortOrder,
  }) =>
      IikoProduct(
        id: id,
        establishmentId: establishmentId,
        code: code ?? this.code,
        name: name ?? this.name,
        nameOriginal: nameOriginal ?? this.nameOriginal,
        unit: unit ?? this.unit,
        groupName: groupName ?? this.groupName,
        groupNameOriginal: groupNameOriginal ?? this.groupNameOriginal,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
