import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

export '../../utils/pos_order_department.dart' show posDepartmentLabelKeyForRoute;

/// Тип экрана модуля POS / склада / закупки (пока заглушка с локализованным текстом).
enum PosFeature {
  hallOrders,
  hallCashRegister,
  hallTables,
  departmentOrders,
  warehouse,
  procurement,
  warehouseEstablishment,
  ordersDisplaySettings,
}

/// Заглушка раздела зала, подразделений, склада и настроек отображения заказов.
class PosFeaturePlaceholderScreen extends StatelessWidget {
  const PosFeaturePlaceholderScreen({
    super.key,
    required this.feature,
    this.departmentLabelKey,
    this.scopeLabel,
  });

  final PosFeature feature;

  /// Ключ локализации подразделения (kitchen, bar, dining_room) — опционально.
  final String? departmentLabelKey;

  /// Уже переведённая подпись (например «Заведение») — если нужна без ключа.
  final String? scopeLabel;

  String _title(LocalizationService loc) {
    switch (feature) {
      case PosFeature.hallOrders:
        return loc.t('pos_hall_orders_title');
      case PosFeature.hallCashRegister:
        return loc.t('pos_hall_cash_title');
      case PosFeature.hallTables:
        return loc.t('pos_hall_tables_title');
      case PosFeature.departmentOrders:
        return loc.t('pos_department_orders_title');
      case PosFeature.warehouse:
        return loc.t('pos_warehouse_title');
      case PosFeature.procurement:
        return loc.t('pos_procurement_title');
      case PosFeature.warehouseEstablishment:
        return loc.t('pos_warehouse_establishment_title');
      case PosFeature.ordersDisplaySettings:
        return loc.t('pos_orders_display_settings_title');
    }
  }

  String? _subtitle(LocalizationService loc) {
    if (scopeLabel != null && scopeLabel!.isNotEmpty) {
      return scopeLabel;
    }
    if (departmentLabelKey != null) {
      final d = loc.t(departmentLabelKey!);
      if (d.isNotEmpty) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final title = _title(loc);
    final sub = _subtitle(loc);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _icon(feature),
              size: 64,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                sub,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Text(
              loc.t('pos_common_coming_soon'),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(PosFeature f) {
    switch (f) {
      case PosFeature.hallOrders:
      case PosFeature.departmentOrders:
        return Icons.receipt_long;
      case PosFeature.hallCashRegister:
        return Icons.point_of_sale;
      case PosFeature.hallTables:
        return Icons.table_restaurant;
      case PosFeature.warehouse:
      case PosFeature.warehouseEstablishment:
        return Icons.warehouse;
      case PosFeature.procurement:
        return Icons.local_shipping;
      case PosFeature.ordersDisplaySettings:
        return Icons.tune;
    }
  }
}
