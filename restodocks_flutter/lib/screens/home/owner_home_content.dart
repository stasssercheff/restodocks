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
    final account = context.watch<AccountManagerSupabase>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ГРАФИК (все сотрудники)
        _Tile(
          icon: Icons.calendar_month,
          title: loc.t('schedule'),
          subtitle: loc.t('all_employees_schedule'),
          onTap: () => context.push('/schedule'),
        ),

        // ВХОДЯЩИЕ
        _Tile(
          icon: Icons.inbox,
          title: loc.t('inbox'),
          onTap: () => context.push('/notifications'),
        ),

        const SizedBox(height: 16),

        // КУХНЯ
        _SectionTitle(title: loc.t('kitchen')),
        _Tile(
          icon: Icons.schedule,
          title: loc.t('schedule'),
          onTap: () => context.push('/department/kitchen'),
        ),
        _Tile(
          icon: Icons.restaurant_menu,
          title: loc.t('menu'),
          onTap: () => context.push('/products'),
        ),
        _Tile(
          icon: Icons.description,
          title: loc.t('tech_cards'),
          onTap: () => context.push('/tech-cards'),
        ),
        _Tile(
          icon: Icons.assignment,
          title: loc.t('nomenclature'),
          onTap: () => context.push('/nomenclature'),
        ),

        const SizedBox(height: 16),

        // БАР (pro)
        _SectionTitle(title: '${loc.t('bar')} (${loc.t('pro')})'),
        _Tile(
          icon: Icons.schedule,
          title: loc.t('schedule'),
          onTap: () => context.push('/department/bar'),
        ),
        _Tile(
          icon: Icons.wine_bar,
          title: loc.t('menu'),
          onTap: () => context.push('/products'),
        ),
        _Tile(
          icon: Icons.description,
          title: loc.t('tech_cards'),
          onTap: () => context.push('/tech-cards'),
        ),
        _Tile(
          icon: Icons.assignment,
          title: loc.t('nomenclature'),
          subtitle: loc.t('bar_nomenclature'),
          onTap: () => context.push('/nomenclature/bar'),
        ),

        const SizedBox(height: 16),

        // ЗАЛ
        _SectionTitle(title: loc.t('dining_room')),
        _Tile(
          icon: Icons.schedule,
          title: loc.t('schedule'),
          onTap: () => context.push('/department/hall'),
        ),
        _Tile(
          icon: Icons.assignment,
          title: loc.t('nomenclature'),
          subtitle: loc.t('hall_nomenclature'),
          onTap: () => context.push('/nomenclature/hall'),
        ),

        const SizedBox(height: 16),

        // УПРАВЛЕНИЕ
        _SectionTitle(title: loc.t('management')),
        _Tile(
          icon: Icons.people,
          title: loc.t('employees'),
          onTap: () => context.push('/employees'),
        ),

        // РАСХОДЫ (pro)
        _SectionTitle(title: '${loc.t('expenses')} (${loc.t('pro')})'),
        _Tile(
          icon: Icons.payments,
          title: 'ФЗП',
          subtitle: loc.t('salary_expenses'),
          onTap: () => context.push('/expenses/salary'),
        ),
        _Tile(
          icon: Icons.business,
          title: 'Аренда',
          subtitle: loc.t('rent_expenses'),
          onTap: () => context.push('/expenses/rent'),
        ),
        _Tile(
          icon: Icons.shopping_cart,
          title: 'Закупка',
          subtitle: loc.t('purchase_expenses'),
          onTap: () => context.push('/expenses/purchase'),
        ),
        _Tile(
          icon: Icons.settings,
          title: loc.t('custom_expense'),
          subtitle: loc.t('configurable_expense_name'),
          onTap: () => context.push('/expenses/custom'),
        ),

        // ДОПОЛНИТЕЛЬНЫЕ ФУНКЦИИ
        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('additional')),
        _Tile(
          icon: Icons.upload_file,
          title: loc.t('upload_products'),
          onTap: () => context.push('/products/upload'),
        ),
        _Tile(
          icon: Icons.inventory,
          title: loc.t('inventory_blank'),
          onTap: () => context.push('/inventory'),
        ),
        _Tile(
          icon: Icons.checklist,
          title: loc.t('checklists'),
          onTap: () => context.push('/checklists'),
        ),
        _Tile(
          icon: Icons.settings,
          title: loc.t('settings'),
          onTap: () => context.push('/settings'),
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