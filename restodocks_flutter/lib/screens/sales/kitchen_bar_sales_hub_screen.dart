import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/localization_service.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Хаб «Продажи» для кухни/бара: статистика и план.
class KitchenBarSalesHubScreen extends StatelessWidget {
  const KitchenBarSalesHubScreen({super.key, required this.department});

  final String department;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dept = department == 'bar' ? 'bar' : 'kitchen';
    final titleKey = posDepartmentLabelKeyForRoute(dept);
    final deptTitle = titleKey != null ? loc.t(titleKey) : dept;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('sales_title')} — $deptTitle'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: Text(loc.t('sales_statistics')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/sales/$dept/statistics'),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(loc.t('sales_plan_menu')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/sales/$dept/plan'),
            ),
          ),
        ],
      ),
    );
  }
}
