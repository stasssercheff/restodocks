import 'package:equatable/equatable.dart';

/// Тип чеклиста: Заготовки (ТТК ПФ + своё) или Задачи (своё).
enum ChecklistType {
  prep('prep', 'Заготовки'),
  tasks('tasks', 'Задачи');

  const ChecklistType(this.code, this.displayName);
  final String code;
  final String displayName;

  static ChecklistType? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return ChecklistType.values.where((t) => t.code == code).firstOrNull;
  }
}

/// Конфигурация «окна действия»: цифра, выбор, тумблер.
class ChecklistActionConfig {
  final bool hasNumeric;
  final List<String>? dropdownOptions;
  final bool hasToggle;

  const ChecklistActionConfig({
    this.hasNumeric = false,
    this.dropdownOptions,
    this.hasToggle = true,
  });

  factory ChecklistActionConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChecklistActionConfig();
    final opts = json['dropdown_options'] as List<dynamic>?;
    return ChecklistActionConfig(
      hasNumeric: json['has_numeric'] == true,
      dropdownOptions: opts?.map((e) => e.toString()).toList(),
      hasToggle: json['has_toggle'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'has_numeric': hasNumeric,
        if (dropdownOptions != null) 'dropdown_options': dropdownOptions,
        'has_toggle': hasToggle,
      };
}

/// Шаблон чеклиста: шеф может править и создавать по аналогии.
class Checklist extends Equatable {
  final String id;
  final String establishmentId;
  final String createdBy;
  final String name;
  /// Дополнительное название (подзаголовок).
  final String? additionalName;
  /// Тип: prep (Заготовки) или tasks (Задачи).
  final ChecklistType? type;
  /// Конфигурация окна действия.
  final ChecklistActionConfig actionConfig;
  final List<ChecklistItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Цех/отдел, где отображается чеклист (горячий цех, холодный цех и т.д.)
  final String? assignedSection;
  /// Сотрудник, которому назначен чеклист (опционально)
  final String? assignedEmployeeId;

  const Checklist({
    required this.id,
    required this.establishmentId,
    required this.createdBy,
    required this.name,
    this.additionalName,
    this.type,
    this.actionConfig = const ChecklistActionConfig(),
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.assignedSection,
    this.assignedEmployeeId,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    final ac = json['action_config'];
    return Checklist(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String,
      name: json['name'] as String,
      additionalName: json['additional_name'] as String?,
      type: ChecklistType.fromCode(json['type'] as String?),
      actionConfig: ac is Map
          ? ChecklistActionConfig.fromJson(Map<String, dynamic>.from(ac))
          : ChecklistActionConfig.fromJson(null),
      items: [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      assignedSection: json['assigned_section'] as String?,
      assignedEmployeeId: json['assigned_employee_id'] as String?,
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
      if (additionalName != null) 'additional_name': additionalName,
      if (type != null) 'type': type!.code,
      if (assignedSection != null) 'assigned_section': assignedSection,
      if (assignedEmployeeId != null) 'assigned_employee_id': assignedEmployeeId,
    };
  }

  Checklist copyWith({
    String? id,
    String? establishmentId,
    String? createdBy,
    String? name,
    String? additionalName,
    ChecklistType? type,
    ChecklistActionConfig? actionConfig,
    List<ChecklistItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? assignedSection,
    String? assignedEmployeeId,
  }) {
    return Checklist(
      id: id ?? this.id,
      establishmentId: establishmentId ?? this.establishmentId,
      createdBy: createdBy ?? this.createdBy,
      name: name ?? this.name,
      additionalName: additionalName ?? this.additionalName,
      type: type ?? this.type,
      actionConfig: actionConfig ?? this.actionConfig,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedSection: assignedSection ?? this.assignedSection,
      assignedEmployeeId: assignedEmployeeId ?? this.assignedEmployeeId,
    );
  }

  @override
  List<Object?> get props => [id, establishmentId, createdBy, name, items, createdAt, updatedAt];
}

/// Пункт чеклиста-шаблона.
class ChecklistItem extends Equatable {
  final String id;
  final String checklistId;
  /// Текст (для custom или fallback). Для ТТК ПФ — название из techCard, если есть.
  final String title;
  final int sortOrder;
  /// ID ТТК ПФ (если пункт — ссылка на полуфабрикат).
  final String? techCardId;

  const ChecklistItem({
    required this.id,
    required this.checklistId,
    required this.title,
    this.sortOrder = 0,
    this.techCardId,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      checklistId: json['checklist_id'] as String,
      title: (json['title'] as String?) ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      techCardId: json['tech_card_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checklist_id': checklistId,
      'title': title,
      'sort_order': sortOrder,
      if (techCardId != null) 'tech_card_id': techCardId,
    };
  }

  /// Для создания нового пункта (id и checklist_id задаются при сохранении).
  factory ChecklistItem.template({
    required String title,
    int sortOrder = 0,
    String? techCardId,
  }) {
    return ChecklistItem(
      id: '',
      checklistId: '',
      title: title,
      sortOrder: sortOrder,
      techCardId: techCardId,
    );
  }

  ChecklistItem copyWith({
    String? id,
    String? checklistId,
    String? title,
    int? sortOrder,
    String? techCardId,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      checklistId: checklistId ?? this.checklistId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
      techCardId: techCardId ?? this.techCardId,
    );
  }

  @override
  List<Object?> get props => [id, checklistId, title, sortOrder, techCardId];
}
