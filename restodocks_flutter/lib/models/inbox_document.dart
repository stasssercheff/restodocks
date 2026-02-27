import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../services/localization_service.dart';

part 'inbox_document.g.dart';

/// Типы документов во входящих
enum DocumentType {
  inventory,
  productOrder,
  shiftConfirmation,
  checklistSubmission,
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
      case DocumentType.checklistSubmission:
        return Icons.checklist;
    }
  }

  /// Локализованный заголовок документа (title)
  String getLocalizedTitle(LocalizationService loc) {
    switch (type) {
      case DocumentType.inventory:
        final date = metadata?['header']?['date']?.toString() ?? '';
        return loc.t('inbox_title_inventory').replaceFirst('%s', date);
      case DocumentType.productOrder:
        final supplier = metadata?['header']?['supplierName']?.toString() ?? '—';
        return loc.t('inbox_title_order').replaceFirst('%s', supplier);
      case DocumentType.checklistSubmission:
        // title хранится как "Чеклист: <name>" — извлекаем имя
        final colonIdx = title.indexOf(': ');
        final name = colonIdx >= 0 ? title.substring(colonIdx + 2) : title;
        return loc.t('inbox_title_checklist').replaceFirst('%s', name);
      case DocumentType.shiftConfirmation:
        return loc.t('doc_type_shift_confirmation');
    }
  }

  /// Получить локализованное название типа документа
  String getTypeName(LocalizationService loc) {
    switch (type) {
      case DocumentType.inventory:
        return loc.t('doc_type_inventory');
      case DocumentType.productOrder:
        return loc.t('doc_type_product_order');
      case DocumentType.shiftConfirmation:
        return loc.t('doc_type_shift_confirmation');
      case DocumentType.checklistSubmission:
        return loc.t('doc_type_checklist');
    }
  }

  /// Получить локализованное название отдела
  String getDepartmentName(LocalizationService loc) {
    switch (department) {
      case 'kitchen':
        return loc.t('dept_kitchen');
      case 'bar':
        return loc.t('dept_bar');
      case 'hall':
        return loc.t('dept_hall');
      case 'management':
        return loc.t('dept_management');
      default:
        return department;
    }
  }

}