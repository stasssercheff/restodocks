import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/number_format_utils.dart';
import '../../utils/pos_orders_list_subtitle_style.dart';
import '../../widgets/app_bar_home_button.dart';

/// Виртуальная касса: столы, где запрошен счёт, с суммой к оплате по ТТК.
class HallCashRegisterScreen extends StatefulWidget {
  const HallCashRegisterScreen({super.key});

  @override
  State<HallCashRegisterScreen> createState() => _HallCashRegisterScreenState();
}

class _HallCashRegisterScreenState extends State<HallCashRegisterScreen> {
  bool _loading = true;
  Object? _error;
  List<PosCashRegisterRow> _rows = [];

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
      final list =
          await PosOrderService.instance.fetchCashRegisterRows(est.id);
      if (!mounted) return;
      setState(() {
        _rows = list;
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

  String _formatDue(double amount) {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final currency = est?.defaultCurrency ?? 'RUB';
    final sym = est?.currencySymbol ??
        Establishment.currencySymbolFor(currency);
    final numStr = NumberFormatUtils.formatSum(amount, currency);
    return '$numStr $sym';
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

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_hall_cash_title')),
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
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_cash_register_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _rows[i];
        final o = r.order;
        final tn = o.tableNumber ?? 0;
        final sub = [
          '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
          _statusLabel(loc, o.status),
          timeFmt.format(o.updatedAt.toLocal()),
          loc.t('pos_order_bill_requested'),
        ].join(' · ');
        return ListTile(
          leading: const Icon(Icons.point_of_sale),
          title: Text(loc.t('pos_table_number', args: {'n': '$tn'})),
          subtitle: Text(
            sub,
            style: posOrderListSubtitleStyle(context),
          ),
          trailing: Text(
            _formatDue(r.totalDue),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          onTap: () => context.push('/pos/hall/orders/${o.id}'),
        );
      },
    );
  }
}
