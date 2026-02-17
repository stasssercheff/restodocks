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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Tile(icon: Icons.calendar_month, title: loc.t('schedule'), onTap: () => context.push('/schedule')),
        _Tile(icon: Icons.notifications, title: loc.t('notifications'), onTap: () => context.push('/notifications')),
        _Tile(icon: Icons.people, title: loc.t('employees'), onTap: () => context.push('/employees')),
        if (isChef || roles.contains('sous_chef'))
          _Tile(icon: Icons.how_to_reg, title: loc.t('shift_confirmation'), onTap: () => context.push('/shift-confirmation')),
        if (isChef) _Tile(icon: Icons.shopping_bag, title: loc.t('products'), onTap: () => context.push('/products')),
        // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
        if (employee.department == 'kitchen' || isChef || roles.contains('sous_chef'))
          _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.push('/checklists')),
        _Tile(icon: Icons.description, title: isBarManager ? loc.t('ttk_bar') : loc.t('ttk_kitchen'), onTap: () => context.push('/tech-cards')),
        _Tile(icon: Icons.inventory_2, title: loc.t('nomenclature'), onTap: () => context.push('/products')),
        _Tile(icon: Icons.library_books, title: loc.t('product_catalog'), onTap: () => context.push('/products/catalog')),
        if (isChef || isBarManager)
          _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.push('/product-order')),
        if (isChef) ...[
          _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.push('/inventory')),
          _Tile(icon: Icons.inbox, title: loc.t('inventory_received'), onTap: () => context.push('/inventory-received')),
        ],
        if (isGeneral) ...[
          _Tile(icon: Icons.savings, title: '${loc.t('expenses')} (${loc.t('pro')})', onTap: () => context.push('/expenses')),
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
