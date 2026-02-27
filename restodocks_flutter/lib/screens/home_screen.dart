import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import '../services/services.dart';
import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';

/// Главный экран — контент домашней вкладки по роли.
/// Нижняя навигация управляется AppShell (ShellRoute).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.initialTabIndex});

  final int? initialTabIndex;

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

    return Scaffold(
      appBar: AppBar(
        leading: GoRouter.of(context).canPop() ? appBarBackButton(context) : null,
        title: Text(loc.t('app_name')),
      ),
      body: _buildContent(context, currentEmployee),
    );
  }

  Widget _buildContent(BuildContext context, Employee employee) {
    if (employee.hasRole('owner')) {
      final pref = context.read<OwnerViewPreferenceService>();
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
}

/// Экран личного кабинета — меню: Профиль, Настройки, Выход.
class PersonalCabinetScreen extends StatelessWidget {
  const PersonalCabinetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final loc = context.watch<LocalizationService>();

    if (employee == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      appBar: AppBar(title: Text(loc.t('personal_cabinet'))),
      body: SingleChildScrollView(
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
      ),
    );
  }
}
