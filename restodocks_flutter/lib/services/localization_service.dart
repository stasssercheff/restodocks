import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

const _keyLocale = 'restodocks_locale';

/// Сервис управления локализацией
class LocalizationService extends ChangeNotifier {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  static const List<Locale> supportedLocales = [
    Locale('ru', 'RU'),
    Locale('en', 'US'),
    Locale('es', 'ES'),
    Locale('de', 'DE'),
    Locale('fr', 'FR'),
  ];

  /// Коды языков для названий продуктов (ru, en, es, de, fr)
  static const List<String> productLanguageCodes = ['ru', 'en', 'es', 'de', 'fr'];

  Locale _currentLocale = const Locale('ru', 'RU');
  Map<String, Map<String, String>> _translations = {};

  // Геттеры
  Locale get currentLocale => _currentLocale;
  String get currentLanguageCode => _currentLocale.languageCode;

  /// Инициализация сервиса
  static Future<void> initialize() async {
    await _instance._loadTranslations();
    await _instance._loadSavedLocale();
  }

  /// Загрузка переводов
  Future<void> _loadTranslations() async {
    try {
      final jsonString = await rootBundle.loadString('assets/translations/localizable.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      _translations = {};
      // Структура: {"ru": {"key": "value"}, "en": {"key": "value"}}
      jsonData.forEach((languageCode, translations) {
        if (translations is Map<String, dynamic>) {
          final Map<String, String> languageTranslations = {};
          translations.forEach((key, value) {
            languageTranslations[key] = value.toString();
          });
          _translations[languageCode] = languageTranslations;
        }
      });
    } catch (e) {
      print('Ошибка загрузки переводов: $e');
    }
  }

  /// Загрузка сохраненной локали
  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_keyLocale);
      if (code == null) return;
      for (final l in supportedLocales) {
        if (l.languageCode == code) {
          _currentLocale = l;
          return;
        }
      }
    } catch (_) {}
  }

  /// Установка текущей локали (сохраняется в SharedPreferences)
  Future<void> setLocale(Locale locale) async {
    if (!supportedLocales.any((l) => l.languageCode == locale.languageCode)) return;
    _currentLocale = supportedLocales.firstWhere((l) => l.languageCode == locale.languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLocale, _currentLocale.languageCode);
    } catch (_) {}
  }

  /// Получение перевода для текущей локали (fallback: en → ru → key)
  String translate(String key, {Map<String, String>? args}) {
    var translation = _translations[currentLanguageCode]?[key] ??
        _translations['en']?[key] ??
        _translations['ru']?[key] ??
        key;

    // Замена аргументов в переводе
    if (args != null) {
      args.forEach((argKey, argValue) {
        translation = translation.replaceAll('{$argKey}', argValue);
      });
    }

    return translation;
  }

  /// Получение перевода с сокращенным синтаксисом
  String t(String key, {Map<String, String>? args}) {
    return translate(key, args: args);
  }

  /// Проверка, выбран ли язык
  bool get isLanguageSelected => true; // Пока всегда true

  /// Получение названия языка
  String getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return 'Русский';
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'de':
        return 'Deutsch';
      case 'fr':
        return 'Français';
      default:
        return languageCode;
    }
  }

  /// Получение списка доступных языков
  List<Map<String, String>> get availableLanguages {
    return supportedLocales.map((locale) {
      return {
        'code': locale.languageCode,
        'name': getLanguageName(locale.languageCode),
        'flag': _getLanguageFlag(locale.languageCode),
      };
    }).toList();
  }

  String _getLanguageFlag(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return '🇷🇺';
      case 'en':
        return '🇺🇸';
      case 'es':
        return '🇪🇸';
      case 'de':
        return '🇩🇪';
      case 'fr':
        return '🇫🇷';
      default:
        return '🏳️';
    }
  }
}