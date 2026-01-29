import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Безопасное хранилище для чувствительных данных.
///
/// На iOS/Android/desktop использует [FlutterSecureStorage] (Keychain / EncryptedSharedPreferences).
/// На Web — [SharedPreferences] (secure storage недоступен в браузере).
const _sessionPrefix = 'restodocks_secure_';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  FlutterSecureStorage? _secure;
  SharedPreferences? _prefs;

  /// Используем secure storage везде, кроме web.
  bool get _useSecure => !kIsWeb;

  FlutterSecureStorage get _storage {
    if (_secure == null) {
      throw StateError('SecureStorageService not initialized');
    }
    return _secure!;
  }

  /// Инициализация. Вызвать до использования (например, из [AccountManagerSupabase.initialize]).
  Future<void> initialize() async {
    if (_useSecure) {
      _secure = const FlutterSecureStorage();
    } else {
      _secure = null;
      _prefs = await SharedPreferences.getInstance();
    }
  }

  Future<String?> _getSecure(String key) async {
    if (_useSecure) return await _storage.read(key: _sessionPrefix + key);
    return _prefs?.getString(_sessionPrefix + key);
  }

  Future<void> _setSecure(String key, String value) async {
    if (_useSecure) {
      await _storage.write(key: _sessionPrefix + key, value: value);
    } else {
      await _prefs?.setString(_sessionPrefix + key, value);
    }
  }

  Future<void> _removeSecure(String key) async {
    if (_useSecure) {
      await _storage.delete(key: _sessionPrefix + key);
    } else {
      await _prefs?.remove(_sessionPrefix + key);
    }
  }

  Future<String?> get(String key) => _getSecure(key);

  Future<void> set(String key, String value) => _setSecure(key, value);

  Future<void> remove(String key) => _removeSecure(key);

  Future<void> clear() async {
    if (_useSecure) {
      final all = await _storage.readAll();
      for (final k in all.keys) {
        if (k.startsWith(_sessionPrefix)) await _storage.delete(key: k);
      }
    } else {
      final keys = _prefs?.getKeys().where((k) => k.startsWith(_sessionPrefix)).toList() ?? [];
      for (final k in keys) await _prefs?.remove(k);
    }
  }
}
