import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_list.dart';
import 'supabase_service.dart';

const _keyPrefix = 'restodocks_order_lists_';
const _table = 'establishment_order_list_data';

/// Загружает списки поставщиков: приоритет Supabase, fallback SharedPreferences с миграцией.
Future<List<OrderList>> loadOrderLists(String establishmentId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';

  // 1. Пробуем Supabase
  try {
    final supabase = SupabaseService().client;
    final res = await supabase
        .from(_table)
        .select('data')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (res != null && res['data'] != null) {
      final listRaw = res['data'];
      if (listRaw is List && listRaw.isNotEmpty) {
        return listRaw
            .map((e) => OrderList.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (listRaw is List && listRaw.isEmpty) return [];
    }
  } catch (_) {}

  // 2. Fallback: SharedPreferences
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    final orderLists = list
        .map((e) => OrderList.fromJson(e as Map<String, dynamic>))
        .toList();
    unawaited(_migrateToSupabase(establishmentId, orderLists));
    return orderLists;
  } catch (_) {
    return [];
  }
}

/// Сохраняет списки поставщиков в Supabase; при ошибке — в SharedPreferences.
Future<void> saveOrderLists(String establishmentId, List<OrderList> lists) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final data = lists.map((e) => e.toJson()).toList();
  final encoded = jsonEncode(data);

  try {
    final supabase = SupabaseService().client;
    final existing = await supabase
        .from(_table)
        .select('id')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (existing != null) {
      await supabase
          .from(_table)
          .update({'data': data, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('establishment_id', establishmentId);
    } else {
      await supabase.from(_table).insert({
        'establishment_id': establishmentId,
        'data': data,
      });
    }
    await prefs.setString(key, encoded);
  } catch (_) {
    await prefs.setString(key, encoded);
  }
}

Future<void> _migrateToSupabase(String establishmentId, List<OrderList> lists) async {
  try {
    final data = lists.map((e) => e.toJson()).toList();
    await SupabaseService().client.from(_table).upsert(
      {
        'establishment_id': establishmentId,
        'data': data,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'establishment_id',
    );
  } catch (_) {}
}
