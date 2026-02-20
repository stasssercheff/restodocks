import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Входящие: Подтверждение смен, Инвентаризация, Заказ продуктов
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inbox')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InboxTile(
            icon: Icons.how_to_reg,
            title: loc.t('shift_confirmation'),
            onTap: () => context.push('/shift-confirmation'),
          ),
          _InboxTile(
            icon: Icons.assignment,
            title: loc.t('inventory_received'),
            onTap: () => context.push('/inventory-received'),
          ),
          _InboxTile(
            icon: Icons.shopping_cart,
            title: loc.t('product_order'),
            onTap: () => context.push('/product-order-received'),
          ),
          _InboxTile(
            icon: Icons.checklist,
            title: loc.t('checklist_received'),
            onTap: () => context.push('/checklists-received'),
          ),
        ],
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({
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
