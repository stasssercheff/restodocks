import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../models/models.dart';

/// Домашняя страница сотрудника (кухня/бар/зал): график, меню, ТТК, чеклисты.
class StaffHomeContent extends StatelessWidget {
  const StaffHomeContent({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Tile(
          icon: Icons.calendar_month,
          title: loc.t('schedule'),
          onTap: () => context.push('/schedule'),
        ),
        _Tile(icon: Icons.inventory_2, title: loc.t('nomenclature'), onTap: () => context.push('/products')),
        _Tile(icon: Icons.library_books, title: loc.t('product_catalog'), onTap: () => context.push('/products/catalog')),
        _Tile(icon: Icons.upload_file, title: loc.t('upload_products'), onTap: () => context.push('/products/upload')),
        _Tile(
          icon: Icons.restaurant_menu,
          title: loc.t('menu'),
          onTap: () => context.push('/products'),
        ),
        _Tile(
          icon: Icons.description,
          title: employee.department == 'bar' ? loc.t('ttk_bar') : loc.t('ttk_kitchen'),
          onTap: () => context.push('/tech-cards'),
        ),
        if (employee.department == 'kitchen') ...[
          _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.push('/checklists')),
          _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.push('/inventory')),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
