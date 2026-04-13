import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyPrefix = 'restodocks_home_layout_';
const _hiddenKeyPrefix = 'restodocks_home_hidden_';
const _ownerLiteOrderPrefix = 'restodocks_owner_lite_home_order_';

/// Идентификаторы плиток на домашнем экране (для сотрудника)
enum HomeTileId {
  messages,
  schedule,
  documentation,
  productOrder,
  suppliers,
  menu,
  ttk,
  banquetMenu,
  banquetTtk,
  checklists,
  nomenclature,
  inventory,
  writeoffs,
  hallOrders,
  hallCashRegister,
  hallTables,
  departmentOrders,
  departmentSales,
}

extension HomeTileIdExt on HomeTileId {
  String get key => name;
  static HomeTileId? fromKey(String k) {
    return HomeTileId.values.where((e) => e.name == k).firstOrNull;
  }
}

/// Сервис настройки порядка кнопок на домашнем экране.
/// Каждый сотрудник может менять расположение кнопок — порядок сохраняется по employeeId.
class HomeLayoutConfigService extends ChangeNotifier {
  static final HomeLayoutConfigService _instance =
      HomeLayoutConfigService._internal();
  factory HomeLayoutConfigService() => _instance;
  HomeLayoutConfigService._internal();

  /// employeeId → порядок tile IDs
  final Map<String, List<String>> _cache = {};
  /// employeeId → скрытые tile IDs
  final Map<String, List<String>> _hiddenCache = {};
  /// employeeId → порядок кнопок домашнего экрана владельца в Lite (owner_* keys)
  final Map<String, List<String>> _ownerLiteOrderCache = {};

  List<HomeTileId> getOrder(String? employeeId) {
    if (employeeId == null || employeeId.isEmpty)
      return HomeTileId.values.toList();
    final saved = _cache[employeeId];
    if (saved != null && saved.isNotEmpty) {
      final result = saved
          .map((k) => HomeTileIdExt.fromKey(k))
          .whereType<HomeTileId>()
          .toList();
      final missing =
          HomeTileId.values.where((t) => !result.contains(t)).toList();
      return [...result, ...missing];
    }
    return HomeTileId.values.toList();
  }

  Future<void> setOrder(String? employeeId, List<HomeTileId> order) async {
    if (employeeId == null || employeeId.isEmpty) return;
    _cache[employeeId] = order.map((t) => t.key).toList();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_keyPrefix$employeeId', _cache[employeeId]!);
    } catch (_) {}
  }

  Set<String> getHiddenKeys(String? employeeId) {
    if (employeeId == null || employeeId.isEmpty) return <String>{};
    final hidden = _hiddenCache[employeeId];
    if (hidden == null || hidden.isEmpty) return <String>{};
    return hidden.toSet();
  }

  Future<void> setHiddenKeys(String? employeeId, Set<String> hiddenKeys) async {
    if (employeeId == null || employeeId.isEmpty) return;
    _hiddenCache[employeeId] = hiddenKeys.toList(growable: false);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          '$_hiddenKeyPrefix$employeeId', _hiddenCache[employeeId]!);
    } catch (_) {}
  }

  Future<void> loadForEmployee(String? employeeId) async {
    if (employeeId == null || employeeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('$_keyPrefix$employeeId');
      if (saved != null) {
        _cache[employeeId] = saved;
      }
      final hidden = prefs.getStringList('$_hiddenKeyPrefix$employeeId');
      if (hidden != null) {
        _hiddenCache[employeeId] = hidden;
      }
      final ownerLiteOrder =
          prefs.getStringList('$_ownerLiteOrderPrefix$employeeId');
      if (ownerLiteOrder != null) {
        _ownerLiteOrderCache[employeeId] = ownerLiteOrder;
      }
      notifyListeners();
    } catch (_) {}
  }

  List<String> getOwnerLiteOrder(String? employeeId, List<String> defaults) {
    if (employeeId == null || employeeId.isEmpty) {
      return List<String>.from(defaults);
    }
    final saved = _ownerLiteOrderCache[employeeId];
    if (saved == null || saved.isEmpty) return List<String>.from(defaults);
    final ordered = saved.where(defaults.contains).toList(growable: true);
    for (final key in defaults) {
      if (!ordered.contains(key)) ordered.add(key);
    }
    return ordered;
  }

  Future<void> setOwnerLiteOrder(String? employeeId, List<String> order) async {
    if (employeeId == null || employeeId.isEmpty) return;
    _ownerLiteOrderCache[employeeId] = List<String>.from(order);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        '$_ownerLiteOrderPrefix$employeeId',
        _ownerLiteOrderCache[employeeId]!,
      );
    } catch (_) {}
  }
}
