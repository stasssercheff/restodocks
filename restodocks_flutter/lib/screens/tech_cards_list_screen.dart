import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:excel/excel.dart' hide Border;

import '../utils/number_format_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:feature_spotlight/feature_spotlight.dart';

import '../models/models.dart';
import '../services/page_tour_service.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/tour_tooltip.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';
import '../services/ai_service.dart';
import '../services/ai_service_supabase.dart';
import '../services/services.dart';
import '../services/excel_export_service.dart';
import '../services/tech_card_cost_hydrator.dart';
import '../services/tech_card_nutrition_hydrator.dart';

enum _TtkImportMode { single, multi }

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen(
      {super.key, this.department = 'kitchen', this.embedded = false});

  final String department;
  final bool embedded;

  @override
  State<TechCardsListScreen> createState() => _TechCardsListScreenState();
}

class _TechCardsListScreenState extends State<TechCardsListScreen> {
  List<TechCard> _list = [];
  // Индексы/кэши для рекурсивного расчёта себестоимости (включая вложенные ПФ из импортированных ТТК).
  Map<String, TechCard> _techCardsById = {};
  Map<String, ({double cost, double output})> _resolvedCostMemo = {};

  /// Для расчёта ₽/кг в списке по ценам номенклатуры (ингредиенты в БД часто без cost/pricePerKg).
  ProductStoreSupabase? _priceProductStore;
  String? _priceEstablishmentId;
  final Map<String, double> _nomenclaturePriceByName = {};
  bool _loading = true;
  /// Фоновая догрузка продуктов/номенклатуры и гидрация цен/нутриентов после первого показа списка.
  bool _listDetailsHydrating = false;
  int _loadHydrateToken = 0;
  int _loadRequestToken = 0;
  bool _loadingExcel = false;
  bool _loadingTtkIsPdf = false;
  String? _error;
  Set<String> _selectedTechCards = {}; // ID выбранных карточек
  bool _selectionMode = false;
  String? _filterSection; // null = все цеха
  String? _filterCategory; // null = все категории
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Map<String, List<TechCard>> _pfCandidatesByNormalizedName = {};
  List<({TechCard tc, int issues, String subtitle})>? _cachedReviewList;
  int? _cachedReviewCount;
  Object? _lastReviewCacheKey;
  bool _reviewCacheScheduled = false;
  int _listVersion = 0;
  Timer? _searchDebounceTimer;
  Timer? _reconcileTimer;
  TechCardsReconcileNotifier? _reconcileNotifier;
  int _lastReconcileNotifierVersion = 0;
  bool _reconciling = false;
  DateTime _lastReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ttkTourCheckDone = false;
  SpotlightController? _ttkTourController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTtkTour());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (!mounted) return;
      _reconcileNotifier = context.read<TechCardsReconcileNotifier>();
      _lastReconcileNotifierVersion = _reconcileNotifier!.version;
      _reconcileNotifier!.addListener(_handleTechCardsReconcileSignal);
      _reconcileTimer?.cancel();
      _reconcileTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _tryReconcileTechCards(force: false);
      });
      _tryReconcileTechCards(force: false);
    });
  }

  Future<void> _maybeShowTtkTour() async {
    if (_ttkTourCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    if (employee == null) return;
    _ttkTourCheckDone = true;
    final tourService = context.read<PageTourService>();
    final forceReplay =
        tourService.consumeReplayRequest(PageTourKeys.techCards);
    if (!forceReplay &&
        await tourService.isPageTourSeen(employee.id, PageTourKeys.techCards))
      return;
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    // Цвет подсветки для кнопок в красной AppBar
    const actionGlowColor = Colors.white;
    final controller = SpotlightController(
      steps: [
        SpotlightStep(
          id: 'ttk-subdivision',
          text: PageTourService.getTourTtkSubdivision(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkSubdivision(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: true,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-tab-pf',
          text: PageTourService.getTourTtkTabPf(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkTabPf(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-tab-dishes',
          text: PageTourService.getTourTtkTabDishes(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkTabDishes(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-tab-review',
          text: PageTourService.getTourTtkTabReview(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkTabReview(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-count',
          text: PageTourService.getTourTtkCount(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          glowColor: actionGlowColor,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkCount(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-create',
          text: PageTourService.getTourTtkCreate(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          glowColor: actionGlowColor,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkCreate(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-import',
          text: PageTourService.getTourTtkImport(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          glowColor: actionGlowColor,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkImport(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-export',
          text: PageTourService.getTourTtkExport(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          glowColor: actionGlowColor,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkExport(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: false,
            nextLabel: PageTourService.getTourNext(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
        SpotlightStep(
          id: 'ttk-refresh',
          text: PageTourService.getTourTtkRefresh(loc),
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          glowColor: actionGlowColor,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: PageTourService.getTourTtkRefresh(loc),
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: false,
            isLastStep: true,
            nextLabel: PageTourService.getTourDone(loc),
            skipLabel: PageTourService.getTourFinish(loc),
          ),
        ),
      ],
      onTourCompleted: () async {
        if (!forceReplay)
          await tourService.markPageTourSeen(
              employee.id, PageTourKeys.techCards);
        if (mounted) setState(() => _ttkTourController = null);
      },
      onTourSkipped: () async {
        if (!forceReplay)
          await tourService.markPageTourSeen(
              employee.id, PageTourKeys.techCards);
        if (mounted) setState(() => _ttkTourController = null);
      },
    );
    if (!mounted) return;
    setState(() => _ttkTourController = controller);
    // Ждём 2 кадра + 400мс — чтобы таргет ttk-subdivision успел отрендериться и подсветиться.
    void startWhenReady() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Future.delayed(const Duration(milliseconds: 400), () {
            if (!mounted) return;
            try {
              FeatureSpotlight.of(context).startTour(controller);
            } catch (e) {
              debugPrint('[Tour] TTK startTour error: $e');
              if (mounted) setState(() => _ttkTourController = null);
            }
          });
        });
      });
    }

    startWhenReady();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _reconcileTimer?.cancel();
    if (_reconcileNotifier != null) {
      _reconcileNotifier!.removeListener(_handleTechCardsReconcileSignal);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Порядок категорий: кухня (без напитков) и бар (только напитки/снеки)
  static const _kitchenCategoryOrder = [
    'sauce',
    'vegetables',
    'zagotovka',
    'salad',
    'zakuska',
    'meat',
    'seafood',
    'poultry',
    'side',
    'subside',
    'bakery',
    'dessert',
    'decor',
    'soup',
    'misc',
    'banquet',
    'catering'
  ];
  static const _barCategoryOrder = [
    'alcoholic_cocktails',
    'non_alcoholic_drinks',
    'hot_drinks',
    'drinks_pure',
    'snacks',
    'zakuska',
    'beverages'
  ];

  List<({String category, List<TechCard> cards})> _groupByCategory(
      List<TechCard> cards) {
    final order = (widget.department == 'bar' ||
            widget.department == 'banquet-catering-bar')
        ? _barCategoryOrder
        : _kitchenCategoryOrder;
    final grouped = <String, List<TechCard>>{};
    for (final tc in cards) {
      final cat = tc.category.isNotEmpty ? tc.category : 'misc';
      grouped.putIfAbsent(cat, () => []).add(tc);
    }
    final result = <({String category, List<TechCard> cards})>[];
    for (final cat in order) {
      final list = grouped.remove(cat);
      if (list != null && list.isNotEmpty)
        result.add((category: cat, cards: list));
    }
    for (final e in grouped.entries) {
      result.add((category: e.key, cards: e.value));
    }
    return result;
  }

  /// Группировка по цеху.
  static const _sectionOrder = [
    'all',
    'hot_kitchen',
    'cold_kitchen',
    'preparation',
    'prep',
    'confectionery',
    'pastry',
    'grill',
    'pizza',
    'sushi',
    'bakery',
    'banquet_catering',
    'bar',
    'hidden'
  ];

  List<({String section, List<TechCard> cards})> _groupBySection(
      List<TechCard> cards) {
    final grouped = <String, List<TechCard>>{};
    for (final tc in cards) {
      final key = _sectionKeyForGroup(tc);
      grouped.putIfAbsent(key, () => []).add(tc);
    }
    final result = <({String section, List<TechCard> cards})>[];
    final seen = <String>{};
    for (final s in _sectionOrder) {
      final list = grouped.remove(s);
      if (list != null && list.isNotEmpty) {
        result.add((section: s, cards: list));
        seen.add(s);
      }
    }
    for (final e in grouped.entries) {
      result.add((section: e.key, cards: e.value));
    }
    return result;
  }

  String _sectionKeyForGroup(TechCard tc) {
    if (tc.sections.isEmpty) return 'hidden';
    if (tc.sections.contains('all')) return 'all';
    return tc.sections.first;
  }

  String _sectionLabelForDisplay(TechCard tc, LocalizationService loc) {
    if (tc.sections.isEmpty) return loc.t('ttk_sections_hidden');
    if (tc.sections.contains('all')) return loc.t('ttk_sections_all');
    final labels = tc.sections
        .map((s) => _sectionCodeToLabel(s, loc))
        .where((l) => l.isNotEmpty);
    return labels.join(', ');
  }

  String _sectionCodeToLabel(String code, LocalizationService loc) {
    const keys = {
      'hot_kitchen': 'section_hot_kitchen',
      'cold_kitchen': 'section_cold_kitchen',
      'preparation': 'section_prep',
      'prep': 'section_prep',
      'confectionery': 'section_pastry',
      'pastry': 'section_pastry',
      'grill': 'section_grill',
      'pizza': 'section_pizza',
      'sushi': 'section_sushi',
      'bakery': 'section_bakery',
      'banquet_catering': 'section_banquet_catering',
    };
    final key = keys[code];
    return key != null ? (loc.t(key) ?? code) : code;
  }

  String _sectionGroupLabel(String sectionKey, LocalizationService loc) {
    if (sectionKey == 'all') return loc.t('ttk_sections_all');
    if (sectionKey == 'hidden') return loc.t('ttk_sections_hidden');
    return _sectionCodeToLabel(sectionKey, loc);
  }

  /// Метка текущего подразделения (цех) для шапки
  String _departmentHeaderLabel(LocalizationService loc) {
    switch (widget.department) {
      case 'kitchen':
        return loc.t('department_kitchen');
      case 'bar':
        return loc.t('department_bar');
      case 'banquet-catering':
        return loc.t('banquet_catering');
      case 'banquet-catering-bar':
        return '${loc.t('banquet_catering')} + ${loc.t('department_bar')}';
      default:
        return loc.t('department_kitchen');
    }
  }

  /// id -> name для пользовательских категорий (загружаются в _load).
  final Map<String, String> _customCategoryNames = {};

  String _categoryLabel(String c, LocalizationService loc) {
    if (TechCardServiceSupabase.isCustomCategory(c)) {
      final id = TechCardServiceSupabase.customCategoryId(c);
      return _customCategoryNames[id] ?? c;
    }
    final lang = loc.currentLanguageCode;
    final Map<String, Map<String, String>> categoryTranslations = {
      'sauce': {'ru': 'Соус', 'en': 'Sauce'},
      'vegetables': {'ru': 'Овощи', 'en': 'Vegetables'},
      'zagotovka': {'ru': 'Заготовка', 'en': 'Preparation'},
      'salad': {'ru': 'Салат', 'en': 'Salad'},
      'meat': {'ru': 'Мясо', 'en': 'Meat'},
      'seafood': {'ru': 'Рыба', 'en': 'Seafood'},
      'poultry': {'ru': 'Птица', 'en': 'Poultry'},
      'side': {'ru': 'Гарнир', 'en': 'Side dish'},
      'subside': {'ru': 'Подгарнир', 'en': 'Sub-side dish'},
      'bakery': {'ru': 'Выпечка', 'en': 'Bakery'},
      'dessert': {'ru': 'Десерт', 'en': 'Dessert'},
      'decor': {'ru': 'Декор', 'en': 'Decor'},
      'soup': {'ru': 'Суп', 'en': 'Soup'},
      'misc': {'ru': 'Разное', 'en': 'Misc'},
      'beverages': {'ru': 'Напитки', 'en': 'Beverages'},
      'alcoholic_cocktails': {
        'ru': 'Алкогольные коктейли',
        'en': 'Alcoholic cocktails'
      },
      'non_alcoholic_drinks': {
        'ru': 'Безалкогольные напитки',
        'en': 'Non-alcoholic drinks'
      },
      'hot_drinks': {'ru': 'Горячие напитки', 'en': 'Hot drinks'},
      'drinks_pure': {'ru': 'Напитки в чистом виде', 'en': 'Drinks (neat)'},
      'snacks': {'ru': 'Снеки', 'en': 'Snacks'},
      'zakuska': {'ru': 'Закуска', 'en': 'Appetizer'},
      'banquet': {'ru': 'Банкет', 'en': 'Banquet'},
      'catering': {'ru': 'Кейтеринг', 'en': 'Catering'},
    };

    return categoryTranslations[c]?[lang] ?? c;
  }

  /// То же, что «Итого стоимость за кг» в редакторе — один источник истины.
  /// Рекурсивно учитывает вложенные ПФ (sourceTechCardId) через _resolveTechCardCostOutput.
  /// Fallback: TechCardCostHydrator по гидратированным ингредиентам; выход — tc.yield если сумма по строкам 0.
  double _calculateCostPerKg(TechCard tc) {
    final resolved = _resolveTechCardCostOutput(tc.id, <String>{});
    final effectiveOutput =
        resolved.output > 0 ? resolved.output : (tc.yield > 0 ? tc.yield : 0.0);
    if (effectiveOutput > 0 && resolved.cost > 0) {
      return (resolved.cost / effectiveOutput) * 1000;
    }
    final hydrated = _techCardsById[tc.id];
    if (hydrated != null) {
      final fromHydrator = TechCardCostHydrator.costPerKgOutput(hydrated);
      if (fromHydrator > 0) return fromHydrator;
    }
    return 0.0;
  }

  /// Себестоимость за порцию (для блюд): totalCost * portionWeight / yield.
  double _calculateCostPerPortion(TechCard tc) {
    if (tc.ingredients.isEmpty || tc.portionWeight <= 0) return 0.0;
    final resolved = _resolveTechCardCostOutput(tc.id, <String>{});
    if (resolved.cost <= 0 || resolved.output <= 0) return 0.0;
    final yieldG = tc.yield > 0 ? tc.yield : resolved.output;
    if (yieldG <= 0) return 0.0;
    return resolved.cost * tc.portionWeight / yieldG;
  }

  double _ingredientResolvedOutput(TTIngredient ing) {
    if (ing.outputWeight > 0) return ing.outputWeight;
    if (ing.netWeight > 0) return ing.netWeight;
    return ing.grossWeight;
  }

  double _costFromPricePerKgLine(double pricePerKg, TTIngredient ing) {
    if (pricePerKg <= 0) return 0.0;
    final qty = ing.grossWeight > 0
        ? ing.grossWeight
        : (ing.netWeight > 0 ? ing.netWeight : ing.outputWeight);
    if (qty <= 0) return 0.0;
    final u = ing.unit.toLowerCase().trim();
    if (u == 'шт' || u == 'pcs') {
      final gpp = ing.gramsPerPiece ?? 50.0;
      if (gpp <= 0) return 0.0;
      return pricePerKg * (qty / gpp);
    }
    return pricePerKg * (qty / 1000.0);
  }

  /// Стоимость строки-продукта: из ТТК, pricePerKg строки, номенклатуры (как в редакторе).
  /// Нужны loadProducts + loadNomenclature; для филиала ключ цены — id филиала, не головы.
  double _leafIngredientMonetaryCost(TTIngredient ing) {
    if (ing.effectiveCost > 0) return ing.effectiveCost;
    // В БД часто netWeight=0 при ненулевом брутто — effectiveCost даёт 0, хотя pricePerKg задан.
    if (ing.pricePerKg != null && ing.pricePerKg! > 0 && ing.grossWeight > 0) {
      final fromLine = _costFromPricePerKgLine(ing.pricePerKg!, ing);
      if (fromLine > 0) return fromLine;
    }
    final store = _priceProductStore;
    final estId = _priceEstablishmentId;
    if (store == null || estId == null || estId.isEmpty) return 0.0;
    final pid = ing.productId;
    final name = ing.productName.trim();
    if ((pid == null || pid.isEmpty) && name.isEmpty) return 0.0;

    final product = store.findProductForIngredient(pid, name);
    final resolvedId =
        product?.id ?? (pid != null && pid.isNotEmpty ? pid : null);
    if (resolvedId == null || resolvedId.isEmpty) {
      final byName = _nomenclaturePriceByName[
              _normalizeForTechCardName(_stripPfPrefix(name))] ??
          0.0;
      return _costFromPricePerKgLine(byName, ing);
    }

    final ep = store.getEstablishmentPrice(resolvedId, estId);
    double unitPrice = ep?.$1 ?? 0.0;
    if (unitPrice <= 0 &&
        product != null &&
        product.basePrice != null &&
        product.basePrice! > 0) {
      unitPrice = product.basePrice!;
    }
    return _costFromPricePerKgLine(unitPrice, ing);
  }

  Future<void> _buildNomenclatureNamePriceIndex(
      ProductStoreSupabase store, String estId) async {
    _nomenclaturePriceByName.clear();
    final ids = store.nomenclatureProductIds.toList(growable: false);
    if (ids.isEmpty) return;

    const chunkSize = 500;
    final client = Supabase.instance.client;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
          i, i + chunkSize > ids.length ? ids.length : i + chunkSize);
      try {
        final data = await client
            .from('products')
            .select('id, name, names')
            .inFilter('id', chunk);
        final list = data as List;
        for (final row in list) {
          final m = Map<String, dynamic>.from(row as Map);
          final id = (m['id'] ?? '').toString();
          if (id.isEmpty) continue;
          final ep = store.getEstablishmentPrice(id, estId);
          final price = ep?.$1 ?? 0.0;
          if (price <= 0) continue;

          final rawNames = <String>[
            (m['name'] ?? '').toString(),
          ];
          final namesObj = m['names'];
          if (namesObj is Map) {
            for (final v in namesObj.values) {
              if (v != null) rawNames.add(v.toString());
            }
          }

          for (final n in rawNames) {
            final key = _normalizeForTechCardName(_stripPfPrefix(n));
            if (key.isEmpty) continue;
            _nomenclaturePriceByName.putIfAbsent(key, () => price);
          }
        }
      } catch (_) {
        // Не блокируем открытие списка ТТК.
      }
    }
  }

  String _normalizeForTechCardName(String s) {
    final cleaned = s
        .replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9\s]+'), ' ')
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return cleaned;
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty)
        .toList()
      ..sort();
    return tokens.join(' ');
  }

  String _stripPfPrefix(String s) {
    final r =
        RegExp(r'^(пф|п/ф|п\.ф\.|pf|prep|sf|hf)\s*', caseSensitive: false);
    return s.trim().replaceFirst(r, '').trim();
  }

  void _rebuildPfCandidatesIndex(LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final pfCards = _list.where((t) => t.isSemiFinished).toList();
    final map = <String, List<TechCard>>{};
    for (final pf in pfCards) {
      final names = <String>[
        pf.getDisplayNameInLists(lang),
        pf.getLocalizedDishName(lang),
        pf.dishName,
      ];
      for (final n in names) {
        final k = _normalizeForTechCardName(_stripPfPrefix(n));
        if (k.isEmpty) continue;
        final list = map.putIfAbsent(k, () => []);
        if (!list.any((x) => x.id == pf.id)) list.add(pf);
      }
    }
    _pfCandidatesByNormalizedName = map;
  }

  /// Отфильтрованный список для вкладки «На проверку».
  List<TechCard> _getReviewFilteredList(LocalizationService loc) {
    final query = _searchController.text.trim().toLowerCase();
    var result = _list;
    if (query.isNotEmpty) {
      final lang = loc.currentLanguageCode;
      result = result
          .where((tc) =>
              tc.getDisplayNameInLists(lang).toLowerCase().contains(query))
          .toList();
    }
    if (_filterSection != null) {
      result = result
          .where((tc) =>
              tc.sections.contains(_filterSection) ||
              tc.sections.contains('all'))
          .toList();
    }
    if (_filterCategory != null) {
      result = result
          .where((tc) =>
              (tc.category.isEmpty ? 'misc' : tc.category) == _filterCategory)
          .toList();
    }
    return result;
  }

  /// Ключ для инвалидации кэша «На проверку» — меняется при смене списка/фильтров.
  Object _reviewCacheKey(List<TechCard> reviewFiltered) =>
      (_listVersion, _filterSection, _filterCategory, _searchController.text);

  /// Тяжёлые вычисления для вкладки «На проверку» — в след. кадре, чтобы не блокировать UI.
  void _ensureReviewCache(
      LocalizationService loc, List<TechCard> reviewFiltered) {
    final key = _reviewCacheKey(reviewFiltered);
    if (_lastReviewCacheKey == key) return;
    if (_reviewCacheScheduled) return;
    _reviewCacheScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reviewCacheScheduled = false;
      if (!mounted) return;
      _rebuildPfCandidatesIndex(loc);
      final list = reviewFiltered
          .map((tc) {
            final issues = _reviewIssuesCount(tc, loc);
            return (
              tc: tc,
              issues: issues,
              subtitle: _getReviewSubtitle(tc, loc)
            );
          })
          .where((e) => e.issues > 0)
          .toList()
        ..sort((a, b) => b.issues.compareTo(a.issues));
      if (!mounted) return;
      setState(() {
        _lastReviewCacheKey = key;
        _cachedReviewList = list;
        _cachedReviewCount = list.length;
      });
    });
  }

  int _ambiguousPfIngredientCount(TechCard tc, LocalizationService loc) {
    if (tc.ingredients.isEmpty) return 0;
    var cnt = 0;
    for (final ing in tc.ingredients) {
      final sid = ing.sourceTechCardId;
      final hasSourceId = sid != null && sid.isNotEmpty;
      if (hasSourceId) continue;
      final name = ing.productName.trim();
      if (name.isEmpty) continue;
      final key = _normalizeForTechCardName(_stripPfPrefix(name));
      final candidates = (_pfCandidatesByNormalizedName[key] ?? const [])
          .where((c) => c.id != tc.id)
          .toList();
      final sameEst = candidates
          .where((c) => c.establishmentId == tc.establishmentId)
          .toList();
      final ambiguous =
          sameEst.length > 1 || (sameEst.isEmpty && candidates.length > 1);
      if (ambiguous) cnt++;
    }
    return cnt;
  }

  /// Проверяет, есть ли в ТТК проблемы с ценами (отсутствуют цены у ингредиентов или вложенных ПФ)
  int _missingPriceIssuesCount(TechCard tc) {
    if (tc.ingredients.isEmpty) return 0;
    var cnt = 0;
    for (final ing in tc.ingredients) {
      // Проверяем листовые ингредиенты (продукты)
      if (ing.sourceTechCardId == null || ing.sourceTechCardId!.isEmpty) {
        if (ing.productName.trim().isNotEmpty) {
          // Есть продукт, но нет цены
          if (ing.effectiveCost <= 0 &&
              (ing.pricePerKg == null || ing.pricePerKg! <= 0)) {
            // Проверяем, есть ли цена в номенклатуре
            final product = _priceProductStore?.findProductForIngredient(
                ing.productId, ing.productName);
            if (product != null && _priceEstablishmentId != null) {
              final priceInfo = _priceProductStore!
                  .getEstablishmentPrice(product.id, _priceEstablishmentId!);
              final pricePerKg = priceInfo?.$1 ?? 0.0;
              final basePrice = product.basePrice ?? 0.0;
              if (pricePerKg <= 0 && basePrice <= 0) {
                cnt++; // Нет цены ни в номенклатуре, ни базовой
              }
            } else {
              cnt++; // Продукт не найден или нет номенклатуры
            }
          }
        }
      } else {
        // Проверяем вложенные ПФ
        final pfId = ing.sourceTechCardId!;
        final pf = _techCardsById[pfId];
        if (pf != null) {
          // Рекурсивно проверяем ПФ на отсутствие цен
          final pfIssues = _missingPriceIssuesCount(pf);
          if (pfIssues > 0) {
            cnt++; // В ПФ есть проблемы с ценами
          }
        }
      }
    }
    return cnt;
  }

  /// Проверяет, есть ли проблемы с весом в ТТК
  int _missingWeightIssuesCount(TechCard tc) {
    var cnt = 0;

    // Проверяем общий выход (вес готового продукта)
    if (tc.yield <= 0) {
      cnt++;
    }

    // Проверяем вес порции для блюд
    if (!tc.isSemiFinished && tc.portionWeight <= 0) {
      cnt++;
    }

    // Проверяем веса ингредиентов (нетто и брутто)
    for (final ing in tc.ingredients) {
      if (ing.netWeight <= 0 || ing.grossWeight <= 0) {
        cnt++;
      }
    }

    return cnt;
  }

  /// Проверяет, есть ли проблемы с технологией в ТТК
  int _missingTechnologyIssuesCount(TechCard tc) {
    var cnt = 0;

    // Проверяем технологию приготовления (многоязычная)
    if (tc.technologyLocalized == null || tc.technologyLocalized!.isEmpty) {
      cnt++;
    } else {
      // Проверяем, что есть хотя бы одна непустая технология
      final hasNonEmptyTechnology =
          tc.technologyLocalized!.values.any((tech) => tech.trim().isNotEmpty);
      if (!hasNonEmptyTechnology) {
        cnt++;
      }
    }

    return cnt;
  }

  /// Общий счётчик проблем для вкладки "На проверку"
  int _reviewIssuesCount(TechCard tc, LocalizationService loc) {
    final ambiguousCount = _ambiguousPfIngredientCount(tc, loc);
    final priceIssuesCount = _missingPriceIssuesCount(tc);
    final weightIssuesCount = _missingWeightIssuesCount(tc);
    final technologyIssuesCount = _missingTechnologyIssuesCount(tc);
    return ambiguousCount +
        priceIssuesCount +
        weightIssuesCount +
        technologyIssuesCount;
  }

  /// Генерирует подзаголовок для элемента в списке "На проверку"
  String _getReviewSubtitle(TechCard tc, LocalizationService loc) {
    final ambiguousCount = _ambiguousPfIngredientCount(tc, loc);
    final priceIssuesCount = _missingPriceIssuesCount(tc);
    final weightIssuesCount = _missingWeightIssuesCount(tc);
    final technologyIssuesCount = _missingTechnologyIssuesCount(tc);

    final issues = <String>[];
    if (ambiguousCount > 0) {
      issues.add('Неоднозначных ПФ: $ambiguousCount');
    }
    if (priceIssuesCount > 0) {
      issues.add('Без цен: $priceIssuesCount');
    }
    if (weightIssuesCount > 0) {
      issues.add('Без веса: $weightIssuesCount');
    }
    if (technologyIssuesCount > 0) {
      issues.add('Без технологии: $technologyIssuesCount');
    }

    return issues.join(', ');
  }

  List<TechCard> _pfCandidatesByIngredientName(String name) {
    final key = _normalizeForTechCardName(_stripPfPrefix(name));
    if (key.isEmpty) return const [];

    final indexed = _pfCandidatesByNormalizedName[key];
    if (indexed != null && indexed.isNotEmpty) return indexed;

    // Fallback для расчёта цены: если индекс ещё не собран, ищем ПФ по всем загруженным ТТК.
    final out = <TechCard>[];
    for (final tc in _techCardsById.values) {
      if (!tc.isSemiFinished) continue;
      final names = <String>[
        tc.dishName,
        ...?tc.dishNameLocalized?.values,
      ];
      for (final n in names) {
        final k = _normalizeForTechCardName(_stripPfPrefix(n));
        if (k != key) continue;
        if (!out.any((x) => x.id == tc.id)) out.add(tc);
      }
    }
    return out;
  }

  String? _inferNestedPfId(TechCard owner, TTIngredient ing) {
    final sid = ing.sourceTechCardId;
    if (sid != null && sid.isNotEmpty) return sid;
    final name = ing.productName.trim();
    if (name.isEmpty) return null;

    final candidates = _pfCandidatesByIngredientName(name)
        .where((c) => c.id != owner.id)
        .toList();
    if (candidates.isEmpty) return null;

    final sameEst = candidates
        .where((c) => c.establishmentId == owner.establishmentId)
        .toList();
    if (sameEst.length == 1) return sameEst.first.id;
    if (sameEst.isEmpty && candidates.length == 1) return candidates.first.id;
    return null;
  }

  Widget _buildReviewList(LocalizationService loc, bool canEdit) {
    final lang = loc.currentLanguageCode;
    final list = _cachedReviewList;

    if (list == null) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Нет ТТК на проверку',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final item = list[i];
          final tc = item.tc;
          final name = tc.getDisplayNameInLists(lang);
          return ListTile(
            tileColor: Theme.of(ctx).colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant)),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showReviewBottomSheet(tc, loc),
          );
        },
      ),
    );
  }

  /// Собирает список неоднозначных ПФ ингредиентов
  List<({TTIngredient ing, List<TechCard> candidates})>
      _getAmbiguousPfIngredients(TechCard tc) {
    final matches = <({TTIngredient ing, List<TechCard> candidates})>[];
    for (final ing in tc.ingredients) {
      final sid = ing.sourceTechCardId;
      if (sid != null && sid.isNotEmpty && sid == tc.id) {
        continue;
      }
      final hasSourceId = sid != null && sid.isNotEmpty;
      if (hasSourceId) continue;
      final name = ing.productName.trim();
      if (name.isEmpty) continue;
      final key = _normalizeForTechCardName(_stripPfPrefix(name));
      final candidates = (_pfCandidatesByNormalizedName[key] ?? const [])
          .where((c) => c.id != tc.id)
          .toList();
      final sameEst = candidates
          .where((c) => c.establishmentId == tc.establishmentId)
          .toList();
      final effectiveCandidates = sameEst.isNotEmpty ? sameEst : candidates;
      if (effectiveCandidates.length > 1) {
        matches.add((ing: ing, candidates: effectiveCandidates));
      }
    }
    return matches;
  }

  /// Собирает список ингредиентов без цен
  List<TTIngredient> _getMissingPriceIngredients(TechCard tc) {
    final missingPrice = <TTIngredient>[];
    for (final ing in tc.ingredients) {
      // Проверяем листовые ингредиенты (продукты)
      if (ing.sourceTechCardId == null || ing.sourceTechCardId!.isEmpty) {
        if (ing.productName.trim().isNotEmpty) {
          // Есть продукт, но нет цены
          if (ing.effectiveCost <= 0 &&
              (ing.pricePerKg == null || ing.pricePerKg! <= 0)) {
            // Проверяем, есть ли цена в номенклатуре
            final product = _priceProductStore?.findProductForIngredient(
                ing.productId, ing.productName);
            if (product != null && _priceEstablishmentId != null) {
              final priceInfo = _priceProductStore!
                  .getEstablishmentPrice(product.id, _priceEstablishmentId!);
              final pricePerKg = priceInfo?.$1 ?? 0.0;
              final basePrice = product.basePrice ?? 0.0;
              if (pricePerKg <= 0 && basePrice <= 0) {
                missingPrice.add(ing); // Нет цены ни в номенклатуре, ни базовой
              }
            } else {
              missingPrice.add(ing); // Продукт не найден или нет номенклатуры
            }
          }
        }
      }
    }
    return missingPrice;
  }

  /// Собирает список проблем с весом
  List<String> _getMissingWeightIssues(TechCard tc) {
    final issues = <String>[];

    // Проверяем общий выход (вес готового продукта)
    if (tc.yield <= 0) {
      issues.add('Отсутствует общий выход (вес готового продукта)');
    }

    // Проверяем вес порции для блюд
    if (!tc.isSemiFinished && tc.portionWeight <= 0) {
      issues.add('Отсутствует вес порции');
    }

    // Проверяем веса ингредиентов (нетто и брутто)
    for (final ing in tc.ingredients) {
      if (ing.netWeight <= 0 || ing.grossWeight <= 0) {
        final issuesList = <String>[];
        if (ing.netWeight <= 0) issuesList.add('нетто');
        if (ing.grossWeight <= 0) issuesList.add('брутто');
        issues.add('Нет веса (${issuesList.join(', ')}): ${ing.productName}');
      }
    }

    return issues;
  }

  /// Собирает список проблем с технологией
  List<String> _getMissingTechnologyIssues(TechCard tc) {
    final issues = <String>[];

    // Проверяем технологию приготовления (многоязычная)
    if (tc.technologyLocalized == null || tc.technologyLocalized!.isEmpty) {
      issues.add('Отсутствует технология приготовления');
    } else {
      // Проверяем, что есть хотя бы одна непустая технология
      final hasNonEmptyTechnology =
          tc.technologyLocalized!.values.any((tech) => tech.trim().isNotEmpty);
      if (!hasNonEmptyTechnology) {
        issues.add('Все технологии приготовления пустые');
      }
    }

    return issues;
  }

  Future<void> _showReviewBottomSheet(
      TechCard tc, LocalizationService loc) async {
    final lang = loc.currentLanguageCode;
    final ambiguousMatches = _getAmbiguousPfIngredients(tc);
    final missingPriceIngredients = _getMissingPriceIngredients(tc);
    final missingWeightIssues = _getMissingWeightIssues(tc);
    final missingTechnologyIssues = _getMissingTechnologyIssues(tc);

    if (ambiguousMatches.isEmpty &&
        missingPriceIngredients.isEmpty &&
        missingWeightIssues.isEmpty &&
        missingTechnologyIssues.isEmpty) return;

    final selected = <String, String>{
      for (final m in ambiguousMatches) m.ing.id: m.candidates.first.id,
    };
    var saving = false;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateDlg) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: 12 + MediaQuery.of(ctx2).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'На проверку: ${tc.getDisplayNameInLists(lang)}',
                            style: Theme.of(ctx2)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed:
                              saving ? null : () => Navigator.of(ctx2).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          // Секция неоднозначных ПФ
                          if (ambiguousMatches.isNotEmpty) ...[
                            Text(
                              'Неоднозначные полуфабрикаты (${ambiguousMatches.length})',
                              style:
                                  Theme.of(ctx2).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                            ),
                            const SizedBox(height: 8),
                            ...ambiguousMatches.map((m) {
                              final selId =
                                  selected[m.ing.id] ?? m.candidates.first.id;
                              final selPf = m.candidates.firstWhere(
                                  (c) => c.id == selId,
                                  orElse: () => m.candidates.first);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Theme.of(ctx2)
                                          .colorScheme
                                          .outlineVariant),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Theme.of(ctx2)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(m.ing.productName,
                                        style: Theme.of(ctx2)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: selId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                          isDense: true,
                                          labelText: 'Кандидат ПФ'),
                                      items: m.candidates
                                          .map((c) => DropdownMenuItem<String>(
                                                value: c.id,
                                                child: Text(
                                                    c.getDisplayNameInLists(
                                                        lang)),
                                              ))
                                          .toList(),
                                      onChanged: saving
                                          ? null
                                          : (v) {
                                              if (v == null) return;
                                              setStateDlg(
                                                  () => selected[m.ing.id] = v);
                                            },
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () =>
                                            _showTechCardCompositionDialog(
                                                ctx2, selPf, lang),
                                        child: const Text('Состав'),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                          // Секция ингредиентов без цен
                          if (missingPriceIngredients.isNotEmpty) ...[
                            if (ambiguousMatches.isNotEmpty)
                              const SizedBox(height: 16),
                            Text(
                              'Ингредиенты без цен (${missingPriceIngredients.length})',
                              style:
                                  Theme.of(ctx2).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                            ),
                            const SizedBox(height: 8),
                            ...missingPriceIngredients.map((ing) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Theme.of(ctx2)
                                          .colorScheme
                                          .outlineVariant),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Theme.of(ctx2)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        ing.productName,
                                        style:
                                            Theme.of(ctx2).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                          // Секция проблем с весом
                          if (missingWeightIssues.isNotEmpty) ...[
                            if (ambiguousMatches.isNotEmpty ||
                                missingPriceIngredients.isNotEmpty)
                              const SizedBox(height: 16),
                            Text(
                              'Проблемы с весом (${missingWeightIssues.length})',
                              style:
                                  Theme.of(ctx2).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                            ),
                            const SizedBox(height: 8),
                            ...missingWeightIssues.map((issue) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Theme.of(ctx2)
                                          .colorScheme
                                          .outlineVariant),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Theme.of(ctx2)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.scale, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        issue,
                                        style:
                                            Theme.of(ctx2).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                          // Секция проблем с технологией
                          if (missingTechnologyIssues.isNotEmpty) ...[
                            if (ambiguousMatches.isNotEmpty ||
                                missingPriceIngredients.isNotEmpty ||
                                missingWeightIssues.isNotEmpty)
                              const SizedBox(height: 16),
                            Text(
                              'Проблемы с технологией (${missingTechnologyIssues.length})',
                              style:
                                  Theme.of(ctx2).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                            ),
                            const SizedBox(height: 8),
                            ...missingTechnologyIssues.map((issue) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Theme.of(ctx2)
                                          .colorScheme
                                          .outlineVariant),
                                  borderRadius: BorderRadius.circular(10),
                                  color: Theme.of(ctx2)
                                      .colorScheme
                                      .surfaceContainerLowest,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.engineering, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        issue,
                                        style:
                                            Theme.of(ctx2).textTheme.bodyMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    Navigator.of(ctx2).pop();
                                    final needRefresh = await context
                                        .push<bool>('/tech-cards/${tc.id}');
                                    if (mounted && needRefresh == true)
                                      _load(showLoading: false);
                                  },
                            child: const Text('Открыть карточку'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (ambiguousMatches.isNotEmpty)
                          Expanded(
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setStateDlg(() => saving = true);
                                      try {
                                        final svc = context
                                            .read<TechCardServiceSupabase>();
                                        final updatedIngredients =
                                            tc.ingredients.map((ing) {
                                          final pickedId = selected[ing.id];
                                          if (pickedId == null) return ing;
                                          final pf = _list.firstWhere(
                                            (x) => x.id == pickedId,
                                            orElse: () =>
                                                _pfCandidatesByNormalizedName
                                                    .values
                                                    .expand((e) => e)
                                                    .firstWhere((x) =>
                                                        x.id == pickedId),
                                          );
                                          final display =
                                              pf.getDisplayNameInLists(lang);
                                          return ing.copyWith(
                                            sourceTechCardId: pf.id,
                                            sourceTechCardName: display,
                                            productName: display,
                                          );
                                        }).toList();
                                        final updatedTc = tc.copyWith(
                                            ingredients: updatedIngredients);
                                        await svc.saveTechCard(updatedTc);
                                        if (mounted) {
                                          await _load();
                                        }
                                        if (ctx2.mounted)
                                          Navigator.of(ctx2).pop();
                                      } catch (e) {
                                        if (ctx2.mounted) {
                                          ScaffoldMessenger.of(ctx2)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Ошибка сохранения: $e')));
                                        }
                                      } finally {
                                        if (ctx2.mounted)
                                          setStateDlg(() => saving = false);
                                      }
                                    },
                              child: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Text('Применить'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTechCardCompositionDialog(
      BuildContext ctx, TechCard tc, String lang) {
    final items = tc.ingredients
        .where((i) => i.productName.trim().isNotEmpty)
        .toList(growable: false);
    final text = items.isEmpty
        ? '—'
        : items.map((i) {
            final w = i.outputWeight > 0
                ? i.outputWeight
                : (i.netWeight > 0 ? i.netWeight : i.grossWeight);
            final unit =
                i.unit?.trim().isNotEmpty == true ? i.unit!.trim() : 'г';
            return '${i.productName} — ${w.toStringAsFixed(0)} $unit';
          }).join('\n');

    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(tc.getDisplayNameInLists(lang)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child:
                Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: Text(MaterialLocalizations.of(dctx).closeButtonLabel),
          ),
        ],
      ),
    );
  }

  /// Возвращает рекурсивно посчитанную себестоимость ТТК и её "выход" (сумма выходов по строкам).
  /// Важно: для импортированных вложенных ПФ `ingredient.cost` может быть 0, поэтому считаем глубоко.
  ({double cost, double output}) _resolveTechCardCostOutput(
    String techCardId,
    Set<String> resolving,
  ) {
    final cached = _resolvedCostMemo[techCardId];
    if (cached != null) return cached;

    if (!resolving.add(techCardId)) {
      // Цикл ссылок (ошибка данных) — чтобы не уйти в бесконечную рекурсию.
      return (cost: 0.0, output: 0.0);
    }

    final tc = _techCardsById[techCardId];
    if (tc == null) {
      resolving.remove(techCardId);
      return (cost: 0.0, output: 0.0);
    }

    double totalCost = 0.0;
    double totalOutput = 0.0;

    for (final ing in tc.ingredients) {
      final ingredientOutput = _ingredientResolvedOutput(ing);
      totalOutput += ingredientOutput;

      final nestedId = _inferNestedPfId(tc, ing);
      // Продукты из номенклатуры: в БД часто cost=0 — подтягиваем цену из ProductStore.
      if (nestedId == null || nestedId.isEmpty) {
        totalCost += _leafIngredientMonetaryCost(ing);
        continue;
      }
      final nested = _resolveTechCardCostOutput(nestedId, resolving);
      if (ingredientOutput <= 0) continue;

      // Масштабируем себестоимость вложенной ТТК пропорционально "выходу" этой строки.
      if (nested.output > 0 && nested.cost > 0) {
        totalCost += nested.cost * ingredientOutput / nested.output;
      } else if (ing.effectiveCost > 0) {
        // Fallback: в строке могла сохраниться стоимость после гидратации в редакторе.
        totalCost += ing.effectiveCost;
      }
    }

    final resolved = (cost: totalCost, output: totalOutput);
    _resolvedCostMemo[techCardId] = resolved;
    resolving.remove(techCardId);
    return resolved;
  }

  bool _legacyBarCardMatch(TechCard tc, Set<String> customBarIds) {
    const barCats = {
      'beverages',
      'alcoholic_cocktails',
      'non_alcoholic_drinks',
      'hot_drinks',
      'drinks_pure',
      'snacks',
      'zakuska'
    };
    final cat = (String c) => c.isEmpty ? 'misc' : c;
    final c = cat(tc.category);
    if (barCats.contains(c)) return true;
    if (tc.sections.contains('bar')) return true;
    if (TechCardServiceSupabase.isCustomCategory(tc.category) &&
        customBarIds
            .contains(TechCardServiceSupabase.customCategoryId(tc.category)))
      return true;
    return false;
  }

  List<TechCard> _filterListByDepartment(
      List<TechCard> processedAll, Set<String> customBarIds) {
    if (widget.department == 'banquet-catering') {
      return processedAll
          .where((tc) => tc.category == 'banquet' || tc.category == 'catering')
          .toList();
    }
    if (widget.department == 'banquet-catering-bar') {
      const barCategories = {
        'beverages',
        'alcoholic_cocktails',
        'non_alcoholic_drinks',
        'hot_drinks',
        'drinks_pure',
        'snacks',
        'zakuska'
      };
      return processedAll
          .where((tc) =>
              (tc.category == 'banquet' || tc.category == 'catering') &&
              (tc.sections.contains('bar') ||
                  tc.sections.contains('all') ||
                  barCategories.contains(tc.category)))
          .toList();
    }
    if (widget.department == 'bar') {
      return processedAll.where((tc) {
        final dep = tc.department.trim().toLowerCase();
        if (dep == 'bar') return true;
        // Старые карточки без department=bar — по категории и цеху.
        if (dep.isNotEmpty && dep != 'kitchen') return false;
        return _legacyBarCardMatch(tc, customBarIds);
      }).toList();
    }
    if (widget.department == 'hall') return [];
    // Кухня: не отсекаем по «барным» категориям — в БД tech_cards.department = kitchen.
    return processedAll
        .where((tc) => tc.department.trim().toLowerCase() != 'bar')
        .toList();
  }

  Future<void> _load({bool showLoading = true}) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    final requestToken = ++_loadRequestToken;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'no_establishment';
        _listDetailsHydrating = false;
      });
      return;
    }
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
        _listDetailsHydrating = false;
      });
    }
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final productStore = context.read<ProductStoreSupabase>();

      // Минимум для показа списка: только ТТК и категории (без вложенных ingredients).
      late Future<List<TechCard>> allCardsFuture;
      if (est.isBranch) {
        allCardsFuture = Future.wait([
          svc.getTechCardsForEstablishment(est.dataEstablishmentId, includeIngredients: false),
          svc.getTechCardsForEstablishment(est.id, includeIngredients: false),
        ]).then((results) => [...results[0], ...results[1]]);
      } else {
        allCardsFuture =
            svc.getTechCardsForEstablishment(est.dataEstablishmentId, includeIngredients: false);
      }
      final customCategoriesFuture = Future.wait([
        svc.getCustomCategories(est.dataEstablishmentId, 'kitchen'),
        svc.getCustomCategories(est.dataEstablishmentId, 'bar'),
      ]);
      final all = await allCardsFuture;
      if (!mounted || requestToken != _loadRequestToken) return;
      List<({String id, String name})> customKitchen = const [];
      List<({String id, String name})> customBar = const [];
      try {
        final customResults = await customCategoriesFuture
            .timeout(const Duration(milliseconds: 350));
        customKitchen = customResults[0];
        customBar = customResults[1];
      } catch (_) {}
      var customBarIds = customBar.map((c) => c.id).toSet();

      final toPersistSelfLink = <TechCard>[];
      final sanitizedAll = <TechCard>[];
      for (final tc in all) {
        final s = stripInvalidNestedPfSelfLinks(tc);
        sanitizedAll.add(s);
        if (!identical(s, tc)) toPersistSelfLink.add(s);
      }
      var processedAll = sanitizedAll;

      final canSeeCosts = emp?.hasRole('owner') == true ||
          emp?.hasRole('executive_chef') == true ||
          emp?.hasRole('sous_chef') == true ||
          emp?.hasRole('manager') == true ||
          emp?.hasRole('general_manager') == true;

      // Тяжёлое (products, nomenclature, fillIngredients, hydrate, индекс цен) — в фоне
      final hydrateToken = ++_loadHydrateToken;
      Future.microtask(() async {
        try {
          await productStore.loadProducts().catchError((_) {});
          if (est.isBranch) {
            await productStore
                .loadNomenclatureForBranch(est.id, est.dataEstablishmentId!)
                .catchError((_) {});
          } else {
            await productStore
                .loadNomenclature(est.dataEstablishmentId)
                .catchError((_) {});
          }
          if (!mounted || requestToken != _loadRequestToken) return;
          var withData = List<TechCard>.from(processedAll);
          // В shallow-режиме в cards ингредиенты не вшиты — догружаем всегда,
          // иначе вкладки/подсчёты (в т.ч. для без-цены ролей) будут работать некорректно.
          withData = await svc.fillIngredientsForCardsBulk(withData);
          if (canSeeCosts) {
            final estPriceId = est.isBranch ? est.id : est.dataEstablishmentId;
            if (estPriceId != null && estPriceId.isNotEmpty) {
              withData = TechCardCostHydrator.hydrate(
                  withData, productStore, estPriceId);
            }
          }
          withData =
              TechCardNutritionHydrator.hydrate(withData, productStore);
          if (!mounted || requestToken != _loadRequestToken) return;
          await _buildNomenclatureNamePriceIndex(
              productStore, est.isBranch ? est.id : est.dataEstablishmentId);
          if (!mounted || requestToken != _loadRequestToken) return;
          var filteredList = _filterListByDepartment(withData, customBarIds);
          final byId = {for (final tc in withData) tc.id: tc};
          final referencedIds = <String>{};
          for (final tc in withData) {
            for (final ing in tc.ingredients) {
              final id = ing.sourceTechCardId;
              if (id != null && id.trim().isNotEmpty)
                referencedIds.add(id.trim());
            }
          }
          final existing = filteredList.map((e) => e.id).toSet();
          for (final id in referencedIds) {
            final ref = byId[id];
            if (ref != null && !existing.contains(id)) {
              filteredList = [...filteredList, ref];
              existing.add(id);
            }
          }
          if (!mounted || requestToken != _loadRequestToken) return;
          setState(() {
            _list = filteredList;
            _listVersion++;
            _cachedReviewList = null;
            _cachedReviewCount = null;
            _lastReviewCacheKey = null;
            _techCardsById = {for (final t in withData) t.id: t};
            _priceProductStore = productStore;
            _priceEstablishmentId =
                est.isBranch ? est.id : est.dataEstablishmentId;
          });
          if (mounted && requestToken == _loadRequestToken) {
            _rebuildPfCandidatesIndex(context.read<LocalizationService>());
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _list.isEmpty) return;
              final loc = context.read<LocalizationService>();
              _ensureReviewCache(loc, _getReviewFilteredList(loc));
            });
          }
        } catch (_) {
        } finally {
          if (mounted &&
              requestToken == _loadRequestToken &&
              hydrateToken == _loadHydrateToken) {
            setState(() => _listDetailsHydrating = false);
          }
        }
      });

      _customCategoryNames.clear();
      for (final c in customKitchen) _customCategoryNames[c.id] = c.name;
      for (final c in customBar) _customCategoryNames[c.id] = c.name;
      List<TechCard> list = _filterListByDepartment(processedAll, customBarIds);

      // Добавляем ТТК, на которые есть ссылки из ингредиентов
      try {
        final byId = {for (final tc in processedAll) tc.id: tc};
        final referencedIds = <String>{};
        for (final tc in processedAll) {
          for (final ing in tc.ingredients) {
            final id = ing.sourceTechCardId;
            if (id != null && id.trim().isNotEmpty)
              referencedIds.add(id.trim());
          }
        }
        final existing = list.map((e) => e.id).toSet();
        for (final id in referencedIds) {
          final ref = byId[id];
          if (ref == null) continue;
          if (existing.contains(id)) continue;
          list.add(ref);
          existing.add(id);
        }
      } catch (_) {}
      if (mounted) {
        _priceProductStore = productStore;
        _priceEstablishmentId = est.isBranch ? est.id : est.dataEstablishmentId;
        setState(() {
          _list = list;
          _listVersion++;
          _cachedReviewList = null;
          _cachedReviewCount = null;
          _lastReviewCacheKey = null;
          _loading = false;
          _listDetailsHydrating = list.isNotEmpty;
        });
        _techCardsById = {for (final tc in processedAll) tc.id: tc};
        _resolvedCostMemo.clear();
        _ensureTechCardTranslations(svc, list);
        _warmPdfParser();
        // Предзагрузка кэша «На проверку» — чтобы при переключении вкладки данные были готовы
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _list.isEmpty) return;
          final loc = context.read<LocalizationService>();
          _ensureReviewCache(loc, _getReviewFilteredList(loc));
        });
      }

      // Если категории не успели к первому кадру — догружаем и обновляем фильтрацию/лейблы позднее.
      unawaited(customCategoriesFuture.then((customResults) {
        if (!mounted || requestToken != _loadRequestToken) return;
        final kitchen = customResults[0];
        final bar = customResults[1];
        final newBarIds = bar.map((c) => c.id).toSet();
        _customCategoryNames.clear();
        for (final c in kitchen) {
          _customCategoryNames[c.id] = c.name;
        }
        for (final c in bar) {
          _customCategoryNames[c.id] = c.name;
        }
        customBarIds = newBarIds;
        final relisted = _filterListByDepartment(processedAll, customBarIds);
        setState(() {
          _list = relisted;
          _listVersion++;
          _cachedReviewList = null;
          _cachedReviewCount = null;
          _lastReviewCacheKey = null;
        });
      }).catchError((_) {}));

      if (toPersistSelfLink.isNotEmpty && mounted) {
        Future.microtask(() async {
          final saveSvc = context.read<TechCardServiceSupabase>();
          for (final tc in toPersistSelfLink.take(25)) {
            if (!mounted) break;
            try {
              await saveSvc.saveTechCard(tc, skipHistory: true);
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
          _listDetailsHydrating = false;
        });
    }
  }

  void _warmPdfParser() {
    final ai = context.read<AiService>();
    if (ai is AiServiceSupabase) ai.warmPdfParser();
  }

  Future<void> _ensureTechCardTranslations(
      TechCardServiceSupabase svc, List<TechCard> cards) async {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (lang == 'ru') return;
    final missing = cards
        .where(
          (tc) => !(tc.dishNameLocalized?.containsKey(lang) == true &&
              (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false)),
        )
        .toList();
    var i = 0;
    for (final tc in missing) {
      if (!mounted) break;
      if (i > 0 && i % 2 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      i++;
      try {
        final translated = await svc
            .translateTechCardName(tc.id, tc.dishName, lang)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (translated != null && mounted) {
          final idx = _list.indexWhere((c) => c.id == tc.id);
          if (idx >= 0) {
            final updated = _list[idx].copyWith(
              dishNameLocalized: {
                ...(_list[idx].dishNameLocalized ?? {}),
                lang: translated
              },
            );
            setState(() => _list[idx] = updated);
          }
        }
      } catch (_) {}
    }
  }

  /// Экспорт одной ТТК
  Future<void> _exportSingleTechCard(TechCard techCard) async {
    try {
      await ExcelExportService().exportSingleTechCard(techCard);
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  loc.t('ttk_exported').replaceFirst('%s', techCard.dishName))),
        );
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
        );
      }
    }
  }

  /// Экспорт выбранных ТТК
  Future<void> _exportSelectedTechCards() async {
    final selectedCards =
        _list.where((card) => _selectedTechCards.contains(card.id)).toList();
    if (selectedCards.isEmpty) {
      final loc = context.read<LocalizationService>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ttk_select_at_least_one'))),
      );
      return;
    }

    try {
      await ExcelExportService().exportSelectedTechCards(selectedCards);
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc
                  .t('ttk_exported_selected')
                  .replaceFirst('%s', '${selectedCards.length}'))),
        );
        setState(() {
          _selectedTechCards.clear();
          _selectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
        );
      }
    }
  }

  /// Экспорт всех ТТК
  Future<void> _exportAllTechCards() async {
    final loc = context.read<LocalizationService>();
    if (_list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ttk_none_to_export'))),
      );
      return;
    }

    try {
      await ExcelExportService().exportAllTechCards(_list);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc
                  .t('ttk_exported_all')
                  .replaceFirst('%s', '${_list.length}'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
        );
      }
    }
  }

  /// Переключение режима выбора
  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedTechCards.clear();
      }
    });
  }

  /// Выбор/снятие выбора ТТК
  void _toggleTechCardSelection(String techCardId) {
    setState(() {
      if (_selectedTechCards.contains(techCardId)) {
        _selectedTechCards.remove(techCardId);
      } else {
        _selectedTechCards.add(techCardId);
      }
    });
  }

  void _handleTechCardsReconcileSignal() {
    if (!mounted) return;
    final notifier =
        _reconcileNotifier ?? context.read<TechCardsReconcileNotifier>();
    if (notifier.version == _lastReconcileNotifierVersion) return;
    _lastReconcileNotifierVersion = notifier.version;
    _tryReconcileTechCards(force: true);
  }

  Future<void> _tryReconcileTechCards({required bool force}) async {
    if (!mounted) return;
    if (_reconciling) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastReconcileAt) < const Duration(seconds: 30)) return;
    if (_loading) return;
    if (_list.isEmpty) return;

    _reconciling = true;
    _lastReconcileAt = now;
    try {
      final loc = context.read<LocalizationService>();
      _rebuildPfCandidatesIndex(loc);
      final svc = context.read<TechCardServiceSupabase>();
      final lang = loc.currentLanguageCode;

      final updated = <TechCard>[];
      for (final tc in _list) {
        if (tc.ingredients.isEmpty) continue;
        var working = stripInvalidNestedPfSelfLinks(tc);
        var changed = !identical(working, tc);
        final newIngredients = working.ingredients.map((ing) {
          final sid = ing.sourceTechCardId;
          if (sid != null && sid.isNotEmpty && sid == working.id) {
            changed = true;
            return ing.copyWith(
                sourceTechCardId: null, sourceTechCardName: null);
          }
          final hasSourceId = sid != null && sid.isNotEmpty;
          if (hasSourceId) return ing;
          final name = ing.productName.trim();
          if (name.isEmpty) return ing;
          final key = _normalizeForTechCardName(_stripPfPrefix(name));
          final candidatesAll = (_pfCandidatesByNormalizedName[key] ?? const [])
              .where((c) => c.id != working.id)
              .toList();
          final sameEst = candidatesAll
              .where((c) => c.establishmentId == working.establishmentId)
              .toList();
          if (sameEst.length != 1) return ing; // не угадываем
          final picked = sameEst.first;
          final display = picked.getDisplayNameInLists(lang);
          changed = true;
          return ing.copyWith(
            sourceTechCardId: picked.id,
            sourceTechCardName: display,
            productName: display,
          );
        }).toList();
        if (changed) {
          updated.add(working.copyWith(ingredients: newIngredients));
        }
      }

      // Ограничиваем нагрузку: максимум 20 карточек за тик.
      final toSave = updated.take(20).toList();
      for (final tc in toSave) {
        await svc.saveTechCard(tc, skipHistory: true);
      }

      if (toSave.isNotEmpty && mounted) {
        await _load(showLoading: false);
      }
    } catch (_) {
      // Фоновая автодосвязка — не критична.
    } finally {
      _reconciling = false;
    }
  }

  static const _maxFilesSingleTtk = 10;
  static const _maxFilesMultiTtk = 10;

  static const _allowedTtkExtensions = [
    'xlsx',
    'xls',
    'csv',
    'pdf',
    'docx',
    'doc'
  ];

  Future<void> _createFromExcel(
      BuildContext context, LocalizationService loc) async {
    _TtkImportMode dialogMode = _TtkImportMode.single;
    // Возвращаем (mode, files) — FilePicker вызывается внутри onPressed, без Navigator.pop перед ним,
    // чтобы сохранить «user gesture» и сработать на мобильных (Safari/Chrome требуют прямой вызов из tap).
    final result =
        await showDialog<({_TtkImportMode mode, List<PlatformFile> files})>(
      context: context,
      builder: (ctx) {
        final l = ctx.read<LocalizationService>();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(l.t('ttk_import_file') ?? 'Импорт ТТК'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<_TtkImportMode>(
                      value: _TtkImportMode.single,
                      groupValue: dialogMode,
                      onChanged: (_) =>
                          setState(() => dialogMode = _TtkImportMode.single),
                      title: Text(l.t('ttk_import_mode_single') ??
                          'Одна ТТК в документе'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48, bottom: 8),
                      child: Text(
                        l.t('ttk_import_mode_single_hint') ??
                            'Можно выбрать до 10 файлов (в каждом файле — одна карточка).',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                    RadioListTile<_TtkImportMode>(
                      value: _TtkImportMode.multi,
                      groupValue: dialogMode,
                      onChanged: (_) =>
                          setState(() => dialogMode = _TtkImportMode.multi),
                      title: Text(l.t('ttk_import_mode_multi') ??
                          'Несколько ТТК в документе'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text(
                        l.t('ttk_import_multi_format_hint') ??
                            'Excel и Word: карточки — друг под другом, в один столбец (не рядом в 2 колонки). Одинаковая разметка: у каждой ТТК те же колонки (название, продукты, вес, технология). Иначе система не распознает.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(l.t('cancel') ?? 'Отмена'),
                ),
                FilledButton(
                  onPressed: () async {
                    // Вызов pickFiles напрямую из tap — без pop до него — сохраняет user gesture (мобильные).
                    // На мобильных FileType.any избегает бага с allowedExtensions (каталоги не открываются).
                    final pickResult = kIsWeb
                        ? await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: _allowedTtkExtensions,
                            withData: true,
                            allowMultiple: true,
                          )
                        : await FilePicker.platform.pickFiles(
                            type: FileType.any,
                            withData: true,
                            allowMultiple: true,
                          );
                    if (!ctx.mounted) return;
                    if (pickResult == null || pickResult.files.isEmpty) return;
                    final valid = pickResult.files.where((f) {
                      final parts = f.name.split('.');
                      final ext =
                          (f.extension ?? (parts.length > 1 ? parts.last : ''))
                              .toLowerCase();
                      return _allowedTtkExtensions.contains(ext) &&
                          (f.bytes != null && f.bytes!.isNotEmpty);
                    }).toList();
                    if (valid.isEmpty) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text(l.t('file_read_failed') ??
                                  'Не удалось прочитать файл')),
                        );
                      }
                      return;
                    }
                    Navigator.of(ctx).pop((mode: dialogMode, files: valid));
                  },
                  child:
                      Text(l.t('ttk_import_select_files') ?? 'Выбрать файлы'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || result == null) return;

    final mode = result.mode;
    final files = result.files;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.t('file_read_failed'))));
      return;
    }
    final maxFiles =
        mode == _TtkImportMode.single ? _maxFilesSingleTtk : _maxFilesMultiTtk;
    if (files.length > maxFiles) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mode == _TtkImportMode.single
            ? (loc.t('ttk_import_max_files') ??
                'Выберите до $_maxFilesSingleTtk файлов (1 файл = 1 ТТК)')
            : (loc.t('ttk_import_max_files_multi') ??
                'Выберите до $_maxFilesMultiTtk файлов')),
      ));
      return;
    }
    setState(() {
      _loadingExcel = true;
      _loadingTtkIsPdf =
          files.any((f) => (f.extension?.toLowerCase() ?? '').contains('pdf'));
    });
    try {
      final est = context.read<AccountManagerSupabase>().establishment;
      final establishmentId = est?.dataEstablishmentId;
      final ai = context.read<AiService>();
      final productStore = context.read<ProductStoreSupabase>();
      // Подсказки из номенклатуры для AI (приоритет — данные карточки; номенклатура только подсказка)
      List<String>? nomenclatureNames;
      if (establishmentId != null) {
        try {
          await productStore.loadProducts();
          await productStore.loadNomenclature(establishmentId);
          final prods = productStore.getNomenclatureProducts(establishmentId);
          nomenclatureNames = prods
              .expand((p) =>
                  [p.name, ...?p.names?.values.map((n) => n?.toString())])
              .whereType<String>()
              .where((s) => s.trim().length > 1)
              .toSet()
              .take(300)
              .toList();
        } catch (_) {}
      }
      var allCards = <TechCardRecognitionResult>[];
      int failedCount = 0;
      for (final file in files) {
        final bytes = file.bytes!;
        final uBytes = Uint8List.fromList(bytes);
        final isPdf = (file.extension?.toLowerCase() ?? '').contains('pdf');
        List<TechCardRecognitionResult> list;
        if (isPdf) {
          list = await ai.parseTechCardsFromPdf(uBytes,
              establishmentId: establishmentId,
              nomenclatureProductNames: nomenclatureNames);
        } else {
          int? sheetIndex;
          if (ai is AiServiceSupabase) {
            final sheetNames =
                await AiServiceSupabase.getExcelSheetNames(uBytes);
            if (sheetNames.length > 1 && mounted) {
              sheetIndex =
                  await _showSheetPicker(context, loc, file.name, sheetNames);
              if (!mounted) return;
              if (sheetIndex == null) continue; // пользователь отменил
            } else if (sheetNames.length == 1) {
              sheetIndex = 0;
            }
          }
          list = await ai.parseTechCardsFromExcel(uBytes,
              establishmentId: establishmentId,
              sheetIndex: sheetIndex,
              nomenclatureProductNames: nomenclatureNames);
          // Если парсер вернул пусто и «несколько листов» — показываем выбор листа и парсим выбранный
          if (list.isEmpty &&
              ai is AiServiceSupabase &&
              AiServiceSupabase.lastParseMultipleSheetNames != null &&
              AiServiceSupabase.lastParseMultipleSheetNames!.isNotEmpty &&
              mounted) {
            final names = AiServiceSupabase.lastParseMultipleSheetNames!;
            sheetIndex = await _showSheetPicker(context, loc, file.name, names);
            if (!mounted) return;
            if (sheetIndex != null) {
              list = await ai.parseTechCardsFromExcel(uBytes,
                  establishmentId: establishmentId,
                  sheetIndex: sheetIndex,
                  nomenclatureProductNames: nomenclatureNames);
            }
          }
          if (list.isEmpty) list = _parseSimpleExcelNames(uBytes);
        }
        if (!mounted) return;
        if (list.isEmpty) {
          failedCount++;
          continue;
        }
        if (mode == _TtkImportMode.single && list.length > 1) {
          if (mounted) setState(() => _loadingExcel = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text((loc.t('ttk_import_multi_card_in_file') ??
                    'В файле «%s» несколько карточек. Выберите режим «Несколько ТТК в документе» или загрузите файлы по одному.')
                .replaceFirst('%s', file.name)),
            duration: const Duration(seconds: 5),
          ));
          if (!mounted) return;
          await _createFromExcel(context, loc);
          return;
        }
        if (mode == _TtkImportMode.multi && list.isEmpty) {
          // В режиме «несколько ТТК» пустой результат по файлу — пропускаем, не выкидываем в диалог
          failedCount++;
          continue;
        }
        if (mode == _TtkImportMode.multi && list.length == 1) {
          // Одна карточка в режиме «несколько» — всё равно ведём на проверку (парсер мог не найти все блоки)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text((loc.t('ttk_import_one_card_in_multi') ??
                      'В файле «%s» распознана 1 карточка. Если их больше — выберите режим «Одна ТТК в документе» для каждого или проверьте разметку.')
                  .replaceFirst('%s', file.name)),
              duration: const Duration(seconds: 4),
            ));
          }
        }
        allCards.addAll(list);
      }
      // При пустом parse но с rows — создаём placeholder и ведём на проверку для ручного ввода и обучения
      if (allCards.isEmpty) {
        final hasRows = context.read<AiService>() is AiServiceSupabase &&
            AiServiceSupabase.lastParsedRows != null &&
            AiServiceSupabase.lastParsedRows!.length >= 2;
        if (hasRows) {
          allCards = [
            TechCardRecognitionResult(
              dishName: null,
              ingredients: [],
              technologyText: null,
              isSemiFinished: null,
              yieldGrams: null,
            )
          ];
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(loc.t('ttk_import_empty_parse_hint') ??
                  'Не удалось распознать автоматически. Заполните карточку вручную — при следующем импорте похожего файла применится обучение.'),
              duration: const Duration(seconds: 5),
            ));
          }
        } else {
          String msg;
          if (context.read<AiService>() is AiServiceSupabase) {
            final reason = AiServiceSupabase.lastParseTechCardExcelReason ??
                AiServiceSupabase.lastParseTechCardPdfReason;
            if (reason == 'ai_limit_exceeded' || reason == 'limit_3_per_day') {
              msg = loc.t('ai_ttk_limit_3_per_day') ?? '';
            } else if (reason == 'service_unavailable') {
              msg = loc.t('ai_ttk_pdf_service_unavailable') ??
                  'Сервис распознавания временно недоступен. Экспортируйте PDF в Word или Excel и загрузите снова.';
            } else if (reason == 'timeout_or_network') {
              msg = loc.t('ai_ttk_pdf_timeout') ??
                  (loc.t('ai_tech_card_pdf_format_hint') ??
                      'Таймаут загрузки PDF');
            } else if (reason != null &&
                reason.startsWith('extraction_failed')) {
              msg = loc.t('ai_ttk_pdf_extraction_failed') ??
                  (loc.t('ai_tech_card_pdf_format_hint') ??
                      'Не удалось извлечь текст из PDF');
            } else if (reason == 'empty_text') {
              msg = loc.t('ai_ttk_pdf_empty_text') ??
                  (loc.t('ai_tech_card_pdf_format_hint') ?? 'PDF без текста');
            } else if (reason != null && reason.isNotEmpty) {
              msg =
                  '${loc.t(failedCount == files.length && files.any((f) => (f.extension ?? '').toLowerCase().contains('pdf')) ? 'ai_tech_card_pdf_format_hint' : 'ai_tech_card_excel_format_hint') ?? 'Не удалось распознать ТТК'} ($reason)';
            } else {
              msg = loc.t('ai_tech_card_excel_format_hint') ??
                  'Не удалось распознать ТТК';
            }
          } else {
            msg = loc.t('ai_tech_card_excel_format_hint') ??
                'Не удалось распознать ТТК';
          }
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 15),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ));
          return;
        }
      }
      if (!mounted) return;
      if (failedCount > 0 && allCards.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              (loc.t('ttk_import_partial') ?? 'Загружено %s из %s файлов')
                  .replaceFirst('%s', '${allCards.length}')
                  .replaceFirst('%s', '${files.length}')),
          duration: const Duration(seconds: 3),
        ));
      }
      if (allCards.length == 1 && allCards.first.ingredients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  loc.t('ai_tech_card_loaded_names').replaceAll('%s', '1'))),
        );
      }
      final hasValidationErrors =
          context.read<AiService>() is AiServiceSupabase &&
              AiServiceSupabase.lastParseTechCardErrors != null &&
              AiServiceSupabase.lastParseTechCardErrors!.isNotEmpty;
      if (allCards.length == 1 && !hasValidationErrors) {
        final sig = context.read<AiService>() is AiServiceSupabase
            ? AiServiceSupabase.lastParseHeaderSignature
            : null;
        final sourceRows = context.read<AiService>() is AiServiceSupabase
            ? AiServiceSupabase.lastParsedRows
            : null;
        final hasMeta = sig != null && sig.isNotEmpty;
        context.push(
          widget.department == 'bar'
              ? '/tech-cards/new?department=bar'
              : '/tech-cards/new',
          extra: hasMeta || sourceRows != null
              ? {
                  'result': allCards.single,
                  'headerSignature': sig,
                  'sourceRows': sourceRows
                }
              : allCards.single,
        );
      } else {
        final sig = context.read<AiService>() is AiServiceSupabase
            ? AiServiceSupabase.lastParseHeaderSignature
            : null;
        final sourceRows = context.read<AiService>() is AiServiceSupabase
            ? AiServiceSupabase.lastParsedRows
            : null;
        context.push(
            '/tech-cards/import-review?department=${Uri.encodeComponent(widget.department)}',
            extra: {
              'cards': allCards,
              'headerSignature': sig,
              'sourceRows': sourceRows,
            });
      }
    } finally {
      if (mounted) setState(() => _loadingExcel = false);
    }
  }

  Future<void> _createFromText(
      BuildContext context, LocalizationService loc) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('ttk_import_text') ?? 'Вставить из текста'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: InputDecoration(
              hintText:
                  'Название блюда\nнаименование\tЕд.изм\tНорма закладки\t...\n1\tПродукт\tкг\t0,100\t...\nВыход\t\tкг\t1,000',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    setState(() => _loadingExcel = true);
    try {
      final est = context.read<AccountManagerSupabase>().establishment;
      final establishmentId = est?.dataEstablishmentId;
      final list = await context
          .read<AiService>()
          .parseTechCardsFromText(result, establishmentId: establishmentId);
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('ai_tech_card_excel_format_hint') ??
                  'Не удалось распознать ТТК в тексте')),
        );
        return;
      }
      final sig = context.read<AiService>() is AiServiceSupabase
          ? AiServiceSupabase.lastParseHeaderSignature
          : null;
      final sourceRows = context.read<AiService>() is AiServiceSupabase
          ? AiServiceSupabase.lastParsedRows
          : null;
      final hasMeta = sig != null && sig.isNotEmpty;
      if (list.length == 1) {
        context.push(
            widget.department == 'bar'
                ? '/tech-cards/new?department=bar'
                : '/tech-cards/new',
            extra: hasMeta || sourceRows != null
                ? {
                    'result': list.single,
                    'headerSignature': sig,
                    'sourceRows': sourceRows,
                  }
                : list.single);
      } else {
        context.push(
            '/tech-cards/import-review?department=${Uri.encodeComponent(widget.department)}',
            extra: {
              'cards': list,
              'headerSignature': sig,
              'sourceRows': sourceRows,
            });
      }
    } finally {
      if (mounted) setState(() => _loadingExcel = false);
    }
  }

  /// Диалог выбора листа Excel при нескольких листах в файле. Возвращает индекс (0-based) или null при отмене.
  static Future<int?> _showSheetPicker(BuildContext context,
      LocalizationService loc, String fileName, List<String> sheetNames) async {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('ttk_import_select_sheet') ?? 'Выберите лист'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (loc.t('ttk_import_select_sheet_hint') ??
                        'В файле «%s» несколько листов. Импортировать за раз можно только один лист.')
                    .replaceFirst('%s', fileName),
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(sheetNames.length, (i) {
                      final name = sheetNames[i].isEmpty
                          ? '${loc.t('ttk_sheet') ?? 'Лист'} ${i + 1}'
                          : sheetNames[i];
                      return ListTile(
                        title: Text(name),
                        onTap: () => Navigator.of(ctx).pop(i),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );
  }

  static String _pdfFailureMessage(String reason, LocalizationService loc) {
    if (reason == 'ai_limit_exceeded' || reason == 'limit_3_per_day') {
      return loc.t('ai_ttk_limit_3_per_day');
    }
    if (reason.startsWith('empty_text'))
      return 'PDF не содержит извлекаемого текста.';
    if (reason.startsWith('extraction_failed'))
      return 'Не удалось прочитать PDF.';
    if (reason.startsWith('ai_error') ||
        reason.contains('429') ||
        reason.contains('quota')) {
      return 'Лимит ИИ исчерпан. Попробуйте позже.';
    }
    if (reason == 'ai_empty_response' || reason == 'ai_no_cards') {
      return loc.t('ai_tech_card_pdf_format_hint');
    }
    if (reason == 'invoke_null')
      return 'Сервер не ответил (503). Первый запрос после паузы может занять до минуты — подождите и попробуйте снова.';
    return loc.t('ai_tech_card_pdf_format_hint');
  }

  /// Простой разбор Excel: столбец A или B — названия ПФ/блюд.
  static List<TechCardRecognitionResult> _parseSimpleExcelNames(
      Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes.toList());
      final sheetName =
          excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
      if (sheetName == null) return [];
      final sheet = excel.tables[sheetName]!;
      final list = <TechCardRecognitionResult>[];
      for (var r = 0; r < sheet.maxRows; r++) {
        String name = _excelCellToStr(sheet
                .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
                .value)
            .trim();
        if (name.isEmpty && sheet.maxColumns > 1) {
          name = _excelCellToStr(sheet
                  .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r))
                  .value)
              .trim();
        }
        if (name.isEmpty) continue;
        list.add(TechCardRecognitionResult(
          dishName: name,
          ingredients: [],
          isSemiFinished: true,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static String _excelCellToStr(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) {
      final val = v.value;
      try {
        final t = (val as dynamic).text;
        if (t != null) return t is String ? t : t.toString();
      } catch (_) {}
      final String s = val is String ? val as String : (val ?? '').toString();
      return s;
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    return v.toString();
  }

  void _showTtkBranchFilterPicker(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase accountManager,
    List<Establishment> branches,
  ) {
    final branchFilter = context.read<TtkBranchFilterService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('ttk_branch_display')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.store),
              title: Text(loc.t('main_establishment_short')),
              trailing: branchFilter.selectedBranchId == null
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () async {
                await branchFilter.setBranchFilter(null);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ...branches.map((b) => ListTile(
                  leading: const Icon(Icons.account_tree),
                  title: Text(b.name),
                  trailing: branchFilter.selectedBranchId == b.id
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () async {
                    await branchFilter.setBranchFilter(b.id);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }

  /// Себестоимость видят только руководство: собственник, шеф, су-шеф, барменеджер.
  bool _canSeeCost(AccountManagerSupabase acc) {
    final emp = acc.currentEmployee;
    if (emp == null) return false;
    return emp.hasRole('owner') ||
        emp.hasRole('executive_chef') ||
        emp.hasRole('sous_chef') ||
        emp.hasRole('bar_manager');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final canEdit =
        accountManager.currentEmployee?.canEditChecklistsAndTechCards ?? false;
    final showCost = _canSeeCost(accountManager);

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
                tooltip: loc.t('ttk_cancel_selection'),
              )
            : (widget.embedded ? null : appBarBackButton(context)),
        title: ScrollToTopAppBarTitle(
          child: Text(
            _selectionMode
                ? loc
                    .t('ttk_select_count')
                    .replaceFirst('%s', '${_selectedTechCards.length}')
                : loc.t('tech_cards'),
          ),
        ),
        actions: _buildAppBarActions(loc, canEdit),
      ),
      body: Stack(
        children: [
          _buildBody(loc, canEdit, showCost),
          if (_loadingExcel)
            ColoredBox(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(height: 16),
                        Text(_loadingTtkIsPdf
                            ? loc.t('loading_ttk_pdf')
                            : loc.t('loading_excel')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  List<Widget> _buildAppBarActions(LocalizationService loc, bool canEdit) {
    final ctrl = _ttkTourController;
    Widget wrap(String id, Widget w) =>
        ctrl != null ? SpotlightTarget(id: id, controller: ctrl, child: w) : w;

    final countWidget = !_selectionMode
        ? Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_list.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          )
        : null;
    final createWidget = canEdit
        ? IconButton(
            icon: Icon(Icons.add,
                color: _loading ? Theme.of(context).disabledColor : null),
            tooltip: loc.t('create_tech_card'),
            onPressed: _loading
                ? null
                : () async {
                    final path = widget.department == 'bar'
                        ? '/tech-cards/new?department=bar'
                        : '/tech-cards/new';
                    final needRefresh = await context.push<bool>(path);
                    if (mounted && needRefresh == true)
                      _load(showLoading: false);
                  },
          )
        : null;
    final importWidget = canEdit
        ? PopupMenuButton<String>(
            icon: const Icon(Icons.upload),
            tooltip: loc.t('ttk_import_file'),
            onSelected: (value) async {
              if (value == 'excel') await _createFromExcel(context, loc);
              if (value == 'text') await _createFromText(context, loc);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'excel',
                child: Text(
                  loc.t('ttk_import_file'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              PopupMenuItem(
                  value: 'text',
                  child: Text(
                    loc.t('ttk_import_paste_text').trim().isEmpty
                        ? 'Вставить текст'
                        : loc.t('ttk_import_paste_text'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                  )),
            ],
          )
        : null;
    final exportWidget = PopupMenuButton<String>(
      icon: const Icon(Icons.download),
      tooltip: loc.t('ttk_export_excel'),
      onSelected: (value) async {
        switch (value) {
          case 'single':
            showDialog(
              context: context,
              builder: (ctx) {
                final l = ctx.read<LocalizationService>();
                return AlertDialog(
                  title: Text(l.t('ttk_select_for_export')),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 300,
                    child: ListView.builder(
                      itemCount: _list.length,
                      itemBuilder: (context, index) {
                        final techCard = _list[index];
                        return ListTile(
                          title: Text(techCard
                              .getDisplayNameInLists(l.currentLanguageCode)),
                          subtitle: Text(techCard.isSemiFinished
                              ? l.t('ttk_semi_finished')
                              : l.t('ttk_dish_label')),
                          onTap: () {
                            Navigator.of(context).pop();
                            _exportSingleTechCard(techCard);
                          },
                        );
                      },
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.t('cancel')),
                    ),
                  ],
                );
              },
            );
            break;
          case 'selected':
            if (_selectionMode) {
              await _exportSelectedTechCards();
            } else {
              _toggleSelectionMode();
            }
            break;
          case 'all':
            await _exportAllTechCards();
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'single',
          child: Text(loc.t('ttk_export_single')),
        ),
        PopupMenuItem(
          value: 'selected',
          child: Text(_selectionMode
              ? loc
                  .t('ttk_export_selected')
                  .replaceFirst('%s', '${_selectedTechCards.length}')
              : loc.t('ttk_export_selected_short')),
        ),
        PopupMenuItem(
          value: 'all',
          child: Text(loc.t('ttk_export_all')),
        ),
      ],
    );
    final refreshWidget = IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loading ? null : _load,
        tooltip: loc.t('refresh'));

    final result = <Widget>[];
    if (countWidget != null) result.add(wrap('ttk-count', countWidget));
    if (createWidget != null) result.add(wrap('ttk-create', createWidget));
    if (importWidget != null) result.add(wrap('ttk-import', importWidget));
    result.add(wrap('ttk-export', exportWidget));
    result.add(wrap('ttk-refresh', refreshWidget));
    return result;
  }

  /// Вкладки ПФ / Блюда / На проверку: рамка и текст в цвете primary (как AppBar).
  Widget _ttkTabChip(String label, {int? badgeCount}) {
    final scheme = Theme.of(context).colorScheme;
    final p = scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p, width: 1.2),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTabBarTabs(LocalizationService loc, int reviewCount) {
    final tabPf = Tab(child: _ttkTabChip(loc.t('ttk_tab_pf')));
    final tabDishes = Tab(child: _ttkTabChip(loc.t('ttk_tab_dishes')));
    final tabReview = Tab(
      child: _ttkTabChip(
        loc.t('ttk_tab_review') ?? 'На проверку',
        badgeCount: reviewCount,
      ),
    );
    final ctrl = _ttkTourController;
    if (ctrl != null) {
      return [
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-pf',
            controller: ctrl,
            child: _ttkTabChip(loc.t('ttk_tab_pf')),
          ),
        ),
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-dishes',
            controller: ctrl,
            child: _ttkTabChip(loc.t('ttk_tab_dishes')),
          ),
        ),
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-review',
            controller: ctrl,
            child: _ttkTabChip(
              loc.t('ttk_tab_review') ?? 'На проверку',
              badgeCount: reviewCount,
            ),
          ),
        ),
      ];
    }
    return [tabPf, tabDishes, tabReview];
  }

  Widget _buildBody(LocalizationService loc, bool canEdit, bool showCost) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      final errorText =
          _error == 'no_establishment' ? loc.t('no_establishment') : _error!;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(errorText, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('refresh'))),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(loc.t('tech_cards'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(loc.t('tech_cards_empty'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Разделяем список на ПФ и Блюда, фильтруем по поиску, цеху и категории
    final query = _searchController.text.trim().toLowerCase();
    final catOrder = (widget.department == 'bar' ||
            widget.department == 'banquet-catering-bar')
        ? _barCategoryOrder
        : _kitchenCategoryOrder;
    final customCatsInList = _list
        .map((tc) => tc.category)
        .where(TechCardServiceSupabase.isCustomCategory)
        .toSet()
        .toList();
    final filterCatOrder = [...catOrder, ...customCatsInList];
    final validSectionFilter =
        _filterSection == null || _sectionOrder.any((s) => s == _filterSection);
    final validCategoryFilter = _filterCategory == null ||
        filterCatOrder.any((c) => c == _filterCategory);
    if (!validSectionFilter || !validCategoryFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          if (!validSectionFilter) _filterSection = null;
          if (!validCategoryFilter) _filterCategory = null;
        });
      });
    }
    List<TechCard> filterBySearch(List<TechCard> list) {
      if (query.isEmpty) return list;
      final loc = context.read<LocalizationService>();
      final lang = loc.currentLanguageCode;
      return list
          .where((tc) =>
              tc.getDisplayNameInLists(lang).toLowerCase().contains(query))
          .toList();
    }

    List<TechCard> filterBySectionAndCategory(List<TechCard> list) {
      var result = list;
      if (_filterSection != null) {
        result = result
            .where((tc) =>
                tc.sections.contains(_filterSection) ||
                tc.sections.contains('all'))
            .toList();
      }
      if (_filterCategory != null) {
        result = result
            .where((tc) =>
                (tc.category.isEmpty ? 'misc' : tc.category) == _filterCategory)
            .toList();
      }
      return result;
    }

    final semiFinishedFiltered = filterBySectionAndCategory(
        filterBySearch(_list.where((tc) => tc.isSemiFinished).toList()));
    final dishFiltered = filterBySectionAndCategory(
        filterBySearch(_list.where((tc) => !tc.isSemiFinished).toList()));
    final reviewFiltered = _getReviewFilteredList(loc);
    _ensureReviewCache(loc, reviewFiltered);
    final reviewCount = _cachedReviewCount ?? 0;

    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final showBranchFilter = (emp?.hasRole('executive_chef') == true ||
            emp?.hasRole('sous_chef') == true) &&
        acc.establishment?.isMain == true;

    final initialTabIndex =
        semiFinishedFiltered.isEmpty && dishFiltered.isNotEmpty ? 1 : 0;
    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Column(
        children: [
          if (showBranchFilter)
            FutureBuilder<List<Establishment>>(
              future: acc.getBranchesForEstablishment(acc.establishment!.id),
              builder: (ctx, snap) {
                if (!snap.hasData || snap.data!.isEmpty)
                  return const SizedBox.shrink();
                final branches = snap.data!;
                return Consumer<TtkBranchFilterService>(
                  builder: (_, branchFilter, __) {
                    final selId = branchFilter.selectedBranchId;
                    final label = selId == null
                        ? loc.t('main_establishment_short')
                        : branches
                                .where((b) => b.id == selId)
                                .map((b) => b.name)
                                .firstOrNull ??
                            selId;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          FilterChip(
                            avatar: const Icon(Icons.account_tree, size: 18),
                            label: Text(label),
                            selected: selId != null,
                            onSelected: (_) => _showTtkBranchFilterPicker(
                                context, loc, acc, branches),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          // Шапка: цех (подразделение) над вкладками ТТК/ПФ
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ttkTourController != null
                ? SpotlightTarget(
                    id: 'ttk-subdivision',
                    controller: _ttkTourController!,
                    child: Row(
                      children: [
                        Icon(Icons.business,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${loc.t('ttk_section')}: ${_departmentHeaderLabel(loc)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      Icon(Icons.business,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${loc.t('ttk_section')}: ${_departmentHeaderLabel(loc)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                      ),
                    ],
                  ),
          ),
          TabBar(
            isScrollable: false,
            tabAlignment: TabAlignment.center,
            labelPadding: EdgeInsets.zero,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorPadding: EdgeInsets.zero,
            indicator: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.primary,
            tabs: _buildTabBarTabs(loc, reviewCount),
          ),
          if (_listDetailsHydrating)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          // Поиск и сортировка
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: loc.t('ttk_search_hint'),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _searchDebounceTimer?.cancel();
                              setState(() {});
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) {
                    _searchDebounceTimer?.cancel();
                    _searchDebounceTimer = Timer(
                      const Duration(milliseconds: 150),
                      () {
                        if (mounted) setState(() {});
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _filterSection,
                        decoration: InputDecoration(
                          labelText: loc.t('ttk_section_label'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: null, child: Text(loc.t('all') ?? 'Все')),
                          ..._sectionOrder
                              .where((s) => s != 'hidden' && s != 'all')
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(_sectionCodeToLabel(s, loc)),
                                  )),
                        ],
                        onChanged: (v) => setState(() => _filterSection = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _filterCategory,
                        decoration: InputDecoration(
                          labelText: loc.t('column_category'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: null, child: Text(loc.t('all') ?? 'Все')),
                          ...filterCatOrder.map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(_categoryLabel(c, loc)),
                              )),
                        ],
                        onChanged: (v) => setState(() => _filterCategory = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTechCardsTable(
                  semiFinishedFiltered,
                  loc,
                  canEdit,
                  showCost,
                  isDishesTab: false,
                  hasActiveFilters: _searchController.text.trim().isNotEmpty ||
                      _filterSection != null ||
                      _filterCategory != null,
                ),
                _buildTechCardsTable(
                  dishFiltered,
                  loc,
                  canEdit,
                  showCost,
                  isDishesTab: true,
                  hasActiveFilters: _searchController.text.trim().isNotEmpty ||
                      _filterSection != null ||
                      _filterCategory != null,
                ),
                _buildReviewList(loc, canEdit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Компактная таблица с шапкой и группировкой по категории или цеху.
  /// isDishesTab: для блюд — себестоимость за порцию, для ПФ — стоимость за кг.
  Widget _buildTechCardsTable(List<TechCard> techCards, LocalizationService loc,
      bool canEdit, bool showCost,
      {bool isDishesTab = false, bool hasActiveFilters = false}) {
    if (techCards.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Icon(Icons.description_outlined,
                size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              isDishesTab
                  ? (loc.t('ttk_tab_dishes') == 'ttk_tab_dishes'
                      ? 'Блюда'
                      : loc.t('ttk_tab_dishes'))
                  : (loc.t('ttk_tab_pf') == 'ttk_tab_pf' ? 'ПФ' : loc.t('ttk_tab_pf')),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasActiveFilters ? loc.t('nothing_found') : loc.t('tech_cards_empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final lang = loc.currentLanguageCode;
    final isMobile = MediaQuery.of(context).size.width < 600;
    // На мобильном — уже столбцы, чтобы название получало больше места.
    final colSectionWidth = isMobile ? 72.0 : 118.0;
    final colCatWidth = isMobile ? 52.0 : 84.0;
    final colCostWidth = isMobile ? 48.0 : 56.0;
    final colActionsWidth = isMobile ? 48.0 : 62.0;
    final est = context.read<AccountManagerSupabase>().establishment;
    final costSym = est?.currencySymbol ??
        Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
    final catOrder = (widget.department == 'bar' ||
            widget.department == 'banquet-catering-bar')
        ? _barCategoryOrder
        : _kitchenCategoryOrder;
    List<TechCard> sortCards(List<TechCard> cards, bool bySection) {
      return List.from(cards)
        ..sort((a, b) {
          if (bySection) {
            final sa = _sectionOrder.indexOf(_sectionKeyForGroup(a));
            final sb = _sectionOrder.indexOf(_sectionKeyForGroup(b));
            if (sa != sb) return sa.compareTo(sb);
            final ca =
                catOrder.indexOf(a.category.isNotEmpty ? a.category : 'misc');
            final cb =
                catOrder.indexOf(b.category.isNotEmpty ? b.category : 'misc');
            if (ca != cb) return ca.compareTo(cb);
          } else {
            final ca =
                catOrder.indexOf(a.category.isNotEmpty ? a.category : 'misc');
            final cb =
                catOrder.indexOf(b.category.isNotEmpty ? b.category : 'misc');
            if (ca != cb) return ca.compareTo(cb);
            final sa = _sectionOrder.indexOf(_sectionKeyForGroup(a));
            final sb = _sectionOrder.indexOf(_sectionKeyForGroup(b));
            if (sa != sb) return sa.compareTo(sb);
          }
          return (a.getDisplayNameInLists(lang))
              .toLowerCase()
              .compareTo((b.getDisplayNameInLists(lang)).toLowerCase());
        });
    }

    final groups = _groupByCategory(techCards)
        .map((g) => (
              category: g.category,
              cards: sortCards(g.cards, false),
              isSection: false
            ))
        .toList();
    final costLabel = isDishesTab
        ? loc.t('ttk_col_cost_per_portion').replaceFirst('%s', costSym)
        : '$costSym/${loc.t('kg')}';

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _TableHeaderDelegate(
              colSectionWidth: colSectionWidth,
              colCatWidth: colCatWidth,
              colCostWidth: colCostWidth,
              colActionsWidth: colActionsWidth,
              showCost: showCost,
              color: Theme.of(context).colorScheme.primaryContainer,
              onColor: Theme.of(context).colorScheme.onPrimaryContainer,
              labelName: loc.t('ttk_col_name'),
              labelSection: loc.t('ttk_col_section'),
              labelCat: loc.t('column_category'),
              labelCost: costLabel,
              labelView: loc.t('ttk_col_view'),
            ),
          ),
          ...groups.expand((g) => [
                SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(
                      g.isSection
                          ? _sectionGroupLabel(g.category, loc)
                          : _categoryLabel(g.category, loc),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _buildTechCardRow(
                      techCards: g.cards,
                      index: i,
                      lang: lang,
                      loc: loc,
                      canEdit: canEdit,
                      showCost: showCost,
                      isDishesTab: isDishesTab,
                      colSectionWidth: colSectionWidth,
                      colCatWidth: colCatWidth,
                      colCostWidth: colCostWidth,
                      colActionsWidth: colActionsWidth,
                      costSym: costSym,
                      establishment:
                          context.read<AccountManagerSupabase>().establishment,
                    ),
                    childCount: g.cards.length,
                  ),
                ),
              ]),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildTechCardRow({
    required List<TechCard> techCards,
    required int index,
    required String lang,
    required LocalizationService loc,
    required bool canEdit,
    required bool showCost,
    required bool isDishesTab,
    required double colSectionWidth,
    required double colCatWidth,
    required double colCostWidth,
    required double colActionsWidth,
    required String costSym,
    Establishment? establishment,
  }) {
    final tc = techCards[index];
    final est =
        establishment ?? context.read<AccountManagerSupabase>().establishment;
    // В филиале карточки головного заведения — только просмотр; свои — редактируемые.
    final viewOnlyCard =
        est != null && est.isBranch && tc.establishmentId != est.id;
    final effectiveCanEdit = canEdit && !viewOnlyCard;
    final selected = _selectedTechCards.contains(tc.id);
    final name = tc.getDisplayNameInLists(lang);
    final sectionStr = _sectionLabelForDisplay(tc, loc);
    final cat = _categoryLabel(tc.category, loc);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
          : null,
      child: InkWell(
        onTap: () async {
          if (_selectionMode) {
            _toggleTechCardSelection(tc.id);
          } else {
            final path = effectiveCanEdit
                ? '/tech-cards/${tc.id}'
                : '/tech-cards/${tc.id}?view=1';
            final needRefresh = await context.push<bool>(path);
            if (mounted && needRefresh == true) _load(showLoading: false);
          }
        },
        onLongPress: effectiveCanEdit && !_selectionMode
            ? () async {
                final needRefresh =
                    await context.push<bool>('/tech-cards/${tc.id}?view=1');
                if (mounted && needRefresh == true) _load(showLoading: false);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: colSectionWidth,
                child: Text(
                  sectionStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(
                width: colCatWidth,
                child: Text(
                  cat,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (showCost)
                SizedBox(
                  width: colCostWidth,
                  child: Text(
                    isDishesTab
                        ? '${NumberFormatUtils.formatDecimal(_calculateCostPerPortion(tc))} $costSym'
                        : NumberFormatUtils.formatInt(_calculateCostPerKg(tc)),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: colActionsWidth,
                child: _selectionMode
                    ? Checkbox(
                        value: selected,
                        onChanged: (_) => _toggleTechCardSelection(tc.id),
                      )
                    : IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        tooltip: loc.t('ttk_view'),
                        onPressed: () =>
                            context.push('/tech-cards/${tc.id}?view=1'),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Широкая таблица для планшетов и десктопов.
  Widget _buildWideTable(
      List<TechCard> techCards, LocalizationService loc, String lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
                Theme.of(context).colorScheme.primaryContainer),
            columns: [
              DataColumn(
                  label: Text(loc.t('ttk_col_name'),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text(loc.t('ttk_col_section'),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text(loc.t('ttk_col_category'),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(
                  label: Text(loc.t('ttk_col_cost_per_kg'),
                      style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(techCards.length, (i) {
              final tc = techCards[i];
              final est = context.read<AccountManagerSupabase>().establishment;
              final viewOnlyCard =
                  est != null && est.isBranch && tc.establishmentId != est.id;
              final path = viewOnlyCard
                  ? '/tech-cards/${tc.id}?view=1'
                  : '/tech-cards/${tc.id}';
              return DataRow(
                selected: _selectedTechCards.contains(tc.id),
                cells: [
                  DataCell(Text(tc.getDisplayNameInLists(lang))),
                  DataCell(Text(_sectionLabelForDisplay(tc, loc))),
                  DataCell(Text(_categoryLabel(tc.category, loc))),
                  DataCell(Text(
                      NumberFormatUtils.formatInt(_calculateCostPerKg(tc)))),
                ],
                onSelectChanged:
                    _selectionMode ? null : (_) => context.push(path),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Делегат для липкой шапки таблицы ТТК (Название | Цех | Категория | [₽/кг] | Просмотр).
/// Колонка ₽/кг показывается только если showCost == true (руководство).
class _TableHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TableHeaderDelegate({
    required this.colSectionWidth,
    required this.colCatWidth,
    required this.colCostWidth,
    required this.colActionsWidth,
    required this.showCost,
    required this.color,
    required this.onColor,
    required this.labelName,
    required this.labelSection,
    required this.labelCat,
    required this.labelCost,
    required this.labelView,
  });

  final double colSectionWidth;
  final double colCatWidth;
  final double colCostWidth;
  final double colActionsWidth;
  final bool showCost;
  final Color color;
  final Color onColor;
  final String labelName;
  final String labelSection;
  final String labelCat;
  final String labelCost;
  final String labelView;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final style =
        TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: onColor);
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(labelName, style: style),
          ),
          SizedBox(
            width: colSectionWidth,
            child: Text(
              labelSection,
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: colCatWidth,
            child: Text(
              labelCat,
              style: style,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCost)
            SizedBox(
              width: colCostWidth,
              child: Text(labelCost, style: style, textAlign: TextAlign.center),
            ),
          SizedBox(
            width: colActionsWidth,
            child: Text(labelView,
                style: style,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TableHeaderDelegate oldDelegate) {
    return oldDelegate.colSectionWidth != colSectionWidth ||
        oldDelegate.colCatWidth != colCatWidth ||
        oldDelegate.colCostWidth != colCostWidth ||
        oldDelegate.colActionsWidth != colActionsWidth ||
        oldDelegate.showCost != showCost ||
        oldDelegate.color != color ||
        oldDelegate.onColor != onColor ||
        oldDelegate.labelName != labelName ||
        oldDelegate.labelSection != labelSection ||
        oldDelegate.labelCat != labelCat ||
        oldDelegate.labelCost != labelCost ||
        oldDelegate.labelView != labelView;
  }
}
