import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/cyrillic_transliteration.dart';
import '../utils/dev_log.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/translation.dart';
import 'translation_manager.dart';

/// Локализация интерфейса: **в коде только ключи** (`loc.t('some_key')`), тексты — в
/// `assets/translations/localizable.json` для **каждого** языка из [supportedLocales].
/// Не смешивать в виджетах захардкоженный русский/английский и ключи: пользовательский
/// текст интерфейса всегда из JSON. Исключения — служебное (логи, парсинг CSV/ИИ) и
/// данные с сервера/пользователя, не являющиеся строками оболочки приложения.
class LocalizationService extends ChangeNotifier {
  static final LocalizationService _instance = LocalizationService._internal();
  factory LocalizationService() => _instance;
  LocalizationService._internal();

  static const String prefsKeyLocale = 'restodocks_locale';

  /// Явный выбор языка (настройки / регистрация): при синхронизации профиля не затирать устройство сервером.
  static const String prefsKeyLocaleUserSet = 'restodocks_locale_user_set';

  static const List<Locale> supportedLocales = [
    Locale('ru', 'RU'),
    Locale('en', 'US'),
    Locale('es', 'ES'),
    Locale('de', 'DE'),
    Locale('fr', 'FR'),
    Locale('it', 'IT'),
    Locale('tr', 'TR'),
    Locale('vi', 'VN'),
  ];

  /// Коды языков (продукты, ТТК, DeepL)
  static const List<String> productLanguageCodes = [
    'ru',
    'en',
    'es',
    'de',
    'fr',
    'it',
    'tr',
    'vi',
  ];

