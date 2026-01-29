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

/// Пункт чеклиста-шаблона.
class ChecklistItem extends Equatable {
  final String id;
  final String checklistId;
  final String title;
  final int sortOrder;

  const ChecklistItem({
    required this.id,
    required this.checklistId,
    required this.title,
    this.sortOrder = 0,
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      checklistId: json['checklist_id'] as String,
      title: json['title'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'checklist_id': checklistId,
      'title': title,
      'sort_order': sortOrder,
    };
  }

  /// Для создания нового пункта (id и checklist_id задаются при сохранении).
  factory ChecklistItem.template({required String title, int sortOrder = 0}) {
    return ChecklistItem(
      id: '',
      checklistId: '',
      title: title,
      sortOrder: sortOrder,
    );
  }

  ChecklistItem copyWith({
    String? id,
    String? checklistId,
    String? title,
    int? sortOrder,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      checklistId: checklistId ?? this.checklistId,
      title: title ?? this.title,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [id, checklistId, title, sortOrder];
}
