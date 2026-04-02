import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../services/screen_layout_preference_service.dart';
import '../../models/models.dart';
import '../../core/feature_flags.dart';
import '../../utils/pos_hall_permissions.dart';
import 'expandable_banquet_section.dart';

/// Домашняя страница менеджмента (шеф, барменеджер, менеджер зала, управляющий).
/// Каждый видит только данные своего отдела.
class ManagementHomeContent extends StatelessWidget {
  const ManagementHomeContent(
      {super.key, required this.employee, this.tourController});

  final Employee employee;
  final SpotlightController? tourController;

  /// Подразделение для роутов (dining_room -> hall, management -> kitchen для шефа)
  static String _deptForRoute(String d) =>
      d == 'dining_room' ? 'hall' : (d == 'management' ? 'kitchen' : d);

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final screenPref = context.watch<ScreenLayoutPreferenceService>();
    final roles = employee.roles;
    final isChef = roles.contains('executive_chef');
    final isBarManager = roles.contains('bar_manager');
    final isGeneral = roles.contains('general_manager');
    final isFloorManager = roles.contains('floor_manager');
    final dept = _deptForRoute(employee.department);
    // ТТК: кухня, бар, зал — у каждого подразделения свои
    final showTtk = dept == 'kitchen' || dept == 'bar' || dept == 'hall';
    // Меню: только кухня и бар (у зала нет меню)
    final showMenu = dept == 'kitchen' || dept == 'bar';
    // Номенклатура: шеф, барменеджер, менеджер зала, управляющий — своя подразделения
    final showNomenclature = (isChef ||
            roles.contains('sous_chef') ||
            isBarManager ||
            isFloorManager ||
            isGeneral) &&
        showTtk;

