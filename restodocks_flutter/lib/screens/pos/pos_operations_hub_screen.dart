import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Единая точка входа: столы (зал), заказы, склад, закупка и смежные экраны POS.
class PosOperationsHubScreen extends StatelessWidget {
  const PosOperationsHubScreen({super.key, required this.department});

  final String department;

  String _normalizeDept() {
    final d = department.toLowerCase();
    if (d == 'kitchen' ||
        d == 'bar' ||
        d == 'hall' ||
        d == 'establishment') {
      return d;
    }
    return 'kitchen';
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dept = _normalizeDept();
    final String deptLabel;
    if (dept == 'establishment') {
      deptLabel = loc.t('pos_warehouse_establishment_section');
    } else {
      final deptKey = posDepartmentLabelKeyForRoute(dept);
      deptLabel = deptKey != null ? loc.t(deptKey) : dept;
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('pos_operations_hub_title')),
            Text(
              deptLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            dept == 'establishment'
                ? loc.t('pos_warehouse_establishment_hub_hint')
                : loc.t('pos_operations_hub_hint'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          if (dept == 'establishment') ...[
            _OpTile(
              icon: Icons.warehouse,
              title: loc.t('pos_warehouse_establishment_title'),
              onTap: () => context.push('/pos/warehouse/establishment'),
            ),
            _OpTile(
              icon: Icons.inventory_2_outlined,
              title: loc.t('pos_stock_title'),
              onTap: () => context.push('/pos/stock'),
            ),
          ] else if (dept == 'hall') ...[
            _OpTile(
              icon: Icons.table_restaurant,
              title: loc.t('pos_nav_tables'),
              onTap: () => context.push('/pos/hall/tables'),
            ),
            _OpTile(
              icon: Icons.receipt_long,
              title: loc.t('order_tab_orders'),
              onTap: () => context.push('/pos/hall/orders'),
            ),
            _OpTile(
              icon: Icons.point_of_sale,
              title: loc.t('pos_nav_cash_register'),
              onTap: () => context.push('/pos/hall/cash-register'),
            ),
            _OpTile(
              icon: Icons.history,
              title: loc.t('pos_order_history_title'),
              onTap: () => context.push('/pos/hall/order-history'),
            ),
          ] else ...[
            _OpTile(
              icon: Icons.receipt_long,
              title: loc.t('order_tab_orders'),
              onTap: () => context.push('/pos/orders/$dept'),
            ),
            _OpTile(
              icon: Icons.point_of_sale_outlined,
              title: loc.t('sales_title'),
              onTap: () => context.push('/sales/$dept'),
            ),
            _OpTile(
              icon: Icons.tv_outlined,
              title: loc.t('pos_kds_title'),
              subtitle: loc.t('pos_kds_hint'),
              onTap: () => context.push('/pos/kds/$dept'),
            ),
          ],
          if (dept != 'establishment') ...[
            _OpTile(
              icon: Icons.warehouse_outlined,
              title: loc.t('pos_warehouse_title'),
              subtitle: loc.t('pos_stock_open_movements'),
              onTap: () => context.push('/pos/warehouse/$dept'),
            ),
            _OpTile(
              icon: Icons.inventory_2_outlined,
              title: loc.t('pos_stock_title'),
              onTap: () => context.push('/pos/stock'),
            ),
            _OpTile(
              icon: Icons.local_shipping_outlined,
              title: loc.t('pos_procurement_title'),
              onTap: () => context.push('/pos/procurement/$dept'),
            ),
            _OpTile(
              icon: Icons.playlist_add_check_outlined,
              title: loc.t('pos_procurement_open_order_lists'),
              onTap: () => context.push('/product-order?department=$dept'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpTile extends StatelessWidget {
  const _OpTile({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis)
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
