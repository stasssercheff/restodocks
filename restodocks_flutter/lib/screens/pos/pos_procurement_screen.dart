import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';
import 'procurement_receiving_tab.dart';
import '../order_lists_screen.dart';
import '../suppliers_screen.dart';

/// Закупка: вкладки «Заказ продуктов», «Поставщики», «Приём поставок».
class PosProcurementScreen extends StatelessWidget {
  const PosProcurementScreen({super.key, required this.department});

  final String department;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dept = (department == 'kitchen' ||
            department == 'bar' ||
            department == 'hall')
        ? department
        : 'kitchen';
    final deptKey = posDepartmentLabelKeyForRoute(dept);
    final deptLabel = deptKey != null ? loc.t(deptKey) : dept;
    final title =
        '${loc.t('pos_procurement_title')} ${deptLabel.toLowerCase()}';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(title),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: loc.t('pos_procurement_tab_product_order')),
              Tab(text: loc.t('order_tab_suppliers')),
              Tab(text: loc.t('pos_procurement_tab_receiving')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            OrderListsScreen(embeddedInTab: true, department: dept),
            SuppliersScreen(embedded: true, department: dept),
            ProcurementReceivingTab(department: dept),
          ],
        ),
      ),
    );
  }
}
