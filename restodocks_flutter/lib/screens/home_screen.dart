import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import 'home/schedule_screen.dart';
import 'home/inbox_screen.dart';
import '../services/services.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';
import 'checklists_screen.dart';
import 'tech_cards_list_screen.dart';
import 'order_lists_screen.dart';

/// Главный экран: 3 вкладки (Домой, График/Уведомления, Личный кабинет), контент по роли.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.initialTabIndex});

  /// При переходе из Профиля/Настроек — 0 = вкладка «Домой», не личный кабинет.
  final int? initialTabIndex;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex != null
        ? (widget.initialTabIndex!.clamp(0, 2))
        : 0;
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != null && widget.initialTabIndex != oldWidget.initialTabIndex) {
      setState(() => _selectedIndex = widget.initialTabIndex!.clamp(0, 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (currentEmployee == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isOwner = currentEmployee.hasRole('owner');
    final homeBtnConfig = context.watch<HomeButtonConfigService>();
    final middleAction = homeBtnConfig.action;
    final noDataAccess = !isOwner && !currentEmployee.dataAccessEnabled;
    final middleLabel = noDataAccess
        ? (loc.t('personal_schedule') ?? 'Личный график')
        : _labelForAction(loc, middleAction);

    return Scaffold(
      appBar: _selectedIndex == 1
          ? null
          : AppBar(
              leading: GoRouter.of(context).canPop() ? appBarBackButton(context) : null,
              title: Text(_appBarTitle(loc, isOwner, noDataAccess, middleLabel)),
            ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(currentEmployee),
          _buildMiddleTab(currentEmployee, isOwner, loc),
          const _ProfileTabContent(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          setState(() => _selectedIndex = i);
        },
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

  String _appBarTitle(LocalizationService loc, bool isOwner, bool noDataAccess, String middleLabel) {
    switch (_selectedIndex) {
      case 0:
        return loc.t('app_name');
      case 1:
        return middleLabel;
      case 2:
        return loc.t('personal_cabinet');
      default:
        return loc.t('app_name');
    }
  }

  Widget _buildHomeTab(Employee employee) {
    if (employee.hasRole('owner')) {
      final pref = context.read<OwnerViewPreferenceService>();
      // Если у собственника есть должность и выбран режим «по должности» — показываем интерфейс должности
      if (employee.positionRole != null && !pref.viewAsOwner) {
        if (employee.canViewDepartment('management')) {
          return ManagementHomeContent(employee: employee);
        }
        return StaffHomeContent(employee: employee);
      }
      return const OwnerHomeContent();
    }
    if (employee.canViewDepartment('management')) {
      return ManagementHomeContent(employee: employee);
    }
    return StaffHomeContent(employee: employee);
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

  Widget _buildMiddleTab(Employee employee, bool isOwner, LocalizationService loc) {
    final homeBtnConfig = context.read<HomeButtonConfigService>();
    final action = homeBtnConfig.action;
    final noDataAccess = !isOwner && !employee.dataAccessEnabled;

    if (noDataAccess) {
      return ScheduleScreen(personalOnly: true, embedded: true);
    }
    switch (action) {
      case HomeButtonAction.schedule:
        return ScheduleScreen(embedded: true);
      case HomeButtonAction.inbox:
        return const InboxScreen(embedded: true);
      case HomeButtonAction.checklists:
        return const ChecklistsScreen(embedded: true);
      case HomeButtonAction.ttk:
        return TechCardsListScreen(embedded: true);
      case HomeButtonAction.productOrder:
        return const OrderListsScreen(embedded: true);
    }
  }

}

/// Личный кабинет — только меню: Профиль | Настройки | Выход. Без карточки с данными (они в «Профиль»).
class _ProfileTabContent extends StatelessWidget {
  const _ProfileTabContent();

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (employee == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(loc.t('profile')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile'),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(loc.t('settings')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(loc.t('logout'), style: const TextStyle(color: Colors.red)),
            onTap: () async {
              await accountManager.logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
