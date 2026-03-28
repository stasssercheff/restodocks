import 'package:flutter/material.dart';

import 'pos_closed_orders_report_screen.dart';

/// Сводка по закрытым счетам за выбранный период (по умолчанию сегодня).
class PosShiftReportScreen extends StatelessWidget {
  const PosShiftReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosClosedOrdersReportScreen(
      titleKey: 'pos_shift_report_title',
      subtitleKey: 'pos_shift_report_subtitle_intro',
    );
  }
}
