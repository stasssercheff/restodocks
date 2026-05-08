import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const _keyHomeButton = 'restodocks_home_button_action';

/// Подразделение для роута с приоритетом роли сотрудника.
String _deptForRoute(Employee? e) {
  final d = e?.department;
  if (d == 'dining_room') return 'hall';
  if (d != 'management') return d ?? 'kitchen';
  if (e?.hasRole('bar_manager') == true) return 'bar';
  if (e?.hasRole('floor_manager') == true) return 'hall';
  if (e?.hasRole('executive_chef') == true || e?.hasRole('sous_chef') == true) {
    return 'kitchen';
  }
  return 'management';
}

/// Действия для средней кнопки на главном экране
enum HomeButtonAction {
  inbox,
  messages,
  schedule,
  productOrder,
  menu,
  ttk,
  checklists,
  nomenclature,
  inventory,
  expenses,
}

extension HomeButtonActionExt on HomeButtonAction {
  /// [kitchenOnlySchedule]: Lite — график только кухня (`/schedule/kitchen`), не «все подразделения».
  String routeFor(Employee? emp, {bool kitchenOnlySchedule = false}) {
    final dept = _deptForRoute(emp);
    final isOwner = emp?.hasRole('owner') ?? false;
    switch (this) {
      case HomeButtonAction.inbox:
        return '/inbox';
      case HomeButtonAction.messages:
        return '/notifications?tab=messages';
      case HomeButtonAction.schedule:
        if (kitchenOnlySchedule) return '/schedule/kitchen';
        return isOwner ? '/schedule/all' : '/schedule/$dept';
      case HomeButtonAction.productOrder:
        return '/product-order?department=$dept';
      case HomeButtonAction.menu:
        return '/menu/$dept';
      case HomeButtonAction.ttk:
        return '/tech-cards/$dept';
      case HomeButtonAction.checklists:
        return '/checklists?department=$dept';
      case HomeButtonAction.nomenclature:
        return '/nomenclature/$dept';
      case HomeButtonAction.inventory:
        return '/inventory';
      case HomeButtonAction.expenses:
        return '/expenses';
    }
  }

  IconData get icon {
    switch (this) {
      case HomeButtonAction.inbox:
        return Icons.inbox;
      case HomeButtonAction.messages:
        return Icons.chat_bubble;
      case HomeButtonAction.schedule:
        return Icons.calendar_month;
      case HomeButtonAction.productOrder:
        return Icons.shopping_cart;
      case HomeButtonAction.menu:
        return Icons.restaurant_menu;
      case HomeButtonAction.ttk:
        return Icons.description;
      case HomeButtonAction.checklists:
        return Icons.checklist;
      case HomeButtonAction.nomenclature:
        return Icons.assignment;
      case HomeButtonAction.inventory:
        return Icons.assignment;
      case HomeButtonAction.expenses:
        return Icons.payments;
    }
  }

  IconData get iconOutlined {
    switch (this) {
      case HomeButtonAction.inbox:
        return Icons.inbox_outlined;
      case HomeButtonAction.messages:
        return Icons.chat_bubble_outlined;
      case HomeButtonAction.schedule:
        return Icons.calendar_month_outlined;
      case HomeButtonAction.productOrder:
        return Icons.shopping_cart_outlined;
      case HomeButtonAction.menu:
        return Icons.restaurant_menu_outlined;
      case HomeButtonAction.ttk:
        return Icons.description_outlined;
      case HomeButtonAction.checklists:
        return Icons.checklist_outlined;
      case HomeButtonAction.nomenclature:
        return Icons.assignment_outlined;
      case HomeButtonAction.inventory:
        return Icons.assignment_outlined;
      case HomeButtonAction.expenses:
        return Icons.payments_outlined;
    }
  }

  String get storageKey {
    return name;
  }

  static HomeButtonAction fromStorageKey(String key) {
    return HomeButtonAction.values.where((a) => a.storageKey == key).firstOrNull ?? HomeButtonAction.schedule;
  }
}

/// Доступные действия для роли. [hasProSubscription] — раздел «Расходы» только при Pro.
/// [ownerLiteHome] — у владельца на Lite средняя кнопка только график (без переключения на меню).
List<HomeButtonAction> homeButtonActionsFor(Employee? emp,
    {bool hasProSubscription = false, bool ownerLiteHome = false}) {
  if (emp == null) return [HomeButtonAction.schedule];
  final isOwner = emp.hasRole('owner');
  final isChef = emp.hasRole('executive_chef') || emp.hasRole('sous_chef');
  final isManagement = emp.department == 'management' || isChef ||
      emp.hasRole('bar_manager') || emp.hasRole('floor_manager') || emp.hasRole('general_manager');

  if (isOwner) {
    if (ownerLiteHome) {
      return [HomeButtonAction.schedule];
    }
    return [HomeButtonAction.inbox, HomeButtonAction.messages, HomeButtonAction.schedule, HomeButtonAction.menu];
  }
  if (isChef || isManagement) {
    return [
      HomeButtonAction.inbox,
      HomeButtonAction.messages,
      HomeButtonAction.schedule,
      HomeButtonAction.productOrder,
      HomeButtonAction.menu,
      HomeButtonAction.ttk,
      HomeButtonAction.checklists,
      HomeButtonAction.nomenclature,
      HomeButtonAction.inventory,
      if (hasProSubscription || kIsWeb) HomeButtonAction.expenses,
    ];
  }
  // Линейный сотрудник
  return [
    HomeButtonAction.messages,
    HomeButtonAction.schedule,
    HomeButtonAction.productOrder,
    HomeButtonAction.menu,
    HomeButtonAction.ttk,
    HomeButtonAction.checklists,
  ];
}

/// Сервис настройки средней кнопки на главном экране
class HomeButtonConfigService extends ChangeNotifier {
  static final HomeButtonConfigService _instance = HomeButtonConfigService._internal();
  factory HomeButtonConfigService() => _instance;
  HomeButtonConfigService._internal();

  HomeButtonAction _action = HomeButtonAction.schedule;

  HomeButtonAction get action => _action;

  /// Действие с учётом допустимых для роли (если сохранённое недоступно — первое из списка)
  HomeButtonAction effectiveAction(Employee? emp,
      {bool hasProSubscription = false, bool ownerLiteHome = false}) {
    final allowed = homeButtonActionsFor(emp,
        hasProSubscription: hasProSubscription,
        ownerLiteHome: ownerLiteHome);
    return allowed.contains(_action)
        ? _action
        : (allowed.firstOrNull ?? HomeButtonAction.schedule);
  }

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
