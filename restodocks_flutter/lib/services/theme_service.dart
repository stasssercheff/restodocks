import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyThemeMode = 'restodocks_theme_mode';

/// Сервис управления темой (светлая / тёмная)
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  /// Сохранение `ui_theme` в профиль (ставится из main, без циклических импортов).
  static Future<void> Function(ThemeMode mode)? accountPersistHook;

  /// По умолчанию светлая тема (до загрузки из prefs и при отсутствии сохранённого выбора).
  ThemeMode _themeMode = ThemeMode.light;

  bool _suppressAccountPersist = false;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  /// Инициализация — загрузить сохранённую тему
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyThemeMode);
      if (value == 'dark') {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.light;
      }
    } catch (_) {}
  }

  /// Значения `light` / `dark` из `employees.ui_theme` (синхронизация аккаунта).
  Future<void> applyFromServer(String? uiTheme) async {
    if (uiTheme != 'light' && uiTheme != 'dark') return;
    final mode = uiTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == mode) return;
    _suppressAccountPersist = true;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _keyThemeMode, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
    _suppressAccountPersist = false;
  }

  /// Установить тему (светлая или тёмная)
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
    final hook = accountPersistHook;
    if (!_suppressAccountPersist && hook != null) {
      unawaited(hook(mode));
    }
  }

  /// Переключить между светлой и тёмной
  Future<void> toggle() async {
    await setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
