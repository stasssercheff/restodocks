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
    String? note,
  }) async {
    final row = await _supabase.client.from('haccp_quality_logs').insert({
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
    }).select().single();
    return HaccpLog.fromQualityJson(Map<String, dynamic>.from(row));
  }

  /// Удалить запись.
  Future<void> delete(HaccpLog log) async {
    final table = _tableName(log.sourceTable);
    await _supabase.client.from(table).delete().eq('id', log.id);
  }
}
