import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_order_totals.dart';
import '../../widgets/app_bar_home_button.dart';

class _ShiftRow {
  _ShiftRow({
    required this.order,
    required this.grandTotal,
    required this.payments,
  });

  final PosOrder order;
  final double grandTotal;
  final List<PosOrderPayment> payments;
}

/// Сводка по закрытым счетам за сегодня (локальный день).
class PosShiftReportScreen extends StatefulWidget {
  const PosShiftReportScreen({super.key});

  @override
  State<PosShiftReportScreen> createState() => _PosShiftReportScreenState();
}

class _PosShiftReportScreenState extends State<PosShiftReportScreen> {
  bool _loading = true;
  Object? _error;
  List<_ShiftRow> _rows = [];

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
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final orders = await PosOrderService.instance.fetchClosedOrdersPaidBetween(
        establishmentId: est.id,
        fromUtc: start.toUtc(),
        toUtc: end.toUtc(),
      );
      final out = <_ShiftRow>[];
      for (final o in orders) {
        final lines = await PosOrderService.instance.fetchLines(o.id);
        var menu = 0.0;
        for (final l in lines) {
          final p = l.sellingPrice;
          if (p == null) continue;
          menu += l.quantity * p;
        }
        final grand = computePosOrderTotalsRaw(
          menuSubtotal: menu,
          discountAmount: o.discountAmount,
          serviceChargePercent: o.serviceChargePercent,
          tipsAmount: o.tipsAmount,
        ).grandTotal;
        final pays = await PosOrderService.instance.fetchPaymentsForOrder(o.id);
        out.add(_ShiftRow(order: o, grandTotal: grand, payments: pays));
      }
      if (!mounted) return;
      setState(() {
        _rows = out;
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

  Map<PosPaymentMethod, double> _sumByMethod() {
    final m = <PosPaymentMethod, double>{};
    for (final r in _rows) {
      if (r.payments.isNotEmpty) {
        for (final p in r.payments) {
          m[p.paymentMethod] = (m[p.paymentMethod] ?? 0) + p.amount;
        }
      } else {
        final pm = r.order.paymentMethod;
        if (pm != null && pm != PosPaymentMethod.split) {
          m[pm] = (m[pm] ?? 0) + r.grandTotal;
        }
      }
    }
    return m;
  }

  double _sumGrand() {
    var s = 0.0;
    for (final r in _rows) {
      s += r.grandTotal;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_shift_report_title')),
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
    if (_error == 'no_establishment') {
      return Center(child: Text(loc.t('error_no_establishment_or_employee')));
    }
    if (_error != null) {
      return Center(child: Text('${loc.t('error')}: $_error'));
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Center(child: Text(loc.t('pos_shift_report_empty'))),
          ],
        ),
      );
    }

    final byMethod = _sumByMethod();
    final grand = _sumGrand();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            loc.t('pos_shift_report_subtitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            loc.t('pos_shift_report_orders', args: {'n': '${_rows.length}'}),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${loc.t('pos_shift_report_grand')}: ${formatPosOrderMenuDue(context, grand)}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (byMethod.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              loc.t('pos_shift_report_by_method'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...byMethod.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_methodLabel(loc, e.key)),
                    Text(formatPosOrderMenuDue(context, e.value)),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 24),
          ..._rows.map((r) {
            final o = r.order;
            final tn = o.tableNumber ?? 0;
            final paid = o.paidAt != null
                ? '${timeFmt.format(o.paidAt!.toLocal())}'
                : '';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(loc.t('pos_table_number', args: {'n': '$tn'})),
                subtitle: Text(
                  '${formatPosOrderMenuDue(context, r.grandTotal)} · $paid',
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _methodLabel(LocalizationService loc, PosPaymentMethod m) {
    switch (m) {
      case PosPaymentMethod.cash:
        return loc.t('pos_order_payment_cash');
      case PosPaymentMethod.card:
        return loc.t('pos_order_payment_card');
      case PosPaymentMethod.transfer:
        return loc.t('pos_order_payment_transfer');
      case PosPaymentMethod.other:
        return loc.t('pos_order_payment_other');
      case PosPaymentMethod.split:
        return loc.t('pos_order_payment_split');
    }
  }
}
