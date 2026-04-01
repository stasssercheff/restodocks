import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Планы продаж POS в Supabase (`pos_sales_plans`), общие для web и приложения.
/// Однократный перенос из старых локальных prefs при пустой таблице.
class SalesPlanStorageService {
  SalesPlanStorageService._();
  static final SalesPlanStorageService instance = SalesPlanStorageService._();

  static const _uuid = Uuid();
  static const _legacyKeyPrefix = 'restodocks_sales_plans_';

  final SupabaseService _supabase = SupabaseService();

  String newId() => _uuid.v4();

  Future<List<SalesPlan>> loadAll(String establishmentId) async {
    if (establishmentId.isEmpty) return [];
    try {
      var list = await _fetchFromServer(establishmentId);
      if (list.isEmpty) {
        await _migrateLegacySharedPreferencesOnce(establishmentId);
        list = await _fetchFromServer(establishmentId);
      }
      return list;
    } catch (e, st) {
      devLog('SalesPlanStorageService: loadAll $e $st');
      return [];
    }
  }

  Future<List<SalesPlan>> _fetchFromServer(String establishmentId) async {
    final rows = await _supabase.client
        .from('pos_sales_plans')
        .select()
        .eq('establishment_id', establishmentId)
        .order('updated_at', ascending: false);
    final out = <SalesPlan>[];
    for (final row in rows as List<dynamic>) {
      if (row is! Map<String, dynamic>) continue;
      try {
        out.add(SalesPlan.fromJson(Map<String, dynamic>.from(row)));
      } catch (e) {
        devLog('SalesPlanStorageService: skip row $e');
      }
    }
    return out;
  }

  Future<void> _migrateLegacySharedPreferencesOnce(String establishmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_legacyKeyPrefix$establishmentId');
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final e in decoded) {
        if (e is! Map) continue;
        final plan = SalesPlan.fromJson(Map<String, dynamic>.from(e));
        await upsert(establishmentId, plan);
      }
      await prefs.remove('$_legacyKeyPrefix$establishmentId');
    } catch (e, st) {
      devLog('SalesPlanStorageService: legacy migrate $e $st');
    }
  }

  Future<SalesPlan?> getById(String establishmentId, String id) async {
    if (establishmentId.isEmpty || id.isEmpty) return null;
    try {
      final row = await _supabase.client
          .from('pos_sales_plans')
          .select()
          .eq('establishment_id', establishmentId)
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return SalesPlan.fromJson(Map<String, dynamic>.from(row));
    } catch (e, st) {
      devLog('SalesPlanStorageService: getById $e $st');
      return null;
    }
  }

  /// [createdByEmployeeId] сохраняется только при первой вставке строки.
  Future<void> upsert(
    String establishmentId,
    SalesPlan plan, {
    String? createdByEmployeeId,
  }) async {
    if (establishmentId.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final base = <String, dynamic>{
      'establishment_id': establishmentId,
      'department': plan.department,
      'period_kind': plan.periodKind.name,
      'period_start': plan.periodStart.toUtc().toIso8601String(),
      'period_end': plan.periodEnd.toUtc().toIso8601String(),
      'target_cash_amount': plan.targetCashAmount,
      'lines': plan.lines.map((e) => e.toJson()).toList(),
      'updated_at': now,
    };
    try {
      final existing = await _supabase.client
          .from('pos_sales_plans')
          .select('id')
          .eq('id', plan.id)
          .eq('establishment_id', establishmentId)
          .maybeSingle();
      if (existing == null) {
        await _supabase.client.from('pos_sales_plans').insert({
          ...base,
          'id': plan.id,
          'created_at': plan.createdAt.toUtc().toIso8601String(),
          if (createdByEmployeeId != null && createdByEmployeeId.isNotEmpty)
            'created_by': createdByEmployeeId,
        });
      } else {
        await _supabase.client.from('pos_sales_plans').update(base).eq('id', plan.id);
      }
    } catch (e, st) {
      devLog('SalesPlanStorageService: upsert $e $st');
      rethrow;
    }
  }

  Future<void> delete(String establishmentId, String id) async {
    if (establishmentId.isEmpty) return;
    try {
      await _supabase.client
          .from('pos_sales_plans')
          .delete()
          .eq('establishment_id', establishmentId)
          .eq('id', id);
    } catch (e, st) {
      devLog('SalesPlanStorageService: delete $e $st');
      rethrow;
    }
  }

  Future<SalesPlan?> activePlanForDay({
    required String establishmentId,
    required String department,
    required DateTime dayLocal,
  }) async {
    final all = await loadAll(establishmentId);
    final candidates = all.where((p) {
      if (p.department != department) return false;
      final d = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
      final ps = p.periodStart.toLocal();
      final pe = p.periodEnd.toLocal();
      final ds = DateTime(ps.year, ps.month, ps.day);
      final de = DateTime(pe.year, pe.month, pe.day);
      return !d.isBefore(ds) && !d.isAfter(de);
    }).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final ua = a.updatedAt ?? a.createdAt;
      final ub = b.updatedAt ?? b.createdAt;
      return ub.compareTo(ua);
    });
    return candidates.first;
  }
}
