import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import 'supabase_service.dart';

/// Сервис журналов ХАССП (Supabase). Маршрутизация в numeric/status/quality по log_type.
class HaccpLogServiceSupabase {
  static final HaccpLogServiceSupabase _instance = HaccpLogServiceSupabase._internal();
  factory HaccpLogServiceSupabase() => _instance;
  HaccpLogServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  String _tableName(HaccpLogTable t) {
    switch (t) {
      case HaccpLogTable.numeric:
        return 'haccp_numeric_logs';
      case HaccpLogTable.status:
        return 'haccp_status_logs';
      case HaccpLogTable.quality:
        return 'haccp_quality_logs';
    }
  }

  HaccpLog _parseRow(Map<String, dynamic> row, HaccpLogTable table) {
    switch (table) {
      case HaccpLogTable.numeric:
        return HaccpLog.fromNumericJson(row);
      case HaccpLogTable.status:
        return HaccpLog.fromStatusJson(row);
      case HaccpLogTable.quality:
        return HaccpLog.fromQualityJson(row);
    }
  }

  /// Загрузить записи журнала по establishment и типу.
  Future<List<HaccpLog>> getLogs({
    required String establishmentId,
    required HaccpLogType logType,
    DateTime? from,
    DateTime? to,
    int limit = 500,
  }) async {
    final table = _tableName(logType.targetTable);

    dynamic query = _supabase.client
        .from(table)
        .select('*')
        .eq('establishment_id', establishmentId)
        .eq('log_type', logType.code);

    if (from != null) {
      query = query.filter('created_at', 'gte', from.toIso8601String());
    }
    if (to != null) {
      final endOfDay = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      query = query.filter('created_at', 'lte', endOfDay.toIso8601String());
    }

    query = query.order('created_at', ascending: false).limit(limit);

    final data = await query;
    return (data as List)
        .map((e) => _parseRow(Map<String, dynamic>.from(e as Map), logType.targetTable))
        .toList();
  }

  /// Добавить запись (автоматический выбор таблицы по log_type).
  Future<HaccpLog> insertNumeric({
    required String establishmentId,
    required String createdByEmployeeId,
    required HaccpLogType logType,
    required double value1,
    double? value2,
    String? equipment,
    String? note,
  }) async {
    final row = await _supabase.client.from('haccp_numeric_logs').insert({
      'establishment_id': establishmentId,
      'created_by_employee_id': createdByEmployeeId,
      'log_type': logType.code,
      'value1': value1,
      'value2': value2,
      'equipment': equipment,
      'note': note,
    }).select().single();
    return HaccpLog.fromNumericJson(Map<String, dynamic>.from(row));
  }

  Future<HaccpLog> insertStatus({
    required String establishmentId,
    required String createdByEmployeeId,
    required HaccpLogType logType,
    required bool statusOk,
    bool? status2Ok,
    String? description,
    String? location,
    String? note,
  }) async {
    final row = await _supabase.client.from('haccp_status_logs').insert({
      'establishment_id': establishmentId,
      'created_by_employee_id': createdByEmployeeId,
      'log_type': logType.code,
      'status_ok': statusOk,
      'status2_ok': status2Ok,
      'description': description,
      'location': location,
      'note': note,
    }).select().single();
    return HaccpLog.fromStatusJson(Map<String, dynamic>.from(row));
  }

