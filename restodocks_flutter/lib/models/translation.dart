import 'package:equatable/equatable.dart';

/// Типы сущностей для перевода
enum TranslationEntityType {
  product,
  techCard,
  checklist,
  ui,
}

/// Модель для хранения переводов
class Translation extends Equatable {
  final String id;
  final TranslationEntityType entityType;
  final String entityId;
  final String fieldName; // название поля (name, description, etc.)
  final String sourceText;
  final String sourceLanguage;
  final String targetLanguage;
  final String translatedText;
  final DateTime createdAt;
  final String? createdBy;
  final bool isManualOverride; // true если перевод был изменен вручную

  const Translation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fieldName,
    required this.sourceText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.translatedText,
    required this.createdAt,
    this.createdBy,
    this.isManualOverride = false,
  });

  /// Создать новый перевод
  factory Translation.create({
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
    required String translatedText,
    String? createdBy,
  }) {
    return Translation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sourceText: sourceText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      translatedText: translatedText,
      createdAt: DateTime.now(),
      createdBy: createdBy,
    );
  }

  /// Ключ для кеширования (entity + field + languages)
  String get cacheKey => '${entityType}_${entityId}_${fieldName}_${sourceLanguage}_${targetLanguage}';

  @override
  List<Object?> get props => [
    id,
    entityType,
    entityId,
    fieldName,
    sourceText,
    sourceLanguage,
    targetLanguage,
    translatedText,
    createdAt,
    createdBy,
    isManualOverride,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'entity_type': entityType.name,
    'entity_id': entityId,
    'field_name': fieldName,
    'source_text': sourceText,
    'source_language': sourceLanguage,
    'target_language': targetLanguage,
    'translated_text': translatedText,
    'created_at': createdAt.toIso8601String(),
    'created_by': createdBy,
    'is_manual_override': isManualOverride,
  };

  factory Translation.fromJson(Map<String, dynamic> json) => Translation(
    id: json['id'],
    entityType: TranslationEntityType.values.firstWhere(
      (e) => e.name == json['entity_type'],
      orElse: () => TranslationEntityType.product,
    ),
    entityId: json['entity_id'],
    fieldName: json['field_name'],
    sourceText: json['source_text'],
    sourceLanguage: json['source_language'],
    targetLanguage: json['target_language'],
    translatedText: json['translated_text'],
    createdAt: DateTime.parse(json['created_at']),
    createdBy: json['created_by'],
    isManualOverride: json['is_manual_override'] ?? false,
  );
}