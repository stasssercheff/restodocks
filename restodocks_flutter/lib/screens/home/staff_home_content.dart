import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../services/home_layout_config_service.dart';
import '../../models/models.dart';

/// Домашняя страница сотрудника (кухня/бар/зал): график, меню, ТТК, чеклисты.
class StaffHomeContent extends StatelessWidget {
  const StaffHomeContent({super.key, required this.employee});

  final Employee employee;

  /// Подразделение для роутов (dining_room -> hall)
  static String _deptForRoute(String d) => d == 'dining_room' ? 'hall' : d;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    // Без доступа к данным (в т.ч. временный с истёкшим периодом)
    if (!employee.hasRole('owner') && !employee.effectiveDataAccess) {
      // Сотрудник в цехе (кухня): только график общий и сообщения
      if (employee.department == 'kitchen') {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Tile(
              icon: Icons.calendar_month,
              title: loc.t('schedule'),
              onTap: () => context.go('/schedule'),
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
      // Бар/зал: только личный график
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

    final layoutSvc = context.watch<HomeLayoutConfigService>();
    final order = layoutSvc.getOrder(employee.id);
    final tiles = <HomeTileId, Widget>{
      HomeTileId.messages: _Tile(
        icon: Icons.chat_bubble_outline,
        title: loc.t('inbox_tab_messages') ?? 'Сообщения',
        onTap: () => context.go('/notifications'),
      ),
      HomeTileId.schedule: _Tile(
        icon: Icons.calendar_month,
        title: loc.t('schedule'),
        onTap: () => context.go('/schedule'),
      ),
      HomeTileId.productOrder: _Tile(
        icon: Icons.shopping_cart,
        title: loc.t('product_order'),
        onTap: () => context.go('/product-order?department=${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.suppliers: _Tile(
        icon: Icons.store_outlined,
        title: loc.t('order_tab_suppliers') ?? 'Поставщики',
        onTap: () => context.go('/suppliers/${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.menu: _Tile(
        icon: Icons.restaurant_menu,
        title: loc.t('menu'),
        onTap: () => context.go('/menu/${employee.department}'),
      ),
      HomeTileId.ttk: _Tile(
        icon: Icons.description,
        title: employee.department == 'bar' ? loc.t('ttk_bar') : loc.t('ttk_kitchen'),
        onTap: () => context.go('/tech-cards'),
      ),
      HomeTileId.banquetMenu: _Tile(
        icon: Icons.restaurant_menu,
        title: '${loc.t('menu')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
        onTap: () => context.go('/menu/banquet-catering'),
      ),
      HomeTileId.banquetTtk: _Tile(
        icon: Icons.description,
        title: '${loc.t('ttk_kitchen')} — ${loc.t('banquet_catering') ?? 'Банкет / Кейтринг'}',
        onTap: () => context.go('/tech-cards/banquet-catering'),
      ),
      HomeTileId.checklists: _Tile(
        icon: Icons.checklist,
        title: loc.t('checklists'),
        onTap: () => context.go('/checklists?department=${_deptForRoute(employee.department)}'),
      ),
      HomeTileId.inventory: _Tile(icon: Icons.assignment, title: loc.t('inventory_blank'), onTap: () => context.push('/inventory')),
    };
    final showChecklists = employee.department == 'kitchen' || employee.department == 'bar' || employee.department == 'dining_room';
    final showBanquet = employee.department == 'kitchen';
    final ordered = order
        .where((id) => id != HomeTileId.checklists || showChecklists)
        .where((id) => (id != HomeTileId.banquetMenu && id != HomeTileId.banquetTtk) || showBanquet)
        .where((id) => tiles.containsKey(id))
        .map((id) => tiles[id]!)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: ordered,
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
