import 'dart:convert';

import 'haccp_log_type.dart';

/// Запись журнала ХАССП (унифицированная обёртка для numeric/status/quality).
class HaccpLog {
  final String id;
  final String establishmentId;
  final String createdByEmployeeId;
  final HaccpLogType logType;
  final HaccpLogTable sourceTable;
  final DateTime createdAt;

  // numeric
  final double? value1;
  final double? value2;
  final String? equipment;

  // status
  final bool? statusOk;
  final bool? status2Ok;
  final String? description;
  final String? location;

  // quality
  final String? techCardId;
  final String? productName;
  final String? result;
  final double? weight;
  final String? reason;
  final String? action;
  final String? oilName;
  final String? agent;
  final String? concentration;
  // Приложение 4: бракераж готовой продукции
  final String? timeBrakerage;
  final String? approvalToSell;
  final String? commissionSignatures;
  final String? weighingResult;
  // Приложение 5: бракераж скоропортящейся
  final String? packaging;
  final String? manufacturerSupplier;
  final double? quantityKg;
  final String? documentNumber;
  final String? storageConditions;
  final DateTime? expiryDate;
  final DateTime? dateSold;
  // Учёт фритюрных жиров (Приложение 8)
  final String? organolepticStart;
  final String? fryingEquipmentType;
  final String? fryingProductType;
  final String? fryingEndTime;
  final String? organolepticEnd;
  final double? carryOverKg;
  final double? utilizedKg;

  final String? note;

  const HaccpLog({
    required this.id,
    required this.establishmentId,
    required this.createdByEmployeeId,
    required this.logType,
    required this.sourceTable,
    required this.createdAt,
    this.value1,
    this.value2,
    this.equipment,
    this.statusOk,
    this.status2Ok,
    this.description,
    this.location,
    this.techCardId,
    this.productName,
    this.result,
    this.weight,
    this.reason,
    this.action,
    this.oilName,
    this.agent,
    this.concentration,
    this.timeBrakerage,
    this.approvalToSell,
    this.commissionSignatures,
    this.weighingResult,
    this.packaging,
    this.manufacturerSupplier,
    this.quantityKg,
    this.documentNumber,
    this.storageConditions,
    this.expiryDate,
    this.dateSold,
    this.organolepticStart,
    this.fryingEquipmentType,
    this.fryingProductType,
    this.fryingEndTime,
    this.organolepticEnd,
    this.carryOverKg,
    this.utilizedKg,
    this.note,
  });

  /// Сводка для списка и PDF.
  Map<String, String> toPdfRow() {
    final m = <String, String>{};
    if (value1 != null) m['value1'] = value1!.toStringAsFixed(1);
    if (value2 != null) m['value2'] = value2!.toStringAsFixed(1);
    if (equipment != null && equipment!.isNotEmpty) m['equipment'] = equipment!;
    if (statusOk != null) m['status'] = statusOk! ? 'Да' : 'Нет';
    if (status2Ok != null) m['status2'] = status2Ok! ? 'Да' : 'Нет';
    if (description != null && description!.isNotEmpty) m['description'] = description!;
    if (location != null && location!.isNotEmpty) m['location'] = location!;
    if (productName != null && productName!.isNotEmpty) m['product'] = productName!;
    if (result != null && result!.isNotEmpty) m['result'] = result!;
    if (weight != null) m['weight'] = weight!.toString();
    if (reason != null && reason!.isNotEmpty) m['reason'] = reason!;
    if (action != null && action!.isNotEmpty) m['action'] = action!;
    if (oilName != null && oilName!.isNotEmpty) m['oil_name'] = oilName!;
    if (agent != null && agent!.isNotEmpty) m['agent'] = agent!;
    if (concentration != null && concentration!.isNotEmpty) m['concentration'] = concentration!;
    if (note != null && note!.isNotEmpty) m['note'] = note!;
    return m;
  }

  String summaryLine() {
    final parts = <String>[];
    if (value1 != null) parts.add('${value1!.toStringAsFixed(1)}');
    if (value2 != null) parts.add('${value2!.toStringAsFixed(1)}');
    if (statusOk != null) parts.add(statusOk! ? 'Ок' : '—');
    if (productName != null && productName!.isNotEmpty) parts.add(productName!);
    if (result != null && result!.isNotEmpty) parts.add(result!);
    if (description != null && description!.isNotEmpty) parts.add(description!);
    return parts.take(3).join(' · ');
  }

