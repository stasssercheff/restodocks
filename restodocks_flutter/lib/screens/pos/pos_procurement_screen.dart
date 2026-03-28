import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Закупка из POS: переход к спискам заказа поставщикам по подразделению.
class PosProcurementScreen extends StatelessWidget {
  const PosProcurementScreen({super.key, required this.department});

  final String department;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dept = (department == 'kitchen' || department == 'bar' || department == 'hall')
        ? department
        : 'kitchen';
    final deptKey = posDepartmentLabelKeyForRoute(dept);
    final deptLabel = deptKey != null ? loc.t(deptKey) : dept;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('pos_procurement_title')),
            Text(
              deptLabel,
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
              loc.t('pos_procurement_hub_hint'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  context.push('/product-order?department=$dept'),
              icon: const Icon(Icons.playlist_add_check),
              label: Text(loc.t('pos_procurement_open_order_lists')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('/product-order/new?department=$dept'),
              icon: const Icon(Icons.add_business_outlined),
              label: Text(loc.t('pos_procurement_new_supplier_order')),
            ),
          ],
        ),
      ),
    );
  }
}
