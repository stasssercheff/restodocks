import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_orders_list_subtitle_style.dart';
import '../../widgets/app_bar_home_button.dart';

/// Виртуальная касса: счета к оплате, выдача, смена.
class HallCashRegisterScreen extends StatefulWidget {
  const HallCashRegisterScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<HallCashRegisterScreen> createState() => _HallCashRegisterScreenState();
}

class _HallCashRegisterScreenState extends State<HallCashRegisterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  Object? _error;
  List<PosCashRegisterRow> _orderRows = [];
  List<PosCashDisbursement> _disbursements = [];
  PosCashShift? _activeShift;
  double _cashInShift = 0;
  double _expectedDrawer = 0;
  PosShiftReportAudienceSettings _shiftReportAudience =
      PosShiftReportAudienceSettings.kDefaultAll;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      final orders =
          await PosOrderService.instance.fetchCashRegisterRows(est.id);
      final shift = await PosCashHallService.instance.fetchActiveShift(est.id);
      final reportAudience =
          await PosShiftReportAudienceService.instance.fetchForEstablishment(est.id);
      List<PosCashDisbursement> disb;
      double cashIn = 0;
      double expected = 0;
      if (shift != null) {
        disb = await PosCashHallService.instance
            .fetchDisbursementsForShift(shift.id);
        cashIn = await PosCashHallService.instance.sumCashPaymentsInPeriod(
          establishmentId: est.id,
          fromUtc: shift.startedAt.toUtc(),
          toUtc: DateTime.now().toUtc(),
        );
        final disbSum =
            PosCashHallService.instance.sumDisbursementAmounts(disb);
        expected = shift.openingBalance + cashIn - disbSum;
      } else {
        disb = await PosCashHallService.instance
            .fetchRecentDisbursements(establishmentId: est.id);
      }
      if (!mounted) return;
      setState(() {
        _orderRows = orders;
        _activeShift = shift;
        _disbursements = disb;
        _cashInShift = cashIn;
        _expectedDrawer = expected;
        _shiftReportAudience = reportAudience;
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

  String _cashRegisterAppBarTitle(LocalizationService loc) {
    switch (_tabController.index) {
      case 0:
        return loc.t('pos_cash_tab_orders');
      case 1:
        return loc.t('pos_cash_tab_disbursements');
      case 2:
        return loc.t('pos_cash_tab_shift');
      default:
        return loc.t('pos_hall_cash_title');
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
      case PosOrderStatus.cancelled:
        return loc.t('pos_order_status_cancelled');
    }
  }

  Future<void> _openShiftDialog(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final est = account.establishment;
    if (emp == null || est == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pos_cash_error_no_employee'))),
      );
      return;
    }
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_cash_shift_open_title')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: loc.t('pos_cash_shift_opening_hint'),
            border: const OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    if (v < 0) return;
    try {
      await PosCashHallService.instance.openShift(
        establishmentId: est.id,
        openingBalance: v,
        openedByEmployeeId: emp.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pos_cash_shift_opened_ok'))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
    }
  }

  Future<void> _closeShiftDialog(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final shift = _activeShift;
    final est = account.establishment;
    if (emp == null || shift == null || est == null) return;
    final isOwner = emp.hasRole('owner');
    var selectedScope = _shiftReportAudience.scope;
    final selectedZones = <String>{..._shiftReportAudience.zones};
    final ctrl = TextEditingController(
      text: _expectedDrawer.toStringAsFixed(2),
    );
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(loc.t('pos_cash_shift_close_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                '${loc.t('pos_cash_shift_expected')}: ${formatPosOrderMenuDue(context, _expectedDrawer)}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: loc.t('pos_cash_shift_closing_hint'),
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: loc.t('pos_cash_shift_notes_optional'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Text(
                'Аудитория отчета закрытия',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
                if (isOwner)
                  DropdownButtonFormField<PosShiftReportAudienceScope>(
                    initialValue: selectedScope,
                    decoration: const InputDecoration(
                      labelText: 'Режим рассылки',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PosShiftReportAudienceScope.all,
                        child: Text('Весь объект'),
                      ),
                      DropdownMenuItem(
                        value: PosShiftReportAudienceScope.zones,
                        child: Text('Только выбранные зоны'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setModalState(() {
                        selectedScope = v;
                      });
                    },
                  )
                else
                  Text(
                    selectedScope == PosShiftReportAudienceScope.all
                        ? 'Весь объект'
                        : 'Только выбранные зоны',
                  ),
                if (selectedScope == PosShiftReportAudienceScope.zones) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _zoneChip(
                        loc: loc,
                        zone: 'kitchen',
                        selectedZones: selectedZones,
                        editable: isOwner,
                        onChanged: () => setModalState(() {}),
                      ),
                      _zoneChip(
                        loc: loc,
                        zone: 'bar',
                        selectedZones: selectedZones,
                        editable: isOwner,
                        onChanged: () => setModalState(() {}),
                      ),
                      _zoneChip(
                        loc: loc,
                        zone: 'banquet',
                        selectedZones: selectedZones,
                        editable: isOwner,
                        onChanged: () => setModalState(() {}),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final closing = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    if (selectedScope == PosShiftReportAudienceScope.zones &&
        selectedZones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну зону для отчета.')),
      );
      return;
    }
    final appliedSettings = PosShiftReportAudienceSettings(
      scope: selectedScope,
      zones: selectedZones.toList(),
    );
    try {
      if (isOwner) {
        await PosShiftReportAudienceService.instance.upsertForOwner(
          establishmentId: est.id,
          updatedByEmployeeId: emp.id,
          settings: appliedSettings,
        );
      }
      await PosCashHallService.instance.closeShift(
        shiftId: shift.id,
        closingBalance: closing,
        closedByEmployeeId: emp.id,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        closeReportScope: appliedSettings.isAll ? 'all' : 'zones',
        closeReportZones: appliedSettings.zones,
      );
      if (!mounted) return;
      final diff = closing - _expectedDrawer;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${loc.t('pos_cash_shift_closed_ok')} (${loc.t('pos_cash_shift_discrepancy')}: ${formatPosOrderMenuDue(context, diff)})',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
    }
  }

  FilterChip _zoneChip({
    required LocalizationService loc,
    required String zone,
    required Set<String> selectedZones,
    required bool editable,
    required VoidCallback onChanged,
  }) {
    final selected = selectedZones.contains(zone);
    return FilterChip(
      label: Text(_zoneLabel(loc, zone)),
      selected: selected,
      onSelected: editable
          ? (v) {
              if (v) {
                selectedZones.add(zone);
              } else {
                selectedZones.remove(zone);
              }
              onChanged();
            }
          : null,
    );
  }

  String _zoneLabel(LocalizationService loc, String zone) {
    switch (zone) {
      case 'kitchen':
        return loc.t('dept_kitchen');
      case 'bar':
        return loc.t('dept_bar');
      case 'banquet':
        return 'Банкет';
      default:
        return zone;
    }
  }

  Future<void> _addDisbursement(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final est = account.establishment;
    if (emp == null || est == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pos_cash_error_no_employee'))),
      );
      return;
    }
    final amountCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_cash_disburse_dialog_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                decoration: InputDecoration(
                  labelText: loc.t('pos_cash_field_amount'),
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: purposeCtrl,
                decoration: InputDecoration(
                  labelText: loc.t('pos_cash_field_purpose'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: loc.t('pos_cash_field_recipient_name'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final amount =
        double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0) return;
    final purpose = purposeCtrl.text.trim();
    if (purpose.isEmpty) return;
    try {
      await PosCashHallService.instance.addDisbursement(
        establishmentId: est.id,
        shiftId: _activeShift?.id,
        amount: amount,
        purpose: purpose,
        recipientName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
        createdByEmployeeId: emp.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('pos_cash_disburse_saved'))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $e')),
      );
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
        title: Text(_cashRegisterAppBarTitle(loc)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: loc.t('pos_order_history_title'),
            onPressed: () => context.push('/pos/hall/order-history'),
          ),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: loc.t('pos_cash_tab_orders')),
            Tab(text: loc.t('pos_cash_tab_disbursements')),
            Tab(text: loc.t('pos_cash_tab_shift')),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorBody(loc)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _ordersTab(loc, timeFmt),
                    _disbursementsTab(loc),
                    _shiftTab(loc, timeFmt),
                  ],
                ),
      floatingActionButton: _tabController.index == 1 && !_loading && _error == null
          ? FloatingActionButton(
              onPressed: () => _addDisbursement(loc),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _errorBody(LocalizationService loc) {
    final message = _error == 'no_establishment'
        ? loc.t('error_no_establishment_or_employee')
        : loc.t('pos_tables_load_error');
    return Center(child: Text(message, textAlign: TextAlign.center));
  }

  Widget _ordersTab(LocalizationService loc, DateFormat timeFmt) {
    if (_orderRows.isEmpty) {
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
                    loc.t('pos_cash_register_empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _orderRows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = _orderRows[i];
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
            isThreeLine: true,
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  posFloorRoomSummaryLine(loc,
                      floorName: o.floorName, roomName: o.roomName),
                  style: posOrderListSubtitleStyle(context)?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: posOrderListSubtitleStyle(context),
                ),
              ],
            ),
            trailing: Text(
              formatPosOrderMenuDue(context, r.totalDue),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            onTap: () async {
              await context.push('/pos/hall/orders/${o.id}');
              if (mounted) await _load();
            },
          );
        },
      ),
    );
  }

  Widget _disbursementsTab(LocalizationService loc) {
    if (_disbursements.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    loc.t('pos_cash_disburse_empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final localeName = Localizations.localeOf(context).toString();
    final dFmt = DateFormat.yMMMd(localeName);
    final tFmt = DateFormat.Hm(localeName);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _disbursements.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final d = _disbursements[i];
          final extra = [
            if (d.recipientName != null && d.recipientName!.isNotEmpty)
              d.recipientName,
          ].whereType<String>().join(' · ');
          return ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(d.purpose),
            subtitle: Text(
              [
                '${dFmt.format(d.createdAt.toLocal())} ${tFmt.format(d.createdAt.toLocal())}',
                if (extra.isNotEmpty) extra,
              ].join(' · '),
            ),
            trailing: Text(
              formatPosOrderMenuDue(context, d.amount),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
    );
  }

  Widget _shiftTab(LocalizationService loc, DateFormat timeFmt) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (_activeShift == null) ...[
            Text(
              loc.t('pos_cash_shift_no_active'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openShiftDialog(loc),
              icon: const Icon(Icons.lock_open),
              label: Text(loc.t('pos_cash_shift_open_action')),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.push('/pos/kds/kitchen'),
              icon: const Icon(Icons.restaurant_menu),
              label: Text(loc.t('pos_kds_title')),
            ),
          ] else ...[
            Text(
              loc.t('pos_cash_shift_active'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('pos_cash_shift_started')}: ${timeFmt.format(_activeShift!.startedAt.toLocal())}',
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('pos_cash_shift_opening_label')}: ${formatPosOrderMenuDue(context, _activeShift!.openingBalance)}',
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('pos_cash_shift_cash_in')}: ${formatPosOrderMenuDue(context, _cashInShift)}',
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('pos_cash_shift_disbursed')}: ${formatPosOrderMenuDue(context, PosCashHallService.instance.sumDisbursementAmounts(_disbursements))}',
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('pos_cash_shift_expected')}: ${formatPosOrderMenuDue(context, _expectedDrawer)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _closeShiftDialog(loc),
              icon: const Icon(Icons.lock),
              label: Text(loc.t('pos_cash_shift_close_action')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push('/pos/hall/orders'),
              icon: const Icon(Icons.receipt_long),
              label: Text(loc.t('pos_cash_tab_orders')),
            ),
            const SizedBox(height: 12),
            Text(
              'Аудитория отчета закрытия: ${_shiftReportAudience.isAll ? 'Весь объект' : 'Только выбранные зоны (${_shiftReportAudience.zones.map((z) => _zoneLabel(loc, z)).join(', ')})'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
