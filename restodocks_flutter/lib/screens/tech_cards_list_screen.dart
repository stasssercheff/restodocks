import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:excel/excel.dart' hide Border;

import '../utils/layout_breakpoints.dart';
import '../utils/number_format_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:feature_spotlight/feature_spotlight.dart';

import '../models/models.dart';
import '../services/page_tour_service.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/tour_tooltip.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';
import '../widgets/subscription_required_dialog.dart';
import '../services/ai_service.dart';
import '../services/ai_service_supabase.dart';
import '../services/services.dart';
import '../services/excel_export_service.dart';
import '../services/tech_card_cost_hydrator.dart';
import '../services/tech_card_nutrition_hydrator.dart';
import '../services/tech_card_translation_cache.dart';
import '../services/on_device_ocr/on_device_ocr_service.dart';
import '../widgets/on_device_ocr_dialog.dart';

enum _TtkImportMode { single, multi }

enum _TtkNewDraftChoice { continueDraft, startNew, cancel }

/// Снимок списка ТТК между заходами (заведение + department).
class _TtkListMemoryCache {
  _TtkListMemoryCache._();

  static String _key(Establishment est, String department) =>
      '${est.id}|${est.dataEstablishmentId}|${est.isBranch}|$department';

  static String? _cachedKey;
  static DateTime? _cachedAt;
  static List<TechCard>? _cachedList;
  static Map<String, TechCard>? _cachedById;

  static const Duration _ttl = Duration(minutes: 5);

  static bool restoreIfFresh(
    Establishment est,
    String department,
    void Function(List<TechCard> list, Map<String, TechCard> byId) apply,
  ) {
    final k = _key(est, department);
    if (_cachedKey != k ||
        _cachedList == null ||
        _cachedById == null ||
        _cachedAt == null) {
      return false;
    }
    if (DateTime.now().difference(_cachedAt!) > _ttl) return false;
    apply(
      List<TechCard>.from(_cachedList!),
      Map<String, TechCard>.from(_cachedById!),
    );
    return true;
  }

  static void put(
    Establishment est,
    String department,
    List<TechCard> list,
    Map<String, TechCard> byId,
  ) {
    if (list.isEmpty) return;
    _cachedKey = _key(est, department);
    _cachedAt = DateTime.now();
    _cachedList = List<TechCard>.from(list);
    _cachedById = Map<String, TechCard>.from(byId);
  }

  static void invalidate() {
    _cachedKey = null;
    _cachedAt = null;
    _cachedList = null;
    _cachedById = null;
  }
}

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen(
      {super.key, this.department = 'kitchen', this.embedded = false});

  final String department;
  final bool embedded;

  @override
  State<TechCardsListScreen> createState() => _TechCardsListScreenState();
}