    // Без доступа к данным
    if (!employee.hasRole('owner') && !employee.effectiveDataAccess) {
      final firstTile = _Tile(
        icon: Icons.calendar_month,
        title: loc.t('personal_schedule'),
        onTap: () => context.go('/schedule?personal=1'),
      );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (tourController != null)
            SpotlightTarget(
                id: 'home-content',
                controller: tourController!,
                child: firstTile)
          else
            firstTile,
          _Tile(
            icon: Icons.chat_bubble_outline,
            title: loc.t('inbox_tab_messages') ?? 'Сообщения',
            onTap: () => context.go('/notifications?tab=messages'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              loc.t('data_access_required_hint') ??
                  'Доступ к остальным разделам выдаёт руководитель.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final firstTile = _Tile(
        icon: Icons.calendar_month,
        title: loc.t('schedule'),
        onTap: () =>
            context.go('/schedule/${_deptForRoute(employee.department)}'));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tourController != null)
          SpotlightTarget(
              id: 'home-content', controller: tourController!, child: firstTile)
        else
          firstTile,
        _Tile(
            icon: Icons.description_outlined,
            title: loc.t('documentation') ?? 'Документация',
            onTap: () => context.go('/documentation')),
        _Tile(
            icon: Icons.assignment,
            title: loc.t('haccp_journals') ?? 'Журналы и ХАССП',
            onTap: () => context.go('/haccp-journals')),
        _Tile(
            icon: Icons.chat_bubble_outline,
            title: loc.t('inbox_tab_messages') ?? 'Сообщения',
            onTap: () => context.go('/notifications?tab=messages')),
        _Tile(
            icon: Icons.inbox,
            title: loc.t('inbox'),
            onTap: () => context.go('/inbox')),
        _Tile(
            icon: Icons.people,
            title: loc.t('employees'),
            onTap: () => context.go('/employees')),
        // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
        if (employee.department == 'kitchen' ||
            isChef ||
            roles.contains('sous_chef') ||
            employee.department == 'bar' ||
            employee.department == 'dining_room')
          _Tile(
              icon: Icons.checklist,
              title: loc.t('checklists'),
              onTap: () => context.go(
                  '/checklists?department=${_deptForRoute(employee.department)}')),
        if (showMenu)
          _Tile(
              icon: Icons.restaurant_menu,
              title: loc.t('menu'),
              onTap: () => context.go('/menu/$dept')),
        if (showTtk)
          _Tile(
            icon: Icons.description,
            title: dept == 'bar'
                ? loc.t('ttk_bar')
                : (dept == 'hall' ? loc.t('ttk_hall') : loc.t('ttk_kitchen')),
            onTap: () => context.go('/tech-cards/$dept'),
          ),
        if (showNomenclature)
          _Tile(
              icon: Icons.assignment,
              title: loc.t('nomenclature'),
              onTap: () => context.go('/nomenclature/$dept')),
        _Tile(
            icon: Icons.add_business,
            title: loc.t('suppliers') ??
                loc.t('order_tab_suppliers') ??
                'Поставщики',
            onTap: () => context.push('/suppliers/$dept')),
        _Tile(
            icon: Icons.shopping_cart,
            title: loc.t('product_order'),
            onTap: () => context.go(
                '/product-order?department=${_deptForRoute(employee.department)}')),
        if (FeatureFlags.posModuleEnabled && dept == 'hall') ...[
          _Tile(
            icon: Icons.receipt_long,
            title: loc.t('order_tab_orders') ?? 'Заказы',
            onTap: () => context.push('/pos/hall/orders'),
          ),
          _Tile(
            icon: Icons.point_of_sale,
            title: loc.t('pos_nav_cash_register') ?? 'Касса',
            onTap: () => context.push('/pos/hall/cash-register'),
          ),
          _Tile(
            icon: Icons.table_restaurant,
            title: loc.t('pos_nav_tables') ?? 'Столы',
            onTap: () => context.push('/pos/hall/tables'),
          ),
          if (posCanViewPosShiftReport(employee))
            _Tile(
              icon: Icons.summarize_outlined,
              title: loc.t('pos_shift_report_title'),
              onTap: () => context.push('/pos/shift-report'),
            ),
        ],
        if (FeatureFlags.posModuleEnabled && (dept == 'kitchen' || dept == 'bar')) ...[
          _Tile(
            icon: Icons.receipt_long,
            title: loc.t('order_tab_orders') ?? 'Заказы',
            onTap: () => context.push('/pos/orders/$dept'),
          ),
          _Tile(
            icon: Icons.point_of_sale_outlined,
            title: loc.t('sales_title') ?? 'Продажи',
            onTap: () => context.push('/sales/$dept'),
          ),
          _Tile(
            icon: Icons.tv_outlined,
            title: loc.t('pos_kds_title'),
            subtitle: loc.t('pos_kds_hint'),
            onTap: () => context.push('/pos/kds/$dept'),
          ),
        ],
        if (FeatureFlags.posModuleEnabled) ...[
          _Tile(
            icon: Icons.warehouse,
            title: loc.t('pos_nav_warehouse') ?? 'Склад',
            onTap: () => context.push('/pos/warehouse/$dept'),
          ),
          _Tile(
            icon: Icons.local_shipping,
            title: loc.t('pos_nav_procurement') ?? 'Закупка',
            onTap: () => context.push('/pos/procurement/$dept'),
          ),
        ],
        _Tile(
            icon: Icons.assignment,
            title: loc.t('inventory_blank'),
            onTap: () => context.push('/inventory')),
        _Tile(
            icon: Icons.remove_circle_outline,
            title: loc.t('writeoffs') ?? 'Списания',
            onTap: () => context.push('/writeoffs')),
        if ((isChef || roles.contains('sous_chef')) &&
            screenPref.showBanquetCatering) ...[
          const SizedBox(height: 8),
          ExpandableBanquetSection(loc: loc, department: 'kitchen'),
        ],
        if (isBarManager && screenPref.showBanquetCatering) ...[
          const SizedBox(height: 8),
          ExpandableBanquetSection(loc: loc, department: 'bar'),
        ],
        if (isGeneral) ...[
          _Tile(
              icon: Icons.savings,
              title: '${loc.t('expenses')} (${loc.t('pro')})',
              onTap: () => context.go('/expenses')),
        ],
        // ФЗП подразделения для руководителей: шеф/су-шеф (кухня), менеджер зала (зал), барменеджер (бар)
        if ((isChef || roles.contains('sous_chef')) && !isGeneral)
          _Tile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              onTap: () => context.go('/expenses/salary?department=kitchen')),
        if (roles.contains('floor_manager') && !isGeneral)
          _Tile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              onTap: () => context.go('/expenses/salary?department=hall')),
        if (isBarManager && !isGeneral)
          _Tile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              onTap: () => context.go('/expenses/salary?department=bar')),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.onTap});

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
