import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/ai_service.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран просмотра и правки распознанных ТТК перед созданием (пакетный импорт из Excel).
class TechCardsImportReviewScreen extends StatefulWidget {
  const TechCardsImportReviewScreen({super.key, required this.cards});

  final List<TechCardRecognitionResult> cards;

  @override
  State<TechCardsImportReviewScreen> createState() => _TechCardsImportReviewScreenState();
}

class _TechCardsImportReviewScreenState extends State<TechCardsImportReviewScreen> {
  /// Цеха для выбора при импорте ТТК (код → ключ локализации)
  static const _sectionOptions = [
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

  static const _categoryOptions = [
    'misc', 'vegetables', 'fruits', 'meat', 'seafood', 'dairy', 'grains',
    'bakery', 'pantry', 'spices', 'beverages', 'eggs', 'legumes', 'nuts',
  ];

  late List<_ReviewItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.cards.map((c) => _ReviewItem(
      result: c,
      category: _inferCategory(c.dishName ?? ''),
      sections: const ['all'],
      isSemiFinished: c.isSemiFinished ?? true,
    )).toList();
  }

  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (lower.contains('овощ') || lower.contains('vegetable') || lower.contains('салат')) return 'vegetables';
    if (lower.contains('фрукт') || lower.contains('fruit') || lower.contains('ягод')) return 'fruits';
    if (lower.contains('мяс') || lower.contains('meat') || lower.contains('куриц') || lower.contains('говядин')) return 'meat';
    if (lower.contains('рыб') || lower.contains('fish') || lower.contains('море')) return 'seafood';
    if (lower.contains('молок') || lower.contains('dairy') || lower.contains('сыр') || lower.contains('cream')) return 'dairy';
    if (lower.contains('круп') || lower.contains('grain') || lower.contains('рис') || lower.contains('макарон')) return 'grains';
    if (lower.contains('выпеч') || lower.contains('bakery') || lower.contains('хлеб') || lower.contains('тест')) return 'bakery';
    if (lower.contains('напит') || lower.contains('beverage') || lower.contains('сок') || lower.contains('компот')) return 'beverages';
    if (lower.contains('специ') || lower.contains('spice')) return 'spices';
    if (lower.contains('яйц') || lower.contains('egg')) return 'eggs';
    if (lower.contains('боб') || lower.contains('legume')) return 'legumes';
    if (lower.contains('орех') || lower.contains('nut')) return 'nuts';
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
    if (lang == 'ru') {
      const map = {
        'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
        'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
        'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
        'nuts': 'Орехи', 'misc': 'Разное',
      };
      return map[c] ?? c;
    }
    return c;
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
        context.go('/tech-cards?refresh=1');
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
