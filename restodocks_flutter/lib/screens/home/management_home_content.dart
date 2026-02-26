import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../models/models.dart';

/// Домашняя страница менеджмента (шеф, барменеджер, менеджер зала, управляющий).
class ManagementHomeContent extends StatelessWidget {
  const ManagementHomeContent({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final roles = employee.roles;
    final isChef = roles.contains('executive_chef');
    final isBarManager = roles.contains('bar_manager');
    final isGeneral = roles.contains('general_manager');

    // Без доступа к данным — только личный график (как в личном кабинете)
    if (!employee.hasRole('owner') && !employee.dataAccessEnabled) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Tile(
            icon: Icons.calendar_month,
            title: loc.t('personal_schedule'),
            onTap: () => context.go('/schedule?personal=1'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              loc.t('data_access_required_hint') ?? 'Доступ к остальным разделам выдаёт руководитель.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Tile(icon: Icons.calendar_month, title: loc.t('schedule'), onTap: () => context.go('/schedule')),
        _Tile(icon: Icons.inbox, title: loc.t('inbox'), onTap: () => context.go('/notifications')),
        _Tile(icon: Icons.people, title: loc.t('employees'), onTap: () => context.go('/employees')),
        if (isChef || roles.contains('sous_chef'))
          _Tile(icon: Icons.how_to_reg, title: loc.t('shift_confirmation'), onTap: () => context.go('/shift-confirmation')),
        // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
        if (employee.department == 'kitchen' || isChef || roles.contains('sous_chef'))
          _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists')),
        _Tile(icon: Icons.description, title: isBarManager ? loc.t('ttk_bar') : loc.t('ttk_kitchen'), onTap: () => context.go('/tech-cards')),
        if (isChef)
          _Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature')),
        _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order')),
        _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.go('/inventory')),
        if (isGeneral) ...[
          _Tile(icon: Icons.savings, title: '${loc.t('expenses')} (${loc.t('pro')})', onTap: () => context.go('/expenses')),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
