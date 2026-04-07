import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/feature_flags.dart';
import '../../services/services.dart';
import '../../widgets/home_feature_tile.dart';
import '../../services/home_layout_config_service.dart';
import '../../services/screen_layout_preference_service.dart';
import '../../models/models.dart';
import 'expandable_banquet_section.dart';

/// Домашняя страница сотрудника (кухня/бар/зал): график, меню, ТТК, чеклисты.
class StaffHomeContent extends StatelessWidget {
  const StaffHomeContent(
      {super.key, required this.employee, this.tourController});

  final Employee employee;
  final SpotlightController? tourController;

  /// Подразделение для роутов (dining_room -> hall)
  static String _deptForRoute(String d) => d == 'dining_room' ? 'hall' : d;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final subOk = context.watch<AccountManagerSupabase>().hasProSubscription;

    // Без доступа к данным (в т.ч. временный с истёкшим периодом)
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

    final layoutSvc = context.watch<HomeLayoutConfigService>();
    final screenPref = context.watch<ScreenLayoutPreferenceService>();
    final order = layoutSvc.getOrder(employee.id);
    final tiles = <HomeTileId, Widget>{
      HomeTileId.messages: HomeFeatureTile(
        icon: Icons.chat_bubble_outline,
        title: loc.t('inbox_tab_messages') ?? 'Сообщения',
        onTap: () => context.go('/notifications?tab=messages'),
      ),
      HomeTileId.documentation: HomeFeatureTile(
        icon: Icons.description_outlined,
        title: loc.t('documentation') ?? 'Документация',
        onTap: () => context.go('/documentation'),
      ),
      HomeTileId.schedule: HomeFeatureTile(
        icon: Icons.calendar_month,
        title: loc.t('schedule'),
        onTap: () =>
            context.go('/schedule/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.productOrder: HomeFeatureTile(
        icon: Icons.shopping_cart,
        title: loc.t('product_order'),
        onTap: () => context.go(
            '/product-order?department=${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.suppliers: HomeFeatureTile(
        icon: Icons.add_business,
        title:
            loc.t('suppliers') ?? loc.t('order_tab_suppliers') ?? 'Поставщики',
        onTap: () =>
            context.push('/suppliers/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.menu: HomeFeatureTile(
        icon: Icons.restaurant_menu,
        title: loc.t('menu'),
        onTap: () => context.go('/menu/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.ttk: HomeFeatureTile(
        icon: Icons.description,
        title: employee.department == 'bar'
            ? loc.t('ttk_bar')
            : (employee.department == 'hall' ||
                    employee.department == 'dining_room')
                ? loc.t('ttk_hall')
                : loc.t('ttk_kitchen'),
        onTap: () =>
            context.go('/tech-cards/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.checklists: HomeFeatureTile(
        icon: Icons.checklist,
        title: loc.t('checklists'),
        onTap: () => context
            .go('/checklists?department=${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.nomenclature: HomeFeatureTile(
        icon: Icons.assignment,
        title: loc.t('nomenclature'),
        onTap: () =>
            context.go('/nomenclature/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.inventory: HomeFeatureTile(
          icon: Icons.assignment,
          title: loc.t('inventory_blank'),
          subscriptionLocked: !subOk,
          onTap: () => context.push('/inventory')),
      HomeTileId.writeoffs: HomeFeatureTile(
          icon: Icons.remove_circle_outline,
          title: loc.t('writeoffs') ?? 'Списания',
          subscriptionLocked: !subOk,
          onTap: () => context.push('/writeoffs')),
      HomeTileId.hallOrders: HomeFeatureTile(
        icon: Icons.receipt_long,
        title: loc.t('order_tab_orders') ?? 'Заказы',
        onTap: () => context.push('/pos/hall/orders'),
      ),
      HomeTileId.hallCashRegister: HomeFeatureTile(
        icon: Icons.point_of_sale,
        title: loc.t('pos_nav_cash_register') ?? 'Касса',
        onTap: () => context.push('/pos/hall/cash-register'),
      ),
      HomeTileId.hallTables: HomeFeatureTile(
        icon: Icons.table_restaurant,
        title: loc.t('pos_nav_tables') ?? 'Столы',
        onTap: () => context.push('/pos/hall/tables'),
      ),
      HomeTileId.departmentOrders: HomeFeatureTile(
        icon: Icons.receipt_long,
        title: loc.t('order_tab_orders') ?? 'Заказы',
        onTap: () =>
            context.push('/pos/orders/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.departmentSales: HomeFeatureTile(
        icon: Icons.point_of_sale_outlined,
        title: loc.t('sales_title') ?? 'Продажи',
        onTap: () =>
            context.push('/sales/${_deptForRoute(employee.department)}'),
      ),
    };
    final showHallPos =
        employee.department == 'hall' || employee.department == 'dining_room';
    final showDeptOrdersTile =
        employee.department == 'kitchen' || employee.department == 'bar';
    final showDeptSalesTile = showDeptOrdersTile;
    final showChecklists = employee.department == 'kitchen' ||
        employee.department == 'bar' ||
        employee.department == 'dining_room';
    final showNomenclature = employee.department == 'kitchen' ||
        employee.department == 'bar' ||
        employee.department == 'hall' ||
        employee.department == 'dining_room';
    final showSuppliers = employee.department == 'kitchen' ||
        employee.department == 'bar' ||
        employee.department == 'hall' ||
        employee.department == 'dining_room';
    final showBanquet =
        (employee.department == 'kitchen' || employee.department == 'bar') &&
            screenPref.showBanquetCatering;
    // ТТК: кухня, бар, зал — у каждого подразделения свои
    final showTtk = employee.department == 'kitchen' ||
        employee.department == 'bar' ||
        employee.department == 'hall' ||
        employee.department == 'dining_room';
    // Меню: кухня, бар и зал (зал видит stop/go с подсветкой)
    final showMenu = employee.department == 'kitchen' ||
        employee.department == 'bar' ||
        employee.department == 'hall' ||
        employee.department == 'dining_room';
    final ordered = <Widget>[];
    for (final id in order) {
      if (!FeatureFlags.posModuleEnabled &&
          (id == HomeTileId.hallOrders ||
              id == HomeTileId.hallCashRegister ||
              id == HomeTileId.hallTables ||
              id == HomeTileId.departmentOrders ||
              id == HomeTileId.departmentSales)) {
        continue;
      }
      if ((id == HomeTileId.hallOrders ||
              id == HomeTileId.hallCashRegister ||
              id == HomeTileId.hallTables) &&
          !showHallPos) {
        continue;
      }
      if (id == HomeTileId.departmentOrders && !showDeptOrdersTile) continue;
      if (id == HomeTileId.departmentSales && !showDeptSalesTile) continue;
      if (id == HomeTileId.checklists && !showChecklists) continue;
      if (id == HomeTileId.suppliers && !showSuppliers) continue;
      if (id == HomeTileId.menu && !showMenu) continue;
      if (id == HomeTileId.nomenclature && !showNomenclature) continue;
      if ((id == HomeTileId.banquetMenu || id == HomeTileId.banquetTtk) &&
          !showBanquet) continue;
      if (id == HomeTileId.banquetTtk) continue;
      if (id == HomeTileId.ttk && !showTtk) continue;
      if (id == HomeTileId.banquetMenu && showBanquet) {
        ordered.add(ExpandableBanquetSection(
            loc: loc,
            department: employee.department == 'bar' ? 'bar' : 'kitchen'));
        continue;
      }
      if (tiles.containsKey(id)) ordered.add(tiles[id]!);
    }
    final children = tourController != null && ordered.isNotEmpty
        ? [
            SpotlightTarget(
                id: 'home-content',
                controller: tourController!,
                child: ordered.first),
            ...ordered.skip(1),
          ]
        : ordered;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

