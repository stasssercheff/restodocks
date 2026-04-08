// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InboxDocument _$InboxDocumentFromJson(Map<String, dynamic> json) =>
    InboxDocument(
      id: json['id'] as String,
      type: $enumDecode(_$DocumentTypeEnumMap, json['type']),
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      employeeId: json['employeeId'] as String,
      employeeName: json['employeeName'] as String,
      department: json['department'] as String,
      fileUrl: json['fileUrl'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$InboxDocumentToJson(InboxDocument instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$DocumentTypeEnumMap[instance.type]!,
      'title': instance.title,
      'description': instance.description,
      'createdAt': instance.createdAt.toIso8601String(),
      'employeeId': instance.employeeId,
      'employeeName': instance.employeeName,
      'department': instance.department,
      'fileUrl': instance.fileUrl,
      'metadata': instance.metadata,
    };

const _$DocumentTypeEnumMap = {
  DocumentType.inventory: 'inventory',
  DocumentType.iikoInventory: 'iikoInventory',
  DocumentType.productOrder: 'productOrder',
  DocumentType.shiftConfirmation: 'shiftConfirmation',
  DocumentType.checklistSubmission: 'checklistSubmission',
  DocumentType.checklistMissedDeadline: 'checklistMissedDeadline',
  DocumentType.writeoff: 'writeoff',
  DocumentType.techCardChangeRequest: 'techCardChangeRequest',
  DocumentType.procurementPriceApproval: 'procurementPriceApproval',
};
