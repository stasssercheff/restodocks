import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/account_manager_supabase.dart';
import '../../services/kitchen_bar_sales_service.dart';
import '../../services/localization_service.dart';
import '../../services/sales_plan_calendar_prefs_service.dart';
import '../../services/sales_plan_storage_service.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

/// Календарь: факт продаж по дням и доля плана (если план на период есть).
class KitchenBarSalesPlanScreen extends StatefulWidget {
  const KitchenBarSalesPlanScreen({super.key, required this.department});

  final String department;

  @override
  State<KitchenBarSalesPlanScreen> createState() =>
      _KitchenBarSalesPlanScreenState();
}

class _KitchenBarSalesPlanScreenState extends State<KitchenBarSalesPlanScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  SalesPlanCalendarDisplayMode _displayMode =
      SalesPlanCalendarDisplayMode.percent;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final est = context
        .read<AccountManagerSupabase>()
        .establishment
        ?.dataEstablishmentId;
    if (est == null || est.isEmpty) return;
    final m = await SalesPlanCalendarPrefsService.getMode(est);
    if (!mounted) return;
    setState(() {
      _displayMode = m;
      _loadingPrefs = false;
    });
  }

  Future<void> _setMode(SalesPlanCalendarDisplayMode m) async {
    final est = context
        .read<AccountManagerSupabase>()
        .establishment
        ?.dataEstablishmentId;
    if (est == null || est.isEmpty) return;
    setState(() => _displayMode = m);
    await SalesPlanCalendarPrefsService.setMode(est, m);
  }

  Future<double> _factForDay(DateTime day) async {
    final est = context
        .read<AccountManagerSupabase>()
        .establishment
        ?.dataEstablishmentId;
    if (est == null || est.isEmpty) return 0;
    return KitchenBarSalesService.instance.factSellingTotalForLocalDay(
      establishmentId: est,
      routeDepartment: widget.department == 'bar' ? 'bar' : 'kitchen',
      dayLocal: day,
    );
  }

  Future<(double, SalesPlan?)> _dayCellModel(
    DateTime day,
    String establishmentId,
    String department,
  ) async {
    final plan = await SalesPlanStorageService.instance.activePlanForDay(
      establishmentId: establishmentId,
      department: department,
      dayLocal: day,
    );
    final fact = await _factForDay(day);
    return (fact, plan);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final est = acc.establishment?.dataEstablishmentId ?? '';
    final dept = widget.department == 'bar' ? 'bar' : 'kitchen';
    final titleKey = posDepartmentLabelKeyForRoute(dept);
    final deptTitle = titleKey != null ? loc.t(titleKey) : dept;

    if (_loadingPrefs) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text('${loc.t('sales_plan_menu') ?? ''} — $deptTitle'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final first = DateTime(_month.year, _month.month, 1);
    final lastDay = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('sales_plan_calendar') ?? ''} — $deptTitle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: loc.t('sales_plan_create') ?? '',
            onPressed: () => context.push('/sales/$dept/plan/form'),
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month - 1, 1);
                  });
                },
              ),
              Text(
                DateFormat.yMMMM(Localizations.localeOf(context).toString())
                    .format(_month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _month = DateTime(_month.year, _month.month + 1, 1);
                  });
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<SalesPlanCalendarDisplayMode>(
              segments: [
                ButtonSegment(
                  value: SalesPlanCalendarDisplayMode.percent,
                  label: Text(loc.t('sales_plan_display_percent') ?? '%'),
                ),
                ButtonSegment(
                  value: SalesPlanCalendarDisplayMode.amountFraction,
                  label: Text(loc.t('sales_plan_display_amount') ?? 'Σ'),
                ),
              ],
              selected: {_displayMode},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) _setMode(s.first);
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonal(
              onPressed: () async {
                final plans =
                    await SalesPlanStorageService.instance.loadAll(est);
                final active =
                    plans.where((p) => p.department == dept).toList();
                if (!context.mounted) return;
                if (active.isEmpty) {
                  context.push('/sales/$dept/plan/form');
                  return;
                }
                active.sort((a, b) {
                  final ua = a.updatedAt ?? a.createdAt;
                  final ub = b.updatedAt ?? b.createdAt;
                  return ub.compareTo(ua);
                });
                context.push('/sales/$dept/plan/form?id=${active.first.id}');
              },
              child: Text(loc.t('sales_plan_adjust') ?? ''),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: lead + lastDay,
              itemBuilder: (context, i) {
                if (i < lead) return const SizedBox.shrink();
                final d = i - lead + 1;
                final day = DateTime(_month.year, _month.month, d);
                return _MonthDayCell(
                  day: day,
                  future: _dayCellModel(day, est, dept),
                  displayMode: _displayMode,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.future,
    required this.displayMode,
  });

  final DateTime day;
  final Future<(double, SalesPlan?)> future;
  final SalesPlanCalendarDisplayMode displayMode;

  double? _dailyPlanTarget(SalesPlan? p) {
    if (p == null) return null;
    final start = DateTime(p.periodStart.year, p.periodStart.month, p.periodStart.day);
    final end = DateTime(p.periodEnd.year, p.periodEnd.month, p.periodEnd.day);
    final days = end.difference(start).inDays + 1;
    if (days <= 0) return p.targetCashAmount;
    return p.targetCashAmount / days;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<(double, SalesPlan?)>(
        future: future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final fact = snap.data!.$1;
          final plan = snap.data!.$2;
          final daily = _dailyPlanTarget(plan);
          final nf = NumberFormat('#,###', 'ru');
          String label;
          if (plan == null || daily == null || daily <= 0) {
            label = displayMode == SalesPlanCalendarDisplayMode.percent
                ? '—'
                : nf.format(fact.round());
          } else if (displayMode == SalesPlanCalendarDisplayMode.percent) {
            final pct = (fact / daily * 100).clamp(0, 9999);
            label = '${pct.toStringAsFixed(0)}%';
          } else {
            label = '${nf.format(fact.round())} / ${nf.format(daily.round())}';
          }
          return Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