  factory HaccpLog.fromNumericJson(Map<String, dynamic> json) {
    final logTypeStr = json['log_type']?.toString();
    final type = HaccpLogType.fromCode(logTypeStr) ?? HaccpLogType.healthHygiene;
    return HaccpLog(
      id: json['id']?.toString() ?? '',
      establishmentId: json['establishment_id']?.toString() ?? '',
      createdByEmployeeId: json['created_by_employee_id']?.toString() ?? '',
      logType: type,
      sourceTable: HaccpLogTable.numeric,
      createdAt: _parseDateTime(json['created_at']),
      value1: _parseNum(json['value1']),
      value2: _parseNum(json['value2']),
      equipment: json['equipment']?.toString(),
      note: json['note']?.toString(),
    );
  }

  factory HaccpLog.fromStatusJson(Map<String, dynamic> json) {
    final logTypeStr = json['log_type']?.toString();
    final type = HaccpLogType.fromCode(logTypeStr) ?? HaccpLogType.healthHygiene;
    return HaccpLog(
      id: json['id']?.toString() ?? '',
      establishmentId: json['establishment_id']?.toString() ?? '',
      createdByEmployeeId: json['created_by_employee_id']?.toString() ?? '',
      logType: type,
      sourceTable: HaccpLogTable.status,
      createdAt: _parseDateTime(json['created_at']),
      statusOk: json['status_ok'] as bool?,
      status2Ok: json['status2_ok'] as bool?,
      description: json['description']?.toString(),
      location: json['location']?.toString(),
      note: json['note']?.toString(),
    );
  }

  factory HaccpLog.fromQualityJson(Map<String, dynamic> json) {
    final logTypeStr = json['log_type']?.toString();
    final type = HaccpLogType.fromCode(logTypeStr) ?? HaccpLogType.healthHygiene;
    return HaccpLog(
      id: json['id']?.toString() ?? '',
      establishmentId: json['establishment_id']?.toString() ?? '',
      createdByEmployeeId: json['created_by_employee_id']?.toString() ?? '',
      logType: type,
      sourceTable: HaccpLogTable.quality,
      createdAt: _parseDateTime(json['created_at']),
      techCardId: json['tech_card_id']?.toString(),
      productName: json['product_name']?.toString(),
      result: json['result']?.toString(),
      weight: _parseNum(json['weight']),
      reason: json['reason']?.toString(),
      action: json['action']?.toString(),
      oilName: json['oil_name']?.toString(),
      agent: json['agent']?.toString(),
      concentration: json['concentration']?.toString(),
      timeBrakerage: json['time_brakerage']?.toString(),
      approvalToSell: json['approval_to_sell']?.toString(),
      commissionSignatures: json['commission_signatures']?.toString(),
      weighingResult: json['weighing_result']?.toString(),
      packaging: json['packaging']?.toString(),
      manufacturerSupplier: json['manufacturer_supplier']?.toString(),
      quantityKg: _parseNum(json['quantity_kg']),
      documentNumber: json['document_number']?.toString(),
      storageConditions: json['storage_conditions']?.toString(),
      expiryDate: _parseDateTime(json['expiry_date']),
      dateSold: _parseDateTime(json['date_sold']),
      organolepticStart: json['organoleptic_start']?.toString(),
      fryingEquipmentType: json['frying_equipment_type']?.toString(),
      fryingProductType: json['frying_product_type']?.toString(),
      fryingEndTime: json['frying_end_time']?.toString(),
      organolepticEnd: json['organoleptic_end']?.toString(),
      carryOverKg: _parseNum(json['carry_over_kg']),
      utilizedKg: _parseNum(json['utilized_kg']),
      note: json['note']?.toString(),
    );
  }

  static DateTime _parseDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    final d = DateTime.tryParse(s);
    return d ?? DateTime.now();
  }

  static double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Для гигиенического журнала: парсим description как JSON {employee_id?, position?}.
  static ({String? subjectEmployeeId, String? positionOverride}) parseHealthHygieneDescription(String? description) {
    if (description == null || description.trim().isEmpty) return (subjectEmployeeId: null, positionOverride: null);
    try {
      final map = jsonDecode(description) as Map<String, dynamic>?;
      if (map == null) return (subjectEmployeeId: null, positionOverride: null);
      final eid = map['employee_id']?.toString();
      final pos = map['position']?.toString();
      return (
        subjectEmployeeId: eid?.isNotEmpty == true ? eid : null,
        positionOverride: pos?.isNotEmpty == true ? pos : null,
      );
    } catch (_) {
      return (subjectEmployeeId: null, positionOverride: null);
    }
  }

  /// Собрать description для сохранения записи гигиенического журнала.
  static String buildHealthHygieneDescription({required String employeeId, String? positionOverride}) {
    final map = <String, dynamic>{'employee_id': employeeId};
    if (positionOverride != null && positionOverride.trim().isNotEmpty) {
      map['position'] = positionOverride.trim();
    }
    return jsonEncode(map);
  }
}
