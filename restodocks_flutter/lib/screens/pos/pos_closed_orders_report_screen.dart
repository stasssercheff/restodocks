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
    this.isCancelled = false,
  });

  final PosOrder order;
  final double grandTotal;
  final List<PosOrderPayment> payments;
  final bool isCancelled;
}

/// Закрытые счета за выбранный период (дни по локальному календарю).
class PosClosedOrdersReportScreen extends StatefulWidget {
  const PosClosedOrdersReportScreen({
    super.key,
    required this.titleKey,
    this.subtitleKey,
  });

  final String titleKey;
  /// Если null — подзаголовок только из выбранного периода.
  final String? subtitleKey;

  @override
  State<PosClosedOrdersReportScreen> createState() =>
      _PosClosedOrdersReportScreenState();
}

class _PosClosedOrdersReportScreenState extends State<PosClosedOrdersReportScreen> {
  bool _loading = true;
  Object? _error;
  List<_ShiftRow> _rows = [];
  late DateTime _rangeStartLocal;
  late DateTime _rangeEndLocal;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStartLocal = DateTime(now.year, now.month, now.day);
    _rangeEndLocal = _rangeStartLocal;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  (DateTime, DateTime) _fromToUtc() {
    final fromLocal = DateTime(
      _rangeStartLocal.year,
      _rangeStartLocal.month,
      _rangeStartLocal.day,
    );
    final endDay = DateTime(
      _rangeEndLocal.year,
      _rangeEndLocal.month,
      _rangeEndLocal.day,
    );
    final toExclusiveLocal = endDay.add(const Duration(days: 1));
    return (fromLocal.toUtc(), toExclusiveLocal.toUtc());
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
      final range = _fromToUtc();
      final closed = await PosOrderService.instance.fetchClosedOrdersPaidBetween(
        establishmentId: est.id,
        fromUtc: range.$1,
        toUtc: range.$2,
      );
      final cancelled =
          await PosOrderService.instance.fetchCancelledOrdersUpdatedBetween(
        establishmentId: est.id,
        fromUtc: range.$1,
        toUtc: range.$2,
      );
      final out = <_ShiftRow>[];
      for (final o in closed) {
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
      for (final o in cancelled) {
        out.add(_ShiftRow(
          order: o,
          grandTotal: 0,
          payments: const [],
          isCancelled: true,
        ));
      }
      out.sort((a, b) {
        final ta =
            a.isCancelled ? a.order.updatedAt : (a.order.paidAt ?? a.order.updatedAt);
        final tb =
            b.isCancelled ? b.order.updatedAt : (b.order.paidAt ?? b.order.updatedAt);
        return tb.compareTo(ta);
      });
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

  Future<void> _pickRange() async {
    final loc = Localizations.localeOf(context);
    final now = DateTime.now();
    final first = now.subtract(const Duration(days: 400));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: _rangeStartLocal,
        end: _rangeEndLocal,
      ),
      locale: loc,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rangeStartLocal = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _rangeEndLocal = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  Map<PosPaymentMethod, double> _sumByMethod() {
    final m = <PosPaymentMethod, double>{};
    for (final r in _rows) {
      if (r.isCancelled) continue;
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
      if (r.isCancelled) continue;
      s += r.grandTotal;
    }
    return s;
  }

  String _periodLabel(LocalizationService loc) {
    final fmt = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    if (_rangeStartLocal.year == _rangeEndLocal.year &&
        _rangeStartLocal.month == _rangeEndLocal.month &&
        _rangeStartLocal.day == _rangeEndLocal.day) {
      return fmt.format(_rangeStartLocal);
    }
    return loc.t('pos_closed_orders_period_range', args: {
      'from': fmt.format(_rangeStartLocal),
      'to': fmt.format(_rangeEndLocal),
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t(widget.titleKey)),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _loading ? null : _pickRange,
            tooltip: loc.t('pos_closed_orders_pick_period'),
          ),
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
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    _periodLabel(loc),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.t('pos_shift_report_empty'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final byMethod = _sumByMethod();
    final grand = _sumGrand();
    final subtitle = widget.subtitleKey != null
        ? '${loc.t(widget.subtitleKey!)}\n${_periodLabel(loc)}'
        : _periodLabel(loc);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            subtitle,
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
                ? timeFmt.format(o.paidAt!.toLocal())
                : '';
            final whenCancelled =
                timeFmt.format(o.updatedAt.toLocal());
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(loc.t('pos_table_number', args: {'n': '$tn'})),
                subtitle: Text(
                  r.isCancelled
                      ? '${loc.t('pos_order_status_cancelled')} · $whenCancelled'
                      : '${formatPosOrderMenuDue(context, r.grandTotal)} · $paid',
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
