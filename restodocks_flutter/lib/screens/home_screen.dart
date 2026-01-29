import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'home/owner_home_content.dart';
import 'home/staff_home_content.dart';
import 'home/management_home_content.dart';
import '../services/services.dart';
import '../models/models.dart';

/// Главный экран: 3 вкладки (Домой, График/Уведомления, Профиль), контент по роли.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

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
    final isManagement = currentEmployee.canViewDepartment('management') && !isOwner;
    final middleLabel = isOwner ? loc.t('notifications') : loc.t('schedule');

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : null,
        title: Text(_appBarTitle(loc, isOwner)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: loc.t('logout'),
          ),
        ],
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
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: loc.t('home'),
          ),
          NavigationDestination(
            icon: Icon(isOwner ? Icons.notifications_none : Icons.calendar_month_outlined),
            selectedIcon: Icon(isOwner ? Icons.notifications : Icons.calendar_month),
            label: middleLabel,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: loc.t('profile'),
          ),
        ],
      ),
    );
  }

  String _appBarTitle(LocalizationService loc, bool isOwner) {
    switch (_selectedIndex) {
      case 0:
        return loc.t('app_name');
      case 1:
        return isOwner ? loc.t('notifications') : loc.t('schedule');
      case 2:
        return loc.t('profile');
      default:
        return loc.t('app_name');
    }
  }

  Widget _buildHomeTab(Employee employee) {
    if (employee.hasRole('owner')) {
      return const OwnerHomeContent();
    }
    if (employee.canViewDepartment('management')) {
      return ManagementHomeContent(employee: employee);
    }
    return StaffHomeContent(employee: employee);
  }

  Widget _buildMiddleTab(Employee employee, bool isOwner, LocalizationService loc) {
    if (isOwner) {
      return _MiddleTabBody(
        icon: Icons.notifications_none,
        title: loc.t('notifications'),
        onTap: () => context.push('/notifications'),
      );
    }
    return _MiddleTabBody(
      icon: Icons.calendar_month,
      title: loc.t('schedule'),
      onTap: () => context.push('/schedule'),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.logout();
    if (context.mounted) context.go('/login');
  }
}

class _MiddleTabBody extends StatelessWidget {
  const _MiddleTabBody({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.open_in_new),
            label: Text(title),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabContent extends StatelessWidget {
  const _ProfileTabContent();

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final establishment = accountManager.establishment;
    final loc = context.watch<LocalizationService>();

    if (employee == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, size: 40, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Text(employee.fullName, style: Theme.of(context).textTheme.titleMedium),
                  Text(employee.email, style: Theme.of(context).textTheme.bodySmall),
                  if (establishment != null) Text(establishment.name, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(loc.t('profile')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/profile'),
          ),
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
