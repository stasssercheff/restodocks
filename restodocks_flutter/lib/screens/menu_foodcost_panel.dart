import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/product_store_supabase.dart';
import '../services/tech_card_cost_hydrator.dart';
import '../utils/number_format_utils.dart';
import '../utils/tech_card_section_display.dart';

enum FoodcostPricingMode {
  markupOnCost,
  costShareOfPrice,
}

class _DishTargetState {
  _DishTargetState({this.useCustom = false, this.pctText = ''});

  bool useCustom;
  String pctText;
}

class _FoodcostColumnWidths {
  const _FoodcostColumnWidths({
    required this.no,
    required this.dish,
    required this.cost,
    required this.metric,
    required this.withMarkup,
    required this.menu,
    required this.pct,
  });

  final double no;
  final double dish;
  final double cost;
  final double metric;
  final double withMarkup;
  final double menu;
  final double pct;
}

/// Табличный фудкост: цеха, с/с порции, наценка / доля с/с, оптимальная и фактическая цена.
class MenuFoodcostPanel extends StatefulWidget {
  const MenuFoodcostPanel({
    super.key,
    required this.dishes,

    /// `establishment_products.establishment_id`: у филиала — id филиала, у головы — id данных.
    required this.nomenclatureEstablishmentId,

    /// У филиала — id головного заведения для [ProductStoreSupabase.loadNomenclatureForBranch]; у головы — null.
    this.nomenclatureMergeParentEstablishmentId,

    /// Ключ настроек (целевой %, режим) — id текущего заведения в аккаунте.
    required this.prefsScopeEstablishmentId,

    /// ISO 4217 (как в заведении/сотруднике): для VND и др. — без копеек, разделитель тысяч.
    required this.currencyCode,
    required this.currencySym,
    required this.langCode,
    this.openCardInEditMode = false,
    this.menuSegmentValue,
    this.onMenuSegmentChanged,
  });

  final List<TechCard> dishes;
  final String nomenclatureEstablishmentId;
  final String? nomenclatureMergeParentEstablishmentId;
  final String prefsScopeEstablishmentId;
  final String currencyCode;
  final String currencySym;
  final String langCode;
  final bool openCardInEditMode;
  final int? menuSegmentValue;
  final ValueChanged<int>? onMenuSegmentChanged;

  @override
  State<MenuFoodcostPanel> createState() => _MenuFoodcostPanelState();
}

class _MenuFoodcostPanelState extends State<MenuFoodcostPanel> {
  List<TechCard> _hydrated = [];
  bool _busy = true;
  String _query = '';
  FoodcostPricingMode _mode = FoodcostPricingMode.markupOnCost;
  final _targetPctController = TextEditingController(text: '100');
  final _headerHScroll = ScrollController();
  final _bodyHScroll = ScrollController();
  final _vScroll = ScrollController();
  bool _syncingHScroll = false;
  double _lastVScrollPixels = 0;
  bool _hideControlsOnScroll = false;

  final Map<String, _DishTargetState> _dishTargets = {};
  final Map<String, TextEditingController> _dishPctControllers = {};

  static String _prefsKeyMode(String est) => 'restodocks_foodcost_mode_$est';
  static String _prefsKeyTarget(String est) =>
      'restodocks_foodcost_target_$est';
  static String _prefsKeyDishOverrides(String est) =>
      'restodocks_foodcost_dish_overrides_$est';

