import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyThemeMode = 'restodocks_theme_mode';

/// Сервис управления темой (светлая / тёмная)
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  /// По умолчанию светлая тема (до загрузки из prefs и при отсутствии сохранённого выбора).
  ThemeMode _themeMode = ThemeMode.light;

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

  /// Установить тему (светлая или тёмная)
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }

  /// Переключить между светлой и тёмной
  Future<void> toggle() async {
    await setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
