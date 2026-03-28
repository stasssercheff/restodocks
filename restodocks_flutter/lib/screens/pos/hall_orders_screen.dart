import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../utils/pos_order_live_duration.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_orders_list_subtitle_style.dart';
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
  PosOrdersDisplaySettingsService? _displaySettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _displaySettings = context.read<PosOrdersDisplaySettingsService>();
      _displaySettings!.addListener(_onPosDisplayChanged);
      _startElapsedTimer();
      await _load();
      if (!mounted) return;
      await _maybeOpenFromTableQuery();
    });
  }

  void _onPosDisplayChanged() {
    if (!mounted) return;
    _startElapsedTimer();
    setState(() {});
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    final sec = _displaySettings?.timerIntervalSeconds ?? 30;
    _elapsedTimer = Timer.periodic(Duration(seconds: sec), (_) {
      if (mounted &&
          (_buckets.active.isNotEmpty || _buckets.served.isNotEmpty)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _displaySettings?.removeListener(_onPosDisplayChanged);
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

  /// Этаж и зал для подписи в диалоге нового заказа (как на экране столов).
  String _dialogFloorRoomLine(LocalizationService loc, PosDiningTable t) {
    final floor = t.floorName?.trim();
    final room = t.roomName?.trim();
    final floorPart = (floor == null || floor.isEmpty)
        ? loc.t('pos_tables_tab_floor_default')
        : loc.t('pos_tables_tab_floor_named', args: {'name': floor});
    final roomPart = (room == null || room.isEmpty)
        ? loc.t('pos_tables_tab_room_default')
        : loc.t('pos_tables_tab_room_named', args: {'name': room});
    return '$floorPart · $roomPart';
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
      await PosDiningLayoutService.instance.ensureDefaultDiningLayoutIfEmpty(est.id);
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _dialogFloorRoomLine(loc, selected),
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<PosDiningTable>(
                    key: ValueKey(selected.id),
                    initialValue: selected,
                    decoration: InputDecoration(
                      labelText: loc.t('pos_orders_select_table'),
                    ),
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
                  const SizedBox(height: 20),
                  TextField(
                    controller: guestsCtrl,
                    decoration: InputDecoration(
                      labelText: loc.t('pos_orders_guests_label'),
                    ),
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
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final canDisplaySettings = posCanConfigureOrdersDisplay(emp);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_hall_orders_title')),
        actions: [
          if (canDisplaySettings)
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              onPressed: () => context.push('/settings/orders-display'),
              tooltip: loc.t('pos_orders_display_settings_title'),
            ),
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
      body: _body(context, loc, timeFmt),
    );
  }

  List<PosOrder> get _visibleOrders =>
      _bucket == _HallBucket.active ? _buckets.active : _buckets.served;

  Widget _body(
      BuildContext context, LocalizationService loc, DateFormat timeFmt) {
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
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    loc.t('pos_orders_empty_active'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
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
          child: RefreshIndicator(
            onRefresh: _load,
            child: _visibleOrders.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.35,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _bucket == _HallBucket.active
                                  ? loc.t('pos_department_orders_active_empty')
                                  : loc.t('pos_department_orders_served_empty'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                    final due = _buckets.menuDueByOrderId[o.id];
                    final partial =
                        _buckets.menuDuePartialOrderIds.contains(o.id);
                    return ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title:
                          Text(loc.t('pos_table_number', args: {'n': '$tn'})),
                      isThreeLine: due != null,
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sub,
                            style: posOrderListSubtitleStyle(context),
                          ),
                          if (due != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${partial ? '≈ ' : ''}${formatPosOrderMenuDue(context, due)}',
                              style: posOrderListSubtitleStyle(context)
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                      onTap: () => context.push('/pos/hall/orders/${o.id}'),
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}
