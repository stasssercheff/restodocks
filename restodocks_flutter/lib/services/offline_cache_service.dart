import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_storage_service.dart';

const _cachePrefix = 'restodocks_cache_v1:';
const _employeeIdStorageKey = 'restodocks_employee_id';

/// Локальный кэш для ускорения открытия экранов (cache-first).
/// Ключи привязаны к сотруднику + заведению, чтобы не смешивать данные разных доступов.
class OfflineCacheService {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  SharedPreferences? _prefs;
  final SecureStorageService _secureStorage = SecureStorageService();

  Future<SharedPreferences> _sp() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<String> _scopeToken() async {
    await _secureStorage.initialize();
    final employeeId = await _secureStorage.get(_employeeIdStorageKey);
    if (employeeId != null && employeeId.isNotEmpty) return employeeId;
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null && authId.isNotEmpty) return authId;
    return 'guest';
  }

  Future<String> scopedKey({
    required String dataset,
    required String establishmentId,
    String? suffix,
  }) async {
    final token = await _scopeToken();
    final sfx = (suffix != null && suffix.isNotEmpty) ? ':$suffix' : '';
    return '$_cachePrefix$dataset:$establishmentId:$token$sfx';
  }

  Future<void> writeJsonMap(String key, Map<String, dynamic> data) async {
    final prefs = await _sp();
    await prefs.setString(key, jsonEncode(data));
    await prefs.setInt('$key:ts', DateTime.now().millisecondsSinceEpoch);
  }

  Future<Map<String, dynamic>?> readJsonMap(String key) async {
    final prefs = await _sp();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> writeJsonList(
      String key, List<Map<String, dynamic>> data) async {
    final prefs = await _sp();
    await prefs.setString(key, jsonEncode(data));
    await prefs.setInt('$key:ts', DateTime.now().millisecondsSinceEpoch);
  }

  Future<List<Map<String, dynamic>>?> readJsonList(String key) async {
    final prefs = await _sp();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> removeKey(String key) async {
    final prefs = await _sp();
    await prefs.remove(key);
    await prefs.remove('$key:ts');
  }

  Future<void> clearCurrentUserCache() async {
    final token = await _scopeToken();
    final prefs = await _sp();
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_cachePrefix) && k.contains(':$token'))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
      await prefs.remove('$key:ts');
    }
  }
}