  /// Emoji для языка интерфейса (с запасными шрифтами см. [flagEmojiTextStyle]).
  static String flagEmoji(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return '🇷🇺';
      case 'en':
        return '🇺🇸';
      case 'es':
        return '🇪🇸';
      case 'it':
        return '🇮🇹';
      case 'tr':
        return '🇹🇷';
      case 'vi':
        return '🇻🇳';
      case 'de':
        return '🇩🇪';
      case 'fr':
        return '🇫🇷';
      default:
        return '🌐';
    }
  }

  static TextStyle get flagEmojiTextStyle => const TextStyle(
        fontSize: 24,
        height: 1,
        fontFamilyFallback: <String>[
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Noto Color Emoji',
          'Noto Emoji',
        ],
      );

  static bool isSupportedLanguageCode(String code) =>
      supportedLocales.any((l) => l.languageCode == code);

  Locale _currentLocale = const Locale('ru', 'RU');
  Map<String, Map<String, String>> _translations = {};
  TranslationManager? _translationManager;
  final Map<String, Map<String, String>> _autoUiTranslations = {};
  final Set<String> _autoUiInFlight = {};
  final Set<String> _autoUiNoResult = {};
  Timer? _autoUiNotifyDebounce;
  static const int _maxAutoUiInFlight = 2;

  /// Синхронно до смены [currentLocale]: сброс оверлея переводов ТТК, чтобы не кратковременно смешивать языки.
  static void Function()? onBeforeLocaleChanged;

  /// После смены локали: перезагрузка оверлея названий ТТК для нового языка (не импортировать тяжёлые сервисы сюда).
  static Future<void> Function()? onAfterLocaleChanged;

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
      final code = prefs.getString(prefsKeyLocale);
      if (code == null) return;
      for (final l in supportedLocales) {
        if (l.languageCode == code) {
          _currentLocale = l;
          return;
        }
      }
    } catch (_) {}
  }

  /// Язык с экрана входа/регистрации до загрузки профиля — считаем явным выбором.
  Future<void> markLocaleChoiceFromAuthFlow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKeyLocaleUserSet, true);
    } catch (_) {}
  }

  /// Диалог выбора языка (вход, регистрация, общий UI).
  /// После смены локали вызывается [afterApplied], если задан (например сохранить в профиль).
  Future<void> showLocalePickerDialog(
    BuildContext context, {
    Future<void> Function(String languageCode)? afterApplied,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 400),
              decoration: BoxDecoration(
                color: Theme.of(ctx).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                    child: Text(
                      t('language'),
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: supportedLocales.map((locale) {
                        final selected =
                            currentLocale.languageCode == locale.languageCode;
                        return ListTile(
                          leading: Text(
                            flagEmoji(locale.languageCode),
                            style: flagEmojiTextStyle,
                          ),
                          title: Text(getLanguageName(locale.languageCode)),
                          selected: selected,
                          onTap: () async {
                            await setLocale(locale, userChoice: true);
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            final cb = afterApplied;
                            if (cb != null) {
                              await cb(locale.languageCode);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Установка текущей локали (сохраняется в SharedPreferences).
  /// [userChoice]: true — выбор из диалога языка; такой язык приоритетнее при синхронизации с сервером.
  Future<void> setLocale(Locale locale, {bool userChoice = false}) async {
    if (!supportedLocales.any((l) => l.languageCode == locale.languageCode))
      return;
    try {
      onBeforeLocaleChanged?.call();
    } catch (e, st) {
      devLog('onBeforeLocaleChanged: $e $st');
    }
    _currentLocale = supportedLocales
        .firstWhere((l) => l.languageCode == locale.languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKeyLocale, _currentLocale.languageCode);
      if (userChoice) {
        await prefs.setBool(prefsKeyLocaleUserSet, true);
      }
    } catch (_) {}
    try {
      await onAfterLocaleChanged?.call();
      notifyListeners();
    } catch (e, st) {
      devLog('onAfterLocaleChanged: $e $st');
    }
  }

  /// Получение перевода для текущей локали.
  ///
  /// Разрешение: текущий язык → **en** (если для текущего нет строки) → сырой [key].
  /// В коде **нет** fallback на русский или другой язык — в [localizable.json] должны быть
  /// строки интерфейса для **всех** [supportedLocales] (и новые ключи добавлять сразу во все языки).
  String translate(String key, {Map<String, String>? args}) {
    var translation = _autoUiTranslations[currentLanguageCode]?[key] ??
        _translations[currentLanguageCode]?[key] ??
        _translations['en']?[key];

    var out = translation ?? key;

    if (out == key &&
        _shouldAutoTranslateUiString(key, currentLanguageCode)) {
      _scheduleAutoUiTranslation(
          sourceText: key, targetLanguage: currentLanguageCode);
    }

    // Замена аргументов в переводе
    if (args != null) {
      args.forEach((argKey, argValue) {
        out = out.replaceAll('{$argKey}', argValue);
      });
    }

    return out;
  }

  /// Получение перевода с сокращенным синтаксисом
  String t(String key, {Map<String, String>? args}) {
    return translate(key, args: args);
  }

  /// Отображаемое название должности по коду (role_bar_manager → «Барменеджер»).
  /// Используется в профиле, инвентаризации, списке сотрудников и везде, где показывается должность.
  String roleDisplayName(String roleCode) {
    if (roleCode.isEmpty) return t('employee');
    final normalized =
        roleCode.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final key = 'role_$normalized';
    final translated = t(key);
    return translated == key ? roleCode : translated;
  }

  /// Код роли латиницей (`confectioner`) → локализованная подпись; иначе текст как сохранили (свой вариант).
  String formatStoredHealthPosition(String? stored) {
    if (stored == null || stored.trim().isEmpty) return '';
    final s = stored.trim();
    final normalized = s.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
      return roleDisplayName(normalized);
    }
    return s;
  }

  /// [formatStoredHealthPosition] для заданного языка (например экспорт PDF не на языке UI).
  String formatStoredHealthPositionForLanguage(
      String? stored, String languageCode) {
    if (stored == null || stored.trim().isEmpty) return '';
    final s = stored.trim();
    final normalized = s.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
      final key = 'role_$normalized';
      final translated = tForLanguage(languageCode, key);
      return translated == key ? s : translated;
    }
    return s;
  }

  /// ФИО: для нерусского интерфейса — латиница (транслит), для ru — как в базе.
  String displayPersonNameForUi(String? name) {
    if (name == null || name.isEmpty) return '—';
    return displayPersonNameForLanguage(name, currentLanguageCode);
  }

  /// То же для заданного языка (экспорт PDF и т.п.). Пустая строка — пустая ячейка.
  String displayPersonNameForLanguage(String? name, String languageCode) {
    if (name == null || name.isEmpty) return '';
    if (languageCode == 'ru') {
      // Для ru UI пытаемся вернуть кириллицу даже если в БД имя латиницей.
      if (!RegExp(r'[А-Яа-яЁё]').hasMatch(name) &&
          RegExp(r'[A-Za-z]').hasMatch(name)) {
        return transliterateLatinToRuBestEffort(name);
      }
      return name;
    }
    if (!RegExp(r'[А-Яа-яЁё]').hasMatch(name)) return name;
    return transliterateRuToLatin(name);
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
        _translations['en']?[key];

    var out = translation ?? key;

    if (out == key && _shouldAutoTranslateUiString(key, languageCode)) {
      _scheduleAutoUiTranslation(sourceText: key, targetLanguage: languageCode);
    }

    if (args != null) {
      args.forEach((argKey, argValue) {
        out = out.replaceAll('{$argKey}', argValue);
      });
    }

    return out;
  }

  /// Проверка, выбран ли язык
  bool get isLanguageSelected => true; // Пока всегда true

  /// Название языка **на самом языке** (для списков выбора: понятно любому пользователю).
  /// Не зависит от текущей локали UI (в отличие от старых `lang_name_*` в JSON).
  static const Map<String, String> _languageNativeNames = {
    'ru': 'Русский',
    'en': 'English',
    'es': 'Español',
    'it': 'Italiano',
    'tr': 'Türkçe',
    'vi': 'Tiếng Việt',
    'de': 'Deutsch',
    'fr': 'Français',
  };

  /// Получение названия языка для отображения в селекторах (логин, настройки, регистрация, экспорт и т.д.).
  String getLanguageName(String languageCode) {
    final code = languageCode.trim().toLowerCase();
    return _languageNativeNames[code] ?? code;
  }

  /// Получение списка доступных языков
  List<Map<String, String>> get availableLanguages {
    return supportedLocales.map((locale) {
      return {
        'code': locale.languageCode,
        'name': getLanguageName(locale.languageCode),
        'flag': flagEmoji(locale.languageCode),
      };
    }).toList();
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
