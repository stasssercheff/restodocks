import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyViewAsOwner = 'restodocks_owner_view_as_owner';

/// Режим отображения роли: интерфейс как у собственника или по выбранной должности.
/// Хранится в учётной записи и совпадает на всех устройствах (колонка `employees.ui_view_as_owner`).
class OwnerViewPreferenceService extends ChangeNotifier {
  static final OwnerViewPreferenceService _instance = OwnerViewPreferenceService._internal();
  factory OwnerViewPreferenceService() => _instance;
  OwnerViewPreferenceService._internal();

  static Future<void> Function(bool value)? accountPersistHook;

  bool _viewAsOwner = true;
  bool _suppressAccountPersist = false;

  bool get viewAsOwner => _viewAsOwner;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _viewAsOwner = prefs.getBool(_keyViewAsOwner) ?? true;
    } catch (_) {}
  }

  Future<void> applyFromServer(bool? value) async {
    if (value == null) return;
    if (_viewAsOwner == value) return;
    _suppressAccountPersist = true;
    _viewAsOwner = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyViewAsOwner, value);
    } catch (_) {}
    _suppressAccountPersist = false;
  }

  Future<void> setViewAsOwner(bool value) async {
    if (_viewAsOwner == value) return;
    _viewAsOwner = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyViewAsOwner, value);
    } catch (_) {}
    final hook = accountPersistHook;
    if (!_suppressAccountPersist && hook != null) {
      unawaited(hook(value));
    }
  }
}
