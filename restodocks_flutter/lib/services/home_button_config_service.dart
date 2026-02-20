import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyHomeButton = 'restodocks_home_button_action';

/// Действия для средней кнопки на главном экране
enum HomeButtonAction {
  schedule,
  checklists,
  ttk,
  productOrder,
}

extension HomeButtonActionExt on HomeButtonAction {
  String get route {
    switch (this) {
      case HomeButtonAction.schedule:
        return '/schedule';
      case HomeButtonAction.checklists:
        return '/checklists';
      case HomeButtonAction.ttk:
        return '/tech-cards';
      case HomeButtonAction.productOrder:
        return '/product-order';
    }
  }

  IconData get icon {
    switch (this) {
      case HomeButtonAction.schedule:
        return Icons.calendar_month;
      case HomeButtonAction.checklists:
        return Icons.checklist;
      case HomeButtonAction.ttk:
        return Icons.menu_book;
      case HomeButtonAction.productOrder:
        return Icons.shopping_cart;
    }
  }

  IconData get iconOutlined {
    switch (this) {
      case HomeButtonAction.schedule:
        return Icons.calendar_month_outlined;
      case HomeButtonAction.checklists:
        return Icons.checklist_outlined;
      case HomeButtonAction.ttk:
        return Icons.menu_book_outlined;
      case HomeButtonAction.productOrder:
        return Icons.shopping_cart_outlined;
    }
  }

  String get storageKey {
    switch (this) {
      case HomeButtonAction.schedule:
        return 'schedule';
      case HomeButtonAction.checklists:
        return 'checklists';
      case HomeButtonAction.ttk:
        return 'ttk';
      case HomeButtonAction.productOrder:
        return 'product_order';
    }
  }

  static HomeButtonAction fromStorageKey(String key) {
    switch (key) {
      case 'checklists':
        return HomeButtonAction.checklists;
      case 'ttk':
        return HomeButtonAction.ttk;
      case 'product_order':
        return HomeButtonAction.productOrder;
      default:
        return HomeButtonAction.schedule;
    }
  }
}

/// Сервис настройки средней кнопки на главном экране
class HomeButtonConfigService extends ChangeNotifier {
  static final HomeButtonConfigService _instance = HomeButtonConfigService._internal();
  factory HomeButtonConfigService() => _instance;
  HomeButtonConfigService._internal();

  HomeButtonAction _action = HomeButtonAction.schedule;

  HomeButtonAction get action => _action;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_keyHomeButton);
      if (value != null) {
        _action = HomeButtonActionExt.fromStorageKey(value);
      }
    } catch (_) {}
  }

  Future<void> setAction(HomeButtonAction action) async {
    if (_action == action) return;
    _action = action;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyHomeButton, action.storageKey);
    } catch (_) {}
  }
}
