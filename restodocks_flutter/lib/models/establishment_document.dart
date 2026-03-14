import 'package:equatable/equatable.dart';

/// Тип видимости документа
enum DocumentVisibilityType {
  all('all'),
  department('department'),
  section('section'),
  employee('employee');

  const DocumentVisibilityType(this.code);
  final String code;

  static DocumentVisibilityType? fromCode(String? c) {
    if (c == null || c.isEmpty) return null;
    return DocumentVisibilityType.values.where((t) => t.code == c).firstOrNull;
  }
}

/// Документ заведения: название, тема, видимость, текст
class EstablishmentDocument extends Equatable {
  final String id;
  final String establishmentId;
  final String? createdBy;
  final String name;
  final String? topic;
  final DocumentVisibilityType visibilityType;
  final List<String> visibilityIds;
  final String? body;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EstablishmentDocument({
    required this.id,
    required this.establishmentId,
    this.createdBy,
    required this.name,
    this.topic,
    this.visibilityType = DocumentVisibilityType.all,
    this.visibilityIds = const [],
    this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EstablishmentDocument.fromJson(Map<String, dynamic> json) {
    final vtype = json['visibility_type'] as String?;
    final vids = json['visibility_ids'];
    List<String> ids = [];
    if (vids is List) {
      ids = vids.map((e) => e.toString()).toList();
    }
    return EstablishmentDocument(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String?,
      name: json['name'] as String? ?? '',
      topic: json['topic'] as String?,
      visibilityType: DocumentVisibilityType.fromCode(vtype) ?? DocumentVisibilityType.all,
      visibilityIds: ids,
      body: json['body'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'created_by': createdBy,
        'name': name,
        'topic': topic,
        'visibility_type': visibilityType.code,
        'visibility_ids': visibilityIds,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  EstablishmentDocument copyWith({
    String? id,
    String? establishmentId,
    String? createdBy,
    String? name,
    String? topic,
    DocumentVisibilityType? visibilityType,
    List<String>? visibilityIds,
    String? body,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      EstablishmentDocument(
        id: id ?? this.id,
        establishmentId: establishmentId ?? this.establishmentId,
        createdBy: createdBy ?? this.createdBy,
        name: name ?? this.name,
        topic: topic ?? this.topic,
        visibilityType: visibilityType ?? this.visibilityType,
        visibilityIds: visibilityIds ?? this.visibilityIds,
        body: body ?? this.body,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  List<Object?> get props => [id, establishmentId, name, topic, visibilityType, visibilityIds, body, createdAt, updatedAt];
}
