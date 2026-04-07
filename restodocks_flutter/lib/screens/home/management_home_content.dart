import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../services/screen_layout_preference_service.dart';
import '../../models/models.dart';
import '../../core/feature_flags.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/home_feature_tile.dart';
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
    final subOk = context.watch<AccountManagerSupabase>().hasProSubscription;
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
      final firstTile = HomeFeatureTile(
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
          HomeFeatureTile(
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

    final firstTile = HomeFeatureTile(
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
        HomeFeatureTile(
            icon: Icons.description_outlined,
            title: loc.t('documentation') ?? 'Документация',
            onTap: () => context.go('/documentation')),
        HomeFeatureTile(
            icon: Icons.assignment,
            title: loc.t('haccp_journals') ?? 'Журналы и ХАССП',
            subscriptionLocked: !subOk,
            onTap: () => context.go('/haccp-journals')),
        HomeFeatureTile(
            icon: Icons.chat_bubble_outline,
            title: loc.t('inbox_tab_messages') ?? 'Сообщения',
            onTap: () => context.go('/notifications?tab=messages')),
        HomeFeatureTile(
            icon: Icons.inbox,
            title: loc.t('inbox'),
            onTap: () => context.go('/inbox')),
        HomeFeatureTile(
            icon: Icons.people,
            title: loc.t('employees'),
            onTap: () => context.go('/employees')),
        // Чеклисты: кухня или шеф/су-шеф (у шефа часто отдел «Управление» — иначе плитки нет)
        if (employee.department == 'kitchen' ||
            isChef ||
            roles.contains('sous_chef') ||
            employee.department == 'bar' ||
            employee.department == 'dining_room')
          HomeFeatureTile(
              icon: Icons.checklist,
              title: loc.t('checklists'),
              onTap: () => context.go(
                  '/checklists?department=${_deptForRoute(employee.department)}')),
        if (showMenu)
          HomeFeatureTile(
              icon: Icons.restaurant_menu,
              title: loc.t('menu'),
              onTap: () => context.go('/menu/$dept')),
        if (showTtk)
          HomeFeatureTile(
            icon: Icons.description,
            title: dept == 'bar'
                ? loc.t('ttk_bar')
                : (dept == 'hall' ? loc.t('ttk_hall') : loc.t('ttk_kitchen')),
            onTap: () => context.go('/tech-cards/$dept'),
          ),
        if (showNomenclature)
          HomeFeatureTile(
              icon: Icons.assignment,
              title: loc.t('nomenclature'),
              onTap: () => context.go('/nomenclature/$dept')),
        if (!FeatureFlags.posModuleEnabled) ...[
          HomeFeatureTile(
            icon: Icons.local_shipping,
            title: loc.t('pos_nav_procurement') ?? 'Закупка',
            onTap: () => context.push('/procurement/$dept'),
          ),
        ],
        if (FeatureFlags.posModuleEnabled && dept == 'hall') ...[
          HomeFeatureTile(
            icon: Icons.receipt_long,
            title: loc.t('order_tab_orders') ?? 'Заказы',
            onTap: () => context.push('/pos/hall/orders'),
          ),
          HomeFeatureTile(
            icon: Icons.point_of_sale,
            title: loc.t('pos_nav_cash_register') ?? 'Касса',
            onTap: () => context.push('/pos/hall/cash-register'),
          ),
          HomeFeatureTile(
            icon: Icons.table_restaurant,
            title: loc.t('pos_nav_tables') ?? 'Столы',
            onTap: () => context.push('/pos/hall/tables'),
          ),
          if (posCanViewPosShiftReport(employee))
            HomeFeatureTile(
              icon: Icons.summarize_outlined,
              title: loc.t('pos_shift_report_title'),
              onTap: () => context.push('/pos/shift-report'),
            ),
        ],
        if (FeatureFlags.posModuleEnabled && (dept == 'kitchen' || dept == 'bar')) ...[
          HomeFeatureTile(
            icon: Icons.receipt_long,
            title: loc.t('order_tab_orders') ?? 'Заказы',
            onTap: () => context.push('/pos/orders/$dept'),
          ),
          HomeFeatureTile(
            icon: Icons.point_of_sale_outlined,
            title: loc.t('sales_title') ?? 'Продажи',
            onTap: () => context.push('/sales/$dept'),
          ),
          HomeFeatureTile(
            icon: Icons.tv_outlined,
            title: loc.t('pos_kds_title'),
            subtitle: loc.t('pos_kds_hint'),
            onTap: () => context.push('/pos/kds/$dept'),
          ),
        ],
        if (FeatureFlags.posModuleEnabled) ...[
          HomeFeatureTile(
            icon: Icons.warehouse,
            title: loc.t('pos_nav_warehouse') ?? 'Склад',
            onTap: () => context.push('/pos/warehouse/$dept'),
          ),
          HomeFeatureTile(
            icon: Icons.local_shipping,
            title: loc.t('pos_nav_procurement') ?? 'Закупка',
            onTap: () => context.push('/pos/procurement/$dept'),
          ),
          HomeFeatureTile(
            icon: Icons.dashboard_customize_outlined,
            title: loc.t('pos_operations_hub_title'),
            subtitle: loc.t('pos_operations_hub_hint'),
            onTap: () => context.push('/pos/operations/$dept'),
          ),
        ],
        HomeFeatureTile(
            icon: Icons.assignment,
            title: loc.t('inventory_blank'),
            subscriptionLocked: !subOk,
            onTap: () => context.push('/inventory')),
        HomeFeatureTile(
            icon: Icons.remove_circle_outline,
            title: loc.t('writeoffs') ?? 'Списания',
            subscriptionLocked: !subOk,
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
          HomeFeatureTile(
              icon: Icons.savings,
              title: loc.t('expenses'),
              subscriptionLocked: !subOk,
              onTap: () => context.go('/expenses')),
        ],
        // ФЗП подразделения для руководителей: шеф/су-шеф (кухня), менеджер зала (зал), барменеджер (бар)
        if ((isChef || roles.contains('sous_chef')) && !isGeneral)
          HomeFeatureTile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              subscriptionLocked: !subOk,
              onTap: () => context.go('/expenses/salary?department=kitchen')),
        if (roles.contains('floor_manager') && !isGeneral)
          HomeFeatureTile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              subscriptionLocked: !subOk,
              onTap: () => context.go('/expenses/salary?department=hall')),
        if (isBarManager && !isGeneral)
          HomeFeatureTile(
              icon: Icons.payments,
              title: loc.t('salary_tab_fzp') ?? 'ФЗП',
              subscriptionLocked: !subOk,
              onTap: () => context.go('/expenses/salary?department=bar')),
      ],
    );
  }
}
