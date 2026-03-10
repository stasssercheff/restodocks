import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тип отображения уведомлений
enum NotificationDisplayType {
  banner,  // плашка сверху
  modal,   // окошко в центре
  disabled,
}

/// Настройки уведомлений пользователя (локально + опционально Supabase).
class NotificationPreferencesService extends ChangeNotifier {
  static final NotificationPreferencesService _instance = NotificationPreferencesService._internal();
  factory NotificationPreferencesService() => _instance;
  NotificationPreferencesService._internal();

  static const _keyPrefix = 'restodocks_notification_';

  NotificationDisplayType _displayType = NotificationDisplayType.banner;
  bool _messages = true;
  bool _orders = true;
  bool _inventory = true;
  bool _iikoInventory = true;
  bool _notifications = true;

  NotificationDisplayType get displayType => _displayType;
  bool get messages => _messages;
  bool get orders => _orders;
  bool get inventory => _inventory;
  bool get iikoInventory => _iikoInventory;
  bool get notifications => _notifications;

  bool get isEnabled => _displayType != NotificationDisplayType.disabled;

  /// Загрузить настройки для текущего сотрудника
  Future<void> load(String? employeeId) async {
    if (employeeId == null || employeeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}settings_$employeeId';
      final json = prefs.getString(key);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>?;
        if (map != null) {
          _displayType = _parseDisplayType(map['displayType']);
          _messages = map['messages'] as bool? ?? true;
          _orders = map['orders'] as bool? ?? true;
          _inventory = map['inventory'] as bool? ?? true;
          _iikoInventory = map['iikoInventory'] as bool? ?? true;
          _notifications = map['notifications'] as bool? ?? true;
          notifyListeners();
          return;
        }
      }
      _applyDefaults();
      notifyListeners();
    } catch (_) {
      _applyDefaults();
      notifyListeners();
    }
  }

  void _applyDefaults() {
    _displayType = NotificationDisplayType.banner;
    _messages = true;
    _orders = true;
    _inventory = true;
    _iikoInventory = true;
    _notifications = true;
  }

  NotificationDisplayType _parseDisplayType(dynamic v) {
    if (v == null) return NotificationDisplayType.banner;
    final s = v.toString();
    if (s == 'modal') return NotificationDisplayType.modal;
    if (s == 'disabled') return NotificationDisplayType.disabled;
    return NotificationDisplayType.banner;
  }

  String _displayTypeToJson(NotificationDisplayType t) {
    switch (t) {
      case NotificationDisplayType.banner: return 'banner';
      case NotificationDisplayType.modal: return 'modal';
      case NotificationDisplayType.disabled: return 'disabled';
    }
  }

  Future<void> _save(String? employeeId) async {
    if (employeeId == null || employeeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}settings_$employeeId';
      final map = {
        'displayType': _displayTypeToJson(_displayType),
        'messages': _messages,
        'orders': _orders,
        'inventory': _inventory,
        'iikoInventory': _iikoInventory,
        'notifications': _notifications,
      };
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> setDisplayType(NotificationDisplayType value, String? employeeId) async {
    if (_displayType == value) return;
    _displayType = value;
    await _save(employeeId);
    notifyListeners();
  }

  Future<void> setMessages(bool value, String? employeeId) async {
    if (_messages == value) return;
    _messages = value;
    await _save(employeeId);
    notifyListeners();
  }

  Future<void> setOrders(bool value, String? employeeId) async {
    if (_orders == value) return;
    _orders = value;
    await _save(employeeId);
    notifyListeners();
  }

  Future<void> setInventory(bool value, String? employeeId) async {
    if (_inventory == value) return;
    _inventory = value;
    await _save(employeeId);
    notifyListeners();
  }

  Future<void> setIikoInventory(bool value, String? employeeId) async {
    if (_iikoInventory == value) return;
    _iikoInventory = value;
    await _save(employeeId);
    notifyListeners();
  }

  Future<void> setNotifications(bool value, String? employeeId) async {
    if (_notifications == value) return;
    _notifications = value;
    await _save(employeeId);
    notifyListeners();
  }

  /// Нужно ли показывать уведомление для данного типа
  bool shouldNotifyFor(String category) {
    if (_displayType == NotificationDisplayType.disabled) return false;
    switch (category) {
      case 'messages': return _messages;
      case 'orders': return _orders;
      case 'inventory': return _inventory;
      case 'iikoInventory': return _iikoInventory;
      case 'notifications': return _notifications;
      default: return true;
    }
  }
}
