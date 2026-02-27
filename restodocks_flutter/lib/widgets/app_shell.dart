import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';
import '../services/account_manager_supabase.dart';
import '../services/home_button_config_service.dart';

/// Оболочка с нижней навигацией для всех рабочих экранов (кроме инвентаризации).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;

    if (currentEmployee == null) return child;

    final isOwner = currentEmployee.hasRole('owner');
    final homeBtnConfig = context.watch<HomeButtonConfigService>();
    final middleAction = homeBtnConfig.action;
    final noDataAccess = !isOwner && !currentEmployee.dataAccessEnabled;
    final middleLabel = noDataAccess
        ? loc.t('personal_schedule')
        : _labelForAction(loc, middleAction);

    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _indexForLocation(location, middleAction, noDataAccess);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => _onTap(context, i, middleAction, noDataAccess),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: loc.t('home'),
          ),
          NavigationDestination(
            icon: Icon(noDataAccess ? Icons.calendar_month_outlined : middleAction.iconOutlined),
            selectedIcon: Icon(noDataAccess ? Icons.calendar_month : middleAction.icon),
            label: middleLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: loc.t('personal_cabinet'),
          ),
        ],
      ),
    );
  }

  String _labelForAction(LocalizationService loc, HomeButtonAction action) {
    switch (action) {
      case HomeButtonAction.inbox:
        return loc.t('inbox');
      case HomeButtonAction.schedule:
        return loc.t('schedule');
      case HomeButtonAction.checklists:
        return loc.t('checklists');
      case HomeButtonAction.ttk:
        return loc.t('tech_cards');
      case HomeButtonAction.productOrder:
        return loc.t('product_order');
    }
  }

  int _indexForLocation(String location, HomeButtonAction action, bool noDataAccess) {
    if (location == '/home' || location == '/') return 0;
    if (location.startsWith('/personal-cabinet') || location.startsWith('/profile') || location.startsWith('/settings')) return 2;

    final middleRoute = noDataAccess ? '/schedule' : action.route;
    if (location.startsWith(middleRoute)) return 1;

    // Дополнительные маршруты для средней вкладки
    if (location.startsWith('/schedule') ||
        location.startsWith('/inbox') ||
        location.startsWith('/notifications') ||
        location.startsWith('/checklists') ||
        location.startsWith('/tech-cards') ||
        location.startsWith('/product-order')) {
      return 1;
    }
    return 0;
  }

  void _onTap(BuildContext context, int index, HomeButtonAction action, bool noDataAccess) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexForLocation(location, action, noDataAccess);

    // Если переходим на вкладку с меньшим индексом — анимируем как «назад» (вправо)
    final isBackward = index < currentIndex;
    final extra = isBackward ? {'back': true} : null;

    switch (index) {
      case 0:
        context.go('/home', extra: extra);
      case 1:
        context.go(noDataAccess ? '/schedule?personal=1' : action.route, extra: extra);
      case 2:
        context.go('/personal-cabinet', extra: extra);
      default:
        context.go('/home', extra: extra);
    }
  }
}
