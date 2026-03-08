import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

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

  String _categoryLabel(String c, String lang) {
    final Map<String, Map<String, String>> categoryTranslations = {
      'sauce': {'ru': 'Соус', 'en': 'Sauce'},
      'vegetables': {'ru': 'Овощи', 'en': 'Vegetables'},
      'salad': {'ru': 'Салат', 'en': 'Salad'},
      'meat': {'ru': 'Мясо', 'en': 'Meat'},
      'seafood': {'ru': 'Рыба', 'en': 'Seafood'},
      'side': {'ru': 'Гарнир', 'en': 'Side dish'},
      'subside': {'ru': 'Подгарнир', 'en': 'Sub-side dish'},
      'bakery': {'ru': 'Выпечка', 'en': 'Bakery'},
      'dessert': {'ru': 'Десерт', 'en': 'Dessert'},
      'decor': {'ru': 'Декор', 'en': 'Decor'},
      'soup': {'ru': 'Суп', 'en': 'Soup'},
      'misc': {'ru': 'Разное', 'en': 'Misc'},
      'beverages': {'ru': 'Напитки', 'en': 'Beverages'},
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
        setState(() { _loading = false; _error = 'Нет заведения'; });
        return;
      }
      final productStore = context.read<ProductStoreSupabase>();
      final techCardService = context.read<TechCardServiceSupabase>();
      await productStore.loadProducts();
      await productStore.loadNomenclature(est.dataEstablishmentId);
      final emp = acc.currentEmployee;
      final allTcs = await techCardService.getTechCardsForEstablishment(est.dataEstablishmentId);
      // Банкет/кейтеринг: только блюда с категорией banquet или catering
      // Зал: все блюда (отображаем вкладки Бар/Кухня)
      List<TechCard> tcs;
      if (widget.department == 'banquet-catering') {
        tcs = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (tc.category == 'banquet' || tc.category == 'catering')).toList();
      } else if (widget.department == 'hall' || widget.department == 'dining_room') {
        tcs = allTcs.where((tc) => !tc.isSemiFinished).toList();
      } else if (widget.department == 'bar') {
        tcs = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (_barCategories.contains(tc.category) ||
                tc.sections.contains('bar') ||
                tc.sections.contains('all'))).toList();
      } else {
        final byDept = allTcs.where((tc) =>
            !tc.isSemiFinished &&
            (!_barCategories.contains(tc.category) || tc.sections.contains('all'))).toList();
        tcs = emp == null
            ? byDept
            : byDept.where((tc) => emp.canSeeTechCard(tc.sections)).toList();
      }
      if (!mounted) return;
      final currency = emp?.currency ?? acc.establishment?.defaultCurrency ?? 'RUB';
      // Пересчитываем стоимость ингредиентов по актуальным ценам номенклатуры
      final enriched = <TechCard>[];
      for (final tc in tcs) {
        if (!tc.isSemiFinished) {
          enriched.add(_enrichWithCosts(tc, productStore, est.dataEstablishmentId, currency));
        }
      }
      if (mounted) {
        final barOnly = enriched.where((tc) => _barCategories.contains(tc.category)).toList();
        final kitchenOnly = enriched.where((tc) => !_barCategories.contains(tc.category)).toList();
        setState(() {
          _dishes = enriched;
          _dishesBar = barOnly;
          _dishesKitchen = kitchenOnly;
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
            await svc.saveTechCard(updated);
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

  /// Полный вид ТТК (себестоимость, состав, технология): только собственник, шеф (кухня), барменеджер (бар).
  bool _canSeeFullTtkView(Employee? emp, TechCard tc) {
    if (emp == null) return false;
    if (emp.hasRole('owner')) return true;
    if (emp.hasRole('executive_chef') && !_isBarDish(tc)) return true;
    if (emp.hasRole('bar_manager') && _isBarDish(tc)) return true;
    return false;
  }

  bool _hasHallContent(TechCard tc) {
    final d = tc.descriptionForHall?.trim() ?? '';
    final c = tc.compositionForHall?.trim() ?? '';
    return d.isNotEmpty || c.isNotEmpty;
  }

  String _buildSubtitleText(LocalizationService loc, TechCard tc, String lang, double totalCost, String currencySym) {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final cat = _categoryLabel(tc.category, lang);
    if (_canSeeFullTtkView(emp, tc)) {
      return '${cat} • ${loc.t('cost_price')}: ${totalCost.toStringAsFixed(2)} $currencySym';
    }
    final sp = tc.sellingPrice;
    if (sp != null && sp > 0) {
      return '$cat • ${loc.t('selling_price') ?? 'Цена'}: ${sp.toStringAsFixed(2)} $currencySym';
    }
    return cat;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.read<AccountManagerSupabase>();
    final currency = accountManager.currentEmployee?.currency ?? accountManager.establishment?.defaultCurrency ?? 'RUB';
    final sym = accountManager.establishment?.currencySymbol ?? accountManager.currentEmployee?.currencySymbol ?? Establishment.currencySymbolFor(accountManager.establishment?.defaultCurrency ?? 'VND');

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('menu')),
        leading: appBarBackButton(context),
        bottom: _isHallMenu && !_loading && (_dishesBar.isNotEmpty || _dishesKitchen.isNotEmpty)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
                  child: Row(
                    children: [
                      Expanded(
                        child: _HallTabChip(
                          label: loc.t('dept_bar') ?? 'Бар',
                          selected: _hallTab == 'bar',
                          onTap: () => setState(() => _hallTab = 'bar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HallTabChip(
                          label: loc.t('dept_kitchen') ?? 'Кухня',
                          selected: _hallTab == 'kitchen',
                          onTap: () => setState(() => _hallTab = 'kitchen'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
        ],
      ),
      body: _buildBody(loc, sym),
    );
  }

  List<TechCard> get _displayDishes {
    if (_isHallMenu) {
      return _hallTab == 'bar' ? _dishesBar : _dishesKitchen;
    }
    return _dishes;
  }

  Widget _buildBody(LocalizationService loc, String currencySym) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('refresh'))),
            ],
          ),
        ),
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
                'Нет блюд в меню. Добавьте ТТК с типом «Блюдо» в разделе ТТК.',
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
          final totalCost = tc.totalCost;
          final lang = loc.currentLanguageCode;
          final photoUrls = tc.photoUrls ?? [];
          final photoUrl = photoUrls.isNotEmpty ? photoUrls.first : null;
          final fallbackIcon = Icon(
            tc.isSemiFinished ? Icons.inventory_2 : Icons.restaurant,
            color: Theme.of(context).colorScheme.primary,
          );
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
              title: InkWell(
                onTap: () {
                  final emp = context.read<AccountManagerSupabase>().currentEmployee;
                  final useHallView = !_canSeeFullTtkView(emp, tc);
                  context.push('/tech-cards/${tc.id}?view=1${useHallView ? '&hall=1' : ''}');
                },
                child: Text(
                  tc.getDisplayNameInLists(lang),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              subtitle: InkWell(
                onTap: () {
                  final emp = context.read<AccountManagerSupabase>().currentEmployee;
                  final useHallView = !_canSeeFullTtkView(emp, tc);
                  context.push('/tech-cards/${tc.id}?view=1${useHallView ? '&hall=1' : ''}');
                },
                child: Text(
                  _buildSubtitleText(loc, tc, lang, totalCost, currencySym),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: _canSeeFullTtkView(context.read<AccountManagerSupabase>().currentEmployee, tc)
                      ? _MenuDishTable(
                          loc: loc,
                          dishName: tc.dishName,
                          ingredients: tc.ingredients.where((i) => !i.isPlaceholder || i.hasData).toList(),
                          technology: tc.getLocalizedTechnology(lang),
                          currencySym: currencySym,
                          showCost: true,
                        )
                      : _HallDishContent(
                          loc: loc,
                          description: tc.descriptionForHall ?? '',
                          composition: tc.compositionForHall ?? '',
                          sellingPrice: tc.sellingPrice,
                          currencySym: currencySym,
                        ),
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

/// Блок описания, состава и продажной цены для зала (вместо полной ТТК).
class _HallDishContent extends StatelessWidget {
  const _HallDishContent({
    required this.loc,
    required this.description,
    required this.composition,
    this.sellingPrice,
    this.currencySym = '',
  });

  final LocalizationService loc;
  final String description;
  final String composition;
  final double? sellingPrice;
  final String currencySym;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (description.isNotEmpty) ...[
          Text(loc.t('description_for_hall') ?? 'Описание', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
        ],
        if (composition.isNotEmpty) ...[
          Text(loc.t('composition_for_hall') ?? 'Состав', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(composition, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
        ],
        if (sellingPrice != null && sellingPrice! > 0) ...[
          Text(loc.t('selling_price') ?? 'Цена', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${sellingPrice!.toStringAsFixed(2)} $currencySym', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
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
    required this.ingredients,
    required this.technology,
    required this.currencySym,
    this.showCost = true,
  });

  final LocalizationService loc;
  final String dishName;
  final List<TTIngredient> ingredients;
  final String technology;
  final String currencySym;
  final bool showCost;

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
      if (showCost) _cell(context, ing.cost > 0 ? '${ing.cost.toStringAsFixed(2)} $currencySym' : ''),
    ];

    List<Widget> totalCells() => [
      _cell(context, loc.t('ttk_total'), bold: true),
      _cell(context, ''),
      _cell(context, ''),
      _cell(context, ''),
      _cell(context, '${totalOutput.toStringAsFixed(0)} ${loc.t('gram')}', bold: true),
      if (showCost) _cell(context, '${totalCost.toStringAsFixed(2)} $currencySym', bold: true),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
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
                  Text(technology, style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
      ),
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
