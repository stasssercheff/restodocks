import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/services.dart';
import '../utils/product_name_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран просмотра и правки распознанных ТТК перед созданием (пакетный импорт из Excel).
class TechCardsImportReviewScreen extends StatefulWidget {
  const TechCardsImportReviewScreen({super.key, required this.cards, this.department = 'kitchen'});

  final List<TechCardRecognitionResult> cards;
  final String department;

  @override
  State<TechCardsImportReviewScreen> createState() => _TechCardsImportReviewScreenState();
}

class _TechCardsImportReviewScreenState extends State<TechCardsImportReviewScreen> {
  /// Цеха кухни (коды как в создании ТТК: preparation, confectionery)
  static const _kitchenSectionCodes = [
    'hot_kitchen',
    'cold_kitchen',
    'preparation',
    'confectionery',
    'grill',
    'pizza',
    'sushi',
    'bakery',
    'banquet_catering',
  ];

  static const _kitchenSectionLocKeys = {
    'hot_kitchen': 'section_hot_kitchen',
    'cold_kitchen': 'section_cold_kitchen',
    'preparation': 'section_prep',
    'confectionery': 'section_pastry',
    'grill': 'section_grill',
    'pizza': 'section_pizza',
    'sushi': 'section_sushi',
    'bakery': 'section_bakery',
    'banquet_catering': 'section_banquet_catering',
  };

  /// Цех для бара (только bar)
  static const _barSectionCodes = ['bar'];

  /// Кухня: без напитков. Рыба, мясо, птица, заготовка и т.д.
  static const _kitchenCategoryOptions = [
    'sauce', 'vegetables', 'zagotovka', 'salad', 'meat', 'seafood', 'poultry', 'side', 'subside',
    'bakery', 'dessert', 'decor', 'soup', 'misc', 'banquet', 'catering',
  ];

  /// Бар: только напитки и снеки.
  static const _barCategoryOptions = [
    'alcoholic_cocktails', 'non_alcoholic_drinks', 'hot_drinks', 'drinks_pure',
    'snacks', 'beverages',
  ];

  bool get _isBar => widget.department == 'bar' || widget.department == 'banquet-catering-bar';
  List<String> get _categoryOptions => _isBar ? _barCategoryOptions : _kitchenCategoryOptions;

  /// Коды цехов для выбора (кухня или бар)
  List<String> get _sectionCodes => _isBar ? _barSectionCodes : _kitchenSectionCodes;

  Map<String, String> _getSectionLabels(LocalizationService loc) {
    if (_isBar) {
      return {'bar': loc.t('bar') ?? 'Бар'};
    }
    return Map.fromEntries(
      _kitchenSectionCodes.map((c) => MapEntry(c, loc.t(_kitchenSectionLocKeys[c] ?? c) ?? c)),
    );
  }

  String _sectionsDisplayLabel(List<String> sections, LocalizationService loc) {
    if (sections.isEmpty) return loc.t('ttk_sections_hidden') ?? 'Скрыто';
    if (sections.contains('all')) return loc.t('ttk_sections_all') ?? 'Все цеха';
    if (sections.length == 1) {
      return _getSectionLabels(loc)[sections.first] ?? sections.first;
    }
    return (loc.t('ttk_sections_count') ?? '%s цеха').replaceAll('%s', '${sections.length}');
  }

  late List<_ReviewItem> _items;
  bool _saving = false;
  int _saveProgress = 0;
  int _saveTotal = 0;

  /// Ошибки парсинга (битые карточки) — берём из сервиса и очищаем
  List<TtkParseError>? _parseErrors;