class _TechCardsListScreenState extends State<TechCardsListScreen>
    with SingleTickerProviderStateMixin {
  // Временное бизнес-решение: скрываем колонку себестоимости в списке ТТК,
  // не удаляя логику расчёта.
  static const bool _hideCostColumnsInList = true;
  List<TechCard> _list = [];
  // Индексы/кэши для рекурсивного расчёта себестоимости (включая вложенные ПФ из импортированных ТТК).
  Map<String, TechCard> _techCardsById = {};
  Map<String, ({double cost, double output})> _resolvedCostMemo = {};

  /// Полный цикл перевода названий (API) — показываем прогресс, кроме русского UI.
  bool _translationNamesLoading = false;

  /// Детерминированный прогресс: [0..total] шагов (чанки БД + добор переводов).
  int _translationProgressDone = 0;
  int _translationProgressTotal = 0;

  /// Чтобы при смене языка перезапустить оверлей без повторного открытия экрана.
  String? _prefetchListenerLang;
  late final VoidCallback _localizationPrefetchListener;

  String _tcListName(TechCard tc, String lang) =>
      tc.getDisplayNameInLists(lang);

  /// Id всех ТТК заведения + вложенные ПФ по `sourceTechCardId`, чтобы оверлей покрывал состав.
  List<String> _techCardIdsForTranslationOverlay(List<TechCard> all) {
    final ids = <String>{};
    for (final tc in all) {
      ids.add(tc.id);
      for (final ing in tc.ingredients) {
        final sid = ing.sourceTechCardId?.trim();
        if (sid != null && sid.isNotEmpty) ids.add(sid);
      }
    }
    return ids.toList();
  }

  Future<void> _prefetchDishNameTranslationOverlay(
      List<TechCard> allEstablishmentCards) async {
    if (allEstablishmentCards.isEmpty || !mounted) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;
    final dataEstId = est.dataEstablishmentId.trim();
    if (dataEstId.isEmpty) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;

    await TechCardTranslationCache.loadForEstablishment(dataEstId);

    // Уже был полный прогрев для этого заведения и языка — не гоняем пачку API при каждом _load.
    if (TechCard.translationOverlaySessionMatches(dataEstId, lang)) {
      await _refreshTechCardNameOverlayAfterWarmSession(
          allEstablishmentCards, lang);
      return;
    }

    final showProgress = lang != 'ru';
    if (showProgress && mounted) {
      setState(() {
        _translationNamesLoading = true;
        _translationProgressDone = 0;
        _translationProgressTotal = 1;
      });
    }
    try {
      final ts = context.read<TranslationService>();
      final ids = _techCardIdsForTranslationOverlay(allEstablishmentCards);
      const chunkSize = 28;
      final totalChunks =
          ids.isEmpty ? 0 : (ids.length + chunkSize - 1) ~/ chunkSize;
      final preMissing =
          TranslationService.countTechCardsNeedingDishNameTranslation(
        techCards: allEstablishmentCards,
        targetLanguage: lang,
        existingFromDatabase: {},
      );
      var totalWork = totalChunks + preMissing;
      var done = 0;

      void reportProgress() {
        if (!mounted || !showProgress) return;
        setState(() {
          _translationProgressDone = done;
          _translationProgressTotal = totalWork;
        });
      }

      final fromDb =
          await ts.fetchTechCardDishNameTranslationsForTargetLanguage(
        techCardIds: ids,
        targetLanguage: lang,
        onChunkProgress: (chunkDone, chunkTotal) {
          done = chunkDone;
          totalWork = chunkTotal + preMissing;
          reportProgress();
        },
      );
      if (!mounted) return;
      done = totalChunks;
      final missingAfter =
          TranslationService.countTechCardsNeedingDishNameTranslation(
        techCards: allEstablishmentCards,
        targetLanguage: lang,
        existingFromDatabase: fromDb,
      );
      totalWork = totalChunks + missingAfter;
      reportProgress();

      TechCard.setTranslationOverlay(fromDb, languageCode: lang, merge: true);
      final base = TechCard.snapshotTranslationOverlay(lang);
      final map = await ts.ensureMissingTechCardDishNameTranslations(
        techCards: allEstablishmentCards,
        targetLanguage: lang,
        existingFromDatabase: base,
        onProgress: (d, t) {
          done = totalChunks + d;
          totalWork = totalChunks + t;
          reportProgress();
        },
      );
      if (!mounted) return;
      TechCard.setTranslationOverlay(map, languageCode: lang, merge: true);
      TechCard.markTranslationOverlaySession(dataEstId, lang);
      await TechCardTranslationCache.saveForEstablishment(dataEstId);
      setState(() {});
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _translationNamesLoading = false;
          _translationProgressDone = 0;
          _translationProgressTotal = 0;
        });
      }
    }
  }

  /// После первого полного прогрева: только БД + добивка новых карточек без перевода.
  Future<void> _refreshTechCardNameOverlayAfterWarmSession(
      List<TechCard> allEstablishmentCards, String lang) async {
    if (!mounted) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final dataEstId = est?.dataEstablishmentId.trim() ?? '';
    try {
      final ts = context.read<TranslationService>();
      final ids = _techCardIdsForTranslationOverlay(allEstablishmentCards);
      final fromDb =
          await ts.fetchTechCardDishNameTranslationsForTargetLanguage(
        techCardIds: ids,
        targetLanguage: lang,
      );
      if (!mounted) return;
      TechCard.setTranslationOverlay(fromDb, languageCode: lang, merge: true);
      final base = TechCard.snapshotTranslationOverlay(lang);
      final map = await ts.ensureMissingTechCardDishNameTranslations(
        techCards: allEstablishmentCards,
        targetLanguage: lang,
        existingFromDatabase: base,
      );
      if (!mounted) return;
      TechCard.setTranslationOverlay(map, languageCode: lang, merge: true);
      if (dataEstId.isNotEmpty) {
        await TechCardTranslationCache.saveForEstablishment(dataEstId);
      }
      setState(() {});
    } catch (_) {}
  }

  /// Ленивое наполнение `tc.ingredients` для отображения цен.
  /// Идея: при построении видимой строки запрашиваем ингредиенты только для нужных ТТК,
  /// а не для всего списка.
  final Set<String> _ingredientsHydratedIds = {};
  final Set<String> _ingredientsHydrationInFlight = {};
  final Set<String> _ingredientsHydrationPending = {};
  Timer? _ingredientsHydrationDebounce;
  bool _reviewIngredientsWarmUpInFlight = false;

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

  /// Применённый к фильтрам запрос (после debounce), чтобы не пересчитывать список на каждый символ.
  String _appliedSearchQuery = '';

  /// Кэш `id → lower(name)` для быстрого поиска без повторных вызовов `getDisplayNameInLists` на каждый кадр.
  ({int listVersion, String lang})? _lowerSearchNameKey;
  Map<String, String> _lowerSearchNameById = {};

  /// Версия списка, для которой построен индекс ПФ для «На проверку» (не перестраивать при смене только поиска).
  int _pfIndexBuiltForListVersion = -1;
  Timer? _reconcileTimer;
  TechCardsReconcileNotifier? _reconcileNotifier;
  int _lastReconcileNotifierVersion = 0;
  bool _reconciling = false;
  DateTime _lastReconcileAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ttkTourCheckDone = false;
  SpotlightController? _ttkTourController;

  late final TabController _tabController;
  int _tabIndex = 0;
  bool _tabWasTouched = false;
  bool _tabAutoSelectedOnce = false;
  int? _tabIndexFromUrl;
  bool _tabIndexResolvedFromUrl = false;

  /// Старт загрузки только после завершения анимации перехода (не во время свайпа).
  bool _ttkInitialBootstrapDone = false;
  Animation<double>? _ttkRouteAnimation;

  void _onPersistentTechCardsOfflineCacheBump() {
    if (!mounted) return;
    unawaited(_load(showLoading: false));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: 0,
    );
    _tabIndex = _tabController.index;
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final idx = _tabController.index;
      if (idx == _tabIndex) return;
      _tabIndex = idx;
      if (mounted) {
        if (idx == 2) {
          _cachedReviewList = null;
          _cachedReviewCount = null;
          _lastReviewCacheKey = null;
          unawaited(_warmUpReviewIngredients());
        }
        setState(() {});
      }
    });
    _prefetchListenerLang = LocalizationService().currentLanguageCode;
    _localizationPrefetchListener = () {
      if (!mounted || _loading || _techCardsById.isEmpty) return;
      final lang = LocalizationService().currentLanguageCode;
      if (_prefetchListenerLang == lang) return;
      _prefetchListenerLang = lang;
      unawaited(
          _prefetchDishNameTranslationOverlay(_techCardsById.values.toList()));
    };
    LocalizationService().addListener(_localizationPrefetchListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTtkTour());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || kIsWeb) return;
      TechCardServiceSupabase().persistentTechCardsCacheGeneration
          .addListener(_onPersistentTechCardsOfflineCacheBump);
    });
    _scheduleTtkBootstrapAfterRoute();
  }

  void _onTtkRouteAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        !mounted ||
        _ttkInitialBootstrapDone) {
      return;
    }
    _detachTtkRouteListener();
    _ttkInitialBootstrapDone = true;
    unawaited(_bootstrapTtkAfterRoute());
  }

  void _detachTtkRouteListener() {
    _ttkRouteAnimation?.removeStatusListener(_onTtkRouteAnimationStatus);
    _ttkRouteAnimation = null;
  }

  void _scheduleTtkBootstrapAfterRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ttkInitialBootstrapDone) return;
      if (widget.embedded) {
        _ttkInitialBootstrapDone = true;
        unawaited(_bootstrapTtkAfterRoute());
        return;
      }
      final anim = ModalRoute.of(context)?.animation;
      _ttkRouteAnimation = anim;
      if (anim == null || anim.status == AnimationStatus.completed) {
        _ttkInitialBootstrapDone = true;
        unawaited(_bootstrapTtkAfterRoute());
        return;
      }
      anim.addStatusListener(_onTtkRouteAnimationStatus);
    });
  }

  Future<void> _bootstrapTtkAfterRoute() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    var restoredFromMemory = false;
    if (est != null) {
      restoredFromMemory = _TtkListMemoryCache.restoreIfFresh(
        est,
        widget.department,
        (snapshotList, snapshotById) {
          if (!mounted) return;
          setState(() {
            _list = snapshotList;
            _techCardsById = snapshotById;
            _loading = false;
            _error = null;
            _listVersion++;
            _cachedReviewList = null;
            _cachedReviewCount = null;
            _lastReviewCacheKey = null;
            _listDetailsHydrating = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _rebuildPfCandidatesIndex(context.read<LocalizationService>());
          });
        },
      );
    }
    if (!restoredFromMemory) {
      await _load(showLoading: true);
    }
    if (!mounted) return;
    _reconcileNotifier = context.read<TechCardsReconcileNotifier>();
    _lastReconcileNotifierVersion = _reconcileNotifier!.version;
    _reconcileNotifier!.addListener(_handleTechCardsReconcileSignal);
    _reconcileTimer?.cancel();
    _reconcileTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _tryReconcileTechCards(force: false);
    });
    _tryReconcileTechCards(force: false);
  }

  Future<void> _pullToRefresh() async {
    _TtkListMemoryCache.invalidate();
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est != null) {
      final svc = context.read<TechCardServiceSupabase>();
      await svc.clearTechCardsListCacheForEstablishment(est.dataEstablishmentId);
      if (est.isBranch) {
        await svc.clearTechCardsListCacheForEstablishment(est.id);
      }
    }
    // Список не прячем — RefreshIndicator крутится; сеть идёт страницами.
    await _load(showLoading: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabIndexResolvedFromUrl) return;
    _tabIndexResolvedFromUrl = true;
    _tabIndexFromUrl = _readTabIndexFromUrl();
    final idx = _tabIndexFromUrl;
    if (idx != null && idx >= 0 && idx <= 2 && _tabController.index != idx) {
      _tabController.index = idx;
      _tabIndex = idx;
    }
  }

  Future<void> _maybeShowTtkTour() async {
    // В iOS/Flutter 3.38 тур-оверлей периодически ломает семантику/слои
    // на экране ТТК (render asserts и пустой список). Временно отключаем,
    // приоритет — стабильное отображение списка.
    return;
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
    if (!kIsWeb) {
      TechCardServiceSupabase().persistentTechCardsCacheGeneration
          .removeListener(_onPersistentTechCardsOfflineCacheBump);
    }
    _detachTtkRouteListener();
    LocalizationService().removeListener(_localizationPrefetchListener);
    _searchDebounceTimer?.cancel();
    _ingredientsHydrationDebounce?.cancel();
    _reconcileTimer?.cancel();
    _tabController.dispose();
    if (_reconcileNotifier != null) {
      _reconcileNotifier!.removeListener(_handleTechCardsReconcileSignal);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  int? _readTabIndexFromUrl() {
    final state = GoRouterState.of(context);
    final tab = state.queryParameters['tab'];
    if (tab == null) return null;
    final v = tab.trim().toLowerCase();
    if (v == 'pf') return 0;
    if (v == 'dishes') return 1;
    if (v == 'review') return 2;
    final i = int.tryParse(v);
    if (i == null) return null;
    if (i < 0 || i > 2) return null;
    return i;
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
    if (tc.ingredients.isEmpty) {
      _queueIngredientsHydrationForCost(tc.id);
      return 0.0;
    }
    if (tc.portionWeight <= 0) return 0.0;
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
        _tcListName(pf, lang),
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
    _pfIndexBuiltForListVersion = _listVersion;
  }

  void _ensureLowerSearchNameCache(LocalizationService loc) {
    if (_list.isEmpty) {
      _lowerSearchNameById = {};
      _lowerSearchNameKey = null;
      return;
    }
    final lang = loc.currentLanguageCode;
    final key = (listVersion: _listVersion, lang: lang);
    if (_lowerSearchNameKey == key && _lowerSearchNameById.isNotEmpty) return;
    final map = <String, String>{};
    for (final tc in _list) {
      map[tc.id] = _tcListName(tc, lang).toLowerCase();
    }
    _lowerSearchNameById = map;
    _lowerSearchNameKey = key;
  }

  /// Отфильтрованный список для вкладки «На проверку».
  List<TechCard> _getReviewFilteredList(LocalizationService loc) {
    _ensureLowerSearchNameCache(loc);
    final query = _appliedSearchQuery;
    var result = _list;
    if (query.isNotEmpty) {
      final names = _lowerSearchNameById;
      result =
          result.where((tc) => (names[tc.id] ?? '').contains(query)).toList();
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
  Object _reviewCacheKey() =>
      (_listVersion, _filterSection, _filterCategory, _appliedSearchQuery);

  /// Тяжёлые вычисления для вкладки «На проверку» — в след. кадре, чтобы не блокировать UI.
  void _ensureReviewCache(
      LocalizationService loc, List<TechCard> reviewFiltered) {
    final key = _reviewCacheKey();
    if (_lastReviewCacheKey == key) return;
    if (_reviewCacheScheduled) return;
    _reviewCacheScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reviewCacheScheduled = false;
      if (!mounted) return;
      if (_pfIndexBuiltForListVersion != _listVersion) {
        _rebuildPfCandidatesIndex(loc);
      }
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
            loc.t('ttk_review_tab_empty'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _pullToRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final item = list[i];
          final tc = item.tc;
          final name = _tcListName(tc, lang);
          return ListTile(
            tileColor: Theme.of(ctx).colorScheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: Theme.of(ctx).colorScheme.outlineVariant)),
            title: Text(name),
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
                            loc
                                .t('ttk_review_sheet_title')
                                .replaceFirst('%s', _tcListName(tc, lang)),
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
                              loc
                                  .t('ttk_review_ambiguous_pf_section')
                                  .replaceFirst(
                                      '%s', '${ambiguousMatches.length}'),
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
                                      decoration: InputDecoration(
                                          isDense: true,
                                          labelText:
                                              loc.t('ttk_pf_candidate_label')),
                                      items: m.candidates
                                          .map((c) => DropdownMenuItem<String>(
                                                value: c.id,
                                                child:
                                                    Text(_tcListName(c, lang)),
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
                                        child: Text(
                                            loc.t('ttk_composition_short')),
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
                              loc.t('ttk_review_no_price_section').replaceFirst(
                                  '%s', '${missingPriceIngredients.length}'),
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
                              loc.t('ttk_review_weight_section').replaceFirst(
                                  '%s', '${missingWeightIssues.length}'),
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
                              loc
                                  .t('ttk_review_technology_section')
                                  .replaceFirst('%s',
                                      '${missingTechnologyIssues.length}'),
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
                                    final needRefresh =
                                        await context.push<bool>(
                                      '/tech-cards/${tc.id}',
                                      extra: {'initialTechCard': tc},
                                    );
                                    if (mounted && needRefresh == true) {
                                      _TtkListMemoryCache.invalidate();
                                      await _load(showLoading: false);
                                    }
                                  },
                            child: Text(loc.t('ttk_open_tech_card')),
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
                                          final display = _tcListName(pf, lang);
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
                                          _TtkListMemoryCache.invalidate();
                                          await _load();
                                        }
                                        if (ctx2.mounted)
                                          Navigator.of(ctx2).pop();
                                      } catch (e) {
                                        if (ctx2.mounted) {
                                          ScaffoldMessenger.of(ctx2)
                                              .showSnackBar(SnackBar(
                                                  content: Text(loc
                                                      .t('save_error')
                                                      .replaceFirst(
                                                          '%s', '$e'))));
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
                                  : Text(loc.t('apply')),
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
        title: Text(_tcListName(tc, lang)),
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

    if (tc.ingredients.isEmpty) {
      _queueIngredientsHydrationForCost(techCardId);
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

  void _queueIngredientsHydrationForCost(String techCardId) {
    if (techCardId.isEmpty) return;
    if (_ingredientsHydratedIds.contains(techCardId)) return;

    final tc = _techCardsById[techCardId];
    if (tc != null && tc.ingredients.isNotEmpty) {
      _ingredientsHydratedIds.add(techCardId);
      return;
    }

    if (_ingredientsHydrationInFlight.contains(techCardId)) return;
    _ingredientsHydrationPending.add(techCardId);

    _ingredientsHydrationDebounce?.cancel();
    _ingredientsHydrationDebounce =
        Timer(const Duration(milliseconds: 180), () async {
      unawaited(_flushIngredientsHydrationQueue());
    });
  }

  Future<void> _flushIngredientsHydrationQueue() async {
    if (!mounted) return;

    final ids = Set<String>.from(_ingredientsHydrationPending);
    _ingredientsHydrationPending.clear();
    if (ids.isEmpty) return;

    final idsToFetch = <String>{};
    for (final id in ids) {
      if (_ingredientsHydratedIds.contains(id)) continue;
      if (_ingredientsHydrationInFlight.contains(id)) continue;
      final tc = _techCardsById[id];
      if (tc != null && tc.ingredients.isNotEmpty) {
        _ingredientsHydratedIds.add(id);
        continue;
      }
      idsToFetch.add(id);
    }
    if (idsToFetch.isEmpty) return;

    for (final id in idsToFetch) {
      _ingredientsHydrationInFlight.add(id);
    }

    try {
      final svc = context.read<TechCardServiceSupabase>();
      final cards = idsToFetch
          .map((id) => _techCardsById[id])
          .whereType<TechCard>()
          .toList(growable: false);

      final updated = await svc.fillIngredientsForCardsBulk(cards);
      final updatedById = {for (final tc in updated) tc.id: tc};

      if (!mounted) return;

      setState(() {
        for (final id in idsToFetch) {
          final u = updatedById[id];
          if (u == null) continue;
          _techCardsById[id] = u;
          _ingredientsHydratedIds.add(id);
        }

        if (_list.isNotEmpty) {
          final map = updatedById;
          _list = _list.map((tc) => map[tc.id] ?? tc).toList(growable: false);
        }

        // Себестоимость зависит от ингредиентов, поэтому очищаем кеш.
        _resolvedCostMemo.clear();

        // Подсчёт «На проверку» зависит от цен/весов/ПФ, поэтому
        // пересчитаем только если пользователь прямо смотрит этот таб.
        if (_tabController.index == 2) {
          _cachedReviewList = null;
          _cachedReviewCount = null;
          _lastReviewCacheKey = null;
        }
      });
    } catch (_) {
      // Ошибки догрузки ингредиентов не должны ломать список.
    } finally {
      for (final id in idsToFetch) {
        _ingredientsHydrationInFlight.remove(id);
      }
    }
  }

  /// Догрузка ингредиентов для всех карточек после списка с `includeIngredients: false`.
  /// Без этого роли без колонки «Себестоимость» никогда не вызывали ленивую гидрацию — состав и цены оставались пустыми.
  Future<void> _hydrateEmptyIngredientsForLoadedCards(
    TechCardServiceSupabase svc, {
    required int requestToken,
  }) async {
    if (!mounted || requestToken != _loadRequestToken) return;
    final toHydrate = _techCardsById.values
        .where((tc) => tc.ingredients.isEmpty)
        .toList(growable: false);
    if (toHydrate.isEmpty) return;

    const chunkSize = 60;
    final accumulated = <String, TechCard>{};
    for (var i = 0; i < toHydrate.length; i += chunkSize) {
      if (!mounted || requestToken != _loadRequestToken) return;
      final end = (i + chunkSize < toHydrate.length)
          ? (i + chunkSize)
          : toHydrate.length;
      final chunk = toHydrate.sublist(i, end);
      try {
        final updated = await svc.fillIngredientsForCardsBulk(chunk);
        if (!mounted || requestToken != _loadRequestToken) return;
        for (final tc in updated) {
          accumulated[tc.id] = tc;
        }
        if (accumulated.isNotEmpty) {
          setState(() {
            for (final tc in updated) {
              _techCardsById[tc.id] = tc;
              _ingredientsHydratedIds.add(tc.id);
            }
            if (_list.isNotEmpty) {
              _list = _list
                  .map((tc) => accumulated[tc.id] ?? tc)
                  .toList(growable: false);
            }
            _resolvedCostMemo.clear();
            if (_tabController.index == 2) {
              _cachedReviewList = null;
              _cachedReviewCount = null;
              _lastReviewCacheKey = null;
            }
          });
        }
      } catch (_) {
        // как при ленивой догрузке — не ломаем список
      }
    }
  }

  /// Прогрев ингредиентов для вкладки «На проверку», чтобы подсчёт проблем
  /// (особенно цен) был корректным. Запускается лениво при переходе на таб.
  Future<void> _warmUpReviewIngredients() async {
    if (!mounted) return;
    if (_reviewIngredientsWarmUpInFlight) return;

    final loc = context.read<LocalizationService>();
    final reviewFiltered = _getReviewFilteredList(loc);
    final toHydrate =
        reviewFiltered.where((tc) => tc.ingredients.isEmpty).toList();
    if (toHydrate.isEmpty) return;

    _reviewIngredientsWarmUpInFlight = true;
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      final productStore = context.read<ProductStoreSupabase>();
      final svc = context.read<TechCardServiceSupabase>();

      // Гарантируем наличие цен в номенклатуре для проверки «Без цен».
      if (est != null) {
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

        if (!mounted) return;
        await _buildNomenclatureNamePriceIndex(
          productStore,
          est.isBranch ? est.id : est.dataEstablishmentId,
        );
      }

      const chunkSize = 60;
      final hydratedById = <String, TechCard>{};
      for (var i = 0; i < toHydrate.length; i += chunkSize) {
        if (!mounted) break;
        final end = (i + chunkSize < toHydrate.length)
            ? (i + chunkSize)
            : toHydrate.length;
        final chunk = toHydrate.sublist(i, end);
        final updated = await svc.fillIngredientsForCardsBulk(chunk);
        for (final tc in updated) {
          hydratedById[tc.id] = tc;
          _ingredientsHydratedIds.add(tc.id);
        }
      }

      if (!mounted) return;
      setState(() {
        hydratedById.forEach((id, tc) => _techCardsById[id] = tc);
        if (_list.isNotEmpty) {
          _list = _list
              .map((tc) => hydratedById[tc.id] ?? tc)
              .toList(growable: false);
        }
        _resolvedCostMemo.clear();
        _cachedReviewList = null;
        _cachedReviewCount = null;
        _lastReviewCacheKey = null;
      });
    } catch (_) {
      // Прогрев не должен блокировать UI.
    } finally {
      _reviewIngredientsWarmUpInFlight = false;
    }
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
        customBarIds.contains(
            TechCardServiceSupabase.customCategoryId(tc.category))) return true;
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

  /// Санация, фильтр по цеху и подтягивание карточек по ссылкам из состава (без сети).
  ({
    List<TechCard> toPersistSelfLink,
    List<TechCard> processedAll,
    List<TechCard> list
  }) _prepareTechCardListFromRaw(
    Establishment est,
    List<TechCard> all,
    Set<String> customBarIds,
  ) {
    final toPersistSelfLink = <TechCard>[];
    final sanitizedAll = <TechCard>[];
    for (final tc in all) {
      final s = stripInvalidNestedPfSelfLinks(tc);
      sanitizedAll.add(s);
      if (!identical(s, tc)) toPersistSelfLink.add(s);
    }
    final processedAll = sanitizedAll;
    var list = _filterListByDepartment(processedAll, customBarIds);
    try {
      final byId = {for (final tc in processedAll) tc.id: tc};
      final referencedIds = <String>{};
      for (final tc in processedAll) {
        for (final ing in tc.ingredients) {
          final id = ing.sourceTechCardId;
          if (id != null && id.trim().isNotEmpty) referencedIds.add(id.trim());
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
    return (
      toPersistSelfLink: toPersistSelfLink,
      processedAll: processedAll,
      list: list,
    );
  }

  void _applyPagedTtkListProgress({
    required Establishment est,
    required List<TechCard> merged,
    required Set<String> customBarIds,
    required ProductStoreSupabase productStore,
    required bool primeCatalogAndPrices,
    required int requestToken,
  }) {
    if (!mounted || requestToken != _loadRequestToken) return;
    final prep = _prepareTechCardListFromRaw(est, merged, customBarIds);
    _priceProductStore = productStore;
    _priceEstablishmentId =
        est.isBranch ? est.id : est.dataEstablishmentId;
    setState(() {
      _list = prep.list;
      _listVersion++;
      _cachedReviewList = null;
      _cachedReviewCount = null;
      _lastReviewCacheKey = null;
      _loading = false;
      _error = null;
      _listDetailsHydrating =
          primeCatalogAndPrices && prep.list.isNotEmpty;
    });
    _techCardsById = {for (final tc in prep.processedAll) tc.id: tc};
    _resolvedCostMemo.clear();
    if (prep.list.isNotEmpty) {
      _TtkListMemoryCache.put(
          est, widget.department, prep.list, _techCardsById);
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
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

      final customCategoriesFuture = Future.wait([
        svc.getCustomCategories(est.dataEstablishmentId, 'kitchen'),
        svc.getCustomCategories(est.dataEstablishmentId, 'bar'),
      ]);
      late List<({String id, String name})> customKitchen;
      late List<({String id, String name})> customBar;
      try {
        final cr = await customCategoriesFuture.timeout(
          const Duration(milliseconds: 2000),
          onTimeout: () => [
            <({String id, String name})>[],
            <({String id, String name})>[],
          ],
        );
        if (!mounted || requestToken != _loadRequestToken) return;
        customKitchen = List<({String id, String name})>.from(
            cr[0] as List<({String id, String name})>);
        customBar = List<({String id, String name})>.from(
            cr[1] as List<({String id, String name})>);
      } catch (_) {
        if (!mounted || requestToken != _loadRequestToken) return;
        customKitchen = const [];
        customBar = const [];
      }
      if (!mounted || requestToken != _loadRequestToken) return;
      final customBarIds = customBar.map((c) => c.id).toSet();

      // Полный прогон каталога/номенклатуры только при «тяжёлой» загрузке (первый показ, refresh).
      final bool primeCatalogAndPrices = showLoading;

      _customCategoryNames.clear();
      for (final c in customKitchen) _customCategoryNames[c.id] = c.name;
      for (final c in customBar) _customCategoryNames[c.id] = c.name;

      late List<TechCard> all;
      if (kIsWeb) {
        // Параллельно со страничной загрузкой ТТК — не ждём полного списка.
        if (primeCatalogAndPrices) {
          unawaited(Future.microtask(() async {
            try {
              await productStore.loadProducts().catchError((_) {});
              if (est.isBranch) {
                await productStore
                    .loadNomenclatureForBranch(
                        est.id, est.dataEstablishmentId!)
                    .catchError((_) {});
              } else {
                await productStore
                    .loadNomenclature(est.dataEstablishmentId)
                    .catchError((_) {});
              }
              if (!mounted || requestToken != _loadRequestToken) return;
              await _buildNomenclatureNamePriceIndex(
                productStore,
                est.isBranch ? est.id : est.dataEstablishmentId,
              );
            } catch (_) {}
          }));
        }
        final scopeIds = est.isBranch
            ? <String>[est.dataEstablishmentId, est.id]
            : <String>[est.dataEstablishmentId];
        final pre = svc.consumeWebShallowPrefetchIfScopesMatch(scopeIds);
        if (pre != null) {
          all = pre;
          _applyPagedTtkListProgress(
            est: est,
            merged: all,
            customBarIds: customBarIds,
            productStore: productStore,
            primeCatalogAndPrices: primeCatalogAndPrices,
            requestToken: requestToken,
          );
        } else {
          all = await svc.loadAllTechCardsShallowFromNetworkPaged(
            scopeIds,
            pageSize: 90,
            onProgress: (merged) => _applyPagedTtkListProgress(
                  est: est,
                  merged: merged,
                  customBarIds: customBarIds,
                  productStore: productStore,
                  primeCatalogAndPrices: primeCatalogAndPrices,
                  requestToken: requestToken,
                ),
          );
        }
      } else {
        late Future<List<TechCard>> allCardsFuture;
        if (est.isBranch) {
          allCardsFuture = Future.wait([
            svc.getTechCardsForEstablishment(
              est.dataEstablishmentId,
              includeIngredients: false,
            ),
            svc.getTechCardsForEstablishment(
              est.id,
              includeIngredients: false,
            ),
          ]).then((results) => [...results[0], ...results[1]]);
        } else {
          allCardsFuture = svc.getTechCardsForEstablishment(
            est.dataEstablishmentId,
            includeIngredients: false,
          );
        }
        try {
          if (!mounted || requestToken != _loadRequestToken) return;
          all = await allCardsFuture;
        } catch (_) {
          if (!mounted || requestToken != _loadRequestToken) return;
          all = await allCardsFuture;
        }
      }

      if (!mounted || requestToken != _loadRequestToken) return;

      final prep = _prepareTechCardListFromRaw(est, all, customBarIds);
      final toPersistSelfLink = prep.toPersistSelfLink;
      final processedAll = prep.processedAll;
      final list = prep.list;

      if (!kIsWeb && mounted) {
        _priceProductStore = productStore;
        _priceEstablishmentId = est.isBranch ? est.id : est.dataEstablishmentId;
        setState(() {
          _list = list;
          _listVersion++;
          _cachedReviewList = null;
          _cachedReviewCount = null;
          _lastReviewCacheKey = null;
          _loading = false;
          _listDetailsHydrating = primeCatalogAndPrices && list.isNotEmpty;
        });
        _techCardsById = {for (final tc in processedAll) tc.id: tc};
        _resolvedCostMemo.clear();
        if (list.isNotEmpty) {
          _TtkListMemoryCache.put(est, widget.department, list, _techCardsById);
        }
      }

      if (mounted) {
        if (list.isNotEmpty || primeCatalogAndPrices) {
          final hydrateToken = ++_loadHydrateToken;
          Future.microtask(() async {
            try {
              if (primeCatalogAndPrices && !kIsWeb) {
                await productStore.loadProducts().catchError((_) {});
                if (est.isBranch) {
                  await productStore
                      .loadNomenclatureForBranch(
                          est.id, est.dataEstablishmentId!)
                      .catchError((_) {});
                } else {
                  await productStore
                      .loadNomenclature(est.dataEstablishmentId)
                      .catchError((_) {});
                }
                if (!mounted || requestToken != _loadRequestToken) return;
                await _buildNomenclatureNamePriceIndex(
                  productStore,
                  est.isBranch ? est.id : est.dataEstablishmentId,
                );
              }
              if (!mounted || requestToken != _loadRequestToken) return;
              await _hydrateEmptyIngredientsForLoadedCards(
                svc,
                requestToken: requestToken,
              );
              if (!mounted || requestToken != _loadRequestToken) return;
              setState(() {
                _resolvedCostMemo.clear();
              });
              if (_list.isNotEmpty) {
                _TtkListMemoryCache.put(
                    est, widget.department, _list, _techCardsById);
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
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final loc = context.read<LocalizationService>();
          _rebuildPfCandidatesIndex(loc);
          unawaited(_prefetchDishNameTranslationOverlay(processedAll));
          unawaited(_ensureTechCardTranslations(svc, list));
          _warmPdfParser();
          if (_list.isEmpty) return;
          _ensureReviewCache(loc, _getReviewFilteredList(loc));
        });
      }

      if (toPersistSelfLink.isNotEmpty && mounted) {
        Future.microtask(() async {
          final saveSvc = context.read<TechCardServiceSupabase>();
          for (final tc in toPersistSelfLink.take(25)) {
            if (!mounted) break;
            if (tc.ingredients.isEmpty) continue;
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
    final currentLang = context.read<LocalizationService>().currentLanguageCode;
    // Русский интерфейс: название уже в dishName — иначе N вызовов translate-text на каждую ТТК.
    if (currentLang == 'ru') return;
    final targetLanguages = <String>[currentLang];
    var i = 0;
    final pendingUpdates = <String, Map<String, String>>{};
    for (final tc in cards) {
      if (!mounted) break;
      if (i > 0 && i % 2 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      i++;
      final mergedLocalized =
          Map<String, String>.from(tc.dishNameLocalized ?? {});
      var hasUpdates = false;
      for (final lang in targetLanguages) {
        final hasTranslation =
            tc.dishNameLocalized?.containsKey(lang) == true &&
                (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false);
        if (hasTranslation) continue;
        try {
          final translated = await svc
              .translateTechCardName(tc.id, tc.dishName, lang)
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          if (translated != null && translated.trim().isNotEmpty) {
            mergedLocalized[lang] = translated;
            hasUpdates = true;
          }
        } catch (_) {}
      }
      if (hasUpdates && mounted) {
        pendingUpdates[tc.id] = mergedLocalized;
      }
    }
    if (pendingUpdates.isNotEmpty && mounted) {
      setState(() {
        for (final entry in pendingUpdates.entries) {
          final idx = _list.indexWhere((c) => c.id == entry.key);
          if (idx >= 0) {
            _list[idx] = _list[idx].copyWith(dishNameLocalized: entry.value);
          }
        }
      });
    }
  }

  /// Экспорт одной ТТК
  Future<void> _exportSingleTechCard(TechCard techCard) async {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    try {
      final account = context.read<AccountManagerSupabase>();
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        await account.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.ttk,
        );
      }
      await ExcelExportService()
          .exportSingleTechCard(techCard, languageCode: lang);
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
      final lang = context.read<LocalizationService>().currentLanguageCode;
      final account = context.read<AccountManagerSupabase>();
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        await account.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.ttk,
        );
      }
      await ExcelExportService()
          .exportSelectedTechCards(selectedCards, languageCode: lang);
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
      final account = context.read<AccountManagerSupabase>();
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        await account.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.ttk,
        );
      }
      await ExcelExportService()
          .exportAllTechCards(_list, languageCode: loc.currentLanguageCode);
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
          final display = _tcListName(picked, lang);
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
        if (tc.ingredients.isEmpty) continue;
        await svc.saveTechCard(tc, skipHistory: true);
      }

      if (toSave.isNotEmpty && mounted) {
        _TtkListMemoryCache.invalidate();
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
    final acc = context.read<AccountManagerSupabase>();
    if (!acc.hasProSubscription) {
      await showSubscriptionRequiredDialog(context);
      return;
    }
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
    final acc = context.read<AccountManagerSupabase>();
    if (!acc.hasProSubscription) {
      await showSubscriptionRequiredDialog(context);
      return;
    }
    final controller = TextEditingController();
    var sttBusy = false;
    var sttSupported = false;
    try {
      sttSupported = await speechToTextSupported();
    } catch (_) {
      sttSupported = false;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(loc.t('ttk_import_text') ?? 'Вставить из текста'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 12,
                  decoration: InputDecoration(
                    hintText:
                        'Название блюда\nнаименование\tЕд.изм\tНорма закладки\t...\n1\tПродукт\tкг\t0,100\t...\nВыход\t\tкг\t1,000',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (sttSupported) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: sttBusy
                          ? null
                          : () async {
                              setLocalState(() => sttBusy = true);
                              try {
                                final spoken = await speechToTextListenOnce(
                                  languageCode: loc.currentLanguageCode,
                                );
                                if (!ctx.mounted) return;
                                if (spoken != null && spoken.trim().isNotEmpty) {
                                  final current = controller.text.trim();
                                  controller.text = current.isEmpty
                                      ? spoken.trim()
                                      : '$current\n${spoken.trim()}';
                                } else {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        loc.t('speech_not_recognized').trim().isEmpty
                                            ? 'Речь не распознана'
                                            : loc.t('speech_not_recognized'),
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setLocalState(() => sttBusy = false);
                                }
                              }
                            },
                      icon: Icon(sttBusy ? Icons.hearing : Icons.mic),
                      label: Text(
                        sttBusy
                            ? (loc.t('speech_listening').trim().isEmpty
                                ? 'Слушаю...'
                                : loc.t('speech_listening'))
                            : (loc.t('voice_input').trim().isEmpty
                                ? 'Голосом'
                                : loc.t('voice_input')),
                      ),
                    ),
                  ),
                ],
              ],
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

  Future<void> _createFromPhoto(
      BuildContext context, LocalizationService loc) async {
    final acc = context.read<AccountManagerSupabase>();
    if (!acc.hasProSubscription) {
      await showSubscriptionRequiredDialog(context);
      return;
    }
    if (kIsWeb || !OnDeviceOcrService.isSupported) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('on_device_ocr_not_supported'))),
      );
      return;
    }
    final agreed = await showOnDeviceOcrEducationDialog(
      context,
      loc,
      kind: OnDeviceOcrHintKind.ttk,
    );
    if (!agreed || !mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(loc.t('photo_from_camera')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(loc.t('photo_from_gallery')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    setState(() => _loadingExcel = true);
    try {
      final imageService = ImageService();
      final xFile = source == ImageSource.camera
          ? await imageService.takePhotoWithCamera()
          : await imageService.pickImageFromGallery();
      if (xFile == null || !mounted) return;
      final bytes = await imageService.xFileToBytes(xFile);
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final ocr = OnDeviceOcrService();
      final text = await ocr.extractTextFromImageBytes(bytes);
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('on_device_ocr_no_text'))),
        );
        return;
      }
      final establishmentId = acc.establishment?.dataEstablishmentId;
      final list = await context
          .read<AiService>()
          .parseTechCardsFromText(text, establishmentId: establishmentId);
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('ai_tech_card_excel_format_hint') ??
                  'Не удалось распознать ТТК в тексте')),
        );
        return;
      }
      final ai = context.read<AiService>();
      final sig = ai is AiServiceSupabase
          ? AiServiceSupabase.lastParseHeaderSignature
          : null;
      final sourceRows =
          ai is AiServiceSupabase ? AiServiceSupabase.lastParsedRows : null;
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
          },
        );
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

  /// Себестоимость видят руководство и управляющие.
  bool _canSeeCost(AccountManagerSupabase acc) {
    final emp = acc.currentEmployee;
    if (emp == null) return false;
    return emp.hasRole('owner') ||
        emp.hasRole('executive_chef') ||
        emp.hasRole('sous_chef') ||
        emp.hasRole('bar_manager') ||
        emp.hasRole('manager') ||
        emp.hasRole('general_manager');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final canEdit =
        accountManager.currentEmployee?.canEditChecklistsAndTechCards ?? false;
    final showCost = _canSeeCost(accountManager) && !_hideCostColumnsInList;

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
                : 'ТТК',
          ),
        ),
        actions: _buildAppBarActions(
            loc, canEdit, accountManager.hasProSubscription),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_translationNamesLoading)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    minHeight: 3,
                    value: _translationProgressTotal > 0
                        ? (_translationProgressDone / _translationProgressTotal)
                            .clamp(0.0, 1.0)
                        : null,
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      _translationProgressTotal > 0
                          ? '${loc.t('ttk_loading_name_translations')}  '
                              '${_translationProgressDone} / ${_translationProgressTotal} '
                              '(${(_translationProgressDone * 100 / _translationProgressTotal).round()}%)'
                          : loc.t('ttk_loading_name_translations'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                _buildBody(loc, canEdit, showCost),
                if (_loadingExcel)
                  ColoredBox(
                    color:
                        Theme.of(context).colorScheme.surface.withOpacity(0.7),
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
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
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  Future<void> _openManualTechCardCreate(LocalizationService loc) async {
    if (_loading) return;
    const draftKey = 'tech_card_edit_new';
    final merged = await DraftStorageService()
        .loadTechCardEditDraftMerged('new', draftKey);
    if (merged != null &&
        DraftStorageService.techCardDraftLooksNonEmpty(merged)) {
      final choice = await showDialog<_TtkNewDraftChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.t('ttk_draft_unsaved_title')),
          content: Text(loc.t('ttk_draft_unsaved_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _TtkNewDraftChoice.cancel),
              child: Text(loc.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, _TtkNewDraftChoice.startNew),
              child: Text(loc.t('ttk_draft_start_new')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, _TtkNewDraftChoice.continueDraft),
              child: Text(loc.t('continue_action')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == _TtkNewDraftChoice.cancel) return;
      if (choice == _TtkNewDraftChoice.startNew) {
        await DraftStorageService()
            .clearTechCardEditDraftEverywhere('new', draftKey);
      }
    }
    final path = widget.department == 'bar'
        ? '/tech-cards/new?department=bar'
        : '/tech-cards/new';
    final needRefresh = await context.push<bool>(path);
    if (mounted && needRefresh == true) {
      _TtkListMemoryCache.invalidate();
      await _load(showLoading: false);
    }
  }

  Future<void> _onTapCreateTechCard(LocalizationService loc) async {
    if (_loading) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(loc.t('create_tech_card')),
              subtitle: Text(loc.t('ttk_create_manual_hint').trim().isEmpty
                  ? 'Заполнить ТТК вручную'
                  : loc.t('ttk_create_manual_hint')),
              onTap: () => Navigator.of(ctx).pop('manual'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(loc.t('create_with_ai').trim().isEmpty
                  ? 'Создать с ИИ'
                  : loc.t('create_with_ai')),
              subtitle: Text(loc.t('ttk_create_ai_hint').trim().isEmpty
                  ? 'Опишите блюдо текстом, ИИ заполнит ТТК'
                  : loc.t('ttk_create_ai_hint')),
              onTap: () => Navigator.of(ctx).pop('ai'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'manual') {
      await _openManualTechCardCreate(loc);
      return;
    }
    if (action == 'ai') {
      await _createFromText(context, loc);
    }
  }

  List<Widget> _buildAppBarActions(
      LocalizationService loc, bool canEdit, bool hasProSubscription) {
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
            onPressed: _loading ? null : () => _onTapCreateTechCard(loc),
          )
        : null;
    final importWidget = canEdit && hasProSubscription
        ? PopupMenuButton<String>(
            icon: const Icon(Icons.upload),
            tooltip: loc.t('ttk_import_file'),
            onSelected: (value) async {
              if (value == 'excel') await _createFromExcel(context, loc);
              if (value == 'text') await _createFromText(context, loc);
              if (value == 'photo') await _createFromPhoto(context, loc);
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
              if (!kIsWeb && OnDeviceOcrService.isSupported)
                PopupMenuItem(
                  value: 'photo',
                  child: Text(
                    loc.t('ai_tech_card_from_photo').trim().isEmpty
                        ? 'ТТК из фото'
                        : loc.t('ai_tech_card_from_photo'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
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
                          title: Text(
                              _tcListName(techCard, l.currentLanguageCode)),
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
        onPressed: _loading ? null : _pullToRefresh,
        tooltip: loc.t('refresh'));

    final result = <Widget>[];
    if (countWidget != null) result.add(wrap('ttk-count', countWidget));
    if (createWidget != null) result.add(wrap('ttk-create', createWidget));
    if (importWidget != null) result.add(wrap('ttk-import', importWidget));
    result.add(wrap('ttk-export', exportWidget));
    result.add(wrap('ttk-refresh', refreshWidget));
    return result;
  }

  /// Вкладки ПФ / Блюда / На проверку: рамка в primary, выбранная — с заливкой.
  Widget _ttkTabChip(
    String label, {
    required bool selected,
    int? badgeCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final p = scheme.primary;
    final pageFill = Theme.of(context).scaffoldBackgroundColor;
    final unselectedFill = pageFill;
    final selectedFill = Color.alphaBlend(
      const Color(0x33D32F2F),
      pageFill,
    );
    // Чуть увеличиваем расстояние между “кнопками-чипами” как в экране
    // номенклатуры: делаем зазор внешними паддингами, не трогая индикатор.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p, width: 1.2),
          color: selected ? selectedFill : unselectedFill,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
      ),
    );
  }

  List<Widget> _buildTabBarTabs(
    LocalizationService loc,
    int reviewCount, {
    required int selectedIndex,
  }) {
    final ctrl = _ttkTourController;

    Widget chipPf() => _ttkTabChip(
          loc.t('ttk_tab_pf'),
          selected: selectedIndex == 0,
        );
    Widget chipDishes() => _ttkTabChip(
          loc.t('ttk_tab_dishes'),
          selected: selectedIndex == 1,
        );
    Widget chipReview() => _ttkTabChip(
          loc.t('ttk_tab_review'),
          selected: selectedIndex == 2,
          badgeCount: reviewCount,
        );

    if (ctrl != null) {
      return [
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-pf',
            controller: ctrl,
            child: chipPf(),
          ),
        ),
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-dishes',
            controller: ctrl,
            child: chipDishes(),
          ),
        ),
        Tab(
          child: SpotlightTarget(
            id: 'ttk-tab-review',
            controller: ctrl,
            child: chipReview(),
          ),
        ),
      ];
    }
    return [
      Tab(child: chipPf()),
      Tab(child: chipDishes()),
      Tab(child: chipReview()),
    ];
  }

  Widget _buildBody(LocalizationService loc, bool canEdit, bool showCost) {
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            minHeight: 3,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    loc.t('loading'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
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
              FilledButton(
                  onPressed: _pullToRefresh, child: Text(loc.t('refresh'))),
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
    _ensureLowerSearchNameCache(loc);
    final query = _appliedSearchQuery;
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
      final names = _lowerSearchNameById;
      return list.where((tc) => (names[tc.id] ?? '').contains(query)).toList();
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

    final initialTabIndex =
        semiFinishedFiltered.isEmpty && dishFiltered.isNotEmpty ? 1 : 0;
    // Автоматический выбор первой вкладки (как раньше), но только один раз
    // и только если пользователь явно не трогал вкладки.
    if (!_tabAutoSelectedOnce &&
        !_tabWasTouched &&
        _tabIndexFromUrl == null &&
        _list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabWasTouched || _tabAutoSelectedOnce) return;
        _tabController.index = initialTabIndex;
        _tabAutoSelectedOnce = true;
      });
    }

    final narrowLandscape = isHandheldNarrowLayout(context) &&
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final tabBarView = TabBarView(
      controller: _tabController,
      children: [
        _buildTechCardsTable(
          semiFinishedFiltered,
          loc,
          canEdit,
          showCost,
          isDishesTab: false,
          hasActiveFilters: _appliedSearchQuery.isNotEmpty ||
              _filterSection != null ||
              _filterCategory != null,
        ),
        _buildTechCardsTable(
          dishFiltered,
          loc,
          canEdit,
          showCost,
          isDishesTab: true,
          hasActiveFilters: _appliedSearchQuery.isNotEmpty ||
              _filterSection != null ||
              _filterCategory != null,
        ),
        _buildReviewList(loc, canEdit),
      ],
    );

    final chromeChildren = <Widget>[
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabAlignment: TabAlignment.center,
          labelPadding: EdgeInsets.zero,
          dividerColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          indicator: const BoxDecoration(),
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.primary,
          onTap: (_) => _tabWasTouched = true,
          tabs: _buildTabBarTabs(
            loc,
            reviewCount,
            selectedIndex: _tabController.index,
          ),
        ),
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
            ListenableBuilder(
              listenable: _searchController,
              builder: (context, _) {
                return TextField(
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
                              _searchDebounceTimer?.cancel();
                              _searchController.clear();
                              setState(() {
                                _appliedSearchQuery = '';
                              });
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
                      const Duration(milliseconds: 320),
                      () {
                        if (!mounted) return;
                        final q = _searchController.text.trim().toLowerCase();
                        if (q == _appliedSearchQuery) return;
                        setState(() {
                          _appliedSearchQuery = q;
                        });
                      },
                    );
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
    ];

    if (narrowLandscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: chromeChildren,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: tabBarView,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...chromeChildren,
        Expanded(child: tabBarView),
      ],
    );
  }

  /// Компактная таблица с шапкой и группировкой по категории или цеху.
  /// isDishesTab: для блюд — себестоимость за порцию, для ПФ — стоимость за кг.
  Widget _buildTechCardsTable(List<TechCard> techCards, LocalizationService loc,
      bool canEdit, bool showCost,
      {bool isDishesTab = false, bool hasActiveFilters = false}) {
    if (techCards.isEmpty) {
      return RefreshIndicator(
        onRefresh: _pullToRefresh,
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
                  : (loc.t('ttk_tab_pf') == 'ttk_tab_pf'
                      ? 'ПФ'
                      : loc.t('ttk_tab_pf')),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasActiveFilters
                  ? loc.t('nothing_found')
                  : loc.t('tech_cards_empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final lang = loc.currentLanguageCode;
    final isMobile = isHandheldNarrowLayout(context);
    // Показываем все цеха целиком; на мобильном расширяем колонку "Цех".
    final colSectionWidth = isMobile ? 140.0 : 180.0;
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
          return (_tcListName(a, lang))
              .toLowerCase()
              .compareTo((_tcListName(b, lang)).toLowerCase());
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
      onRefresh: _pullToRefresh,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: false,
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
    final name = _tcListName(tc, lang);
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
            final needRefresh = await context.push<bool>(
              path,
              extra: {'initialTechCard': tc},
            );
            if (mounted && needRefresh == true) {
              _TtkListMemoryCache.invalidate();
              await _load(showLoading: false);
            }
          }
        },
        onLongPress: effectiveCanEdit && !_selectionMode
            ? () async {
                final needRefresh = await context.push<bool>(
                  '/tech-cards/${tc.id}?view=1',
                  extra: {'initialTechCard': tc},
                );
                if (mounted && needRefresh == true) {
                  _TtkListMemoryCache.invalidate();
                  await _load(showLoading: false);
                }
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
                  softWrap: true,
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
                  softWrap: true,
                  maxLines: null,
                  overflow: TextOverflow.visible,
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
                  child: Builder(builder: (ctx) {
                    final hasIngredients = tc.ingredients.isNotEmpty;
                    if (!hasIngredients) {
                      _queueIngredientsHydrationForCost(tc.id);
                      return Text(
                        '—',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      );
                    }

                    return Text(
                      isDishesTab
                          ? '${NumberFormatUtils.formatDecimal(_calculateCostPerPortion(tc))} $costSym'
                          : NumberFormatUtils.formatInt(
                              _calculateCostPerKg(tc)),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    );
                  }),
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
                        onPressed: () => context.push(
                          '/tech-cards/${tc.id}?view=1',
                          extra: {'initialTechCard': tc},
                        ),
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
                  DataCell(Text(_tcListName(tc, lang))),
                  DataCell(Text(_sectionLabelForDisplay(tc, loc))),
                  DataCell(Text(_categoryLabel(tc.category, loc))),
                  DataCell(Text(
                      NumberFormatUtils.formatInt(_calculateCostPerKg(tc)))),
                ],
                onSelectChanged: _selectionMode
                    ? null
                    : (_) => context.push(
                          path,
                          extra: {'initialTechCard': tc},
                        ),
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
