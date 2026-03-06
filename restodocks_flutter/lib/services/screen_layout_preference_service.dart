import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyShowBanquetCatering = 'restodocks_show_banquet_catering';
const _keyShowNameTranslit = 'restodocks_show_name_translit';

/// Настройки экрана: показ «Банкет/Кейтринг» в меню, отображение имён транслитом.
class ScreenLayoutPreferenceService extends ChangeNotifier {
  static final ScreenLayoutPreferenceService _instance = ScreenLayoutPreferenceService._internal();
  factory ScreenLayoutPreferenceService() => _instance;
  ScreenLayoutPreferenceService._internal();

  bool _showBanquetCatering = true;
  bool _showNameTranslit = false;

  bool get showBanquetCatering => _showBanquetCatering;
  bool get showNameTranslit => _showNameTranslit;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showBanquetCatering = prefs.getBool(_keyShowBanquetCatering) ?? true;
      _showNameTranslit = prefs.getBool(_keyShowNameTranslit) ?? false;
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
