import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyPrefix = 'restodocks_inbox_viewed_';
const _maxViewedIds = 400;

/// Хранит ID просмотренных документов входящих (заказы, инвентаризации, чеклисты).
/// Бейджи считают только непросмотренные; после открытия документа его ID добавляется сюда.
class InboxViewedService extends ChangeNotifier {
  static final InboxViewedService _instance = InboxViewedService._internal();
  factory InboxViewedService() => _instance;
  InboxViewedService._internal();

  final Map<String, Set<String>> _cache = {};

  Future<Set<String>> getViewedIds(String? establishmentId) async {
    if (establishmentId == null || establishmentId.isEmpty) return {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$establishmentId';
      final json = prefs.getString(key);
      if (json == null) {
        _cache[establishmentId] = {};
        return {};
      }
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) {
        _cache[establishmentId] = {};
        return {};
      }
      final set = list.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
      _cache[establishmentId] = set;
      return set;
    } catch (_) {
      _cache[establishmentId] = {};
      return {};
    }
  }

  /// Синхронный доступ к кэшу (после getViewedIds или addViewed).
  Set<String> getViewedIdsSync(String? establishmentId) {
    if (establishmentId == null || establishmentId.isEmpty) return {};
    return _cache[establishmentId] ?? {};
  }

  Future<void> addViewed(String? establishmentId, String documentId) async {
    if (establishmentId == null || establishmentId.isEmpty || documentId.isEmpty) return;
    try {
      var existing = _cache[establishmentId];
      if (existing == null) existing = await getViewedIds(establishmentId);
      if (existing.contains(documentId)) return;
      final list = [...existing, documentId];
      if (list.length > _maxViewedIds) {
        list.removeRange(0, list.length - _maxViewedIds);
      }
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$establishmentId';
      await prefs.setString(key, jsonEncode(list));
      _cache[establishmentId] = list.toSet();
      notifyListeners();
    } catch (_) {}
  }
}
