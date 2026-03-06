import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyShowBanquetCatering = 'restodocks_show_banquet_catering';

/// Настройки экрана: показ «Банкет/Кейтринг» в меню.
class ScreenLayoutPreferenceService extends ChangeNotifier {
  static final ScreenLayoutPreferenceService _instance = ScreenLayoutPreferenceService._internal();
  factory ScreenLayoutPreferenceService() => _instance;
  ScreenLayoutPreferenceService._internal();

  bool _showBanquetCatering = true;

  bool get showBanquetCatering => _showBanquetCatering;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showBanquetCatering = prefs.getBool(_keyShowBanquetCatering) ?? true;
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
}
