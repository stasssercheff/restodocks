import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import '../services/services.dart';
import '../services/inventory_download.dart';
import '../services/excel_file_saver_stub.dart'
    if (dart.library.html) '../services/excel_file_saver_web.dart' as file_saver;
import '../utils/number_format_utils.dart';
import 'menu_foodcost_panel.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';

/// Экран «Меню»: блюда заведения (ТТК с категорией «блюдо»).
/// Отображает состав как в ТТК и себестоимость всего блюда.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.department = 'kitchen'});

  final String department;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

/// Категории, относящиеся к бару (напитки, коктейли и т.д.).
const _barCategories = {'beverages', 'alcoholic_cocktails', 'non_alcoholic_drinks', 'hot_drinks', 'drinks_pure', 'snacks'};

bool _isBarDish(TechCard tc) => _barCategories.contains(tc.category) || tc.sections.contains('bar');

class _MenuScreenState extends State<MenuScreen> {
  List<TechCard> _dishes = [];
  List<TechCard> _dishesBar = [];
  List<TechCard> _dishesKitchen = [];
  bool _loading = true;
  String? _error;
  /// Для зала: выбранная вкладка (bar | kitchen).
  String _hallTab = 'bar';
  /// 0 — список меню, 1 — фудкост (таблица).
  int _menuSegment = 0;
  /// Stop/Go статусы: ключ 'techCardId_department', значение 'stop' | 'go'.
  Map<String, String> _stopGoMap = {};

