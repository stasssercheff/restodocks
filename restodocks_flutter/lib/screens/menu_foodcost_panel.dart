import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/product_store_supabase.dart';
import '../services/tech_card_cost_hydrator.dart';
import '../utils/tech_card_section_display.dart';

enum FoodcostPricingMode {
  markupOnCost,
  costShareOfPrice,
}

/// Табличный фудкост: цеха, с/с порции, наценка / доля с/с, оптимальная и фактическая цена.
class MenuFoodcostPanel extends StatefulWidget {
  const MenuFoodcostPanel({
    super.key,
    required this.dishes,
    required this.dataEstablishmentId,
    required this.currencySym,
    required this.langCode,
    this.openCardInEditMode = false,
  });

  final List<TechCard> dishes;
  final String dataEstablishmentId;
  final String currencySym;
  final String langCode;
  final bool openCardInEditMode;

  @override
  State<MenuFoodcostPanel> createState() => _MenuFoodcostPanelState();
}

class _MenuFoodcostPanelState extends State<MenuFoodcostPanel> {
  List<TechCard> _hydrated = [];
  bool _busy = true;
  String _query = '';
  FoodcostPricingMode _mode = FoodcostPricingMode.markupOnCost;
  final _targetPctController = TextEditingController(text: '100');

  static String _prefsKeyMode(String est) => 'restodocks_foodcost_mode_$est';
  static String _prefsKeyTarget(String est) => 'restodocks_foodcost_target_$est';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(MenuFoodcostPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dishes != widget.dishes ||
        oldWidget.dataEstablishmentId != widget.dataEstablishmentId) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _busy = true;
    });
    final store = context.read<ProductStoreSupabase>();
    final est = widget.dataEstablishmentId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getString(_prefsKeyMode(est));
      if (m == 'cost_share') {
        _mode = FoodcostPricingMode.costShareOfPrice;
      } else {
        _mode = FoodcostPricingMode.markupOnCost;
      }
      final t = prefs.getString(_prefsKeyTarget(est));
      if (t != null && t.isNotEmpty) {
        _targetPctController.text = t;
      } else if (_mode == FoodcostPricingMode.costShareOfPrice) {
        _targetPctController.text = '35';
      }
    } catch (_) {}

    final h = TechCardCostHydrator.hydrate(
      List<TechCard>.from(widget.dishes),
      store,
      est,
    );
    if (!mounted) return;
    setState(() {
      _hydrated = h;
      _busy = false;
    });
  }

  Future<void> _persistMode(FoodcostPricingMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyMode(widget.dataEstablishmentId),
        mode == FoodcostPricingMode.costShareOfPrice ? 'cost_share' : 'markup',
      );
    } catch (_) {}
  }

  Future<void> _persistTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyTarget(widget.dataEstablishmentId),
        _targetPctController.text.trim(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _targetPctController.dispose();
    super.dispose();
  }

  double _portionCost(TechCard tc) {
    final totalCost = tc.totalCost > 0
        ? tc.totalCost
        : tc.ingredients.fold<double>(0, (s, i) => s + i.cost);
    if (tc.portionWeight <= 0 || tc.yield <= 0) return 0;
    return totalCost * tc.portionWeight / tc.yield;
  }

  double? _parseTargetPct() {
    final raw = _targetPctController.text.trim().replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return v;
  }

  double? _optimalPrice(double cost, double? targetPct) {
    if (targetPct == null || cost <= 0) return null;
    if (_mode == FoodcostPricingMode.markupOnCost) {
      return cost * (1 + targetPct / 100);
    }
    if (targetPct >= 100) return null;
    return cost * 100 / targetPct;
  }

  DataRow _buildRow(
    LocalizationService loc,
    TechCard tc,
    int rowNum,
    double? targetPct, {
    required bool narrow,
  }) {
    final cost = _portionCost(tc);
    final sell = tc.sellingPrice;
    double? markupAct;
    double? shareAct;
    if (cost > 0 && sell != null && sell > 0) {
      markupAct = (sell / cost - 1) * 100;
      shareAct = (cost / sell) * 100;
    }
    final opt = _optimalPrice(cost, targetPct);

    return DataRow(
      cells: [
        DataCell(Text('$rowNum')),
        DataCell(
          SizedBox(
            width: narrow ? 110 : 220,
            child: InkWell(
              onTap: () => context.push(
                widget.openCardInEditMode
                    ? '/tech-cards/${tc.id}'
                    : '/tech-cards/${tc.id}?view=1',
              ),
              child: Text(
                tc.getDisplayNameInLists(widget.langCode),
                maxLines: narrow ? 5 : 4,
                softWrap: true,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  fontSize: narrow ? 12.5 : null,
                ),
              ),
            ),
          ),
        ),
        DataCell(Text(
          cost > 0
              ? '${cost.toStringAsFixed(2)} ${widget.currencySym}'
              : '—',
        )),
        DataCell(Text(
          _mode == FoodcostPricingMode.markupOnCost
              ? (markupAct != null
                  ? '${markupAct.toStringAsFixed(1)}%'
                  : '—')
              : (shareAct != null
                  ? '${shareAct.toStringAsFixed(1)}%'
                  : '—'),
        )),
        DataCell(Text(
          opt != null
              ? '${opt.toStringAsFixed(2)} ${widget.currencySym}'
              : '—',
        )),
        DataCell(Text(
          sell != null && sell > 0
              ? '${sell.toStringAsFixed(2)} ${widget.currencySym}'
              : (loc.t('foodcost_no_selling_price') ?? '—'),
        )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final narrow = MediaQuery.sizeOf(context).width < 560;
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }

    final targetPct = _parseTargetPct();
    final q = _query.trim().toLowerCase();

    var filtered = _hydrated;
    if (q.isNotEmpty) {
      filtered = _hydrated.where((tc) {
        final name = tc.getDisplayNameInLists(widget.langCode).toLowerCase();
        return name.contains(q);
      }).toList();
    }

    final groups = groupTechCardsBySection(filtered);
    var rowNum = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(narrow ? 12 : 16, 0, narrow ? 12 : 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<FoodcostPricingMode>(
                segments: [
                  ButtonSegment<FoodcostPricingMode>(
                    value: FoodcostPricingMode.markupOnCost,
                    label: Text(loc.t('foodcost_mode_markup') ?? 'Наценка к с/с'),
                  ),
                  ButtonSegment<FoodcostPricingMode>(
                    value: FoodcostPricingMode.costShareOfPrice,
                    label: Text(loc.t('foodcost_mode_cost_share') ?? 'Доля с/с в цене'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  final m = s.first;
                  setState(() => _mode = m);
                  unawaited(_persistMode(m));
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetPctController,
                      decoration: InputDecoration(
                        labelText: loc.t('foodcost_target_pct') ?? 'Целевой %',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onSubmitted: (_) => _persistTarget(),
                      onEditingComplete: _persistTarget,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      _mode == FoodcostPricingMode.markupOnCost
                          ? (loc.t('foodcost_mode_markup_hint') ?? 'к с/с')
                          : (loc.t('foodcost_mode_cost_share_hint') ?? '% от цены'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  labelText: loc.t('foodcost_search_hint') ?? 'Поиск',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                  child: Padding(
                  padding: EdgeInsets.fromLTRB(narrow ? 8 : 16, 0, narrow ? 8 : 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groups.isNotEmpty)
                        DataTable(
                          columnSpacing: narrow ? 8 : 16,
                          horizontalMargin: narrow ? 6 : 12,
                          headingRowHeight: narrow ? 36 : 40,
                          dataRowMinHeight: narrow ? 36 : 40,
                          dataRowMaxHeight: narrow ? 80 : 56,
                          columns: [
                            DataColumn(
                              label: Text(
                                loc.t('foodcost_col_num') ?? '#',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                loc.t('foodcost_col_name') ?? 'Блюдо',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(
                                loc.t('foodcost_col_cost') ?? 'С/с порции',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(
                                _mode == FoodcostPricingMode.markupOnCost
                                    ? (loc.t('foodcost_col_markup_actual') ??
                                        'Наценка факт %')
                                    : (loc.t('foodcost_col_cost_share_actual') ??
                                        'С/с от цены факт %'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(
                                loc.t('foodcost_price_optimal'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DataColumn(
                              numeric: true,
                              label: Text(
                                loc.t('foodcost_price_actual'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          rows: [
                            for (final g in groups) ...[
                              DataRow(
                                color: WidgetStatePropertyAll(
                                  Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                ),
                                cells: [
                                  const DataCell(Text('')),
                                  DataCell(
                                    Text(
                                      techCardSectionGroupLabel(g.section, loc),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                  const DataCell(Text('')),
                                ],
                              ),
                              for (final tc in g.cards)
                                _buildRow(loc, tc, ++rowNum, targetPct, narrow: narrow),
                            ],
                          ],
                        ),
                      if (groups.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            loc.t('menu_empty_dishes') ?? '',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