  @override
  void initState() {
    super.initState();
    _parseErrors = AiServiceSupabase.lastParseTechCardErrors;
    if (_parseErrors != null) AiServiceSupabase.lastParseTechCardErrors = null;
    final defaultSections = _isBar ? const ['bar'] : const ['all'];
    _items = widget.cards.map((c) => _ReviewItem(
      result: c,
      category: _inferCategory(c.dishName ?? ''),
      sections: defaultSections,
      isSemiFinished: c.isSemiFinished ?? true,
    )).toList();
  }

  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (_isBar) {
      if (lower.contains('коктейл') || lower.contains('cocktail') || lower.contains('мохито') || lower.contains('маргарит')) return 'alcoholic_cocktails';
      if (lower.contains('лимонад') || lower.contains('сок') || lower.contains('кола') || lower.contains('тоник') || lower.contains('soda') || lower.contains('juice')) return 'non_alcoholic_drinks';
      if (lower.contains('кофе') || lower.contains('чай') || lower.contains('какао') || lower.contains('coffee') || lower.contains('tea') || lower.contains('cocoa')) return 'hot_drinks';
      if (lower.contains('виски') || lower.contains('ром') || lower.contains('водка') || lower.contains('вино') || lower.contains('пиво') || lower.contains('whiskey') || lower.contains('rum') || lower.contains('vodka') || lower.contains('wine') || lower.contains('beer')) return 'drinks_pure';
      if (lower.contains('орех') || lower.contains('чипс') || lower.contains('снек') || lower.contains('nuts') || lower.contains('chips') || lower.contains('snack')) return 'snacks';
    }
    if (lower.contains('соус') || lower.contains('sauce')) return 'sauce';
    if (lower.contains('овощ') || lower.contains('vegetable')) return 'vegetables';
    if (lower.contains('заготовк') || lower.contains('preparation') || lower.contains('подготовк')) return 'zagotovka';
    if (lower.contains('салат') || lower.contains('salad')) return 'salad';
    if (lower.contains('мяс') || lower.contains('meat') || lower.contains('говядин') || lower.contains('свинин') || lower.contains('баран')) return 'meat';
    if (lower.contains('рыб') || lower.contains('fish') || lower.contains('море') || lower.contains('seafood')) return 'seafood';
    if (lower.contains('птиц') || lower.contains('poultry') || lower.contains('куриц') || lower.contains('индейк') || lower.contains('утк') || lower.contains('цыплят')) return 'poultry';
    if (lower.contains('гарнир') || lower.contains('side')) return 'side';
    if (lower.contains('подгарнир') || lower.contains('subside')) return 'subside';
    if (lower.contains('выпеч') || lower.contains('bakery') || lower.contains('хлеб') || lower.contains('тест')) return 'bakery';
    if (lower.contains('десерт') || lower.contains('dessert') || lower.contains('крем') || lower.contains('торт')) return 'dessert';
    if (lower.contains('декор') || lower.contains('decor')) return 'decor';
    if (lower.contains('суп') || lower.contains('soup')) return 'soup';
    if (lower.contains('напит') || lower.contains('beverage') || lower.contains('сок') || lower.contains('компот')) return 'beverages';
    if (lower.contains('банкет') || lower.contains('banquet')) return 'banquet';
    if (lower.contains('кейтринг') || lower.contains('catering')) return 'catering';
    return 'misc';
  }

  /// Нормализация старых кодов (prep->preparation, pastry->confectionery)
  List<String> _normalizeSections(List<String> sections) {
    if (sections.isEmpty) return [];
    if (sections.contains('all')) return const ['all'];
    return sections.map((s) {
      if (s == 'prep') return 'preparation';
      if (s == 'pastry') return 'confectionery';
      return s;
    }).toList();
  }

  Future<void> _showSectionPicker(int index) async {
    final item = _items[index];
    final loc = context.read<LocalizationService>();
    final theme = Theme.of(context);
    final sectionLabels = _getSectionLabels(loc);
    var selected = List<String>.from(_normalizeSections(item.sections));

    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialog) {
            void toggle(String code) {
              setDialog(() {
                if (code == 'all') {
                  selected = selected.contains('all') ? [] : ['all'];
                } else {
                  selected.remove('all');
                  if (selected.contains(code)) {
                    selected.remove(code);
                  } else {
                    selected.add(code);
                  }
                }
              });
            }

            final isHidden = selected.isEmpty;
            final isAll = selected.contains('all');

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.store, color: theme.colorScheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Text(loc.t('ttk_section_select') ?? 'Выбор цеха',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        loc.t('ttk_section_hint') ?? 'ТТК будет видна только поварам выбранных цехов.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isHidden
                              ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
                              : theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isHidden
                                ? theme.colorScheme.error.withValues(alpha: 0.4)
                                : theme.colorScheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(children: [
                          Icon(Icons.visibility_off,
                              size: 18,
                              color: isHidden
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isHidden
                                  ? (loc.t('ttk_section_hidden') ?? 'Скрыто')
                                  : (loc.t('ttk_section_uncheck_hint') ?? 'Снимите все цеха чтобы скрыть'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isHidden
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      ..._sectionCodes.map((code) => _CheckItem(
                            label: sectionLabels[code] ?? code,
                            checked: selected.contains(code),
                            onTap: () => toggle(code),
                            theme: theme,
                          )),
                      const Divider(height: 20),
                      _CheckItem(
                        label: loc.t('ttk_section_all') ?? 'Все цеха',
                        checked: isAll,
                        onTap: () => toggle('all'),
                        theme: theme,
                        icon: Icons.done_all,
                        bold: true,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(loc.t('back') ?? 'Назад'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(selected),
                            child: Text(loc.t('save') ?? 'Сохранить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _items[index] = _ReviewItem(
        result: item.result,
        category: item.category,
        sections: result,
        isSemiFinished: item.isSemiFinished,
      ));
    }
  }

  String _categoryLabel(String c, String lang) {
    const ru = {
      'sauce': 'Соус', 'vegetables': 'Овощи', 'zagotovka': 'Заготовка', 'salad': 'Салат', 'meat': 'Мясо',
      'seafood': 'Рыба', 'poultry': 'Птица', 'side': 'Гарнир', 'subside': 'Подгарнир', 'bakery': 'Выпечка',
      'dessert': 'Десерт', 'decor': 'Декор', 'soup': 'Суп', 'misc': 'Разное',
      'beverages': 'Напитки', 'banquet': 'Банкет', 'catering': 'Кейтеринг',
      'alcoholic_cocktails': 'Алкогольные коктейли', 'non_alcoholic_drinks': 'Безалкогольные напитки',
      'hot_drinks': 'Горячие напитки', 'drinks_pure': 'Напитки в чистом виде', 'snacks': 'Снеки',
    };
    const en = {
      'sauce': 'Sauce', 'vegetables': 'Vegetables', 'zagotovka': 'Preparation', 'salad': 'Salad', 'meat': 'Meat',
      'seafood': 'Seafood', 'poultry': 'Poultry', 'side': 'Side dish', 'subside': 'Sub-side', 'bakery': 'Bakery',
      'dessert': 'Dessert', 'decor': 'Decor', 'soup': 'Soup', 'misc': 'Misc',
      'beverages': 'Beverages', 'banquet': 'Banquet', 'catering': 'Catering',
      'alcoholic_cocktails': 'Alcoholic cocktails', 'non_alcoholic_drinks': 'Non-alcoholic drinks',
      'hot_drinks': 'Hot drinks', 'drinks_pure': 'Drinks (neat)', 'snacks': 'Snacks',
    };
    return (lang == 'ru' ? ru : en)[c] ?? c;
  }

  static String _norm(String s) =>
      stripIikoPrefix(s).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _createAll() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    setState(() => _saving = true);
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final productStore = context.read<ProductStoreSupabase>();
      final products = productStore.getNomenclatureProducts(est.dataEstablishmentId);
      final allTc = await svc.getTechCardsForEstablishment(est.dataEstablishmentId);
      final techCardsPf = allTc
          .where((tc) => tc.isSemiFinished)
          .map((tc) => (id: tc.id, name: tc.dishName))
          .toList();
      var productsForMapping = products.map((p) => (id: p.id, name: p.name)).toList();
      final createdByName = <String, String>{};
      final defCur = est.defaultCurrency;

      // Собираем уникальные названия продуктов (не ПФ) и цены из КК/документа
      final productNamesToCreate = <String>{};
      final priceFromDoc = <String, double>{};
      for (final item in _items) {
        for (final ing in item.result.ingredients) {
          if (ing.productName.trim().isEmpty) continue;
          if (ing.ingredientType == 'semi_finished') continue;
          final norm = _norm(ing.productName);
          if (norm.length < 2) continue;
          final inProducts = productsForMapping.any((p) => _norm(p.name) == norm);
          final inPf = techCardsPf.any((t) => _norm(t.name) == norm);
          if (!inProducts && !inPf) productNamesToCreate.add(ing.productName.trim());
          if (ing.pricePerKg != null && ing.pricePerKg! > 0 && !priceFromDoc.containsKey(norm)) {
            priceFromDoc[norm] = ing.pricePerKg!;
          }
        }
      }

      _saveTotal = productNamesToCreate.length + _items.length + 1;
      _saveProgress = 0;
      if (mounted) setState(() {});

      // Создаём отсутствующие продукты в каталоге, подтягиваем КБЖУ, добавляем в номенклатуру
      for (final rawName in productNamesToCreate) {
        if (mounted) setState(() => _saveProgress++);
        final normalizedName = stripIikoPrefix(rawName).trim();
        if (normalizedName.isEmpty) continue;
        final norm = _norm(normalizedName);
        if (productsForMapping.any((p) => _norm(p.name) == norm)) continue;

        double? calories;
        double? protein;
        double? fat;
        double? carbs;
        bool? containsGluten;
        bool? containsLactose;
        try {
          final nutrition = await NutritionApiService.fetchNutrition(normalizedName);
          if (nutrition != null && nutrition.hasData) {
            calories = nutrition.calories;
            protein = nutrition.protein;
            fat = nutrition.fat;
            carbs = nutrition.carbs;
            containsGluten = nutrition.containsGluten;
            containsLactose = nutrition.containsLactose;
          }
        } catch (_) {}

        final product = Product(
          id: const Uuid().v4(),
          name: normalizedName,
          category: 'manual',
          names: null,
          calories: calories,
          protein: protein,
          fat: fat,
          carbs: carbs,
          containsGluten: containsGluten,
          containsLactose: containsLactose,
          unit: 'g',
          basePrice: null,
          currency: defCur,
        );

        try {
          final savedProduct = await productStore.addProduct(product);
          final docPrice = priceFromDoc[norm];
          await productStore.addToNomenclature(
            est.dataEstablishmentId,
            savedProduct.id,
            price: docPrice,
            currency: defCur,
          );
          productsForMapping = [...productsForMapping, (id: savedProduct.id, name: savedProduct.name)];
        } catch (e) {
          if (e.toString().contains('duplicate') ||
              e.toString().contains('already exists') ||
              e.toString().contains('unique')) {
            final existing = productStore.allProducts
                .where((p) => _norm(p.name) == norm)
                .toList();
            if (existing.isNotEmpty) {
              productsForMapping = [...productsForMapping, (id: existing.first.id, name: existing.first.name)];
            }
          }
        }
      }

      final sorted = List<_ReviewItem>.from(_items)
        ..sort((a, b) => (a.isSemiFinished == b.isSemiFinished) ? 0 : (a.isSemiFinished ? -1 : 1));

      int created = 0;
      final failed = <({String name, String error})>[];
      final failedItems = <_ReviewItem>[];
      for (final item in sorted) {
        try {
          await svc.createTechCardFromRecognitionResult(
            establishmentId: est.dataEstablishmentId,
            createdBy: emp.id,
            createdByName: emp.fullName,
            result: item.result,
            category: item.category,
            sections: _normalizeSections(item.sections),
            isSemiFinishedOverride: item.isSemiFinished,
            languageCode: lang,
            productsForMapping: productsForMapping,
            techCardsPfForMapping: techCardsPf,
            createdTechCardsByName: createdByName,
            productStore: productStore,
          );
          created++;
        } catch (e) {
          final name = (item.result.dishName ?? '').trim().isEmpty ? (loc.t('tech_cards_import_unnamed') ?? 'Без названия') : (item.result.dishName ?? '').trim();
          failed.add((name: name, error: e.toString()));
          failedItems.add(item);
        }
        if (mounted) setState(() => _saveProgress = productNamesToCreate.length + created);
      }
      if (mounted) {
        setState(() => _saving = false);
        if (failed.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('tech_cards_import_created').replaceAll('%s', '$created'))),
          );
          context.go('/tech-cards/${widget.department}?refresh=1');
        } else {
          _items = failedItems;
          final msg = created > 0
              ? '${loc.t('tech_cards_import_created').replaceAll('%s', '$created')}. Не удалось ${failed.length}: ${failed.map((f) => f.name).join(', ')}. Исправьте и повторите.'
              : 'Не удалось сохранить: ${failed.map((f) => f.name).join(', ')}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('tech_cards_import_review_title')),
      ),
      body: Column(
        children: [
          if (_parseErrors != null && _parseErrors!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${loc.t('tech_cards_import_review_loaded') ?? 'Загружено'} ${widget.cards.length} блюд. '
                      '${_parseErrors!.length} ${_parseErrors!.length == 1 ? 'блюдо' : 'блюд'} '
                      '${loc.t('tech_cards_import_review_requires_manual') ?? 'требует ручной правки'}: '
                      '${_parseErrors!.map((e) => e.dishName ?? '—').where((s) => s != '—').take(3).join(', ')}${_parseErrors!.length > 3 ? '...' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              loc.t('tech_cards_import_review_hint'),
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final name = item.result.dishName?.trim().isEmpty != false
                    ? loc.t('tech_cards_import_unnamed')
                    : (item.result.dishName ?? '').trim();
                final count = item.result.ingredients.length;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(name, style: theme.textTheme.titleMedium),
                            ),
                            TextButton.icon(
                              onPressed: _saving ? null : () {
                                context.push('/tech-cards/new', extra: {
                                  'result': item.result,
                                  'category': item.category,
                                  'sections': _normalizeSections(item.sections),
                                  'isSemiFinished': item.isSemiFinished,
                                });
                              },
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(loc.t('open')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<String>(
                              value: _categoryOptions.contains(item.category) ? item.category : 'misc',
                              isDense: true,
                              items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c, lang)))).toList(),
                              onChanged: (v) => setState(() => _items[index] = _ReviewItem(result: item.result, category: v ?? item.category, sections: item.sections, isSemiFinished: item.isSemiFinished)),
                            ),
                            InkWell(
                              onTap: _saving ? null : () => _showSectionPicker(index),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.store, size: 18, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(_sectionsDisplayLabel(_normalizeSections(item.sections), loc)),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, size: 20),
                                  ],
                                ),
                              ),
                            ),
                            DropdownButton<bool>(
                              value: item.isSemiFinished,
                              isDense: true,
                              items: [
                                DropdownMenuItem(value: true, child: Text(loc.t('ttk_semi_finished'))),
                                DropdownMenuItem(value: false, child: Text(loc.t('ttk_dish'))),
                              ],
                              onChanged: (v) => setState(() => _items[index] = _ReviewItem(result: item.result, category: item.category, sections: item.sections, isSemiFinished: v ?? item.isSemiFinished)),
                            ),
                            Text(
                              loc.t('tech_cards_ingredients_count').replaceAll('%s', '$count'),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saving && _saveTotal > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: _saveTotal > 0 ? (_saveProgress / _saveTotal).clamp(0.0, 1.0) : null,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_saveProgress / $_saveTotal',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving || _items.isEmpty ? null : _createAll,
                      child: _saving
                          ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(loc.t('tech_cards_import_create_all')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewItem {
  final TechCardRecognitionResult result;
  final String category;
  final List<String> sections;
  final bool isSemiFinished;

  _ReviewItem({
    required this.result,
    required this.category,
    this.sections = const ['all'],
    this.isSemiFinished = true,
  });
}

class _CheckItem extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;
  final ThemeData theme;
  final IconData icon;
  final bool bold;

  const _CheckItem({
    required this.label,
    required this.checked,
    required this.onTap,
    required this.theme,
    this.icon = Icons.kitchen,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(4),
                color: checked ? theme.colorScheme.primary : Colors.transparent,
                border: Border.all(
                  color: checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: 2,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 16,
                color: checked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: checked ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
