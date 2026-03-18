import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyMobileUiScalePreset = 'restodocks_mobile_ui_scale_preset';

/// Масштаб интерфейса для телефона.
///
/// Preset:
/// 1 = 80% от текущего
/// 2 = 90% от текущего (default для beta)
/// 3 = 100% (как сейчас)
class MobileUiScaleService extends ChangeNotifier {
  static final MobileUiScaleService _instance = MobileUiScaleService._internal();
  factory MobileUiScaleService() => _instance;
  MobileUiScaleService._internal();

  int _preset = 2;

  int get preset => _preset.clamp(1, 3);

  double get scaleFactor {
    switch (preset) {
      case 1:
        return 0.8;
      case 2:
        return 0.9;
      default:
        return 1.0;
    }
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _preset = (prefs.getInt(_keyMobileUiScalePreset) ?? 2).clamp(1, 3);
    } catch (_) {}
  }

  Future<void> setPreset(int value) async {
    final v = value.clamp(1, 3);
    if (_preset == v) return;
    _preset = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyMobileUiScalePreset, v);
    } catch (_) {}
  }
}

