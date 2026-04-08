import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';
import 'procurement_receiving_tab.dart';
import '../order_lists_screen.dart';
import '../suppliers_screen.dart';

/// Закупка: три раздела — только переключение кнопками сверху (без свайпа между экранами).
class PosProcurementScreen extends StatefulWidget {
  const PosProcurementScreen({super.key, required this.department});

  final String department;

  @override
  State<PosProcurementScreen> createState() => _PosProcurementScreenState();
}

class _PosProcurementScreenState extends State<PosProcurementScreen> {
  int _tabIndex = 0;

  String get _dept {
    final d = widget.department;
    if (d == 'kitchen' || d == 'bar' || d == 'hall') return d;
    return 'kitchen';
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final deptKey = posDepartmentLabelKeyForRoute(_dept);
    final deptLabel = deptKey != null ? loc.t(deptKey) : _dept;
    final title =
        '${loc.t('pos_procurement_title')} ${deptLabel.toLowerCase()}';

    // «Приём поставок» доступен и при выключенном POS на прод-витрине (см. FeatureFlags.posModuleEnabled).
    final showReceiving = true;
    final tabs = [
      loc.t('pos_procurement_tab_product_order'),
      if (showReceiving) loc.t('pos_procurement_tab_receiving'),
      loc.t('order_tab_suppliers'),
    ];
    if (_tabIndex >= tabs.length) {
      _tabIndex = tabs.length - 1;
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: List.generate(tabs.length, (i) {
                final selected = _tabIndex == i;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
                    child: selected
                        ? FilledButton(
                            onPressed: () => setState(() => _tabIndex = i),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                            ),
                            child: Text(
                              tabs[i],
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : OutlinedButton(
                            onPressed: () => setState(() => _tabIndex = i),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 10,
                              ),
                            ),
                            child: Text(
                              tabs[i],
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              sizing: StackFit.expand,
              children: [
                OrderListsScreen(embeddedInTab: true, department: _dept),
                if (showReceiving) ProcurementReceivingTab(department: _dept),
                SuppliersScreen(embedded: true, department: _dept),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