  String _categoryLabel(String c, String lang) {
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      if (est == null) {
        setState(() { _loading = false; _error = 'no_establishment'; });
        return;
      }
      final productStore = context.read<ProductStoreSupabase>();
      final techCardService = context.read<TechCardServiceSupabase>();
      final stopGoSvc = context.read<MenuStopGoService>();
      await productStore.loadProducts();
      final stopGoMap = await stopGoSvc.loadStopGoMap(est.dataEstablishmentId);
      if (est.isBranch) {
        await productStore.loadNomenclatureForBranch(
            est.id, est.dataEstablishmentId);
      } else {
        await productStore.loadNomenclature(est.dataEstablishmentId);
      }
      final emp = acc.currentEmployee;
      final allTcs = await techCardService.getTechCardsForEstablishment(est.dataEstablishmentId);
      // Банкет/кейтеринг: только блюда с категорией banquet или catering
      // banquet-catering-bar: банкет/кейтеринг только барные (напитки, коктейли)
      // Зал: все блюда (отображаем вкладки Бар/Кухня)
      List<TechCard> tcs;
      if (widget.department == 'banquet-catering') {
        tcs = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (tc.category == 'banquet' || tc.category == 'catering')).toList();
      } else if (widget.department == 'banquet-catering-bar') {
        tcs = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (tc.category == 'banquet' || tc.category == 'catering') &&
            (tc.sections.contains('bar') || tc.sections.contains('all'))).toList();
      } else if (widget.department == 'hall' || widget.department == 'dining_room') {
        tcs = allTcs.where((tc) => !tc.isSemiFinished).toList();
      } else if (widget.department == 'bar') {
        tcs = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (_barCategories.contains(tc.category) ||
                tc.sections.contains('bar') ||
                tc.sections.contains('all'))).toList();
      } else {
        // Кухня/бар: показываем ВСЕ блюда отдела в меню для сотрудников подразделения (без фильтра по цехам).
        final byDept = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (!_barCategories.contains(tc.category) || tc.sections.contains('all'))).toList();
        tcs = byDept;
      }
      if (!mounted) return;
      final currency = emp?.currency ?? acc.establishment?.defaultCurrency ?? 'RUB';
      // Пересчитываем стоимость ингредиентов по актуальным ценам номенклатуры
      final enriched = <TechCard>[];
      for (final tc in tcs) {
        if (!tc.isSemiFinished) {
          enriched.add(_enrichWithCosts(
              tc, productStore, est.productsEstablishmentId, currency));
        }
      }
      if (mounted) {
        final barOnly = enriched.where((tc) => _barCategories.contains(tc.category)).toList();
        final kitchenOnly = enriched.where((tc) => !_barCategories.contains(tc.category)).toList();
        setState(() {
          _dishes = enriched;
          _dishesBar = barOnly;
          _dishesKitchen = kitchenOnly;
          _stopGoMap = stopGoMap;
          _loading = false;
        });
        // Фоновый перевод для ТТК без локализованного названия
        _translateMissingDishNames(enriched, est.dataEstablishmentId);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Запускает фоновый перевод названий для ТТК, у которых нет dishNameLocalized
  Future<void> _translateMissingDishNames(List<TechCard> cards, String establishmentId) async {
    if (!mounted) return;
    final curLang = context.read<LocalizationService>().currentLanguageCode;
    final translationManager = context.read<TranslationManager>();
    final svc = context.read<TechCardServiceSupabase>();
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null) return;

    for (final tc in cards) {
      final targetLang = curLang == 'ru' ? 'en' : 'ru';
      if (tc.dishNameLocalized == null || !tc.dishNameLocalized!.containsKey(targetLang)) {
        try {
          final translated = await translationManager.getLocalizedText(
            entityType: TranslationEntityType.techCard,
            entityId: tc.id,
            fieldName: 'dish_name',
            sourceText: tc.dishName,
            sourceLanguage: curLang,
            targetLanguage: targetLang,
          );
          if (translated != tc.dishName && mounted) {
            final nameMap = Map<String, String>.from(tc.dishNameLocalized ?? {});
            nameMap[curLang] = tc.dishName;
            nameMap[targetLang] = translated;
            final updated = tc.copyWith(dishNameLocalized: nameMap);
            await svc.saveTechCard(updated, skipHistory: true);
            if (mounted) {
              setState(() {
                final idx = _dishes.indexWhere((d) => d.id == tc.id);
                if (idx != -1) _dishes[idx] = updated;
              });
            }
          }
        } catch (_) {}
      }
    }
  }

  /// Пересчёт стоимости ингредиентов по ценам номенклатуры
  TechCard _enrichWithCosts(TechCard tc, ProductStoreSupabase store, String establishmentId, String currency) {
    final updated = <TTIngredient>[];
    for (final ing in tc.ingredients) {
      if (ing.productId != null) {
        final priceInfo = store.getEstablishmentPrice(ing.productId!, establishmentId);
        final price = priceInfo?.$1 ?? ing.pricePerKg ?? 0;
        final cost = price * (ing.grossWeight / 1000.0);
        updated.add(ing.copyWith(cost: cost, pricePerKg: price, costCurrency: priceInfo?.$2 ?? currency));
      } else {
        updated.add(ing);
      }
    }
    return tc.copyWith(ingredients: updated);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  bool get _isHallMenu => widget.department == 'hall' || widget.department == 'dining_room';

  /// Редактирование stop/go: кухня и бар (не зал, не банкет).
  bool get _canEditStopGo =>
      widget.department == 'kitchen' || widget.department == 'bar';

  /// Подразделение блюда для stop/go: bar или kitchen.
  String _dishDepartment(TechCard tc) => _isBarDish(tc) ? 'bar' : 'kitchen';

  /// Полный вид ТТК (себестоимость, состав, технология): руководство подразделения + ген. директор; в меню зала — менеджер зала.
  bool _canSeeFullTtkView(Employee? emp, TechCard tc) {
    if (emp == null) return false;
    if (emp.hasRole('owner')) return true;
    if (emp.hasRole('general_manager')) return true;
    if (emp.hasRole('floor_manager') && _isHallMenu) return true;
    if ((emp.hasRole('executive_chef') || emp.hasRole('sous_chef')) && !_isBarDish(tc)) return true;
    if (emp.hasRole('bar_manager') && _isBarDish(tc)) return true;
    return false;
  }

  /// Вкладка «Фудкост»: шеф/су-шеф, барменеджер, менеджер зала, ген. директор, собственник, руководство (офис).
  bool _showFoodcostTab(Employee? emp) {
    if (emp == null) return false;
    if (widget.department == 'banquet-catering' ||
        widget.department == 'banquet-catering-bar') {
      return false;
    }
    if (emp.hasRole('owner')) return true;
    if (emp.hasRole('general_manager')) return true;
    final mgmtFoodcost = emp.department == 'management' &&
        (emp.hasRole('manager') ||
            emp.hasRole('assistant_manager') ||
            emp.hasRole('executive_chef') ||
            emp.hasRole('bar_manager') ||
            emp.hasRole('floor_manager'));
    switch (widget.department) {
      case 'bar':
        return emp.hasRole('bar_manager') || mgmtFoodcost;
      case 'hall':
      case 'dining_room':
        return emp.hasRole('floor_manager') || mgmtFoodcost;
      default:
        return emp.hasRole('executive_chef') ||
            emp.hasRole('sous_chef') ||
            mgmtFoodcost;
    }
  }

  /// Скачать карточку блюда могут только руководители подразделения.
  bool _canDownloadDishCard(Employee? emp, TechCard tc) {
    if (emp == null) return false;
    if (emp.hasRole('owner')) return true;
    if (tc.sections.contains('bar') || _isBarDish(tc)) {
      return emp.hasRole('bar_manager') ||
          emp.hasRole('manager') ||
          emp.hasRole('general_manager');
    }
    return emp.hasRole('executive_chef') ||
        emp.hasRole('sous_chef') ||
        emp.hasRole('manager') ||
        emp.hasRole('general_manager');
  }

  bool _hasHallContent(TechCard tc) {
    final d = tc.descriptionForHall?.trim() ?? '';
    final c = tc.compositionForHall?.trim() ?? '';
    return d.isNotEmpty || c.isNotEmpty;
  }

  bool _isViewOnlyCardForEmployee(TechCard tc, Employee? emp) {
    final est = context.read<AccountManagerSupabase>().establishment;
    final branchReadOnly = est != null && est.isBranch && tc.establishmentId != est.id;
    if (branchReadOnly) return true;
    if (emp == null) return true;
    if (emp.hasRole('owner') || emp.hasRole('general_manager')) return false;
    if ((emp.hasRole('executive_chef') || emp.hasRole('sous_chef')) && !_isBarDish(tc)) return false;
    if (emp.hasRole('bar_manager') && _isBarDish(tc)) return false;
    final mgmtEditor = emp.department == 'management' &&
        (emp.hasRole('manager') || emp.hasRole('assistant_manager'));
    return !mgmtEditor;
  }

  Future<void> _openTechCardFromMenu(TechCard tc) async {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final viewOnly = _isViewOnlyCardForEmployee(tc, emp);
    final viewPath = '/tech-cards/${tc.id}?view=1';
    final editPath = '/tech-cards/${tc.id}';
    if (viewOnly) {
      await context.push(viewPath);
      return;
    }
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(loc.t('edit')),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(loc.t('ttk_view')),
              onTap: () => Navigator.of(ctx).pop('view'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('cancel')),
          ),
        ],
      ),
    );
    if (!mounted || mode == null) return;
    await context.push(mode == 'edit' ? editPath : viewPath);
  }

  String _buildSubtitleText(LocalizationService loc, TechCard tc, String lang) {
    final cat = _categoryLabel(tc.category, lang);
    // Меню зала: только описание для зала (без просмотра ТТК/состава/цен).
    if (_isHallMenu) {
      final d = tc.descriptionForHall?.trim() ?? '';
      if (d.isNotEmpty) return d;
      return cat;
    }
    return cat;
  }

  /// Блюда, которые пользователь может скачать (полный вид ТТК).
  List<TechCard> get _downloadableDishes {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    return _displayDishes.where((tc) => _canSeeFullTtkView(emp, tc)).toList();
  }

  Future<void> _downloadMenu() async {
    final loc = context.read<LocalizationService>();
    final list = _downloadableDishes;
    if (list.isEmpty) return;
    try {
      final sym = context.read<AccountManagerSupabase>().establishment?.currencySymbol ?? '₽';
      final fileName = await MenuExportService.saveMenuPdf(
        dishes: list,
        t: loc.t,
        lang: loc.currentLanguageCode,
        currencySym: sym,
        productStore: context.read<ProductStoreSupabase>(),
      );
      if (mounted) AppToastService.show(loc.t('menu') + ' ✓ $fileName');
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error_short')}: $e', duration: const Duration(seconds: 4));
    }
  }

  Future<void> _downloadAllDishes() async {
    final loc = context.read<LocalizationService>();
    final list = _downloadableDishes;
    if (list.isEmpty) return;
    try {
      final sym = context.read<AccountManagerSupabase>().establishment?.currencySymbol ?? '₽';
      final tcs = context.read<TechCardServiceSupabase>();
      final store = context.read<ProductStoreSupabase>();
      int count = 0;
      for (final tc in list) {
        await MenuExportService.saveDishPdf(
          dish: tc,
          techCardService: tcs,
          productStore: store,
          t: loc.t,
          lang: loc.currentLanguageCode,
          currencySym: sym,
        );
        count++;
      }
      if (mounted) AppToastService.show('${loc.t('download_all_dishes')} ✓ ($count)', duration: const Duration(seconds: 3));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error_short')}: $e', duration: const Duration(seconds: 4));
    }
  }

  Future<void> _downloadDish(TechCard tc) async {
    final loc = context.read<LocalizationService>();
    try {
      final fileName = await MenuExportService.saveHallDishPdf(
        dish: tc,
        t: loc.t,
        lang: loc.currentLanguageCode,
      );
      if (mounted) AppToastService.show(loc.t('download_dish') + ' ✓ $fileName');
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error_short')}: $e', duration: const Duration(seconds: 4));
    }
  }

  Future<void> _openDeviceExportDialog() async {
    final loc = context.read<LocalizationService>();
    final isFoodcostTab = _menuSegment == 1;
    final allDishes = List<TechCard>.from(_displayDishes);
    if (allDishes.isEmpty) return;

    String t(String key, String fallback) {
      final v = loc.t(key);
      return v == key ? fallback : v;
    }

    var exportScope = 'all'; // all | selected | above | below
    var exportFormat = 'pdf'; // pdf | xlsx
    var exportLang = loc.currentLanguageCode;
    var selectedIds = <String>{};
    final fcConfig = await _loadFoodcostExportConfig();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t('download', 'Скачать')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isFoodcostTab ? 'Фудкост меню' : 'Меню'),
                const SizedBox(height: 10),
                RadioListTile<String>(
                  dense: true,
                  value: 'all',
                  groupValue: exportScope,
                  title: const Text('Все'),
                  onChanged: (v) => setLocal(() => exportScope = v ?? 'all'),
                ),
                RadioListTile<String>(
                  dense: true,
                  value: 'selected',
                  groupValue: exportScope,
                  title: const Text('Выборочно'),
                  onChanged: (v) => setLocal(() => exportScope = v ?? 'selected'),
                ),
                if (isFoodcostTab) ...[
                  RadioListTile<String>(
                    dense: true,
                    value: 'above',
                    groupValue: exportScope,
                    title: const Text('Выгодно (выше цели)'),
                    onChanged: (v) => setLocal(() => exportScope = v ?? 'above'),
                  ),
                  RadioListTile<String>(
                    dense: true,
                    value: 'below',
                    groupValue: exportScope,
                    title: const Text('Невыгодно (ниже цели)'),
                    onChanged: (v) => setLocal(() => exportScope = v ?? 'below'),
                  ),
                ],
                if (exportScope == 'selected')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final picked = await _pickDishIdsForExport(allDishes, selectedIds);
                        if (picked == null) return;
                        setLocal(() => selectedIds = picked);
                      },
                      icon: const Icon(Icons.checklist),
                      label: Text(
                        selectedIds.isEmpty
                            ? (loc.t('ttk_select_for_export') ?? 'Выбрать позиции')
                            : '${loc.t('ttk_select_for_export') ?? 'Выбрано'}: ${selectedIds.length}',
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Text('Язык сохранения'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: exportLang,
                  items: const [
                    DropdownMenuItem(value: 'ru', child: Text('🇷🇺 Русский')),
                    DropdownMenuItem(value: 'en', child: Text('🇺🇸 English')),
                    DropdownMenuItem(value: 'es', child: Text('🇪🇸 Español')),
                    DropdownMenuItem(value: 'it', child: Text('🇮🇹 Italiano')),
                    DropdownMenuItem(value: 'tr', child: Text('🇹🇷 Türkçe')),
                  ],
                  onChanged: (v) => setLocal(() => exportLang = v ?? exportLang),
                ),
                const SizedBox(height: 10),
                const Text('Формат файла'),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pdf', label: Text('PDF')),
                    ButtonSegment(value: 'xlsx', label: Text('Excel')),
                  ],
                  selected: {exportFormat},
                  onSelectionChanged: (s) => setLocal(() => exportFormat = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  isFoodcostTab
                      ? (loc.t('menu_tab_foodcost') ?? 'Фудкост')
                      : (loc.t('menu_tab_list') ?? 'Список'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('cancel', 'Отмена')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t('save', 'Сохранить')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    List<TechCard> selected;
    if (exportScope == 'selected') {
      selected = allDishes.where((d) => selectedIds.contains(d.id)).toList();
    } else if (exportScope == 'above') {
      selected = allDishes.where((d) => _isDishAboveTarget(d, fcConfig)).toList();
    } else if (exportScope == 'below') {
      selected = allDishes.where((d) => _isDishBelowTarget(d, fcConfig)).toList();
    } else {
      selected = allDishes;
    }
    if (selected.isEmpty) {
      AppToastService.show(loc.t('ttk_none_selected') ?? 'Ничего не выбрано');
      return;
    }
    await _exportMenuOrFoodcost(
      dishes: selected,
      exportLang: exportLang,
      exportFormat: exportFormat,
      isFoodcost: isFoodcostTab,
      foodcostConfig: fcConfig,
    );
  }

  Future<Set<String>?> _pickDishIdsForExport(
      List<TechCard> dishes, Set<String> preselected) async {
    final loc = context.read<LocalizationService>();
    final selected = {...preselected};
    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(loc.t('ttk_select_for_export') ?? 'Выберите позиции'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: ListView.builder(
              itemCount: dishes.length,
              itemBuilder: (_, i) {
                final tc = dishes[i];
                final checked = selected.contains(tc.id);
                return CheckboxListTile(
                  dense: true,
                  value: checked,
                  title: Text(tc.dishName),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) {
                    setLocal(() {
                      if (v == true) {
                        selected.add(tc.id);
                      } else {
                        selected.remove(tc.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(loc.t('cancel')),
            ),
            TextButton(
              onPressed: () {
                setLocal(() {
                  selected
                    ..clear()
                    ..addAll(dishes.map((e) => e.id));
                });
              },
              child: Text(loc.t('select_all') ?? 'Выбрать все'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(loc.t('apply') ?? 'Применить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportMenuOrFoodcost({
    required List<TechCard> dishes,
    required String exportLang,
    required String exportFormat,
    required bool isFoodcost,
    required ({FoodcostPricingMode mode, double? globalPct, Map<String, double> customPct}) foodcostConfig,
  }) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final emp = account.currentEmployee;
    final currencyCode =
        account.currentEmployee?.currency ?? est?.defaultCurrency ?? 'RUB';
    final currencySym = est?.currencySymbol ??
        account.currentEmployee?.currencySymbol ??
        Establishment.currencySymbolFor(currencyCode);
    final chefName = (emp?.fullName.trim().isNotEmpty ?? false) ? emp!.fullName : '—';
    final estName = (est?.name.trim().isNotEmpty ?? false) ? est!.name : '—';
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());
    try {
      if (exportFormat == 'pdf') {
        final bytes = await _buildSimpleMenuPdfBytes(
          dishes: dishes,
          isFoodcost: isFoodcost,
          exportLang: exportLang,
          dateStr: dateStr,
          chefName: chefName,
          establishmentName: estName,
          currencyCode: currencyCode,
          currencySym: currencySym,
          cfg: foodcostConfig,
        );
        final fileName =
            '${_exportFileBaseName(isFoodcost: isFoodcost, exportLang: exportLang, establishmentName: estName)}.pdf';
        await saveFileBytes(fileName, bytes);
        if (mounted) AppToastService.show('${loc.t('saved') ?? 'Сохранено'}: $fileName');
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel['Export'];
      sheet.appendRow(_textRow([
        'Дата',
        dateStr,
      ]));
      sheet.appendRow(_textRow([
        'Заведение',
        estName,
      ]));
      sheet.appendRow(_textRow([
        'Шеф',
        chefName,
      ]));
      sheet.appendRow(_textRow(['']));
      sheet.appendRow(_textRow([
        '№',
        'Блюдо',
        if (isFoodcost) 'Себестоимость',
        isFoodcost
            ? (foodcostConfig.mode == FoodcostPricingMode.markupOnCost
                ? 'Наценка'
                : '% себестоимости')
            : '',
        if (isFoodcost) 'С наценкой',
        if (isFoodcost) 'В меню',
      ]));
      var idx = 1;
      for (final tc in dishes) {
        final cost = _portionCostForFoodcost(tc);
        final menuPrice = tc.sellingPrice;
        final menuPriceValue = menuPrice ?? 0.0;
        final actualPct = _actualPct(tc, foodcostConfig.mode);
        final targetPct = foodcostConfig.customPct[tc.id] ?? foodcostConfig.globalPct;
        final optimal = _optimalPriceForMode(cost, targetPct, foodcostConfig.mode);
        sheet.appendRow(_textRow([
          '$idx',
          tc.dishName,
          if (isFoodcost)
            (cost > 0
                ? NumberFormatUtils.formatSumWithSymbol(
                    cost, currencyCode, currencySym)
                : '—'),
          isFoodcost
              ? (actualPct != null ? '${actualPct.toStringAsFixed(1)}%' : '—')
              : '',
          if (isFoodcost)
            (optimal != null
                ? NumberFormatUtils.formatSumWithSymbol(
                    optimal, currencyCode, currencySym)
                : '—'),
          if (isFoodcost)
            (menuPrice != null && menuPrice > 0
                ? NumberFormatUtils.formatSumWithSymbol(
                    menuPriceValue, currencyCode, currencySym)
                : '—'),
        ]));
        idx++;
      }
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Excel encoding failed');
      final fileName =
          '${_exportFileBaseName(isFoodcost: isFoodcost, exportLang: exportLang, establishmentName: estName)}.xlsx';
      file_saver.saveExcelBytes(Uint8List.fromList(bytes), fileName);
      if (mounted) AppToastService.show('${loc.t('saved') ?? 'Сохранено'}: $fileName');
    } catch (e) {
      if (mounted) {
        AppToastService.show(
          '${loc.t('error_short')}: $e',
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  List<TextCellValue> _textRow(List<String> values) {
    return values.map((v) => TextCellValue(v)).toList();
  }

  String _exportFileBaseName({
    required bool isFoodcost,
    required String exportLang,
    required String establishmentName,
  }) {
    final date = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final prefix = _localizedExportPrefix(
      isFoodcost: isFoodcost,
      lang: exportLang,
    );
    final safeEst = establishmentName
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${prefix}_${safeEst.isEmpty ? 'establishment' : safeEst}_$date';
  }

  String _localizedExportPrefix({
    required bool isFoodcost,
    required String lang,
  }) {
    const map = <String, ({String menu, String foodcost})>{
      'ru': (menu: 'меню', foodcost: 'фудкост'),
      'en': (menu: 'menu', foodcost: 'foodcost'),
      'es': (menu: 'menu', foodcost: 'coste'),
      'it': (menu: 'menu', foodcost: 'foodcost'),
      'tr': (menu: 'menu', foodcost: 'maliyet'),
    };
    final labels = map[lang] ?? map['en']!;
    return isFoodcost ? labels.foodcost : labels.menu;
  }

  Future<Uint8List> _buildSimpleMenuPdfBytes({
    required List<TechCard> dishes,
    required bool isFoodcost,
    required String exportLang,
    required String dateStr,
    required String chefName,
    required String establishmentName,
    required String currencyCode,
    required String currencySym,
    required ({FoodcostPricingMode mode, double? globalPct, Map<String, double> customPct}) cfg,
  }) async {
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final regular = pw.Font.ttf(baseData);
    final bold = pw.Font.ttf(boldData);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final headers = <String>[
      '№',
      'Блюдо',
      if (isFoodcost) 'Себестоимость',
      if (isFoodcost)
        (cfg.mode == FoodcostPricingMode.markupOnCost ? 'Наценка' : '% себестоимости'),
      if (isFoodcost) 'С наценкой',
      if (isFoodcost) 'В меню',
    ];

    final rows = <List<String>>[];
    var idx = 1;
    for (final tc in dishes) {
      final cost = _portionCostForFoodcost(tc);
      final actualPct = _actualPct(tc, cfg.mode);
      final targetPct = cfg.customPct[tc.id] ?? cfg.globalPct;
      final optimal = _optimalPriceForMode(cost, targetPct, cfg.mode);
      rows.add([
        '$idx',
        tc.getDisplayNameInLists(exportLang),
        if (isFoodcost)
          (cost > 0
              ? NumberFormatUtils.formatSumWithSymbol(cost, currencyCode, currencySym)
              : '—'),
        if (isFoodcost) (actualPct != null ? '${actualPct.toStringAsFixed(1)}%' : '—'),
        if (isFoodcost)
          (optimal != null
              ? NumberFormatUtils.formatSumWithSymbol(optimal, currencyCode, currencySym)
              : '—'),
        if (isFoodcost)
          (tc.sellingPrice != null && tc.sellingPrice! > 0
              ? NumberFormatUtils.formatSumWithSymbol(
                  tc.sellingPrice!, currencyCode, currencySym)
              : '—'),
      ]);
      idx++;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text(isFoodcost ? 'Фудкост меню' : 'Меню',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Дата: $dateStr'),
          pw.Text('Заведение: $establishmentName'),
          pw.Text('Шеф: $chefName'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(2.2),
            },
          ),
        ],
      ),
    );
    return doc.save();
  }

  double? _actualPct(TechCard tc, FoodcostPricingMode mode) {
    final sell = tc.sellingPrice;
    final cost = _portionCostForFoodcost(tc);
    if (sell == null || sell <= 0 || cost <= 0) return null;
    if (mode == FoodcostPricingMode.markupOnCost) {
      return (sell / cost - 1) * 100;
    }
    return (cost / sell) * 100;
  }

  double? _optimalPriceForMode(double cost, double? targetPct, FoodcostPricingMode mode) {
    if (targetPct == null || cost <= 0) return null;
    if (mode == FoodcostPricingMode.markupOnCost) {
      return cost * (1 + targetPct / 100);
    }
    if (targetPct >= 100) return null;
    return cost * 100 / targetPct;
  }

  Future<({FoodcostPricingMode mode, double? globalPct, Map<String, double> customPct})>
      _loadFoodcostExportConfig() async {
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    if (estId == null || estId.isEmpty) {
      return (
        mode: FoodcostPricingMode.markupOnCost,
        globalPct: 100.0,
        customPct: <String, double>{},
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString('restodocks_foodcost_mode_$estId');
    final targetRaw = prefs.getString('restodocks_foodcost_target_$estId');
    final overridesRaw = prefs.getString('restodocks_foodcost_dish_overrides_$estId');
    final mode = modeRaw == 'cost_share'
        ? FoodcostPricingMode.costShareOfPrice
        : FoodcostPricingMode.markupOnCost;
    final globalPct =
        _parsePct(targetRaw) ?? (mode == FoodcostPricingMode.costShareOfPrice ? 35.0 : 100.0);
    final custom = <String, double>{};
    if (overridesRaw != null && overridesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(overridesRaw);
        if (decoded is Map<String, dynamic>) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is! Map<String, dynamic>) continue;
            if (v['u'] != true) continue;
            final p = _parsePct(v['p']?.toString());
            if (p != null && p > 0) custom[e.key] = p;
          }
        }
      } catch (_) {}
    }
    return (mode: mode, globalPct: globalPct, customPct: custom);
  }

  double? _parsePct(String? raw) {
    if (raw == null) return null;
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v;
  }

  double _portionCostForFoodcost(TechCard tc) {
    var totalCost = tc.totalCost;
    if (totalCost <= 0) {
      totalCost = tc.ingredients.fold<double>(0, (s, i) => s + i.effectiveCost);
    }
    if (totalCost <= 0) return 0;
    final yieldG = tc.yield > 0
        ? tc.yield
        : tc.ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    if (yieldG <= 0) return 0;
    final portionG = tc.portionWeight > 0 ? tc.portionWeight : yieldG;
    return totalCost * portionG / yieldG;
  }

  bool _isDishAboveTarget(
    TechCard tc,
    ({FoodcostPricingMode mode, double? globalPct, Map<String, double> customPct}) cfg,
  ) {
    final sell = tc.sellingPrice;
    if (sell == null || sell <= 0) return false;
    final cost = _portionCostForFoodcost(tc);
    if (cost <= 0) return false;
    final targetPct = cfg.customPct[tc.id] ?? cfg.globalPct;
    if (targetPct == null) return false;
    if (cfg.mode == FoodcostPricingMode.markupOnCost) {
      final actual = (sell / cost - 1) * 100;
      return actual > targetPct;
    }
    final actual = (cost / sell) * 100;
    return actual < targetPct;
  }

  bool _isDishBelowTarget(
    TechCard tc,
    ({FoodcostPricingMode mode, double? globalPct, Map<String, double> customPct}) cfg,
  ) {
    final sell = tc.sellingPrice;
    if (sell == null || sell <= 0) return false;
    final cost = _portionCostForFoodcost(tc);
    if (cost <= 0) return false;
    final targetPct = cfg.customPct[tc.id] ?? cfg.globalPct;
    if (targetPct == null) return false;
    if (cfg.mode == FoodcostPricingMode.markupOnCost) {
      final actual = (sell / cost - 1) * 100;
      return actual < targetPct;
    }
    final actual = (cost / sell) * 100;
    return actual > targetPct;
  }

  /// Контент раскрытой карточки: полная ТТК с ценой / полная ТТК без цены / описание для зала.
  Widget _buildExpandedContent(Employee? emp, LocalizationService loc,
      TechCard tc, String lang, String currencySym, String currencyCode) {
    if (_isHallMenu) {
      return _HallDishContent(
        loc: loc,
        techCard: tc,
        description: tc.descriptionForHall ?? '',
        composition: tc.compositionForHall ?? '',
        // Для зала показываем только блок "для меню зала": описание/состав и фото (слева).
        sellingPrice: null,
        currencySym: currencySym,
      );
    }
    final showCost = _canSeeFullTtkView(emp, tc);
    final canDownloadDishCard = _canDownloadDishCard(emp, tc);
    final table = _MenuDishTable(
      loc: loc,
      dishName: tc.dishName,
      techCard: tc,
      ingredients: tc.ingredients.where((i) => !i.isPlaceholder || i.hasData).toList(),
      technology: tc.getLocalizedTechnology(lang),
      currencyCode: currencyCode,
      currencySym: currencySym,
      showCost: showCost,
      productStore: context.read<ProductStoreSupabase>(),
    );
    // Кухня/бар: всегда показываем таблицу и технологию.
    if (!showCost) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canDownloadDishCard)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: Text(loc.t('download_dish')),
              onPressed: () => _downloadDish(tc),
            ),
          ),
        table,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.read<AccountManagerSupabase>();
    final emp = accountManager.currentEmployee;
    final estForCur = accountManager.establishment;
    final empForCur = accountManager.currentEmployee;
    final currencyCode =
        empForCur?.currency ?? estForCur?.defaultCurrency ?? 'RUB';
    final sym = estForCur?.currencySymbol ??
        empForCur?.currencySymbol ??
        Establishment.currencySymbolFor(currencyCode);
    final showFoodcost = _showFoodcostTab(emp);
    final menuSeg = showFoodcost ? _menuSegment : 0;
    final hallChips = _isHallMenu &&
        !_loading &&
        (_dishesBar.isNotEmpty || _dishesKitchen.isNotEmpty) &&
        menuSeg == 0;
    double? bottomHeight;
    if (showFoodcost || hallChips) {
      var h = 16.0;
      if (showFoodcost) h += 52;
      if (hallChips) h += 48;
      bottomHeight = h;
    }

    return Scaffold(
      appBar: AppBar(
        title: ScrollToTopAppBarTitle(
          child: Text(loc.t('menu')),
        ),
        leading: appBarBackButton(context),
        bottom: bottomHeight != null
            ? PreferredSize(
                preferredSize: Size.fromHeight(bottomHeight),
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showFoodcost)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SegmentedButton<int>(
                                segments: [
                                  ButtonSegment<int>(
                                    value: 0,
                                    label: Text(loc.t('menu_tab_list')),
                                  ),
                                  ButtonSegment<int>(
                                    value: 1,
                                    label: Text(loc.t('menu_tab_foodcost')),
                                  ),
                                ],
                                selected: {menuSeg},
                                onSelectionChanged: (s) =>
                                    setState(() => _menuSegment = s.first),
                              ),
                            ),
                          ),
                        if (hallChips)
                          Row(
                            children: [
                              Expanded(
                                child: _HallTabChip(
                                  label: loc.t('dept_bar'),
                                  selected: _hallTab == 'bar',
                                  onTap: () => setState(() => _hallTab = 'bar'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _HallTabChip(
                                  label: loc.t('dept_kitchen'),
                                  selected: _hallTab == 'kitchen',
                                  onTap: () => setState(() => _hallTab = 'kitchen'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (_displayDishes.isNotEmpty && !_loading)
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Скачать',
              onPressed: _openDeviceExportDialog,
            ),
          if (menuSeg == 0 && _downloadableDishes.isNotEmpty && !_loading)
            PopupMenuButton<String>(
              icon: const Icon(Icons.download),
              tooltip: loc.t('download'),
              onSelected: (v) async {
                if (v == 'menu') await _downloadMenu();
                if (v == 'all') await _downloadAllDishes();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'menu', child: Text(loc.t('download_menu'))),
                PopupMenuItem(value: 'all', child: Text(loc.t('download_all_dishes'))),
              ],
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
        ],
      ),
      body: _buildBody(loc, sym, currencyCode),
    );
  }

  List<TechCard> get _displayDishes {
    if (_isHallMenu) {
      return _hallTab == 'bar' ? _dishesBar : _dishesKitchen;
    }
    return _dishes;
  }

  Widget _buildBody(
      LocalizationService loc, String currencySym, String currencyCode) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      final errorText = _error == 'no_establishment' ? loc.t('no_establishment') : _error!;
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
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final est = account.establishment;
    final showFoodcost = _showFoodcostTab(emp);
    final menuSeg = showFoodcost ? _menuSegment : 0;
    if (showFoodcost && menuSeg == 1 && est != null) {
      return MenuFoodcostPanel(
        dishes: _displayDishes,
        nomenclatureEstablishmentId: est.productsEstablishmentId,
        nomenclatureMergeParentEstablishmentId:
            est.isBranch ? est.dataEstablishmentId : null,
        prefsScopeEstablishmentId: est.id,
        currencyCode: currencyCode,
        currencySym: currencySym,
        langCode: loc.currentLanguageCode,
        // Вкладка фудкост только у ролей с правом на ценообразование — открываем ТТК без view=1.
        openCardInEditMode: true,
      );
    }
    final dishesToShow = _displayDishes;
    if (dishesToShow.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(loc.t('menu'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                loc.t('menu_empty_dishes'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: dishesToShow.length,
        itemBuilder: (context, index) {
          final tc = dishesToShow[index];
          final lang = loc.currentLanguageCode;
          final dishDept = _dishDepartment(tc);
          final stopGoSvc = context.read<MenuStopGoService>();
          final status = stopGoSvc.getStatus(_stopGoMap, tc.id, dishDept);
          final photoUrls = tc.photoUrls ?? [];
          final photoUrl = photoUrls.isNotEmpty ? photoUrls.first : null;
          final fallbackIcon = Icon(
            tc.isSemiFinished ? Icons.inventory_2 : Icons.restaurant,
            color: Theme.of(context).colorScheme.primary,
          );
          final titleStyle = TextStyle(
            fontWeight: FontWeight.w600,
            color: _isHallMenu && status != null
                ? (status == 'stop'
                    ? Colors.red.shade700
                    : Colors.green.shade700)
                : null,
          );
          final statusBadge = _isHallMenu && status != null
              ? Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: status == 'stop'
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      width: 1.8,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    status == 'stop' ? 'x' : '!',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: status == 'stop'
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                      fontSize: 12,
                    ),
                  ),
                )
              : null;
          if (!_isHallMenu) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                onTap: () => _openTechCardFromMenu(tc),
                leading: GestureDetector(
                  onTap: photoUrl != null
                      ? () => _showPhotoFullscreen(context, photoUrls)
                      : null,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: photoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _LazyPhoto(url: photoUrl, fallback: fallbackIcon),
                          )
                        : fallbackIcon,
                  ),
                ),
                title: Text(tc.getDisplayNameInLists(lang), style: titleStyle),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      _buildSubtitleText(loc, tc, lang),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_canEditStopGo) ...[
                      const SizedBox(height: 6),
                      _StopGoChips(
                        currentStatus: status,
                        onSelect: (s) async {
                          final est = context.read<AccountManagerSupabase>().establishment;
                          if (est == null) return;
                          try {
                            await stopGoSvc.setStatus(
                              establishmentId: est.dataEstablishmentId,
                              techCardId: tc.id,
                              department: dishDept,
                              status: s,
                            );
                            if (mounted) {
                              setState(() {
                                final k = '${tc.id}_$dishDept';
                                if (s == null) {
                                  _stopGoMap.remove(k);
                                } else {
                                  _stopGoMap[k] = s;
                                }
                              });
                            }
                          } catch (_) {}
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              leading: GestureDetector(
                onTap: photoUrl != null
                    ? () => _showPhotoFullscreen(context, photoUrls)
                    : null,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: photoUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _LazyPhoto(url: photoUrl, fallback: fallbackIcon),
                        )
                      : fallbackIcon,
                ),
              ),
              title: Row(
                children: [
                  if (statusBadge != null) ...[
                    statusBadge,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: InkWell(
                      onTap: null,
                      child: Text(
                        tc.getDisplayNameInLists(lang),
                        style: titleStyle,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: null,
                    child: Text(
                      _buildSubtitleText(loc, tc, lang),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: _isHallMenu ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_canEditStopGo) ...[
                    const SizedBox(height: 6),
                    _StopGoChips(
                      currentStatus: status,
                      onSelect: (s) async {
                        final est = context.read<AccountManagerSupabase>().establishment;
                        if (est == null) return;
                        try {
                          await stopGoSvc.setStatus(
                            establishmentId: est.dataEstablishmentId,
                            techCardId: tc.id,
                            department: dishDept,
                            status: s,
                          );
                          if (mounted) {
                            setState(() {
                              final k = '${tc.id}_$dishDept';
                              if (s == null) {
                                _stopGoMap.remove(k);
                              } else {
                                _stopGoMap[k] = s;
                              }
                            });
                          }
                        } catch (_) {}
                      },
                    ),
                  ],
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: _buildExpandedContent(
                    context.read<AccountManagerSupabase>().currentEmployee,
                    loc,
                    tc,
                    lang,
                    currencySym,
                    currencyCode,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPhotoFullscreen(BuildContext ctx, List<String> urls) {
    showDialog(
      context: ctx,
      barrierColor: Colors.black87,
      builder: (_) => _MenuPhotoViewer(urls: urls),
    );
  }
}

/// Чипсы Stop / Go для редактирования в меню кухни/бара.
class _StopGoChips extends StatelessWidget {
  const _StopGoChips({required this.currentStatus, required this.onSelect});

  final String? currentStatus;
  final void Function(String? status) onSelect;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilterChip(
          label: Text(loc.t('stop_list')),
          selected: currentStatus == 'stop',
          onSelected: (_) => onSelect(currentStatus == 'stop' ? null : 'stop'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: Text(loc.t('go_list')),
          selected: currentStatus == 'go',
          onSelected: (_) => onSelect(currentStatus == 'go' ? null : 'go'),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

/// Вкладка для меню зала (Бар / Кухня).
class _HallTabChip extends StatelessWidget {
  const _HallTabChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : null,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Блок описания, состава, КБЖУ, аллергенов и продажной цены для зала.
class _HallDishContent extends StatelessWidget {
  const _HallDishContent({
    required this.loc,
    required this.techCard,
    required this.description,
    required this.composition,
    this.sellingPrice,
    this.currencySym = '',
  });

  final LocalizationService loc;
  final TechCard techCard;
  final String description;
  final String composition;
  final double? sellingPrice;
  final String currencySym;

  @override
  Widget build(BuildContext context) {
    final hallDescription = description.trim();
    final hallComposition = composition.trim();

    final hasAny = hallDescription.isNotEmpty || hallComposition.isNotEmpty;
    if (!hasAny) {
      return Text(
        loc.t('dash'),
        style: const TextStyle(fontSize: 13, height: 1.4),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hallDescription.isNotEmpty) ...[
          Text(
            loc.t('description_for_hall'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            hallDescription,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
        ],
        if (hallComposition.isNotEmpty) ...[
          Text(
            loc.t('composition_for_hall'),
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            hallComposition,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// Таблица состава блюда (только чтение): как в ТТК.
/// Ингредиенты-ПФ (sourceTechCardId) кликабельны — открывают карточку ТТК ПФ в просмотре.
class _MenuDishTable extends StatelessWidget {
  const _MenuDishTable({
    required this.loc,
    required this.dishName,
    required this.techCard,
    required this.ingredients,
    required this.technology,
    required this.currencyCode,
    required this.currencySym,
    this.showCost = true,
    this.productStore,
  });

  final LocalizationService loc;
  final String dishName;
  final TechCard techCard;
  final List<TTIngredient> ingredients;
  final String technology;
  final String currencyCode;
  final String currencySym;
  final bool showCost;
  final ProductStoreSupabase? productStore;

  static const _cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);

  Widget _cell(BuildContext context, String text, {bool bold = false, String? techCardId}) {
    final child = Padding(
      padding: _cellPad,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : null),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
    if (techCardId != null && techCardId.isNotEmpty) {
      return TableCell(
        child: InkWell(
          onTap: () => context.push('/tech-cards/$techCardId?view=1'),
          child: child,
        ),
      );
    }
    return TableCell(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final totalOutput = ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    final totalCost = ingredients.fold<double>(0, (s, i) => s + i.cost);
    const colCount = 6;
    final effectiveColCount = showCost ? colCount : colCount - 1;

    List<Widget> headerCells() => [
      _cell(context, loc.t('ttk_product'), bold: true),
      _cell(context, loc.t('ttk_gross'), bold: true),
      _cell(context, loc.t('ttk_net'), bold: true),
      _cell(context, loc.t('ttk_cooking_method'), bold: true),
      _cell(context, loc.t('ttk_output'), bold: true),
      if (showCost) _cell(context, loc.t('ttk_cost'), bold: true),
    ];

    List<Widget> ingCells(TTIngredient ing) => [
      _cell(context, ing.sourceTechCardName ?? ing.productName, techCardId: ing.sourceTechCardId),
      _cell(context, ing.grossWeight > 0 ? ing.grossWeight.toStringAsFixed(0) : ''),
      _cell(context, ing.netWeight > 0 ? ing.netWeight.toStringAsFixed(0) : ''),
      _cell(context, ing.cookingProcessName ?? loc.t('dash')),
      _cell(context, ing.outputWeight > 0 ? ing.outputWeight.toStringAsFixed(0) : ''),
      if (showCost)
        _cell(
          context,
          ing.cost > 0
              ? NumberFormatUtils.formatSumWithSymbol(
                  ing.cost, currencyCode, currencySym)
              : '',
        ),
    ];

    List<Widget> totalCells() => [
      _cell(context, loc.t('ttk_total'), bold: true),
      _cell(context, ''),
      _cell(context, ''),
      _cell(context, ''),
      _cell(context, '${totalOutput.toStringAsFixed(0)} ${loc.t('gram')}', bold: true),
      if (showCost)
        _cell(
          context,
          NumberFormatUtils.formatSumWithSymbol(
              totalCost, currencyCode, currencySym),
          bold: true,
        ),
    ];

    final tableScroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(width: 0.5, color: Colors.grey),
        columnWidths: {
          0: const FixedColumnWidth(220),
          1: const FixedColumnWidth(80),
          2: const FixedColumnWidth(80),
          3: const FixedColumnWidth(140),
          4: const FixedColumnWidth(80),
          if (showCost) 5: const FixedColumnWidth(90),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)),
            children: headerCells(),
          ),
          if (ingredients.isEmpty)
            TableRow(
              children: List.generate(effectiveColCount, (_) => TableCell(child: Padding(padding: _cellPad, child: Text(loc.t('dash'), style: const TextStyle(fontSize: 12))))),
            )
          else
            ...ingredients.map((ing) => TableRow(children: ingCells(ing))),
          TableRow(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            children: totalCells(),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tableScroll,
        if (techCard.totalCalories > 0 || techCard.totalProtein > 0 || techCard.totalFat > 0 || techCard.totalCarbs > 0) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (ctx) {
              final totalCal = techCard.totalCalories;
              final totalProt = techCard.totalProtein;
              final totalFat = techCard.totalFat;
              final totalCarb = techCard.totalCarbs;
              final allergens = <String>[];
              final store = productStore ?? context.read<ProductStoreSupabase>();
              for (final ing in techCard.ingredients.where((i) => i.productId != null)) {
                final p = store.findProductForIngredient(ing.productId, ing.productName);
                if (p?.containsGluten == true && !allergens.contains('глютен')) allergens.add('глютен');
                if (p?.containsLactose == true && !allergens.contains('лактоза')) allergens.add('лактоза');
              }
              final allergenStr = allergens.isEmpty ? (loc.currentLanguageCode == 'ru' ? 'нет' : 'none') : allergens.join(', ');
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  loc.t('kbju_allergens_in_dish')
                      .replaceFirst('%s', totalCal.round().toString())
                      .replaceFirst('%s', totalProt.toStringAsFixed(1))
                      .replaceFirst('%s', totalFat.toStringAsFixed(1))
                      .replaceFirst('%s', totalCarb.toStringAsFixed(1))
                      .replaceFirst('%s', allergenStr),
                  style: const TextStyle(fontSize: 13),
                ),
              );
            },
          ),
        ],
        if (technology.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.t('ttk_technology'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  technology,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lazy-фото: грузится только когда попадает во viewport,
// пока грузится — показывает placeholder (иконку).
// ─────────────────────────────────────────────────────────────────────────────
class _LazyPhoto extends StatelessWidget {
  final String url;
  final Widget fallback;

  const _LazyPhoto({required this.url, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      // frameBuilder даёт плавное появление без мигания
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallback;
      },
      errorBuilder: (_, __, ___) => fallback,
      // cacheWidth ограничивает декодирование — не тянет полный размер в память
      cacheWidth: 96,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Полноэкранный просмотр фото блюда (из меню)
// ─────────────────────────────────────────────────────────────────────────────
class _MenuPhotoViewer extends StatefulWidget {
  final List<String> urls;
  const _MenuPhotoViewer({required this.urls});

  @override
  State<_MenuPhotoViewer> createState() => _MenuPhotoViewerState();
}

class _MenuPhotoViewerState extends State<_MenuPhotoViewer> {
  late final PageController _ctrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: total,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  widget.urls[i],
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image_not_supported, color: Colors.white, size: 64),
                ),
              ),
            ),
          ),
          // Закрыть
          Positioned(
            top: 16, right: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
          // Индикаторы (если фото > 1)
          if (total > 1)
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_current > 0)
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white, size: 36),
                      onPressed: () => _ctrl.previousPage(
                          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut),
                    ),
                  ...List.generate(total, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _current == i ? 12 : 8,
                    height: _current == i ? 12 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _current == i ? Colors.white : Colors.white38,
                    ),
                  )),
                  if (_current < total - 1)
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white, size: 36),
                      onPressed: () => _ctrl.nextPage(
                          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
