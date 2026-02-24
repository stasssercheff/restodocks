import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Домашняя страница владельца: график, кухня, бар, зал, менеджмент, уведомления, расходы.
/// Визуал как у менеджмента/сотрудника — Card + ListTile, без цветных плиток.
class OwnerHomeContent extends StatelessWidget {
  const OwnerHomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(title: loc.t('schedule')),
        _Tile(icon: Icons.calendar_month, title: loc.t('schedule'), subtitle: loc.t('all_employees_schedule'), onTap: () => context.push('/schedule')),
        _Tile(icon: Icons.inbox, title: 'Входящие', onTap: () => context.push('/inbox')),

        const SizedBox(height: 16),
        _SectionTitle(title: 'Кухня'),
        _Tile(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/kitchen')),
        _Tile(icon: Icons.restaurant_menu, title: 'Меню', onTap: () => context.push('/menu/kitchen')),
        _Tile(icon: Icons.description, title: 'Технологические карты', onTap: () => context.push('/tech-cards/kitchen')),
        _Tile(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/kitchen')),

        const SizedBox(height: 16),
        _SectionTitle(title: 'Бар (pro)'),
        _Tile(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/bar')),
        _Tile(icon: Icons.wine_bar, title: 'Меню', onTap: () => context.push('/menu/bar')),
        _Tile(icon: Icons.description, title: 'Технологические карты', onTap: () => context.push('/tech-cards/bar')),
        _Tile(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/bar')),

        const SizedBox(height: 16),
        _SectionTitle(title: 'Зал'),
        _Tile(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/hall')),
        _Tile(icon: Icons.assignment, title: 'Номенклатура', onTap: () => context.push('/nomenclature/hall')),

        const SizedBox(height: 16),
        _SectionTitle(title: 'Управление'),
        _Tile(icon: Icons.schedule, title: 'График', onTap: () => context.push('/schedule/management')),
        _Tile(icon: Icons.people, title: 'Сотрудники', onTap: () => context.push('/employees')),

        const SizedBox(height: 16),
        _SectionTitle(title: 'Расходы (pro)'),
        _Tile(icon: Icons.payments, title: 'ФЗП', subtitle: loc.t('salary_expenses'), onTap: () => context.push('/expenses/salary')),
        _Tile(icon: Icons.business, title: 'Аренда', subtitle: loc.t('rent_expenses'), onTap: () => context.push('/expenses/rent')),
        _Tile(icon: Icons.shopping_cart, title: 'Закупка', subtitle: loc.t('purchase_expenses'), onTap: () => context.push('/expenses/purchase')),
        _Tile(icon: Icons.settings, title: loc.t('custom_expense'), subtitle: loc.t('configurable_expense_name'), onTap: () => context.push('/expenses/custom')),
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

/// Такой же вид, как в ManagementHomeContent / StaffHomeContent (вход в учётную запись).
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
