import 'package:equatable/equatable.dart';

const _sentinel = Object();

/// Тип чеклиста: Заготовки (ТТК ПФ + своё) или Задачи (своё).
enum ChecklistType {
  prep('prep', 'Заготовки'),
  tasks('tasks', 'Задачи');

  const ChecklistType(this.code, this.displayName);
  final String code;
  final String displayName;

  static const _translations = <String, Map<String, String>>{
    'prep': {'ru': 'Заготовки', 'en': 'Prep', 'es': 'Preparación', 'de': 'Vorbereitung', 'fr': 'Préparation'},
    'tasks': {'ru': 'Задачи', 'en': 'Tasks', 'es': 'Tareas', 'de': 'Aufgaben', 'fr': 'Tâches'},
  };

  String getLocalizedName(String lang) =>
      _translations[code]?[lang] ?? _translations[code]?['en'] ?? displayName;

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
  /// Подразделение: kitchen, bar, hall (default kitchen)
  final String assignedDepartment;
  /// Сотрудник, которому назначен чеклист (опционально, для обратной совместимости)
  final String? assignedEmployeeId;
  /// Сотрудники, которым адресован чеклист. null/пусто = всем
  final List<String>? assignedEmployeeIds;
  /// Срок выполнения (опционально)
  final DateTime? deadlineAt;
  /// На когда назначен чеклист (опционально)
  final DateTime? scheduledForAt;

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
    this.assignedDepartment = 'kitchen',
    this.assignedEmployeeId,
    this.assignedEmployeeIds,
    this.deadlineAt,
    this.scheduledForAt,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    final ac = json['action_config'];
    return Checklist(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String,
      name: (json['name'] as String?) ?? '',
      additionalName: json['additional_name'] as String?,
      type: ChecklistType.fromCode(json['type'] as String?),
      actionConfig: ac is Map
          ? ChecklistActionConfig.fromJson(Map<String, dynamic>.from(ac))
          : ChecklistActionConfig.fromJson(null),
      items: [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      assignedSection: json['assigned_section'] as String?,
      assignedDepartment: json['assigned_department'] as String? ?? 'kitchen',
      assignedEmployeeId: json['assigned_employee_id'] as String?,
      assignedEmployeeIds: (json['assigned_employee_ids'] as List<dynamic>?)
          ?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList(),
      deadlineAt: json['deadline_at'] != null
          ? DateTime.parse(json['deadline_at'] as String)
          : null,
      scheduledForAt: json['scheduled_for_at'] != null
          ? DateTime.parse(json['scheduled_for_at'] as String)
          : null,
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
      'assigned_department': assignedDepartment,
      if (assignedEmployeeId != null) 'assigned_employee_id': assignedEmployeeId,
      if (assignedEmployeeIds != null && assignedEmployeeIds!.isNotEmpty)
        'assigned_employee_ids': assignedEmployeeIds,
      if (deadlineAt != null) 'deadline_at': deadlineAt!.toIso8601String(),
      if (scheduledForAt != null) 'scheduled_for_at': scheduledForAt!.toIso8601String(),
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
    String? assignedDepartment,
    String? assignedEmployeeId,
    List<String>? assignedEmployeeIds,
    DateTime? deadlineAt,
    DateTime? scheduledForAt,
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
      assignedDepartment: assignedDepartment ?? this.assignedDepartment,
      assignedEmployeeId: assignedEmployeeId ?? this.assignedEmployeeId,
      assignedEmployeeIds: assignedEmployeeIds ?? this.assignedEmployeeIds,
      deadlineAt: deadlineAt ?? this.deadlineAt,
      scheduledForAt: scheduledForAt ?? this.scheduledForAt,
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
  /// Необходимое количество (для ПФ: сколько нужно приготовить).
  final double? targetQuantity;
  /// Единица измерения количества (г, кг, порции, шт и т.д.).
  final String? targetUnit;

  const ChecklistItem({
    required this.id,
    required this.checklistId,
    required this.title,
    this.sortOrder = 0,
    this.techCardId,
    this.targetQuantity,
    this.targetUnit,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      checklistId: json['checklist_id'] as String,
      title: (json['title'] as String?) ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      techCardId: json['tech_card_id'] as String?,
      targetQuantity: (json['target_quantity'] as num?)?.toDouble(),
      targetUnit: json['target_unit'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checklist_id': checklistId,
      'title': title,
      'sort_order': sortOrder,
      if (techCardId != null) 'tech_card_id': techCardId,
      if (targetQuantity != null) 'target_quantity': targetQuantity,
      if (targetUnit != null) 'target_unit': targetUnit,
    };
  }

  /// Для создания нового пункта (id и checklist_id задаются при сохранении).
  factory ChecklistItem.template({
    required String title,
    int sortOrder = 0,
    String? techCardId,
    double? targetQuantity,
    String? targetUnit,
  }) {
    return ChecklistItem(
      id: '',
      checklistId: '',
      title: title,
      sortOrder: sortOrder,
      techCardId: techCardId,
      targetQuantity: targetQuantity,
      targetUnit: targetUnit,
    );
  }

  ChecklistItem copyWith({
    String? id,
    String? checklistId,
    String? title,
    int? sortOrder,
    String? techCardId,
    Object? targetQuantity = _sentinel,
    Object? targetUnit = _sentinel,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      checklistId: checklistId ?? this.checklistId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
      techCardId: techCardId ?? this.techCardId,
      targetQuantity: targetQuantity == _sentinel ? this.targetQuantity : targetQuantity as double?,
      targetUnit: targetUnit == _sentinel ? this.targetUnit : targetUnit as String?,
    );
  }

  /// Отображаемая строка количества: «5 кг», «10 порций» и т.д.
  String? get quantityLabel {
    if (targetQuantity == null) return null;
    final qty = targetQuantity! == targetQuantity!.truncateToDouble()
        ? targetQuantity!.toInt().toString()
        : targetQuantity!.toStringAsFixed(1);
    final unit = targetUnit?.isNotEmpty == true ? ' ${targetUnit!}' : '';
    return '$qty$unit';
  }

  @override
  List<Object?> get props => [id, checklistId, title, sortOrder, techCardId, targetQuantity, targetUnit];
}
