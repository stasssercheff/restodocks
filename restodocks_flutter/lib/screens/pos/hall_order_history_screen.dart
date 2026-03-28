import 'package:flutter/material.dart';

import 'pos_closed_orders_report_screen.dart';

/// История закрытых счетов зала за период.
class HallOrderHistoryScreen extends StatelessWidget {
  const HallOrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosClosedOrdersReportScreen(
      titleKey: 'pos_order_history_title',
    );
  }
}
