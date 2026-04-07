import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'localization_service.dart';

const _keyShowBanquetCatering = 'restodocks_show_banquet_catering';
const _keyShowBarSection = 'restodocks_show_bar_section';
const _keyShowHallSection = 'restodocks_show_hall_section';
const _keyShowTranslationNotifications = 'restodocks_show_translation_notifications';
const _keyBirthdayNotifyDays = 'restodocks_birthday_notify_days';
const _keyBirthdayNotifyTime = 'restodocks_birthday_notify_time';

/// Время уведомления о ДР: только часы с шагом 30 минут (00 или 30). Формат "HH:mm".
String formatBirthdayNotifyTime(int hour, int minute) {
  final m = minute == 30 ? 30 : 0;
  return '${hour.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Список вариантов времени для выбора (шаг 30 мин): "00:00", "00:30", ... "23:30".
List<String> get birthdayNotifyTimeOptions {
  final list = <String>[];
  for (var h = 0; h < 24; h++) {
    list.add(formatBirthdayNotifyTime(h, 0));
    list.add(formatBirthdayNotifyTime(h, 30));
  }
  return list;
}

/// Настройки экрана: показ «Банкет/Кейтринг», уведомления о переводах, оповещение о ДР (0 = выкл, 1–5 дней, время HH:mm).
class ScreenLayoutPreferenceService extends ChangeNotifier {
  static final ScreenLayoutPreferenceService _instance = ScreenLayoutPreferenceService._internal();
  factory ScreenLayoutPreferenceService() => _instance;
  ScreenLayoutPreferenceService._internal();

  bool _showBanquetCatering = true;
  bool _showBarSection = true;
  bool _showHallSection = true;
  bool _showTranslationNotifications = false;
  int _birthdayNotifyDays = 0;
  String _birthdayNotifyTime = '09:00';

  bool get showBanquetCatering => _showBanquetCatering;
  bool get showBarSection => _showBarSection;
  bool get showHallSection => _showHallSection;
  /// Транслит имен сотрудников теперь автоматический:
  /// для не-русского интерфейса включен всегда, для русского — выключен.
  bool get showNameTranslit =>
      LocalizationService().currentLanguageCode != 'ru';
  bool get showTranslationNotifications => _showTranslationNotifications;
  /// За сколько дней до ДР уведомлять (0 = без уведомлений, 1–5).
  int get birthdayNotifyDays => _birthdayNotifyDays.clamp(0, 5);
  /// Время уведомления "HH:mm" (шаг 30 мин). По умолчанию 09:00.
  String get birthdayNotifyTime => _birthdayNotifyTime;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showBanquetCatering = prefs.getBool(_keyShowBanquetCatering) ?? true;
      _showBarSection = prefs.getBool(_keyShowBarSection) ?? true;
      _showHallSection = prefs.getBool(_keyShowHallSection) ?? true;
      _showTranslationNotifications = prefs.getBool(_keyShowTranslationNotifications) ?? false;
      _birthdayNotifyDays = prefs.getInt(_keyBirthdayNotifyDays) ?? 0;
      _birthdayNotifyTime = prefs.getString(_keyBirthdayNotifyTime) ?? '09:00';
      if (!birthdayNotifyTimeOptions.contains(_birthdayNotifyTime)) _birthdayNotifyTime = '09:00';
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

  Future<void> setShowBarSection(bool value) async {
    if (_showBarSection == value) return;
    _showBarSection = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowBarSection, value);
    } catch (_) {}
  }

  Future<void> setShowHallSection(bool value) async {
    if (_showHallSection == value) return;
    _showHallSection = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShowHallSection, value);
    } catch (_) {}
  }

  Future<void> setBirthdayNotifyDays(int value) async {
    final v = value.clamp(0, 5);
    if (_birthdayNotifyDays == v) return;
    _birthdayNotifyDays = v;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyBirthdayNotifyDays, v);
    } catch (_) {}
  }

  Future<void> setBirthdayNotifyTime(String value) async {
    if (!birthdayNotifyTimeOptions.contains(value)) return;
    if (_birthdayNotifyTime == value) return;
    _birthdayNotifyTime = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBirthdayNotifyTime, value);
    } catch (_) {}
  }
}
