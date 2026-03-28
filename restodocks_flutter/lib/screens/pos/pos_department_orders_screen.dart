import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Заказы POS для подразделения (кухня / бар / зал): фильтр по типу блюд в строках.
class PosDepartmentOrdersScreen extends StatefulWidget {
  const PosDepartmentOrdersScreen({super.key, required this.department});

  /// `kitchen` | `bar` | `hall` (в URL зал = hall)
  final String department;

  @override
  State<PosDepartmentOrdersScreen> createState() =>
      _PosDepartmentOrdersScreenState();
}

class _PosDepartmentOrdersScreenState extends State<PosDepartmentOrdersScreen> {
  bool _loading = true;
  Object? _error;
  List<PosOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'no_establishment';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PosOrderService.instance.fetchActiveOrdersForDepartment(
        est.id,
        widget.department,
      );
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

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
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final deptKey = posDepartmentLabelKeyForRoute(widget.department);
    final deptLabel =
        deptKey != null ? loc.t(deptKey) : widget.department;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('pos_department_orders_title')),
            Text(
              deptLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _body(loc, timeFmt),
    );
  }

  Widget _body(LocalizationService loc, DateFormat timeFmt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final message = _error == 'no_establishment'
          ? loc.t('error_no_establishment_or_employee')
          : loc.t('pos_tables_load_error');
      return Center(child: Text(message, textAlign: TextAlign.center));
    }
    if (_orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_department_orders_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final o = _orders[i];
        final tn = o.tableNumber ?? 0;
        final sub = [
          '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
          _statusLabel(loc, o.status),
          timeFmt.format(o.createdAt.toLocal()),
        ].join(' · ');
        return ListTile(
          leading: const Icon(Icons.receipt_long),
          title: Text(loc.t('pos_table_number', args: {'n': '$tn'})),
          subtitle: Text(sub),
          onTap: () => context.push('/pos/hall/orders/${o.id}'),
        );
      },
    );
  }
}
