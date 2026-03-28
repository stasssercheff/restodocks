import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

/// Карточка заказа зала (позиции меню — в следующих итерациях).
class HallOrderDetailScreen extends StatelessWidget {
  const HallOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  String _statusLabel(LocalizationService loc, PosOrderStatus s) {
    switch (s) {
      case PosOrderStatus.draft:
        return loc.t('pos_order_status_draft');
      case PosOrderStatus.sent:
        return loc.t('pos_order_status_sent');
      case PosOrderStatus.closed:
        return loc.t('pos_order_status_closed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lc = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(lc);
    final timeFmt = DateFormat.Hm(lc);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_order_detail_title')),
      ),
      body: FutureBuilder<PosOrder?>(
        future: PosOrderService.instance.fetchById(orderId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final o = snap.data;
          if (o == null) {
            return Center(child: Text(loc.t('document_not_found')));
          }
          final tn = o.tableNumber ?? 0;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.t('pos_table_number', args: {'n': '$tn'}),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${loc.t('pos_tables_field_status')}: ${_statusLabel(loc, o.status)}',
                ),
                const SizedBox(height: 8),
                Text(
                    '${dateFmt.format(o.createdAt.toLocal())} ${timeFmt.format(o.createdAt.toLocal())}'),
                const SizedBox(height: 24),
                Text(
                  loc.t('pos_order_detail_hint'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
