import 'package:equatable/equatable.dart';

/// Шаблон чеклиста: шеф может править и создавать по аналогии.
class Checklist extends Equatable {
  final String id;
  final String establishmentId;
  final String createdBy;
  final String name;
  final List<ChecklistItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Checklist({
    required this.id,
    required this.establishmentId,
    required this.createdBy,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    return Checklist(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String,
      name: json['name'] as String,
      items: [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'name': name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Checklist copyWith({
    String? id,
    String? establishmentId,
    String? createdBy,
    String? name,
    List<ChecklistItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Checklist(
      id: id ?? this.id,
      establishmentId: establishmentId ?? this.establishmentId,
      createdBy: createdBy ?? this.createdBy,
      name: name ?? this.name,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [id, establishmentId, createdBy, name, items, createdAt, updatedAt];
}

/// Тип ячейки для пункта чеклиста.
enum ChecklistCellType {
  /// Пустая ячейка для ввода количества.
  quantity,
  /// Ячейка с галочкой (чекбокс).
  checkbox,
  /// Выпадающий список на выбор (опции задаются при создании).
  dropdown,
}

extension ChecklistCellTypeExt on ChecklistCellType {
  String get value => switch (this) {
    ChecklistCellType.quantity => 'quantity',
    ChecklistCellType.checkbox => 'checkbox',
    ChecklistCellType.dropdown => 'dropdown',
  };
  static ChecklistCellType fromString(String? s) {
    switch (s) {
      case 'quantity': return ChecklistCellType.quantity;
      case 'dropdown': return ChecklistCellType.dropdown;
      default: return ChecklistCellType.checkbox;
    }
  }
}

/// Пункт чеклиста-шаблона.
class ChecklistItem extends Equatable {
  final String id;
  final String checklistId;
  final String title;
  final int sortOrder;
  /// Тип ячейки: количество, галочка, выпадающий список.
  final ChecklistCellType cellType;
  /// Опции для выпадающего списка (только для dropdown).
  final List<String> dropdownOptions;

  const ChecklistItem({
    required this.id,
    required this.checklistId,
    required this.title,
    this.sortOrder = 0,
    this.cellType = ChecklistCellType.checkbox,
    this.dropdownOptions = const [],
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    final opts = json['dropdown_options'];
    List<String> options = [];
    if (opts is List) {
      options = opts.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return ChecklistItem(
      id: json['id'] as String,
      checklistId: json['checklist_id'] as String,
      title: json['title'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      cellType: ChecklistCellTypeExt.fromString(json['cell_type'] as String?),
      dropdownOptions: options,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checklist_id': checklistId,
      'title': title,
      'sort_order': sortOrder,
      'cell_type': cellType.value,
      'dropdown_options': dropdownOptions,
    };
  }

  /// Для создания нового пункта (id и checklist_id задаются при сохранении).
  factory ChecklistItem.template({
    required String title,
    int sortOrder = 0,
    ChecklistCellType cellType = ChecklistCellType.checkbox,
    List<String> dropdownOptions = const [],
  }) {
    return ChecklistItem(
      id: '',
      checklistId: '',
      title: title,
      sortOrder: sortOrder,
      cellType: cellType,
      dropdownOptions: List.from(dropdownOptions),
    );
  }

  ChecklistItem copyWith({
    String? id,
    String? checklistId,
    String? title,
    int? sortOrder,
    ChecklistCellType? cellType,
    List<String>? dropdownOptions,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      checklistId: checklistId ?? this.checklistId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
      cellType: cellType ?? this.cellType,
      dropdownOptions: dropdownOptions ?? this.dropdownOptions,
    );
  }

  @override
  List<Object?> get props => [id, checklistId, title, sortOrder, cellType, dropdownOptions];
}

/// Отправленный заполненный чеклист (для входящих шеф-повара).
class ChecklistSubmission extends Equatable {
  final String id;
  final String establishmentId;
  final String checklistId;
  final String checklistName;
  final String filledByEmployeeId;
  final String filledByName;
  final String? filledByRole;
  final DateTime filledAt;
  final Map<String, dynamic> payload;

  const ChecklistSubmission({
    required this.id,
    required this.establishmentId,
    required this.checklistId,
    required this.checklistName,
    required this.filledByEmployeeId,
    required this.filledByName,
    this.filledByRole,
    required this.filledAt,
    required this.payload,
  });

  factory ChecklistSubmission.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    final Map<String, dynamic> p = payload is Map<String, dynamic> ? payload : {};
    return ChecklistSubmission(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      checklistId: json['checklist_id'] as String,
      checklistName: p['checklist_name'] as String? ?? '',
      filledByEmployeeId: json['filled_by_employee_id'] as String,
      filledByName: p['filled_by_name'] as String? ?? '—',
      filledByRole: p['filled_by_role'] as String?,
      filledAt: DateTime.parse(json['created_at'] as String),
      payload: p,
    );
  }

  @override
  List<Object?> get props => [id, checklistId, filledAt];
}
