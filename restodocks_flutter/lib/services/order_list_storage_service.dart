import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_list.dart';

const _keyPrefix = 'restodocks_order_lists_';

Future<List<OrderList>> loadOrderLists(String establishmentId) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => OrderList.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveOrderLists(String establishmentId, List<OrderList> lists) async {
  final prefs = await SharedPreferences.getInstance();
  final key = '$_keyPrefix$establishmentId';
  final encoded = jsonEncode(lists.map((e) => e.toJson()).toList());
  await prefs.setString(key, encoded);
}
