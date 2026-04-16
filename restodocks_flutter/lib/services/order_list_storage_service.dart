import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_list.dart';
import 'supabase_service.dart';

const _keyPrefix = 'restodocks_order_lists_';
const _table = 'establishment_order_list_data';

/// Подразделения (kitchen, bar, hall)
const _departments = ['kitchen', 'bar', 'hall'];

String _normalizeDepartment(String? department) {
  final d = (department ?? '').trim().toLowerCase();
  if (d == 'kitchen' || d == 'bar' || d == 'hall') return d;
  // Legacy aliases used in older builds.
  if (d == 'dining_room') return 'hall';
  if (d == 'management') return 'kitchen';
  return 'kitchen';
}

/// Парсит сырые данные в List<OrderList>. Старый формат (массив без department) → kitchen.
List<OrderList> _parseList(dynamic data) {
  if (data == null || data is! List) return [];
  return data
      .map((e) => OrderList.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Загружает списки для подразделения. [department] = kitchen|bar|hall, default kitchen.
Future<List<OrderList>> loadOrderLists(String establishmentId, {String department = 'kitchen'}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';

  List<OrderList> all = [];
  try {
    final supabase = SupabaseService().client;
    final res = await supabase
        .from(_table)
        .select('data')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (res != null && res['data'] != null) {
      all = _parseList(res['data']);
    }
  } catch (_) {}

  if (all.isEmpty) {
    final raw = prefs.getString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        all = _parseList(jsonDecode(raw));
      } catch (_) {}
    }
  }

  final dept = _normalizeDepartment(department);
  return all
      .where((l) => _normalizeDepartment(l.department) == dept)
      .toList();
}

/// Загружает все списки (все подразделения) для merge при сохранении.
Future<List<OrderList>> _loadAllOrderLists(String establishmentId) async {
  try {
    final supabase = SupabaseService().client;
    final res = await supabase
        .from(_table)
        .select('data')
        .eq('establishment_id', establishmentId)
        .maybeSingle();
    if (res != null && res['data'] != null) return _parseList(res['data']);
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('$_keyPrefix$establishmentId');
  if (raw != null && raw.isNotEmpty) {
    try {
      return _parseList(jsonDecode(raw));
    } catch (_) {}
  }
  return [];
}

/// Сохраняет списки для подразделения. Объединяет с данными других подразделений.
Future<void> saveOrderLists(String establishmentId, List<OrderList> lists, {String department = 'kitchen'}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final dept = _normalizeDepartment(department);
  final listsWithDept = lists.map((l) => l.department == dept ? l : l.copyWith(department: dept)).toList();

  final all = await _loadAllOrderLists(establishmentId);
  final others = all
      .where((l) => _normalizeDepartment(l.department) != dept)
      .toList();
  final merged = [...others, ...listsWithDept];
  final data = merged.map((e) => e.toJson()).toList();
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

/// Добавить продукт в карточку поставщика (шаблон заказа), без дубликатов по [productId].
Future<void> appendProductToSupplierOrderList({
  required String establishmentId,
  required String department,
  required String supplierListId,
  required String productId,
  required String productName,
  String unit = 'g',
}) async {
  if (productId.trim().isEmpty) return;
  final lists = await loadOrderLists(establishmentId, department: department);
  final idx = lists.indexWhere((l) => l.id == supplierListId);
  if (idx < 0) return;
  final list = lists[idx];
  if (list.items.any((i) => i.productId == productId)) return;
  final newItem = OrderListItem(
    productId: productId,
    productName: productName,
    unit: unit,
    quantity: 0,
  );
  lists[idx] = list.copyWith(items: [...list.items, newItem]);
  await saveOrderLists(establishmentId, lists, department: department);
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
