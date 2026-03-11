import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../services/services.dart';
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
  /// Цеха кухни
  static const _kitchenSectionOptions = [
    ('all', 'ttk_sections_all'),
    ('hidden', 'ttk_sections_hidden'),
    ('hot_kitchen', 'section_hot_kitchen'),
    ('cold_kitchen', 'section_cold_kitchen'),
    ('prep', 'section_prep'),
    ('pastry', 'section_pastry'),
    ('grill', 'section_grill'),
    ('sushi', 'section_sushi'),
    ('bakery', 'section_bakery'),
    ('banquet_catering', 'section_banquet_catering'),
  ];

  /// Цеха/видимость для бара
  static const _barSectionOptions = [
    ('all', 'ttk_sections_all'),
    ('hidden', 'ttk_sections_hidden'),
    ('bar', 'bar'),
  ];

  /// Категории кухни: Суп, Салат, Мясо, Десерт и т.д.
  static const _kitchenCategoryOptions = [
    'sauce', 'vegetables', 'zagotovka', 'salad', 'meat', 'seafood', 'side', 'subside',
    'bakery', 'dessert', 'decor', 'soup', 'misc', 'beverages', 'banquet', 'catering',
  ];

  /// Категории бара: коктейли, напитки, снеки и т.д.
  static const _barCategoryOptions = [
    'alcoholic_cocktails', 'non_alcoholic_drinks', 'hot_drinks', 'drinks_pure',
    'snacks', 'zagotovka', 'sauce', 'vegetables', 'salad', 'bakery', 'dessert', 'decor', 'misc', 'beverages',
  ];

  bool get _isBar => widget.department == 'bar' || widget.department == 'banquet-catering-bar';
  List<(String, String)> get _sectionOptions => _isBar ? _barSectionOptions : _kitchenSectionOptions;
  List<String> get _categoryOptions => _isBar ? _barCategoryOptions : _kitchenCategoryOptions;

  late List<_ReviewItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
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
    if (lower.contains('мяс') || lower.contains('meat') || lower.contains('куриц') || lower.contains('говядин')) return 'meat';
    if (lower.contains('рыб') || lower.contains('fish') || lower.contains('море') || lower.contains('seafood')) return 'seafood';
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

  String _sectionsToDropdownValue(List<String> sections) {
    if (sections.contains('all')) return 'all';
    if (sections.isEmpty) return 'hidden';
    return sections.first;
  }

  List<String> _dropdownValueToSections(String value) {
    if (value == 'all') return const ['all'];
    if (value == 'hidden') return const [];
    return [value];
  }

  String _categoryLabel(String c, String lang) {
    const ru = {
      'sauce': 'Соус', 'vegetables': 'Овощи', 'zagotovka': 'Заготовка', 'salad': 'Салат', 'meat': 'Мясо',
      'seafood': 'Рыба', 'side': 'Гарнир', 'subside': 'Подгарнир', 'bakery': 'Выпечка',
      'dessert': 'Десерт', 'decor': 'Декор', 'soup': 'Суп', 'misc': 'Разное',
      'beverages': 'Напитки', 'banquet': 'Банкет', 'catering': 'Кейтеринг',
      'alcoholic_cocktails': 'Алкогольные коктейли', 'non_alcoholic_drinks': 'Безалкогольные напитки',
      'hot_drinks': 'Горячие напитки', 'drinks_pure': 'Напитки в чистом виде', 'snacks': 'Снеки',
    };
    const en = {
      'sauce': 'Sauce', 'vegetables': 'Vegetables', 'zagotovka': 'Preparation', 'salad': 'Salad', 'meat': 'Meat',
      'seafood': 'Seafood', 'side': 'Side dish', 'subside': 'Sub-side', 'bakery': 'Bakery',
      'dessert': 'Dessert', 'decor': 'Decor', 'soup': 'Soup', 'misc': 'Misc',
      'beverages': 'Beverages', 'banquet': 'Banquet', 'catering': 'Catering',
      'alcoholic_cocktails': 'Alcoholic cocktails', 'non_alcoholic_drinks': 'Non-alcoholic drinks',
      'hot_drinks': 'Hot drinks', 'drinks_pure': 'Drinks (neat)', 'snacks': 'Snacks',
    };
    return (lang == 'ru' ? ru : en)[c] ?? c;
  }

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
      final productsForMapping = products.map((p) => (id: p.id, name: p.name)).toList();
      final createdByName = <String, String>{};

      final sorted = List<_ReviewItem>.from(_items)
        ..sort((a, b) => (a.isSemiFinished == b.isSemiFinished) ? 0 : (a.isSemiFinished ? -1 : 1));

      int created = 0;
      for (final item in sorted) {
        await svc.createTechCardFromRecognitionResult(
          establishmentId: est.dataEstablishmentId,
          createdBy: emp.id,
          result: item.result,
          category: item.category,
          sections: item.sections,
          isSemiFinishedOverride: item.isSemiFinished,
          languageCode: lang,
          productsForMapping: productsForMapping,
          techCardsPfForMapping: techCardsPf,
          createdTechCardsByName: createdByName,
        );
        created++;
      }
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('tech_cards_import_created').replaceAll('%s', '$created'))),
        );
        context.go('/tech-cards/${widget.department}?refresh=1');
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
                                context.push('/tech-cards/new', extra: item.result);
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
                            DropdownButton<String>(
                              value: _sectionsToDropdownValue(item.sections),
                              isDense: true,
                              items: _sectionOptions
                                  .map((e) => DropdownMenuItem(value: e.$1, child: Text(loc.t(e.$2) ?? e.$1)))
                                  .toList(),
                              onChanged: (v) => setState(() => _items[index] = _ReviewItem(
                                result: item.result,
                                category: item.category,
                                sections: _dropdownValueToSections(v ?? 'all'),
                                isSemiFinished: item.isSemiFinished,
                              )),
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
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _items.isEmpty ? null : _createAll,
                  child: _saving ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(loc.t('tech_cards_import_create_all')),
                ),
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
