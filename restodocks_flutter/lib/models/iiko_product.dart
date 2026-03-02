/// Продукт из iiko-бланка инвентаризации.
/// Хранится в таблице iiko_products, не связан с основным каталогом products.
/// Все поля хранятся ТОЧНО как в оригинальном бланке — ни один символ не изменяется.
class IikoProduct {
  final String id;
  final String establishmentId;
  final String? code;

  /// Название ТОЧНО как в бланке (например «Т.  Пенообразователь Bubble drops»).
  /// Используется при экспорте — копируется 1-в-1 в выходной файл.
  final String name;

  /// Единица измерения как в бланке (кг, л, шт — не нормализованная).
  final String? unit;

  /// Группа как в бланке (например «Т. Аперитивы/Биттеры»).
  final String? groupName;

  final int sortOrder;

  /// Название листа Excel из которого взят продукт (например «Товары», «Блюда»).
  /// Null означает первый лист или старые данные без разделения по листам.
  final String? sheetName;

  const IikoProduct({
    required this.id,
    required this.establishmentId,
    this.code,
    required this.name,
    this.unit,
    this.groupName,
    this.sortOrder = 0,
    this.sheetName,
  });

  /// Отображаемое название — убирает префикс «Т.» только для показа на экране.
  /// В базе и в Excel всегда хранится оригинал [name].
  String get displayName {
    var v = name.trim();
    if (v.startsWith('Т.')) {
      v = v.replaceFirst(RegExp(r'^Т\.\s*'), '').trim();
    }
    return v.isEmpty ? name : v;
  }

  /// Отображаемое название группы (без «Т.»).
  String? get displayGroupName {
    if (groupName == null) return null;
    var v = groupName!.trim();
    if (v.startsWith('Т.')) {
      v = v.replaceFirst(RegExp(r'^Т\.\s*'), '').trim();
    }
    return v.isEmpty ? groupName : v;
  }

  factory IikoProduct.fromJson(Map<String, dynamic> json) => IikoProduct(
        id: json['id'] as String,
        establishmentId: json['establishment_id'] as String,
        code: json['code'] as String?,
        name: json['name'] as String,
        unit: json['unit'] as String?,
        groupName: json['group_name'] as String?,
        sortOrder: (json['sort_order'] as int?) ?? 0,
        sheetName: json['sheet_name'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'code': code,
        'name': name,
        'unit': unit,
        'group_name': groupName,
        'sort_order': sortOrder,
        'sheet_name': sheetName,
      };

  IikoProduct copyWith({
    String? code,
    String? name,
    String? unit,
    String? groupName,
    int? sortOrder,
    String? sheetName,
  }) =>
      IikoProduct(
        id: id,
        establishmentId: establishmentId,
        code: code ?? this.code,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        groupName: groupName ?? this.groupName,
        sortOrder: sortOrder ?? this.sortOrder,
        sheetName: sheetName ?? this.sheetName,
      );
}
