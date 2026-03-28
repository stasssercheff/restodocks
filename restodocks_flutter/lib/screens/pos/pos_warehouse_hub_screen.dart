import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Склад из POS: переход в модуль остатков (общий по заведению).
class PosWarehouseHubScreen extends StatelessWidget {
  const PosWarehouseHubScreen({super.key, required this.scope});

  /// `kitchen` | `bar` | `hall` | `establishment`
  final String scope;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final isEstablishment = scope == 'establishment';

    late final String title;
    late final String subtitle;
    late final String hintKey;

    if (isEstablishment) {
      title = loc.t('pos_warehouse_establishment_title');
      subtitle = loc.t('pos_warehouse_establishment_section');
      hintKey = 'pos_warehouse_establishment_hub_hint';
    } else {
      title = loc.t('pos_warehouse_title');
      final dept = (scope == 'kitchen' || scope == 'bar' || scope == 'hall')
          ? scope
          : 'kitchen';
      final deptKey = posDepartmentLabelKeyForRoute(dept);
      subtitle = deptKey != null ? loc.t(deptKey) : dept;
      hintKey = 'pos_warehouse_hub_hint';
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t(hintKey),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/inventory'),
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(loc.t('pos_warehouse_open_inventory')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/pos/stock'),
              icon: const Icon(Icons.table_chart_outlined),
              label: Text(loc.t('pos_stock_open_movements')),
            ),
          ],
        ),
      ),
    );
  }
}
