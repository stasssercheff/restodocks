import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'inbox_document.g.dart';

/// Типы документов во входящих
enum DocumentType {
  inventory,
  productOrder,
  shiftConfirmation,
}

/// Модель документа во входящих
@JsonSerializable()
class InboxDocument extends Equatable {
  final String id;
  final DocumentType type;
  final String title;
  final String description;
  final DateTime createdAt;
  final String employeeId;
  final String employeeName;
  final String department; // kitchen, bar, hall, management
  final String? fileUrl; // URL для скачивания файла
  final Map<String, dynamic>? metadata; // дополнительные данные

  const InboxDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.employeeId,
    required this.employeeName,
    required this.department,
    this.fileUrl,
    this.metadata,
  });

  factory InboxDocument.fromJson(Map<String, dynamic> json) =>
      _$InboxDocumentFromJson(json);

  Map<String, dynamic> toJson() => _$InboxDocumentToJson(this);

  @override
  List<Object?> get props => [
        id,
        type,
        title,
        createdAt,
        employeeId,
        department,
      ];

  /// Получить иконку для типа документа
  IconData get icon {
    switch (type) {
      case DocumentType.inventory:
        return Icons.assignment;
      case DocumentType.productOrder:
        return Icons.shopping_cart;
      case DocumentType.shiftConfirmation:
        return Icons.how_to_reg;
    }
  }

  /// Получить цвет для типа документа
  String get typeName {
    switch (type) {
      case DocumentType.inventory:
        return 'Инвентаризация';
      case DocumentType.productOrder:
        return 'Заказ продуктов';
      case DocumentType.shiftConfirmation:
        return 'Подтверждение смены';
    }
  }

  /// Получить название отдела
  String get departmentName {
    switch (department) {
      case 'kitchen':
        return 'Кухня';
      case 'bar':
        return 'Бар';
      case 'hall':
        return 'Зал';
      case 'management':
        return 'Управление';
      default:
        return department;
    }
  }
}