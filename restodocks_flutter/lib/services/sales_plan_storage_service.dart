import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

/// Локальное хранение планов продаж (как на экране — на устройстве).
class SalesPlanStorageService {
  SalesPlanStorageService._();
  static final SalesPlanStorageService instance = SalesPlanStorageService._();

  static const _uuid = Uuid();

  String _key(String establishmentId) =>
      'restodocks_sales_plans_$establishmentId';

  Future<List<SalesPlan>> loadAll(String establishmentId) async {
    if (establishmentId.isEmpty) return [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(establishmentId));
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SalesPlan.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(String establishmentId, List<SalesPlan> plans) async {
    if (establishmentId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(plans.map((e) => e.toJson()).toList());
      await prefs.setString(_key(establishmentId), raw);
    } catch (_) {}
  }

  Future<SalesPlan?> getById(String establishmentId, String id) async {
    final all = await loadAll(establishmentId);
    try {
      return all.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> upsert(String establishmentId, SalesPlan plan) async {
    final all = await loadAll(establishmentId);
    final i = all.indexWhere((p) => p.id == plan.id);
    if (i >= 0) {
      all[i] = plan;
    } else {
      all.add(plan);
    }
    await saveAll(establishmentId, all);
  }

  Future<void> delete(String establishmentId, String id) async {
    final all = await loadAll(establishmentId);
    all.removeWhere((p) => p.id == id);
    await saveAll(establishmentId, all);
  }

  String newId() => _uuid.v4();

  /// План, действующий на дату (последний по созданию, чей период покрывает день).
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
    candidates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return candidates.first;
  }
}
