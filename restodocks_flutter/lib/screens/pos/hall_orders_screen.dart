import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_order_live_duration.dart';
import '../../widgets/app_bar_home_button.dart';

/// Активные заказы зала (pos_orders), создание черновика по столу.
class HallOrdersScreen extends StatefulWidget {
  const HallOrdersScreen({super.key});

  @override
  State<HallOrdersScreen> createState() => _HallOrdersScreenState();
}

enum _HallBucket { active, served }

class _HallOrdersScreenState extends State<HallOrdersScreen> {
  bool _loading = true;
  Object? _error;
  PosDepartmentOrderBuckets _buckets =
      const PosDepartmentOrderBuckets(active: [], served: []);
  _HallBucket _bucket = _HallBucket.active;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          (_buckets.active.isNotEmpty || _buckets.served.isNotEmpty)) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (!mounted) return;
      await _maybeOpenFromTableQuery();
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeOpenFromTableQuery() async {
    final tid = GoRouterState.of(context).queryParameters['table'];
    if (tid == null || tid.isEmpty) return;
    final loc = context.read<LocalizationService>();
    await _openCreate(loc, preselectedTableId: tid);
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
      final buckets = await PosOrderService.instance.fetchDepartmentOrderBuckets(
        est.id,
        'hall',
      );
      if (!mounted) return;
      setState(() {
        _buckets = buckets;
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

  Future<void> _openCreate(LocalizationService loc,
      {String? preselectedTableId}) async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;

    List<PosDiningTable> tables;
    try {
      tables = await PosDiningLayoutService.instance.fetchTables(est.id);
    } catch (e) {
      AppToastService.show('${loc.t('error')}: $e');
      return;
    }
    if (!mounted) return;
    if (tables.isEmpty) {
      AppToastService.show(loc.t('pos_orders_no_tables'));
      return;
    }

    PosDiningTable selected = tables.first;
    if (preselectedTableId != null) {
      for (final t in tables) {
        if (t.id == preselectedTableId) {
          selected = t;
          break;
        }
      }
    }
    final guestsCtrl = TextEditingController(text: '1');
    var guestsParsed = 1;

    if (!mounted) return;
    bool? ok;
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(loc.t('pos_orders_dialog_title')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PosDiningTable>(
                    key: ValueKey(selected.id),
                    initialValue: selected,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_orders_select_table')),
                    items: tables
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(
                              loc.t('pos_table_number',
                                  args: {'n': '${t.tableNumber}'}),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => selected = v);
                    },
                  ),
                  TextField(
                    controller: guestsCtrl,
                    decoration: InputDecoration(
                        labelText: loc.t('pos_orders_guests_label')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.t('pos_orders_create_confirm')),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        guestsParsed = int.tryParse(guestsCtrl.text.trim()) ?? 1;
      }
    } finally {
      guestsCtrl.dispose();
    }

    if (ok != true || !mounted) return;
    final guests = guestsParsed;
    if (guests < 1) {
      AppToastService.show(loc.t('pos_orders_guests_invalid'));
      return;
    }

    try {
      final order = await PosOrderService.instance.createDraft(
        establishmentId: est.id,
        diningTableId: selected.id,
        guestCount: guests,
      );
      if (!mounted) return;
      AppToastService.show(loc.t('pos_orders_created'));
      await context.push('/pos/hall/orders/${order.id}');
      if (mounted) await _load();
    } on PosOrderTableBusyException catch (e) {
      if (!mounted) return;
      AppToastService.show(loc.t('pos_orders_table_busy'));
      await context.push('/pos/hall/orders/${e.existingOrder.id}');
      if (mounted) await _load();
    } catch (e) {
      AppToastService.show('${loc.t('error')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_hall_orders_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : () => _openCreate(loc),
        tooltip: loc.t('pos_orders_fab_new'),
        child: const Icon(Icons.add),
      ),
      body: _body(loc, timeFmt),
    );
  }

  List<PosOrder> get _visibleOrders =>
      _bucket == _HallBucket.active ? _buckets.active : _buckets.served;

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
    if (_buckets.active.isEmpty && _buckets.served.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('pos_orders_empty_active'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<_HallBucket>(
            segments: [
              ButtonSegment(
                value: _HallBucket.active,
                label: Text(loc.t('pos_department_orders_tab_active')),
              ),
              ButtonSegment(
                value: _HallBucket.served,
                label: Text(loc.t('pos_department_orders_tab_served')),
              ),
            ],
            selected: {_bucket},
            onSelectionChanged: (s) => setState(() => _bucket = s.first),
          ),
        ),
        Expanded(
          child: _visibleOrders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _bucket == _HallBucket.active
                          ? loc.t('pos_department_orders_active_empty')
                          : loc.t('pos_department_orders_served_empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _visibleOrders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = _visibleOrders[i];
                    final tn = o.tableNumber ?? 0;
                    final sub = [
                      '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
                      _statusLabel(loc, o.status),
                      timeFmt.format(o.createdAt.toLocal()),
                      loc.t('pos_order_list_timer', args: {
                        'time': formatPosOrderLiveDuration(o.createdAt),
                      }),
                    ].join(' · ');
                    return ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title:
                          Text(loc.t('pos_table_number', args: {'n': '$tn'})),
                      subtitle: Text(sub),
                      onTap: () => context.push('/pos/hall/orders/${o.id}'),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
