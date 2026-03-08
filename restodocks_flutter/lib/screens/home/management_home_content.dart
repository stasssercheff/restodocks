import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../services/screen_layout_preference_service.dart';
import '../../models/models.dart';

/// Домашняя страница менеджмента (шеф, барменеджер, менеджер зала, управляющий).
/// Каждый видит только данные своего отдела.
class ManagementHomeContent extends StatelessWidget {
  const ManagementHomeContent({super.key, required this.employee});

  final Employee employee;

  /// Подразделение для роутов (dining_room -> hall, management -> kitchen для шефа)
  static String _deptForRoute(String d) => d == 'dining_room' ? 'hall' : (d == 'management' ? 'kitchen' : d);

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final screenPref = context.watch<ScreenLayoutPreferenceService>();
    final roles = employee.roles;
    final isChef = roles.contains('executive_chef');
    final isBarManager = roles.contains('bar_manager');
    final isGeneral = roles.contains('general_manager');

    // Без доступа к данным
    if (!employee.hasRole('owner') && !employee.effectiveDataAccess) {
      // Сотрудник в цехе (кухня): только график общий и сообщения
      if (employee.department == 'kitchen') {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Tile(
              icon: Icons.calendar_month,
              title: loc.t('schedule'),
              onTap: () => context.go('/schedule/${_deptForRoute(employee.department)}'),
            ),
            _Tile(
              icon: Icons.chat_bubble_outline,
              title: loc.t('inbox_tab_messages') ?? 'Сообщения',
              onTap: () => context.go('/notifications?tab=messages'),
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
      // Менеджмент не кухня: только личный график
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
        _Tile(icon: Icons.calendar_month, title: loc.t('schedule'), onTap: () => context.go('/schedule/${_deptForRoute(employee.department)}')),
        _Tile(icon: Icons.chat_bubble_outline, title: loc.t('inbox_tab_messages') ?? 'Сообщения', onTap: () => context.go('/notifications?tab=messages')),
        _Tile(icon: Icons.inbox, title: loc.t('inbox'), onTap: () => context.go('/inbox')),
        _Tile(icon: Icons.people, title: loc.t('employees'), onTap: () => context.go('/employees')),
        // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
        if (employee.department == 'kitchen' || isChef || roles.contains('sous_chef') || employee.department == 'bar' || employee.department == 'dining_room')
          _Tile(icon: Icons.checklist, title: loc.t('checklists'), onTap: () => context.go('/checklists?department=${_deptForRoute(employee.department)}')),
        if (employee.department != 'dining_room' && employee.department != 'hall')
          _Tile(icon: Icons.description, title: isBarManager ? loc.t('ttk_bar') : loc.t('ttk_kitchen'), onTap: () => context.go('/tech-cards/${_deptForRoute(employee.department)}')),
        if (isChef)
          _Tile(icon: Icons.assignment, title: loc.t('nomenclature'), onTap: () => context.go('/nomenclature/${_deptForRoute(employee.department)}')),
        _Tile(icon: Icons.shopping_cart, title: loc.t('product_order'), onTap: () => context.go('/product-order?department=${_deptForRoute(employee.department)}')),
        _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.push('/inventory')),
        if ((isChef || roles.contains('sous_chef')) && screenPref.showBanquetCatering) ...[
          const SizedBox(height: 8),
          _ExpandableBanquetSection(loc: loc),
        ],
        if (isGeneral) ...[
          _Tile(icon: Icons.savings, title: '${loc.t('expenses')} (${loc.t('pro')})', onTap: () => context.go('/expenses')),
        ],
        // ФЗП подразделения для руководителей: шеф/су-шеф (кухня), менеджер зала (зал), барменеджер (бар)
        if ((isChef || roles.contains('sous_chef')) && !isGeneral)
          _Tile(icon: Icons.payments, title: loc.t('salary_tab_fzp') ?? 'ФЗП', onTap: () => context.go('/expenses/salary?department=kitchen')),
        if (roles.contains('floor_manager') && !isGeneral)
          _Tile(icon: Icons.payments, title: loc.t('salary_tab_fzp') ?? 'ФЗП', onTap: () => context.go('/expenses/salary?department=hall')),
        if (isBarManager && !isGeneral)
          _Tile(icon: Icons.payments, title: loc.t('salary_tab_fzp') ?? 'ФЗП', onTap: () => context.go('/expenses/salary?department=bar')),
      ],
    );
  }
}

/// Выдвижная секция «Банкет / Кейтринг» — кнопка в стиле остальных, внутри Меню и ТТК.
class _ExpandableBanquetSection extends StatelessWidget {
  const _ExpandableBanquetSection({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.celebration),
        title: Text(loc.t('banquet_catering') ?? 'Банкет / Кейтринг'),
        trailing: const Icon(Icons.chevron_right),
        children: [
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: Text(loc.t('menu')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go('/menu/banquet-catering'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(loc.t('ttk_kitchen')),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => context.go('/tech-cards/banquet-catering'),
          ),
        ],
      ),
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
