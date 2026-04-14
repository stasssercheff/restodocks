import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import '../services/localization_service.dart';

part 'inbox_document.g.dart';

/// Типы документов во входящих
enum DocumentType {
  inventory,
  iikoInventory,
  productOrder,
  shiftConfirmation,
  checklistSubmission,
  /// Чеклист с пропущенным сроком выполнения (не выполнен к дедлайну).
  checklistMissedDeadline,
  /// Списание (персонал, проработка, порча, брекераж, отказ гостя)
  writeoff,
  /// Изменение ТТК на согласовании у владельца
  techCardChangeRequest,
  /// Согласование изменения цен в номенклатуре (приёмка уже сохранена; не-шеф → шефу во входящие).
  procurementPriceApproval,
  /// Документ приёмки товара (procurement_receipt_documents), отдельно от заказов.
  procurementGoodsReceipt,
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
      case DocumentType.iikoInventory:
        return Icons.table_chart_outlined;
      case DocumentType.productOrder:
        return Icons.shopping_cart;
      case DocumentType.shiftConfirmation:
        return Icons.how_to_reg;
      case DocumentType.checklistSubmission:
        return Icons.checklist;
      case DocumentType.checklistMissedDeadline:
        return Icons.warning_amber;
      case DocumentType.writeoff:
        return Icons.remove_circle_outline;
      case DocumentType.techCardChangeRequest:
        return Icons.restaurant_menu;
      case DocumentType.procurementPriceApproval:
        return Icons.price_change_outlined;
      case DocumentType.procurementGoodsReceipt:
        return Icons.inventory_2_outlined;
    }
  }

  /// Локализованный заголовок документа (title)
  String getLocalizedTitle(LocalizationService loc) {
    switch (type) {
      case DocumentType.inventory:
        final date = metadata?['header']?['date']?.toString() ?? '';
        if (metadata?['type']?.toString() == 'selective_inventory') {
          return (loc.t('inventory_selective_inbox_title') ??
                  'Выборочная инвентаризация %s')
              .replaceFirst('%s', date);
        }
        return loc.t('inbox_title_inventory').replaceFirst('%s', date);
      case DocumentType.iikoInventory:
        final date = metadata?['header']?['date']?.toString() ?? '';
        return '${loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko'} $date';
      case DocumentType.productOrder:
        final supplier = metadata?['header']?['supplierName']?.toString() ?? '—';
        return loc.t('inbox_title_order').replaceFirst('%s', supplier);
      case DocumentType.procurementGoodsReceipt:
        final supplier = metadata?['header']?['supplierName']?.toString() ?? '—';
        return loc.t('inbox_title_procurement_receipt').replaceFirst('%s', supplier);
      case DocumentType.checklistSubmission:
        final colonIdx = title.indexOf(': ');
        final name = colonIdx >= 0 ? title.substring(colonIdx + 2) : title;
        return loc.t('inbox_title_checklist').replaceFirst('%s', name);
      case DocumentType.shiftConfirmation:
        return loc.t('doc_type_shift_confirmation');
      case DocumentType.checklistMissedDeadline:
        return title;
      case DocumentType.writeoff:
        final date = metadata?['header']?['date']?.toString() ?? '';
        final cat = metadata?['category']?.toString() ?? '';
        final catName = switch (cat) {
          'staff' => loc.t('writeoff_category_staff') ?? 'Персонал',
          'workingThrough' => loc.t('writeoff_category_working') ?? 'Проработка',
          'spoilage' => loc.t('writeoff_category_spoilage') ?? 'Порча',
          'breakage' => loc.t('writeoff_category_breakage') ?? 'Брекераж',
          'guestRefusal' => loc.t('writeoff_category_guest_refusal') ?? 'Отказ гостя',
          'generic' => loc.t('writeoff_category_simple') ?? 'Списание',
          _ => cat,
        };
        return '${loc.t('writeoffs') ?? 'Списания'} ($catName) $date';
      case DocumentType.techCardChangeRequest:
        return title;
      case DocumentType.procurementPriceApproval:
        final supplier =
            metadata?['receiptSupplier']?.toString() ?? '—';
        return (loc.t('inbox_title_procurement_price_approval') ??
                'Согласование цен: %s')
            .replaceFirst('%s', supplier);
    }
  }

  /// Получить локализованное название типа документа
  String getTypeName(LocalizationService loc) {
    switch (type) {
      case DocumentType.inventory:
        if (metadata?['type']?.toString() == 'selective_inventory') {
          return loc.t('inventory_selective_type_name') ??
              'Выборочная инвентаризация';
        }
        return loc.t('doc_type_inventory');
      case DocumentType.iikoInventory:
        return loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko';
      case DocumentType.productOrder:
        return loc.t('doc_type_product_order');
      case DocumentType.shiftConfirmation:
        return loc.t('doc_type_shift_confirmation');
      case DocumentType.checklistSubmission:
        return loc.t('doc_type_checklist');
      case DocumentType.checklistMissedDeadline:
        return loc.t('inbox_msg_checklist_not_done') ?? 'Чеклист не выполнен';
      case DocumentType.writeoff:
        return loc.t('writeoffs') ?? 'Списания';
      case DocumentType.techCardChangeRequest:
        return loc.t('doc_type_ttk_change');
      case DocumentType.procurementPriceApproval:
        return loc.t('doc_type_procurement_price_approval') ??
            'Согласование цен';
      case DocumentType.procurementGoodsReceipt:
        return loc.t('doc_type_procurement_goods_receipt') ??
            'Приёмка товара';
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

  InboxDocument copyWith({
    String? title,
    String? description,
    String? employeeName,
  }) {
    return InboxDocument(
      id: id,
      type: type,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt,
      employeeId: employeeId,
      employeeName: employeeName ?? this.employeeName,
      department: department,
      fileUrl: fileUrl,
      metadata: metadata,
    );
  }
}