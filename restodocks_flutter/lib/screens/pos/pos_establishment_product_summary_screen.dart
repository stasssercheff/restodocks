import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_sold_lines_to_products.dart';
import '../../widgets/app_bar_home_button.dart';

enum _SummaryScope {
  whole,
  kitchen,
  bar,
}

/// Сводная по продуктам: склад, закупка, корректировки, продажи (с выбором подразделения для оценки продаж по меню).
class PosEstablishmentProductSummaryScreen extends StatefulWidget {
  const PosEstablishmentProductSummaryScreen({super.key});

  @override
  State<PosEstablishmentProductSummaryScreen> createState() =>
      _PosEstablishmentProductSummaryScreenState();
}

class _PosEstablishmentProductSummaryScreenState
    extends State<PosEstablishmentProductSummaryScreen> {
  bool _loading = true;
  Object? _error;
  late DateTime _month;

  Map<String, ({double importGrams, double saleGrams, double adjustmentGrams})>
      _agg = {};
  List<({String productId, double quantityGrams, DateTime updatedAt})>
      _balances = [];
  Map<String, double> _salesExpandedKitchen = {};
  Map<String, double> _salesExpandedBar = {};

  _SummaryScope _scope = _SummaryScope.whole;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
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
      final start = DateTime(_month.year, _month.month);
      final end = DateTime(_month.year, _month.month + 1);
      final stock = PosStockService.instance;
      final agg = await stock.aggregateStockReconciliation(
        establishmentId: est.id,
        fromUtc: start.toUtc(),
        toUtc: end.toUtc(),
      );
      final bal = await stock.fetchBalances(est.id);
      final bundles = await PosOrderService.instance.fetchClosedOrdersWithSalesLines(
        establishmentId: est.id,
        fromUtc: start.toUtc(),
        toUtc: end.toUtc(),
      );
      final allLines = <PosOrderLine>[];
      for (final b in bundles) {
        allLines.addAll(b.lines);
      }
      final tech = TechCardServiceSupabase();
      final cards = await tech.getTechCardsForEstablishment(est.id);
      final tcById = {for (final c in cards) c.id: c};
      final kAgg = aggregateSoldLinesToProducts(
        lines: allLines,
        tcById: tcById,
        filter: PosSalesProductsFilter.kitchen,
      );
      final bAgg = aggregateSoldLinesToProducts(
        lines: allLines,
        tcById: tcById,
        filter: PosSalesProductsFilter.bar,
      );
      final kMap = <String, double>{};
      for (final p in kAgg) {
        final id = p['productId'] as String?;
        if (id == null) continue;
        final net = (p['netGrams'] as num?)?.toDouble() ?? 0;
        kMap[id] = (kMap[id] ?? 0) + net;
      }
      final bMap = <String, double>{};
      for (final p in bAgg) {
        final id = p['productId'] as String?;
        if (id == null) continue;
        final net = (p['netGrams'] as num?)?.toDouble() ?? 0;
        bMap[id] = (bMap[id] ?? 0) + net;
      }
      if (!mounted) return;
      setState(() {
        _agg = agg;
        _balances = bal;
        _salesExpandedKitchen = kMap;
        _salesExpandedBar = bMap;
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

  Future<void> _pickMonth() async {
    final y = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: MaterialLocalizations.of(context).datePickerHelpText,
    );
    if (y == null || !mounted) return;
    setState(() => _month = DateTime(y.year, y.month));
    await _load();
  }

  String _productName(String id, ProductStoreSupabase store) {
    final p = store.allProducts.where((e) => e.id == id).firstOrNull;
    return p?.name ?? id.substring(0, 8);
  }

  double? _saleForScope(String productId) {
    switch (_scope) {
      case _SummaryScope.whole:
        return _agg[productId]?.saleGrams;
      case _SummaryScope.kitchen:
        return _salesExpandedKitchen[productId];
      case _SummaryScope.bar:
        return _salesExpandedBar[productId];
    }
  }

  List<String> _filteredProductIds() {
    final balanceById = <String, double>{
      for (final b in _balances) b.productId: b.quantityGrams,
    };
    final ids = <String>{}
      ..addAll(_agg.keys)
      ..addAll(balanceById.keys)
      ..addAll(_salesExpandedKitchen.keys)
      ..addAll(_salesExpandedBar.keys);
    final out = ids.where((id) {
      final a = _agg[id];
      final bal = balanceById[id] ?? 0;
      final imp = a?.importGrams ?? 0;
      final adj = a?.adjustmentGrams ?? 0;
      final saleMov = a?.saleGrams ?? 0;
      final sk = _salesExpandedKitchen[id] ?? 0;
      final sb = _salesExpandedBar[id] ?? 0;
      return bal.abs() > 0.0001 ||
          imp.abs() > 0.0001 ||
          adj.abs() > 0.0001 ||
          saleMov.abs() > 0.0001 ||
          sk.abs() > 0.0001 ||
          sb.abs() > 0.0001;
    }).toList();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final monthFmt =
        DateFormat.yMMMM(Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_est_summary_title')),
        actions: [
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'no_est'
              ? Center(child: Text(loc.t('error_no_establishment_or_employee')))
              : _error != null
                  ? Center(child: Text('$_error'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          monthFmt.format(_month),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loc.t('pos_est_summary_hint'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<_SummaryScope>(
                          segments: [
                            ButtonSegment(
                              value: _SummaryScope.whole,
                              label: Text(loc.t('pos_est_summary_scope_whole')),
                            ),
                            ButtonSegment(
                              value: _SummaryScope.kitchen,
                              label:
                                  Text(loc.t('pos_est_summary_scope_kitchen')),
                            ),
                            ButtonSegment(
                              value: _SummaryScope.bar,
                              label: Text(loc.t('pos_est_summary_scope_bar')),
                            ),
                          ],
                          selected: {_scope},
                          onSelectionChanged: (s) {
                            setState(() => _scope = s.first);
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_filteredProductIds().isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              loc.t('pos_stock_movements_empty'),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Card(
                              child: _buildTable(loc, store),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _buildTable(LocalizationService loc, ProductStoreSupabase store) {
    final balanceById = <String, double>{
      for (final b in _balances) b.productId: b.quantityGrams,
    };
    final rows = List<String>.from(_filteredProductIds())
      ..sort((a, b) =>
          _productName(a, store).compareTo(_productName(b, store)));

    return DataTable(
      columns: [
        DataColumn(label: Text(loc.t('nomenclature'))),
        DataColumn(
          label: Text(loc.t('pos_est_summary_col_stock')),
          numeric: true,
        ),
        DataColumn(
          label: Text(loc.t('pos_est_summary_col_purchase')),
          numeric: true,
        ),
        DataColumn(
          label: Text(loc.t('pos_est_summary_col_adjustment')),
          numeric: true,
        ),
        DataColumn(
          label: Text(loc.t('pos_est_summary_col_sales')),
          numeric: true,
        ),
        DataColumn(
          label: Text(loc.t('pos_est_summary_col_net')),
          numeric: true,
        ),
      ],
      rows: rows.map((id) {
        final a = _agg[id];
        final bal = balanceById[id] ?? 0;
        final imp = a?.importGrams ?? 0;
        final adj = a?.adjustmentGrams ?? 0;
        final saleDisp = _saleForScope(id) ?? 0;
        final saleMov = a?.saleGrams ?? 0;
        final net = imp - saleMov + adj;
        return DataRow(cells: [
          DataCell(Text(_productName(id, store))),
          DataCell(Text(bal.toStringAsFixed(1))),
          DataCell(Text(imp.toStringAsFixed(1))),
          DataCell(Text(adj.toStringAsFixed(1))),
          DataCell(Text(
            (_scope == _SummaryScope.whole ? saleMov : saleDisp)
                .toStringAsFixed(1),
          )),
          DataCell(Text(net.toStringAsFixed(1))),
        ]);
      }).toList(),
    );
  }
}