  Future<HaccpLog> insertQuality({
    required String establishmentId,
    required String createdByEmployeeId,
    required HaccpLogType logType,
    String? techCardId,
    String? productName,
    String? result,
    double? weight,
    String? reason,
    String? action,
    String? oilName,
    String? agent,
    String? concentration,
    String? timeBrakerage,
    String? approvalToSell,
    String? commissionSignatures,
    String? weighingResult,
    String? packaging,
    String? manufacturerSupplier,
    double? quantityKg,
    String? documentNumber,
    String? storageConditions,
    DateTime? expiryDate,
    DateTime? dateSold,
    String? organolepticStart,
    String? fryingEquipmentType,
    String? fryingProductType,
    String? fryingEndTime,
    String? organolepticEnd,
    double? carryOverKg,
    double? utilizedKg,
    String? medBookEmployeeName,
    String? medBookPosition,
    String? medBookNumber,
    DateTime? medBookValidUntil,
    DateTime? medBookIssuedAt,
    DateTime? medBookReturnedAt,
    String? medExamEmployeeName,
    String? medExamDob,
    String? medExamGender,
    String? medExamPosition,
    String? medExamDepartment,
    DateTime? medExamHireDate,
    String? medExamType,
    String? medExamInstitution,
    String? medExamHarmful1,
    String? medExamHarmful2,
    DateTime? medExamDate,
    String? medExamConclusion,
    String? medExamEmployerDecision,
    DateTime? medExamNextDate,
    DateTime? medExamExclusionDate,
    String? disinfObjectName,
    double? disinfObjectCount,
    double? disinfAreaSqm,
    String? disinfTreatmentType,
    int? disinfFrequencyPerMonth,
    String? disinfAgentName,
    String? disinfConcentrationPct,
    double? disinfConsumptionPerSqm,
    double? disinfSolutionPerTreatment,
    double? disinfNeedPerTreatment,
    double? disinfNeedPerMonth,
    double? disinfNeedPerYear,
    DateTime? disinfReceiptDate,
    String? disinfInvoiceNumber,
    double? disinfQuantity,
    DateTime? disinfExpiryDate,
    String? disinfResponsibleName,
    String? washTime,
    String? washEquipmentName,
    String? washSolutionName,
    String? washSolutionConcentrationPct,
    String? washDisinfectantName,
    String? washDisinfectantConcentrationPct,
    String? washRinsingTemp,
    String? washControllerSignature,
    String? genCleanPremises,
    DateTime? genCleanDate,
    String? genCleanResponsible,
    String? sieveNo,
    String? sieveNameLocation,
    String? sieveCondition,
    DateTime? sieveCleaningDate,
    String? sieveSignature,
    String? sieveComments,
    String? note,
  }) async {
    final map = <String, dynamic>{
      'establishment_id': establishmentId,
      'created_by_employee_id': createdByEmployeeId,
      'log_type': logType.code,
      'tech_card_id': techCardId?.isNotEmpty == true ? techCardId : null,
      'product_name': productName,
      'result': result,
      'weight': weight,
      'reason': reason,
      'action': action,
      'oil_name': oilName,
      'agent': agent,
      'concentration': concentration,
      'note': note,
    };
    if (timeBrakerage != null) map['time_brakerage'] = timeBrakerage;
    if (approvalToSell != null) map['approval_to_sell'] = approvalToSell;
    if (commissionSignatures != null) map['commission_signatures'] = commissionSignatures;
    if (weighingResult != null) map['weighing_result'] = weighingResult;
    if (packaging != null) map['packaging'] = packaging;
    if (manufacturerSupplier != null) map['manufacturer_supplier'] = manufacturerSupplier;
    if (quantityKg != null) map['quantity_kg'] = quantityKg;
    if (documentNumber != null) map['document_number'] = documentNumber;
    if (storageConditions != null) map['storage_conditions'] = storageConditions;
    if (expiryDate != null) map['expiry_date'] = expiryDate.toIso8601String();
    if (dateSold != null) map['date_sold'] = dateSold.toIso8601String();
    if (organolepticStart != null) map['organoleptic_start'] = organolepticStart;
    if (fryingEquipmentType != null) map['frying_equipment_type'] = fryingEquipmentType;
    if (fryingProductType != null) map['frying_product_type'] = fryingProductType;
    if (fryingEndTime != null) map['frying_end_time'] = fryingEndTime;
    if (organolepticEnd != null) map['organoleptic_end'] = organolepticEnd;
    if (carryOverKg != null) map['carry_over_kg'] = carryOverKg;
    if (utilizedKg != null) map['utilized_kg'] = utilizedKg;
    if (medBookEmployeeName != null) map['med_book_employee_name'] = medBookEmployeeName;
    if (medBookPosition != null) map['med_book_position'] = medBookPosition;
    if (medBookNumber != null) map['med_book_number'] = medBookNumber;
    if (medBookValidUntil != null) map['med_book_valid_until'] = medBookValidUntil.toIso8601String().split('T').first;
    if (medBookIssuedAt != null) map['med_book_issued_at'] = medBookIssuedAt.toIso8601String().split('T').first;
    if (medBookReturnedAt != null) map['med_book_returned_at'] = medBookReturnedAt.toIso8601String().split('T').first;
    if (medExamEmployeeName != null) map['med_exam_employee_name'] = medExamEmployeeName;
    if (medExamDob != null) map['med_exam_dob'] = medExamDob;
    if (medExamGender != null) map['med_exam_gender'] = medExamGender;
    if (medExamPosition != null) map['med_exam_position'] = medExamPosition;
    if (medExamDepartment != null) map['med_exam_department'] = medExamDepartment;
    if (medExamHireDate != null) map['med_exam_hire_date'] = medExamHireDate.toIso8601String().split('T').first;
    if (medExamType != null) map['med_exam_type'] = medExamType;
    if (medExamInstitution != null) map['med_exam_institution'] = medExamInstitution;
    if (medExamHarmful1 != null) map['med_exam_harmful_1'] = medExamHarmful1;
    if (medExamHarmful2 != null) map['med_exam_harmful_2'] = medExamHarmful2;
    if (medExamDate != null) map['med_exam_date'] = medExamDate.toIso8601String().split('T').first;
    if (medExamConclusion != null) map['med_exam_conclusion'] = medExamConclusion;
    if (medExamEmployerDecision != null) map['med_exam_employer_decision'] = medExamEmployerDecision;
    if (medExamNextDate != null) map['med_exam_next_date'] = medExamNextDate.toIso8601String().split('T').first;
    if (medExamExclusionDate != null) map['med_exam_exclusion_date'] = medExamExclusionDate.toIso8601String().split('T').first;
    if (disinfObjectName != null) map['disinf_object_name'] = disinfObjectName;
    if (disinfObjectCount != null) map['disinf_object_count'] = disinfObjectCount;
    if (disinfAreaSqm != null) map['disinf_area_sqm'] = disinfAreaSqm;
    if (disinfTreatmentType != null) map['disinf_treatment_type'] = disinfTreatmentType;
    if (disinfFrequencyPerMonth != null) map['disinf_frequency_per_month'] = disinfFrequencyPerMonth;
    if (disinfAgentName != null) map['disinf_agent_name'] = disinfAgentName;
    if (disinfConcentrationPct != null) map['disinf_concentration_pct'] = disinfConcentrationPct;
    if (disinfConsumptionPerSqm != null) map['disinf_consumption_per_sqm'] = disinfConsumptionPerSqm;
    if (disinfSolutionPerTreatment != null) map['disinf_solution_per_treatment'] = disinfSolutionPerTreatment;
    if (disinfNeedPerTreatment != null) map['disinf_need_per_treatment'] = disinfNeedPerTreatment;
    if (disinfNeedPerMonth != null) map['disinf_need_per_month'] = disinfNeedPerMonth;
    if (disinfNeedPerYear != null) map['disinf_need_per_year'] = disinfNeedPerYear;
    if (disinfReceiptDate != null) map['disinf_receipt_date'] = disinfReceiptDate.toIso8601String().split('T').first;
    if (disinfInvoiceNumber != null) map['disinf_invoice_number'] = disinfInvoiceNumber;
    if (disinfQuantity != null) map['disinf_quantity'] = disinfQuantity;
    if (disinfExpiryDate != null) map['disinf_expiry_date'] = disinfExpiryDate.toIso8601String().split('T').first;
    if (disinfResponsibleName != null) map['disinf_responsible_name'] = disinfResponsibleName;
    if (washTime != null) map['wash_time'] = washTime;
    if (washEquipmentName != null) map['wash_equipment_name'] = washEquipmentName;
    if (washSolutionName != null) map['wash_solution_name'] = washSolutionName;
    if (washSolutionConcentrationPct != null) map['wash_solution_concentration_pct'] = washSolutionConcentrationPct;
    if (washDisinfectantName != null) map['wash_disinfectant_name'] = washDisinfectantName;
    if (washDisinfectantConcentrationPct != null) map['wash_disinfectant_concentration_pct'] = washDisinfectantConcentrationPct;
    if (washRinsingTemp != null) map['wash_rinsing_temp'] = washRinsingTemp;
    if (washControllerSignature != null) map['wash_controller_signature'] = washControllerSignature;
    if (genCleanPremises != null) map['gen_clean_premises'] = genCleanPremises;
    if (genCleanDate != null) map['gen_clean_date'] = genCleanDate.toIso8601String().split('T').first;
    if (genCleanResponsible != null) map['gen_clean_responsible'] = genCleanResponsible;
    if (sieveNo != null) map['sieve_no'] = sieveNo;
    if (sieveNameLocation != null) map['sieve_name_location'] = sieveNameLocation;
    if (sieveCondition != null) map['sieve_condition'] = sieveCondition;
    if (sieveCleaningDate != null) map['sieve_cleaning_date'] = sieveCleaningDate.toIso8601String().split('T').first;
    if (sieveSignature != null) map['sieve_signature'] = sieveSignature;
    if (sieveComments != null) map['sieve_comments'] = sieveComments;
    final row = await _supabase.client.from('haccp_quality_logs').insert(map).select().single();
    return HaccpLog.fromQualityJson(Map<String, dynamic>.from(row));
  }

  /// Удалить запись.
  Future<void> delete(HaccpLog log) async {
    final table = _tableName(log.sourceTable);
    await _supabase.client.from(table).delete().eq('id', log.id);
  }
}
