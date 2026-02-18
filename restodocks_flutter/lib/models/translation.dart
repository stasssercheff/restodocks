import 'package:equatable/equatable.dart';

/// Модель для хранения переводов
class Translation extends Equatable {
  final String id;
  final String sourceText;
  final String sourceLanguage;
  final String targetLanguage;
  final String translatedText;
  final DateTime createdAt;
  final String? createdBy;

  const Translation({
    required this.id,
    required this.sourceText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.translatedText,
    required this.createdAt,
    this.createdBy,
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

  /// Ключ для кеширования (sourceText + languages)
  String get cacheKey => '${sourceText}_${sourceLanguage}_${targetLanguage}';

  @override
  List<Object?> get props => [
    id,
    sourceText,
    sourceLanguage,
    targetLanguage,
    translatedText,
    createdAt,
    createdBy,
  ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_text': sourceText,
    'source_language': sourceLanguage,
    'target_language': targetLanguage,
    'translated_text': translatedText,
    'created_at': createdAt.toIso8601String(),
    'created_by': createdBy,
  };

  factory Translation.fromJson(Map<String, dynamic> json) => Translation(
    id: json['id'],
    sourceText: json['source_text'],
    sourceLanguage: json['source_language'],
    targetLanguage: json['target_language'],
    translatedText: json['translated_text'],
    createdAt: DateTime.parse(json['created_at']),
    createdBy: json['created_by'],
  );
}