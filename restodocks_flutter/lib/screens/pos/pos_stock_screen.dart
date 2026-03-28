import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart';

/// Остатки по номенклатуре (граммы) и движения за месяц; обновление в реальном времени.
class PosStockScreen extends StatefulWidget {
  const PosStockScreen({super.key});

  @override
  State<PosStockScreen> createState() => _PosStockScreenState();
}

class _PosStockScreenState extends State<PosStockScreen> {
  bool _loading = true;
  Object? _error;
  List<({String productId, double quantityGrams, DateTime updatedAt})> _balances =
      [];
  List<({DateTime createdAt, String productId, double deltaGrams, String reason})>
      _movements = [];
  Map<String, ({double importGrams, double saleGrams})>? _agg;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  RealtimeChannel? _rtBal;
  RealtimeChannel? _rtMov;
  List<Map<String, dynamic>>? _healthIssues;
  bool _healthLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      _subscribeRt();
    });
  }

  @override
  void dispose() {
    _rtBal?.unsubscribe();
    _rtMov?.unsubscribe();
    super.dispose();
  }

  void _subscribeRt() {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    final client = Supabase.instance.client;
    _rtBal = client
        .channel('pos_stock_bal_$est')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'establishment_stock_balances',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'establishment_id',
            value: est,
          ),
          callback: (_) {
            if (mounted) _load();
          },
        )
        .subscribe();
    _rtMov = client
        .channel('pos_stock_mov_$est')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'establishment_stock_movements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'establishment_id',
            value: est,
          ),
          callback: (_) {
            if (mounted) _loadMovements();
          },
        )
        .subscribe();
  }

  Future<void> _load() async {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'no_est';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = context.read<ProductStoreSupabase>();
      if (store.allProducts.isEmpty) {
        await store.loadProducts();
      }
      final bal = await PosStockService.instance.fetchBalances(est);
      if (!mounted) return;
      setState(() {
        _balances = bal;
        _loading = false;
      });
      await _loadMovements();
      await _loadAgg();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadAgg() async {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    final start = DateTime(_month.year, _month.month);
    final end = DateTime(_month.year, _month.month + 1);
    try {
      final a = await PosStockService.instance.aggregateImportVsSale(
        establishmentId: est,
        fromUtc: start.toUtc(),
        toUtc: end.toUtc(),
      );
      if (!mounted) return;
      setState(() => _agg = a);
    } catch (_) {
      if (mounted) setState(() => _agg = null);
    }
  }

  Future<void> _loadMovements() async {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    final start = DateTime(_month.year, _month.month);
    final end = DateTime(_month.year, _month.month + 1);
    try {
      final m = await PosStockService.instance.fetchMovements(
        establishmentId: est,
        fromUtc: start.toUtc(),
        toUtc: end.toUtc(),
      );
      if (!mounted) return;
      setState(() => _movements = m);
    } catch (_) {}
  }

  String _productName(String id, ProductStoreSupabase store) {
    final p = store.allProducts.where((e) => e.id == id).firstOrNull;
    return p?.name ?? id.substring(0, 8);
  }

  Future<void> _runHealthCheck() async {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    setState(() {
      _healthLoading = true;
      _healthIssues = null;
    });
    try {
      final rows = await PosStockService.instance.runWarehouseHealthCheck(est);
      if (!mounted) return;
      setState(() {
        _healthIssues = rows;
        _healthLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthLoading = false);
    }
  }

  Future<void> _pickMonth() async {
    final y = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: MaterialLocalizations.of(context).datePickerHelpText,
    );
    if (y == null || !mounted) return;
    setState(() {
      _month = DateTime(y.year, y.month);
    });
    await _loadMovements();
    await _loadAgg();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final canHealth = posCanRunWarehouseHealthCheck(emp);
    final monthFmt = DateFormat.yMMMM(Localizations.localeOf(context).toString());
    final showReconciliation = _agg != null &&
        _agg!.entries.any(
          (e) =>
              e.value.importGrams.abs() > 0.0001 ||
              e.value.saleGrams.abs() > 0.0001,
        );

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_stock_title')),
        actions: [
          if (canHealth)
            IconButton(
              icon: _healthLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.health_and_safety_outlined),
              onPressed: _healthLoading ? null : _runHealthCheck,
              tooltip: loc.t('pos_stock_health_check'),
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _pickMonth,
            tooltip: loc.t('pos_stock_month'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _loading && _balances.isEmpty && _error == null
          ? const Center(child: CircularProgressIndicator())
          : _error == 'no_est'
              ? Center(child: Text(loc.t('error_no_establishment_or_employee')))
              : _error != null
                  ? Center(child: Text('$_error'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (canHealth && _healthIssues != null) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: _healthIssues!.isEmpty
                                    ? Text(
                                        loc.t('pos_stock_health_ok'),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            loc.t('pos_stock_health_mismatch'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .error,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          ..._healthIssues!.map((row) {
                                            final pid =
                                                row['product_id']?.toString() ??
                                                    '';
                                            final diff = (row['diff_grams']
                                                    as num?)
                                                ?.toDouble() ??
                                                0;
                                            final name =
                                                _productName(pid, store);
                                            return Card(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .errorContainer
                                                  .withValues(alpha: 0.35),
                                              child: ListTile(
                                                dense: true,
                                                title: Text(name),
                                                subtitle: Text(
                                                  'Δ ${diff.toStringAsFixed(2)} ${loc.t('pos_stock_grams')}',
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text(
                                loc.t('pos_stock_balances_heading'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          if (_balances.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  loc.t('pos_stock_empty'),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final b = _balances[i];
                                  final name = _productName(b.productId, store);
                                  final q = b.quantityGrams.toStringAsFixed(1);
                                  return ListTile(
                                    title: Text(name),
                                    subtitle: Text(
                                        '${loc.t('pos_stock_grams')}: $q'),
                                    dense: true,
                                  );
                                },
                                childCount: _balances.length,
                              ),
                            ),
                          if (showReconciliation) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      loc.t('pos_stock_reconciliation_title'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      loc.t('pos_stock_reconciliation_hint'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Card(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowHeight: 40,
                                      dataRowMinHeight: 36,
                                      dataRowMaxHeight: 48,
                                      columns: [
                                        DataColumn(
                                            label: Text(loc.t('nomenclature'))),
                                        DataColumn(
                                          label: Text(
                                              loc.t('pos_stock_col_import')),
                                          numeric: true,
                                        ),
                                        DataColumn(
                                          label: Text(
                                              loc.t('pos_stock_col_sale')),
                                          numeric: true,
                                        ),
                                        DataColumn(
                                          label: Text(
                                              loc.t('pos_stock_col_net')),
                                          numeric: true,
                                        ),
                                      ],
                                      rows: () {
                                        final rows = _agg!.entries
                                            .where((e) =>
                                                e.value.importGrams.abs() >
                                                    0.0001 ||
                                                e.value.saleGrams.abs() >
                                                    0.0001)
                                            .toList()
                                          ..sort((a, b) => _productName(
                                                  a.key, store)
                                              .compareTo(_productName(b.key, store)));
                                        return rows.map((e) {
                                          final net = e.value.importGrams -
                                              e.value.saleGrams;
                                          return DataRow(cells: [
                                            DataCell(Text(_productName(
                                                e.key, store))),
                                            DataCell(Text(e
                                                .value.importGrams
                                                .toStringAsFixed(1))),
                                            DataCell(Text(e.value.saleGrams
                                                .toStringAsFixed(1))),
                                            DataCell(Text(
                                                net.toStringAsFixed(1))),
                                          ]);
                                        }).toList();
                                      }(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    loc.t('pos_stock_movements_heading'),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  Text(
                                    monthFmt.format(_month),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_movements.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(loc.t('pos_stock_movements_empty')),
                              ),
                            )
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, i) {
                                  final m = _movements[i];
                                  final name = _productName(m.productId, store);
                                  final dt = DateFormat.MMMd(Localizations.localeOf(context).toString())
                                      .add_Hm();
                                  final d = m.deltaGrams.toStringAsFixed(1);
                                  return ListTile(
                                    dense: true,
                                    title: Text(name),
                                    subtitle: Text(
                                      '${dt.format(m.createdAt.toLocal())} · ${m.reason}',
                                    ),
                                    trailing: Text(d),
                                  );
                                },
                                childCount: _movements.length,
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}
