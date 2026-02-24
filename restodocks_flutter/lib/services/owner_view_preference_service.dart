import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyViewAsOwner = 'restodocks_owner_view_as_owner';

/// Предпочтение собственника: показывать интерфейс владельца или интерфейс по должности.
class OwnerViewPreferenceService extends ChangeNotifier {
  static final OwnerViewPreferenceService _instance = OwnerViewPreferenceService._internal();
  factory OwnerViewPreferenceService() => _instance;
  OwnerViewPreferenceService._internal();

  bool _viewAsOwner = true;

  bool get viewAsOwner => _viewAsOwner;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _viewAsOwner = prefs.getBool(_keyViewAsOwner) ?? true;
    } catch (_) {}
  }

  Future<void> setViewAsOwner(bool value) async {
    if (_viewAsOwner == value) return;
    _viewAsOwner = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyViewAsOwner, value);
    } catch (_) {}
  }
}
