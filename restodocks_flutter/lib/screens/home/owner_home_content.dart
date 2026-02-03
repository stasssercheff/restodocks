import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Домашняя страница владельца: график, кухня, бар, зал, менеджмент, уведомления, расходы.
class OwnerHomeContent extends StatelessWidget {
  const OwnerHomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: loc.t('schedule')),
        _Tile(
          icon: Icons.calendar_month,
          title: loc.t('schedule'),
          subtitle: loc.t('manage_schedule'),
          onTap: () => context.push('/schedule'),
        ),
        _Tile(icon: Icons.description, title: loc.t('tech_cards'), onTap: () => context.push('/tech-cards')),
        _Tile(icon: Icons.inventory_2, title: loc.t('nomenclature'), onTap: () => context.push('/products')),
        _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.push('/inventory')),
        _Tile(icon: Icons.restaurant_menu, title: loc.t('inventory_pf_blank'), onTap: () => context.push('/inventory-pf')),
        const SizedBox(height: 20),
        _SectionTitle(title: loc.t('kitchen')),
        _Tile(
          icon: Icons.restaurant,
          title: loc.t('schedule'),
          subtitle: loc.t('payroll_kitchen'),
          onTap: () => context.push('/department/kitchen'),
        ),
        _Tile(
          icon: Icons.restaurant_menu,
          title: loc.t('dish_cards'),
          onTap: () => context.push('/products'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: loc.t('bar')),
        _Tile(
          icon: Icons.local_bar,
          title: loc.t('schedule'),
          subtitle: loc.t('payroll_bar'),
          onTap: () => context.push('/department/bar'),
        ),
        _Tile(
          icon: Icons.wine_bar,
          title: loc.t('drink_cards'),
          onTap: () => context.push('/products'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: loc.t('dining_room')),
        _Tile(
          icon: Icons.table_restaurant,
          title: loc.t('schedule'),
          subtitle: loc.t('payroll_hall'),
          onTap: () => context.push('/department/hall'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: loc.t('management')),
        _Tile(
          icon: Icons.admin_panel_settings,
          title: loc.t('schedule'),
          subtitle: loc.t('payroll_management'),
          onTap: () => context.push('/department/management'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: loc.t('notifications')),
        _Tile(
          icon: Icons.notifications,
          title: loc.t('notifications'),
          onTap: () => context.push('/notifications'),
        ),
        const SizedBox(height: 20),
        _SectionTitle(title: '${loc.t('expenses')} (${loc.t('pro')})'),
        _Tile(
          icon: Icons.savings,
          title: loc.t('expenses'),
          subtitle: '${loc.t('payroll_plan')}, ${loc.t('rent_plan')}, ...',
          onTap: () => context.push('/expenses'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

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
