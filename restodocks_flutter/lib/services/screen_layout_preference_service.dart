import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyShowBanquetCatering = 'restodocks_show_banquet_catering';
const _keyShowNameTranslit = 'restodocks_show_name_translit';
const _keyShowTranslationNotifications = 'restodocks_show_translation_notifications';

/// Настройки экрана: показ «Банкет/Кейтринг», имена транслитом, уведомления о переводах.
class ScreenLayoutPreferenceService extends ChangeNotifier {
  static final ScreenLayoutPreferenceService _instance = ScreenLayoutPreferenceService._internal();
  factory ScreenLayoutPreferenceService() => _instance;
  ScreenLayoutPreferenceService._internal();

  bool _showBanquetCatering = true;
  bool _showNameTranslit = false;
  bool _showTranslationNotifications = false;

  bool get showBanquetCatering => _showBanquetCatering;
  bool get showNameTranslit => _showNameTranslit;
  bool get showTranslationNotifications => _showTranslationNotifications;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showBanquetCatering = prefs.getBool(_keyShowBanquetCatering) ?? true;
      _showNameTranslit = prefs.getBool(_keyShowNameTranslit) ?? false;
      _showTranslationNotifications = prefs.getBool(_keyShowTranslationNotifications) ?? false;
    } catch (_) {}
  }

  Future<void> setShowTranslationNotifications(bool value) async {
    if (_showTranslationNotifications == value) return;
    _showTranslationNotifications = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowTranslationNotifications, value);
    } catch (_) {}
  }

  Future<void> setShowBanquetCatering(bool value) async {
    if (_showBanquetCatering == value) return;
    _showBanquetCatering = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowBanquetCatering, value);
    } catch (_) {}
  }

  Future<void> setShowNameTranslit(bool value) async {
    if (_showNameTranslit == value) return;
    _showNameTranslit = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowNameTranslit, value);
    } catch (_) {}
  }
}