  @override
  void initState() {
    super.initState();
    _headerHScroll.addListener(_syncHeaderToBody);
    _bodyHScroll.addListener(_syncBodyToHeader);
    _vScroll.addListener(_onTableVScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(MenuFoodcostPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dishes != widget.dishes ||
        oldWidget.nomenclatureEstablishmentId !=
            widget.nomenclatureEstablishmentId ||
        oldWidget.nomenclatureMergeParentEstablishmentId !=
            widget.nomenclatureMergeParentEstablishmentId) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _busy = true;
    });
    final store = context.read<ProductStoreSupabase>();
    final prefsScope = widget.prefsScopeEstablishmentId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getString(_prefsKeyMode(prefsScope));
      if (m == 'cost_share') {
        _mode = FoodcostPricingMode.costShareOfPrice;
      } else {
        _mode = FoodcostPricingMode.markupOnCost;
      }
      final t = prefs.getString(_prefsKeyTarget(prefsScope));
      if (t != null && t.isNotEmpty) {
        _targetPctController.text = t;
      } else if (_mode == FoodcostPricingMode.costShareOfPrice) {
        _targetPctController.text = '35';
      }
    } catch (_) {}

    try {
      if (widget.nomenclatureMergeParentEstablishmentId != null) {
        await store.loadNomenclatureForBranch(
          widget.prefsScopeEstablishmentId,
          widget.nomenclatureMergeParentEstablishmentId!,
        );
      } else {
        await store.loadNomenclature(widget.nomenclatureEstablishmentId);
      }
    } catch (_) {}

    await _loadDishOverridesFromPrefs(prefsScope);

    for (final c in _dishPctControllers.values) {
      c.dispose();
    }
    _dishPctControllers.clear();

    for (final tc in widget.dishes) {
      _dishTargets.putIfAbsent(tc.id, () => _DishTargetState());
      final st = _dishTargets[tc.id]!;
      _dishPctControllers[tc.id] = TextEditingController(text: st.pctText);
    }

    final h = TechCardCostHydrator.hydrate(
      List<TechCard>.from(widget.dishes),
      store,
      widget.nomenclatureEstablishmentId,
    );
    if (!mounted) return;
    setState(() {
      _hydrated = h;
      _busy = false;
    });
  }

  Future<void> _loadDishOverridesFromPrefs(String prefsScope) async {
    _dishTargets.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKeyDishOverrides(prefsScope));
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      for (final e in decoded.entries) {
        final v = e.value;
        if (v is! Map<String, dynamic>) continue;
        _dishTargets[e.key] = _DishTargetState(
          useCustom: v['u'] == true,
          pctText: v['p']?.toString() ?? '',
        );
      }
    } catch (_) {}
  }

  Future<void> _persistDishOverrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, dynamic>{};
      for (final tc in widget.dishes) {
        final id = tc.id;
        final st = _dishTargets[id];
        final text = _dishPctControllers[id]?.text.trim() ?? '';
        final u = st?.useCustom ?? false;
        if (!u && text.isEmpty) continue;
        out[id] = {'u': u, 'p': text};
      }
      await prefs.setString(
        _prefsKeyDishOverrides(widget.prefsScopeEstablishmentId),
        jsonEncode(out),
      );
    } catch (_) {}
  }

  Future<void> _persistMode(FoodcostPricingMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyMode(widget.prefsScopeEstablishmentId),
        mode == FoodcostPricingMode.costShareOfPrice ? 'cost_share' : 'markup',
      );
    } catch (_) {}
  }

  Future<void> _persistTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyTarget(widget.prefsScopeEstablishmentId),
        _targetPctController.text.trim(),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _vScroll.removeListener(_onTableVScroll);
    _headerHScroll.removeListener(_syncHeaderToBody);
    _bodyHScroll.removeListener(_syncBodyToHeader);
    _vScroll.dispose();
    _headerHScroll.dispose();
    _bodyHScroll.dispose();
    for (final c in _dishPctControllers.values) {
      c.dispose();
    }
    _dishPctControllers.clear();
    _targetPctController.dispose();
    super.dispose();
  }

  void _onTableVScroll() {
    if (!_vScroll.hasClients) return;
    final p = _vScroll.position.pixels;
    if (_lastVScrollPixels == 0 && p > 0) {
      _lastVScrollPixels = p;
      return;
    }
    final d = p - _lastVScrollPixels;
    _lastVScrollPixels = p;
    if (p <= 8) {
      if (_hideControlsOnScroll) {
        setState(() => _hideControlsOnScroll = false);
      }
      return;
    }
    if (p > 36 && d > 8 && !_hideControlsOnScroll) {
      setState(() => _hideControlsOnScroll = true);
    } else if (d < -8 && _hideControlsOnScroll) {
      setState(() => _hideControlsOnScroll = false);
    }
  }

  void _syncHeaderToBody() {
    if (_syncingHScroll ||
        !_bodyHScroll.hasClients ||
        !_headerHScroll.hasClients) {
      return;
    }
    _syncingHScroll = true;
    final target = _headerHScroll.offset.clamp(
      _bodyHScroll.position.minScrollExtent,
      _bodyHScroll.position.maxScrollExtent,
    );
    _bodyHScroll.jumpTo(target);
    _syncingHScroll = false;
  }

  void _syncBodyToHeader() {
    if (_syncingHScroll ||
        !_headerHScroll.hasClients ||
        !_bodyHScroll.hasClients) {
      return;
    }
    _syncingHScroll = true;
    final target = _bodyHScroll.offset.clamp(
      _headerHScroll.position.minScrollExtent,
      _headerHScroll.position.maxScrollExtent,
    );
    _headerHScroll.jumpTo(target);
    _syncingHScroll = false;
  }

  /// Себестоимость порции: как в списке ТТК — если [TechCard.yield] не задан, оцениваем выход по сумме весов строк состава.
  double _portionCost(TechCard tc) {
    var totalCost = tc.totalCost;
    if (totalCost <= 0) {
      totalCost = tc.ingredients.fold<double>(0, (s, i) => s + i.effectiveCost);
    }
    if (totalCost <= 0) return 0;

    final yieldG = tc.yield > 0
        ? tc.yield
        : TechCardCostHydrator.sumIngredientOutputGrams(tc);
    if (yieldG <= 0) return 0;

    final portionG = tc.portionWeight > 0 ? tc.portionWeight : yieldG;
    return totalCost * portionG / yieldG;
  }

  double? _parsePctString(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null || v <= 0) return null;
    return v;
  }

  double? _parseTargetPct() {
    return _parsePctString(_targetPctController.text);
  }

  double? _effectiveTargetPctForDish(TechCard tc) {
    final st = _dishTargets[tc.id];
    if (st != null && st.useCustom) {
      final fromCtrl = _dishPctControllers[tc.id]?.text ?? '';
      return _parsePctString(fromCtrl.isNotEmpty ? fromCtrl : st.pctText);
    }
    return _parseTargetPct();
  }

  void _showCustomTargetInfoDialog(LocalizationService loc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('foodcost_custom_target_info_title')),
        content: SingleChildScrollView(
          child: Text(loc.t('foodcost_custom_target_info_body')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('tour_done')),
          ),
        ],
      ),
    );
  }

  String? _globalTargetHint(double? globalPct) {
    if (globalPct == null) return null;
    if (globalPct % 1 == 0) return globalPct.toInt().toString();
    return globalPct.toString();
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
    double? globalTargetPct, {
    required bool narrow,
    required _FoodcostColumnWidths w,
  }) {
    final cost = _portionCost(tc);
    final sell = tc.sellingPrice;
    double? markupAct;
    double? shareAct;
    if (cost > 0 && sell != null && sell > 0) {
      markupAct = (sell / cost - 1) * 100;
      shareAct = (cost / sell) * 100;
    }
    final effectivePct = _effectiveTargetPctForDish(tc);
    final opt = _optimalPrice(cost, effectivePct);
    final st = _dishTargets[tc.id]!;
    final ctrl = _dishPctControllers[tc.id]!;

    Widget centeredValue(String value, double width, {double? fontSize}) =>
        SizedBox(
          width: width,
          child: Align(
            alignment: Alignment.center,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: fontSize),
            ),
          ),
        );

    return DataRow(
      cells: [
        DataCell(
            centeredValue('$rowNum', w.no, fontSize: narrow ? 11.5 : null)),
        DataCell(
          SizedBox(
            width: w.dish,
            child: InkWell(
              onTap: () => context.push(
                widget.openCardInEditMode
                    ? '/tech-cards/${tc.id}'
                    : '/tech-cards/${tc.id}?view=1',
              ),
              child: Text(
                tc.getDisplayNameInLists(widget.langCode),
                maxLines: narrow ? 3 : 4,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  fontSize: narrow ? 11.5 : null,
                  height: narrow ? 1.2 : null,
                ),
              ),
            ),
          ),
        ),
        DataCell(centeredValue(
          cost > 0
              ? NumberFormatUtils.formatSumWithSymbol(
                  cost, widget.currencyCode, widget.currencySym)
              : '—',
          w.cost,
          fontSize: narrow ? 11.5 : null,
        )),
        DataCell(centeredValue(
          _mode == FoodcostPricingMode.markupOnCost
              ? (markupAct != null ? '${markupAct.toStringAsFixed(1)}%' : '—')
              : (shareAct != null ? '${shareAct.toStringAsFixed(1)}%' : '—'),
          w.metric,
          fontSize: narrow ? 11.5 : null,
        )),
        DataCell(centeredValue(
          opt != null
              ? NumberFormatUtils.formatSumWithSymbol(
                  opt, widget.currencyCode, widget.currencySym)
              : '—',
          w.withMarkup,
          fontSize: narrow ? 11.5 : null,
        )),
        DataCell(centeredValue(
          sell != null && sell > 0
              ? NumberFormatUtils.formatSumWithSymbol(
                  sell, widget.currencyCode, widget.currencySym)
              : (loc.t('foodcost_no_selling_price') ?? '—'),
          w.menu,
          fontSize: narrow ? 11.5 : null,
        )),
        DataCell(
          SizedBox(
            width: w.pct,
            child: Align(
              alignment: Alignment.center,
              child: narrow
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 40,
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: !st.useCustom
                                  ? _globalTargetHint(globalTargetPct)
                                  : null,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: narrow ? 2 : 8,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            style: TextStyle(fontSize: narrow ? 10.5 : 13),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            onChanged: (_) {
                              if (st.useCustom) setState(() {});
                            },
                            onEditingComplete: () {
                              st.pctText = ctrl.text.trim();
                              setState(() {});
                              unawaited(_persistDishOverrides());
                            },
                            onSubmitted: (_) {
                              st.pctText = ctrl.text.trim();
                              setState(() {});
                              unawaited(_persistDishOverrides());
                            },
                          ),
                        ),
                        const SizedBox(width: 0),
                        Semantics(
                          label: loc.t('foodcost_custom_target_checkbox_a11y'),
                          child: Checkbox(
                            value: st.useCustom,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                st.useCustom = v;
                                st.pctText = ctrl.text.trim();
                              });
                              unawaited(_persistDishOverrides());
                            },
                          ),
                        ),
                        Tooltip(
                          message: loc.t('foodcost_custom_target_info_title'),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _showCustomTargetInfoDialog(loc),
                              child: Padding(
                                padding: EdgeInsets.all(narrow ? 2 : 6),
                                child: Icon(
                                  Icons.info_outline,
                                  size: narrow ? 13 : 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 68,
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: !st.useCustom
                                  ? _globalTargetHint(globalTargetPct)
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 13),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            onChanged: (_) {
                              if (st.useCustom) setState(() {});
                            },
                            onEditingComplete: () {
                              st.pctText = ctrl.text.trim();
                              setState(() {});
                              unawaited(_persistDishOverrides());
                            },
                            onSubmitted: (_) {
                              st.pctText = ctrl.text.trim();
                              setState(() {});
                              unawaited(_persistDishOverrides());
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Semantics(
                          label: loc.t('foodcost_custom_target_checkbox_a11y'),
                          child: Checkbox(
                            value: st.useCustom,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                st.useCustom = v;
                                st.pctText = ctrl.text.trim();
                              });
                              unawaited(_persistDishOverrides());
                            },
                          ),
                        ),
                        Tooltip(
                          message: loc.t('foodcost_custom_target_info_title'),
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _showCustomTargetInfoDialog(loc),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  _FoodcostColumnWidths _resolveColumnWidths(bool narrow) {
    final metricW = _mode == FoodcostPricingMode.costShareOfPrice
        ? (narrow ? 86.0 : 112.0)
        : (narrow ? 70.0 : 96.0);
    return _FoodcostColumnWidths(
      no: narrow ? 26 : 36,
      dish: narrow ? 164 : 260,
      cost: narrow ? 98 : 132,
      metric: metricW,
      withMarkup: narrow ? 100 : 136,
      menu: narrow ? 96 : 132,
      pct: narrow ? 126 : 176,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final narrow = MediaQuery.sizeOf(context).shortestSide < 600;
    final isPhoneLayout = MediaQuery.sizeOf(context).shortestSide < 600;
    final shortViewport = MediaQuery.sizeOf(context).height < 560;
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

    Widget headerLabel(String text) => Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: narrow ? 11 : 13,
              height: 1.05,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
        );

    final w = _resolveColumnWidths(narrow);

    final tableColumns = [
      DataColumn(label: SizedBox(width: w.no, child: headerLabel('№'))),
      DataColumn(label: SizedBox(width: w.dish, child: headerLabel('Блюдо'))),
      DataColumn(
        numeric: true,
        label: SizedBox(width: w.cost, child: headerLabel('Себестоимость')),
      ),
      DataColumn(
        label: SizedBox(
          width: w.metric,
          child: _mode == FoodcostPricingMode.markupOnCost
              ? headerLabel('Наценка')
              : headerLabel('%\nсебестоимости'),
        ),
      ),
      DataColumn(
        numeric: true,
        label: SizedBox(
          width: w.withMarkup,
          child: headerLabel('С наценкой'),
        ),
      ),
      DataColumn(
        label: SizedBox(width: w.menu, child: headerLabel('В меню')),
      ),
      DataColumn(
        label: SizedBox(
          width: w.pct,
          child: headerLabel('%'),
        ),
      ),
    ];

    final tableBorder = TableBorder(
      horizontalInside: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        width: 0.6,
      ),
      verticalInside: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
        width: 0.5,
      ),
    );

    rowNum = 0;
    final tableRows = <DataRow>[
      for (final g in groups) ...[
        DataRow(
          color: WidgetStatePropertyAll(
            Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.6),
          ),
          cells: [
            DataCell(SizedBox(width: w.no)),
            DataCell(
              SizedBox(
                width: w.dish,
                child: Text(
                  techCardSectionGroupLabel(g.section, loc),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            DataCell(SizedBox(width: w.cost)),
            DataCell(SizedBox(width: w.metric)),
            DataCell(SizedBox(width: w.withMarkup)),
            DataCell(SizedBox(width: w.menu)),
            DataCell(SizedBox(width: w.pct)),
          ],
        ),
        for (final tc in g.cards)
          _buildRow(loc, tc, ++rowNum, targetPct, narrow: narrow, w: w),
      ],
    ];

    final foodcostHeaderTable = DataTable(
      columnSpacing: narrow ? 3 : 10,
      horizontalMargin: narrow ? 3 : 10,
      headingRowHeight: narrow ? 30 : 38,
      dataRowMinHeight: 0,
      dataRowMaxHeight: 0,
      showBottomBorder: true,
      border: tableBorder,
      columns: tableColumns,
      rows: const [],
    );

    final foodcostBodyTable = DataTable(
      columnSpacing: narrow ? 3 : 10,
      horizontalMargin: narrow ? 3 : 10,
      headingRowHeight: 0.01,
      dataRowMinHeight: narrow ? 18 : 30,
      dataRowMaxHeight: narrow ? 45 : 64,
      showBottomBorder: true,
      border: tableBorder,
      columns: tableColumns,
      rows: tableRows,
    );

    final tableArea = Scrollbar(
      child: Padding(
        padding: EdgeInsets.fromLTRB(narrow ? 6 : 14, 0, narrow ? 6 : 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groups.isNotEmpty)
              SingleChildScrollView(
                controller: _headerHScroll,
                scrollDirection: Axis.horizontal,
                child: foodcostHeaderTable,
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _vScroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (groups.isNotEmpty)
                      SingleChildScrollView(
                        controller: _bodyHScroll,
                        scrollDirection: Axis.horizontal,
                        child: foodcostBodyTable,
                      ),
                    if (groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: widget.dishes.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : Text(
                                loc.t('menu_empty_dishes') ?? '',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final modeSegment = SegmentedButton<FoodcostPricingMode>(
      segments: [
        ButtonSegment<FoodcostPricingMode>(
          value: FoodcostPricingMode.markupOnCost,
          label: Text(
            loc.t('foodcost_mode_markup') ?? 'Наценка к с/с',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(fontSize: isPhoneLayout ? 11 : 13),
          ),
        ),
        ButtonSegment<FoodcostPricingMode>(
          value: FoodcostPricingMode.costShareOfPrice,
          label: Text(
            loc.t('foodcost_mode_cost_share') ?? 'Доля с/с в цене',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(fontSize: isPhoneLayout ? 11 : 13),
          ),
        ),
      ],
      selected: {_mode},
      onSelectionChanged: (s) {
        final m = s.first;
        setState(() => _mode = m);
        unawaited(_persistMode(m));
      },
      showSelectedIcon: false,
    );

    final menuSegment = (shortViewport &&
            widget.onMenuSegmentChanged != null &&
            widget.menuSegmentValue != null)
        ? SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(
                value: 0,
                label: Text(
                  loc.t('menu') ?? 'Меню',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text(
                  loc.t('menu_tab_foodcost'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
            selected: {widget.menuSegmentValue!},
            onSelectionChanged: (s) => widget.onMenuSegmentChanged!(s.first),
            showSelectedIcon: false,
          )
        : null;

    final pctField = SizedBox(
      width: narrow ? 82 : 96,
      child: TextField(
        controller: _targetPctController,
        decoration: const InputDecoration(
          labelText: '%',
          border: OutlineInputBorder(),
          isDense: true,
          isCollapsed: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _persistTarget(),
        onEditingComplete: _persistTarget,
      ),
    );

    final compactControls = isPhoneLayout;
    final controls = Padding(
      padding: EdgeInsets.fromLTRB(narrow ? 8 : 14, 0, narrow ? 8 : 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compactControls)
            Row(
              children: [
                if (shortViewport && menuSegment != null) ...[
                  Flexible(fit: FlexFit.loose, child: menuSegment),
                  const SizedBox(width: 4),
                ],
                Expanded(child: modeSegment),
                const SizedBox(width: 4),
                pctField,
              ],
            )
          else
            modeSegment,
          if (!compactControls) ...[
            const SizedBox(height: 6),
            Align(
              alignment: narrow ? Alignment.center : Alignment.centerLeft,
              child: pctField,
            ),
          ],
          SizedBox(height: shortViewport ? 4 : 6),
          TextField(
            decoration: InputDecoration(
              labelText: loc.t('foodcost_search_hint') ?? 'Поиск',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 10, vertical: shortViewport ? 7 : 10),
            ),
            textAlignVertical: TextAlignVertical.center,
            onChanged: (v) => setState(() => _query = v),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_hideControlsOnScroll) controls,
        Expanded(
          child: tableArea,
        ),
      ],
    );
  }
}
