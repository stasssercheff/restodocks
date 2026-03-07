import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../services/screen_layout_preference_service.dart';

/// Домашняя страница владельца: график, кухня, бар, зал, менеджмент, уведомления, расходы.
/// Визуал как у менеджмента/сотрудника — Card + ListTile, без цветных плиток.
class OwnerHomeContent extends StatelessWidget {
  const OwnerHomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final screenPref = context.watch<ScreenLayoutPreferenceService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Управление — сверху: сообщения и входящие
        _SectionTitle(title: loc.t('management')),
        _Tile(icon: Icons.chat_bubble_outline, title: loc.t('inbox_tab_messages') ?? 'Сообщения', onTap: () => context.go('/notifications?tab=messages')),
        _Tile(icon: Icons.inbox, title: loc.t('inbox'), onTap: () => context.go('/inbox')),
        _Tile(icon: Icons.people, title: loc.t('employees'), onTap: () => context.go('/employees')),
        _Tile(icon: Icons.calendar_month, title: loc.t('schedule'), onTap: () => context.go('/schedule/all')),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('kitchen')),
        _Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/kitchen')),
        _Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/kitchen')),
        _Tile(icon: Icons.description, title: loc.t('ttk_kitchen'), onTap: () => context.go('/tech-cards/kitchen')),
        _Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature/kitchen')),
        _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=kitchen')),
        _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=kitchen')),
        _Tile(icon: Icons.store_outlined, title: loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.go('/suppliers/kitchen')),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('bar')),
        _Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/bar')),
        _Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/bar')),
        _Tile(icon: Icons.description, title: loc.t('ttk_bar') ?? 'ТТК бара', onTap: () => context.go('/tech-cards/bar')),
        _Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature/bar')),
        _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=bar')),
        _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=bar')),
        _Tile(icon: Icons.store_outlined, title: loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.go('/suppliers/bar')),

        const SizedBox(height: 16),
        _SectionTitle(title: loc.t('dining_room')),
        _Tile(icon: Icons.schedule, title: loc.t('schedule'), onTap: () => context.go('/schedule/hall')),
        _Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/hall')),
        _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=hall')),
        _Tile(icon: Icons.store_outlined, title: loc.t('order_tab_suppliers') ?? 'Поставщики', onTap: () => context.go('/suppliers/hall')),
        _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=hall')),

        if (screenPref.showBanquetCatering) ...[
          const SizedBox(height: 16),
          _SectionTitle(title: loc.t('banquet_catering') ?? 'Банкет / Кейтринг'),
          _Tile(icon: Icons.restaurant_menu, title: loc.t('menu'), onTap: () => context.go('/menu/banquet-catering')),
          _Tile(icon: Icons.description, title: loc.t('ttk_kitchen'), onTap: () => context.go('/tech-cards/banquet-catering')),
        ],
        const SizedBox(height: 16),
        _SectionTitle(title: '${loc.t('expenses')} (${loc.t('pro')})'),
        _Tile(icon: Icons.payments, title: loc.t('expenses'), subtitle: loc.t('salary_period_hint'), onTap: () => context.go('/expenses')),
        // Аренда, Закупка, Свой вариант — временно скрыты
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
