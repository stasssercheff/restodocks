import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_order_live_duration.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../widgets/app_bar_home_button.dart';

/// Крупный список заказов подразделения для монитора (KDS).
class PosKitchenDisplayScreen extends StatefulWidget {
  const PosKitchenDisplayScreen({super.key, required this.department});

  final String department;

  @override
  State<PosKitchenDisplayScreen> createState() =>
      _PosKitchenDisplayScreenState();
}

class _PosKitchenDisplayScreenState extends State<PosKitchenDisplayScreen> {
  bool _loading = true;
  Object? _error;
  PosDepartmentOrderBuckets _buckets =
      const PosDepartmentOrderBuckets(active: [], served: []);
  Timer? _timer;
  PosOrdersDisplaySettingsService? _displaySettings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _displaySettings = context.read<PosOrdersDisplaySettingsService>();
      _displaySettings!.addListener(_onDisplayChanged);
      _timer = Timer.periodic(
        Duration(seconds: _displaySettings?.timerIntervalSeconds ?? 30),
        (_) {
          if (mounted &&
              (_buckets.active.isNotEmpty || _buckets.served.isNotEmpty)) {
            setState(() {});
          }
        },
      );
      _load();
    });
  }

  void _onDisplayChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _displaySettings?.removeListener(_onDisplayChanged);
    _timer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final timeFmt = DateFormat.Hm(Localizations.localeOf(context).toString());
    final baseStyle = Theme.of(context).textTheme.titleLarge!;
    final bigStyle = baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 20) + 6);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.15)),
      child: Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('pos_kds_title')),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
              tooltip: loc.t('refresh'),
            ),
          ],
        ),
        body: _body(loc, timeFmt, bigStyle),
      ),
    );
  }

  Widget _body(
    LocalizationService loc,
    DateFormat timeFmt,
    TextStyle bigStyle,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error == 'no_establishment') {
      return Center(child: Text(loc.t('error_no_establishment_or_employee')));
    }
    if (_error != null) {
      return Center(child: Text('${loc.t('error')}: $_error'));
    }
    final orders = [..._buckets.active, ..._buckets.served];
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(child: Text(loc.t('pos_orders_empty_active'))),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, i) {
          final o = orders[i];
          final tn = o.tableNumber ?? 0;
          final due = _buckets.grandDueByOrderId[o.id];
          final partial = _buckets.menuDuePartialOrderIds.contains(o.id);
          final elapsed = loc.t('pos_order_list_timer', args: {
            'time': formatPosOrderLiveDuration(o.createdAt),
          });
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              title: Text(
                loc.t('pos_table_number', args: {'n': '$tn'}),
                style: bigStyle,
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      posFloorRoomSummaryLine(
                        loc,
                        floorName: o.floorName,
                        roomName: o.roomName,
                      ),
                      style: bigStyle.copyWith(fontSize: bigStyle.fontSize! - 2),
                    ),
                    if (due != null)
                      Text(
                        '${partial ? '≈ ' : ''}${formatPosOrderMenuDue(context, due)}',
                        style: bigStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    Text(
                      elapsed,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      '${timeFmt.format(o.createdAt.toLocal())}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              onTap: () => context.push(
                    '/pos/hall/orders/${o.id}?dept=kitchen',
                  ),
            ),
          );
        },
      ),
    );
  }
}
