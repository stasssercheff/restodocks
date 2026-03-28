import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../utils/pos_order_department.dart';
import '../../utils/pos_order_live_duration.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_orders_list_subtitle_style.dart';
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

enum _DeptBucket { active, served }

class _PosDepartmentOrdersScreenState extends State<PosDepartmentOrdersScreen> {
  bool _loading = true;
  Object? _error;
  PosDepartmentOrderBuckets _buckets =
      const PosDepartmentOrderBuckets(active: [], served: []);
  _DeptBucket _bucket = _DeptBucket.active;
  Timer? _elapsedTimer;
  PosOrdersDisplaySettingsService? _displaySettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _displaySettings = context.read<PosOrdersDisplaySettingsService>();
      _displaySettings!.addListener(_onPosDisplayChanged);
      _startElapsedTimer();
      _load();
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
        widget.department,
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

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final deptKey = posDepartmentLabelKeyForRoute(widget.department);
    final deptLabel =
        deptKey != null ? loc.t(deptKey) : widget.department;
    final canDisplaySettings = posCanConfigureOrdersDisplay(emp);

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
      body: _body(context, loc, timeFmt),
    );
  }

  List<PosOrder> get _visibleOrders =>
      _bucket == _DeptBucket.active ? _buckets.active : _buckets.served;

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
                    loc.t('pos_department_orders_empty'),
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
          child: SegmentedButton<_DeptBucket>(
            segments: [
              ButtonSegment(
                value: _DeptBucket.active,
                label: Text(loc.t('pos_department_orders_tab_active')),
              ),
              ButtonSegment(
                value: _DeptBucket.served,
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
                              _bucket == _DeptBucket.active
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
                      title: Text(loc.t('pos_table_number', args: {'n': '$tn'})),
                      isThreeLine: true,
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            posFloorRoomSummaryLine(loc,
                                floorName: o.floorName, roomName: o.roomName),
                            style: posOrderListSubtitleStyle(context)?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
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
