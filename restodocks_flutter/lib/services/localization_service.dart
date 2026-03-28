import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/translation.dart';
import 'translation_manager.dart';

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
    Locale('it', 'IT'),
    Locale('tr', 'TR'),
    Locale('vi', 'VN'),
  ];

  /// Коды языков (продукты, ТТК, DeepL)
  static const List<String> productLanguageCodes = [
    'ru',
    'en',
    'es',
    'it',
    'tr',
    'vi'
  ];

  Locale _currentLocale = const Locale('ru', 'RU');
  Map<String, Map<String, String>> _translations = {};
  TranslationManager? _translationManager;
  final Map<String, Map<String, String>> _autoUiTranslations = {};
  final Set<String> _autoUiInFlight = {};
  final Set<String> _autoUiNoResult = {};
  Timer? _autoUiNotifyDebounce;
  static const int _maxAutoUiInFlight = 2;

  void setTranslationManager(TranslationManager manager) {
    _translationManager = manager;
  }

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
      final jsonString =
          await rootBundle.loadString('assets/translations/localizable.json');
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
      devLog('Ошибка загрузки переводов: $e');
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
    if (!supportedLocales.any((l) => l.languageCode == locale.languageCode))
      return;
    _currentLocale = supportedLocales
        .firstWhere((l) => l.languageCode == locale.languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLocale, _currentLocale.languageCode);
    } catch (_) {}
  }

  /// Получение перевода для текущей локали (fallback: en → ru → key)
  String translate(String key, {Map<String, String>? args}) {
    var translation = _autoUiTranslations[currentLanguageCode]?[key] ??
        _translations[currentLanguageCode]?[key] ??
        _translations['en']?[key] ??
        _translations['ru']?[key] ??
        _translations['tr']?[key] ??
        _translations['vi']?[key] ??
        key;

    if (translation == key &&
        _shouldAutoTranslateUiString(key, currentLanguageCode)) {
      _scheduleAutoUiTranslation(
          sourceText: key, targetLanguage: currentLanguageCode);
    }

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

  /// Отображаемое название должности по коду (role_bar_manager → «Барменеджер»).
  /// Используется в профиле, инвентаризации, списке сотрудников и везде, где показывается должность.
  String roleDisplayName(String roleCode) {
    if (roleCode.isEmpty) return t('employee');
    final key = 'role_$roleCode';
    final translated = t(key);
    return translated == key ? roleCode : translated;
  }

  /// Код роли латиницей (`confectioner`) → локализованная подпись; иначе текст как сохранили (свой вариант).
  String formatStoredHealthPosition(String? stored) {
    if (stored == null || stored.trim().isEmpty) return '';
    final s = stored.trim();
    if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s)) {
      return roleDisplayName(s);
    }
    return s;
  }

  /// Должность в гигиеническом журнале: из JSON или из карточки сотрудника.
  String healthHygienePositionLabel(
      {String? storedPosition, Employee? employee}) {
    if (storedPosition != null && storedPosition.trim().isNotEmpty) {
      return formatStoredHealthPosition(storedPosition);
    }
    if (employee != null && employee.roles.isNotEmpty) {
      return roleDisplayName(employee.roles.first);
    }
    return '—';
  }

  /// Отображаемое название отдела по коду (department_kitchen и т.д.), если есть ключ.
  String departmentDisplayName(String departmentCode) {
    if (departmentCode.isEmpty) return departmentCode;
    final key = 'department_$departmentCode';
    final translated = t(key);
    return translated == key ? departmentCode : translated;
  }

  /// Получение перевода для указанного языка (для экспорта списка заказа на выбранном языке)
  String tForLanguage(String languageCode, String key,
      {Map<String, String>? args}) {
    var translation = _autoUiTranslations[languageCode]?[key] ??
        _translations[languageCode]?[key] ??
        _translations['en']?[key] ??
        _translations['ru']?[key] ??
        _translations['tr']?[key] ??
        _translations['vi']?[key] ??
        key;

    if (translation == key && _shouldAutoTranslateUiString(key, languageCode)) {
      _scheduleAutoUiTranslation(sourceText: key, targetLanguage: languageCode);
    }

    if (args != null) {
      args.forEach((argKey, argValue) {
        translation = translation.replaceAll('{$argKey}', argValue);
      });
    }

    return translation;
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
      case 'tr':
        return 'Türkçe';
      case 'it':
        return 'Italiano';
      case 'vi':
        return 'Tiếng Việt';
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
      case 'tr':
        return '🇹🇷';
      case 'it':
        return '🇮🇹';
      case 'vi':
        return '🇻🇳';
      case 'de':
        return '🇩🇪';
      case 'fr':
        return '🇫🇷';
      default:
        return '🏳️';
    }
  }

  /// Получить локализованный текст для сущности (продукты, ТТК, чеклисты)
  Future<String> getLocalizedEntityText({
    required String entityType,
    required String entityId,
    required String fieldName,
    required String sourceText,
    required String sourceLanguage,
  }) async {
    final targetLanguage = currentLanguageCode;
    if (targetLanguage == sourceLanguage) return sourceText;
    if (_translationManager == null) return sourceText;

    try {
      return await _translationManager!.getLocalizedText(
        entityType: TranslationEntityTypeExtension.fromString(entityType),
        entityId: entityId,
        fieldName: fieldName,
        sourceText: sourceText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
    } catch (_) {
      return sourceText;
    }
  }

  /// Обработать сохранение сущности (триггер автоперевода на все языки)
  Future<void> handleEntitySave({
    required String entityType,
    required String entityId,
    required Map<String, String> textFields,
    required String sourceLanguage,
    String? userId,
  }) async {
    if (_translationManager == null) return;
    try {
      await _translationManager!.handleEntitySave(
        entityType: TranslationEntityTypeExtension.fromString(entityType),
        entityId: entityId,
        textFields: textFields,
        sourceLanguage: sourceLanguage,
        userId: userId,
      );
    } catch (_) {}
  }

  bool _shouldAutoTranslateUiString(String value, String targetLanguage) {
    if (targetLanguage == 'ru') return false;
    if (_translationManager == null) return false;
    final text = value.trim();
    if (text.isEmpty) return false;
    // Вероятно это ключ локализации, а не текст интерфейса.
    if (RegExp(r'^[a-z0-9_]+$').hasMatch(text)) return false;
    // Слишком короткие строки/символы обычно не требуют сетевого перевода.
    if (text.length < 3) return false;
    return true;
  }

  void _scheduleAutoUiTranslation({
    required String sourceText,
    required String targetLanguage,
  }) {
    final inFlightKey = '$targetLanguage|$sourceText';
    if (_autoUiNoResult.contains(inFlightKey)) return;
    if (_autoUiInFlight.contains(inFlightKey)) return;
    if (_autoUiInFlight.length >= _maxAutoUiInFlight) return;
    _autoUiInFlight.add(inFlightKey);
    Future<void>(() async {
      try {
        final translated = await _translationManager!.getLocalizedText(
          entityType: TranslationEntityType.ui,
          entityId: 'runtime_ui',
          fieldName: 'text',
          sourceText: sourceText,
          sourceLanguage: 'auto',
          targetLanguage: targetLanguage,
        );
        final normalized = translated.trim();
        if (normalized.isNotEmpty && normalized != sourceText) {
          _autoUiTranslations.putIfAbsent(targetLanguage, () => {});
          _autoUiTranslations[targetLanguage]![sourceText] = normalized;
          _autoUiNotifyDebounce?.cancel();
          _autoUiNotifyDebounce = Timer(const Duration(milliseconds: 180), () {
            notifyListeners();
          });
        } else {
          // Не повторяем безрезультатные попытки на каждом rebuild.
          _autoUiNoResult.add(inFlightKey);
        }
      } catch (_) {
        _autoUiNoResult.add(inFlightKey);
      } finally {
        _autoUiInFlight.remove(inFlightKey);
      }
    });
  }
}
