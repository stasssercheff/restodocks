import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/ai_service_supabase.dart';
import '../services/services.dart';
import '../utils/dev_log.dart';
import '../utils/product_name_utils.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/subscription_required_dialog.dart';

enum _ImportDuplicateAction { createDuplicate, editExisting, deleteExisting }

/// Экран просмотра и правки распознанных ТТК перед созданием (пакетный импорт из Excel).
class TechCardsImportReviewScreen extends StatefulWidget {
  const TechCardsImportReviewScreen(
      {super.key,
      required this.cards,
      this.headerSignature,
      this.sourceRows,
      this.department = 'kitchen'});

  final List<TechCardRecognitionResult> cards;
  final String? headerSignature;
  final List<List<String>>? sourceRows;
  final String department;

  @override
  State<TechCardsImportReviewScreen> createState() =>
      _TechCardsImportReviewScreenState();
}

class _TechCardsImportReviewScreenState
    extends State<TechCardsImportReviewScreen> {
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
    'catering',
  ];

  /// Бар: только напитки и снеки.
  static const _barCategoryOptions = [
    'alcoholic_cocktails',
    'non_alcoholic_drinks',
    'hot_drinks',
    'drinks_pure',
    'snacks',
    'zakuska',
    'beverages',
  ];

  bool get _isBar =>
      widget.department == 'bar' || widget.department == 'banquet-catering-bar';
  List<String> get _categoryOptions =>
      _isBar ? _barCategoryOptions : _kitchenCategoryOptions;

  /// Коды цехов для выбора (кухня или бар)
  List<String> get _sectionCodes =>
      _isBar ? _barSectionCodes : _kitchenSectionCodes;

  Map<String, String> _getSectionLabels(LocalizationService loc) {
    if (_isBar) {
      return {'bar': loc.t('bar') ?? 'Бар'};
    }
    return Map.fromEntries(
      _kitchenSectionCodes
          .map((c) => MapEntry(c, loc.t(_kitchenSectionLocKeys[c] ?? c) ?? c)),
    );
  }

  String _sectionsDisplayLabel(List<String> sections, LocalizationService loc) {
    if (sections.isEmpty) return loc.t('ttk_sections_hidden') ?? 'Скрыто';
    if (sections.contains('all'))
      return loc.t('ttk_sections_all') ?? 'Все цеха';
    if (sections.length == 1) {
      return _getSectionLabels(loc)[sections.first] ?? sections.first;
    }
    return (loc.t('ttk_sections_count') ?? '%s цеха')
        .replaceAll('%s', '${sections.length}');
  }

  late List<_ReviewItem> _items;
  bool _saving = false;
  int _saveProgress = 0;
  int _saveTotal = 0;

  /// Поиск по названию ТТК до сохранения (фильтр отображения).
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Баннер с подсказкой по импорту: можно свернуть или скрыть (восстановление — иконка в AppBar).
  bool _importReviewHelpDismissed = false;
  bool _importReviewHelpExpanded = false;

  /// Ошибки парсинга (битые карточки) — берём из сервиса и очищаем
  List<TtkParseError>? _parseErrors;

  /// Установить перед названием «ПФ» для всех ПФ при сохранении (если ещё нет).
  bool _ensurePfPrefix = true;

  /// Версия массового выбора типа (Все ПФ / Все блюда). Нужна, чтобы массовая команда могла перебить ручные правки в карточке.
  int _typeRevision = 0;

  /// Массовый режим типа на экране проверки импорта. Если null — пользователь вручную правит карточки.
  bool?
      _bulkIsSemiFinished; // true=все ПФ, false=все блюда, null=нет массового режима

  /// Индексы в _items, проходящие фильтр поиска по названию.
  List<int> get _filteredIndices {
    if (_searchQuery.isEmpty) return List.generate(_items.length, (i) => i);
    final q = _searchQuery.toLowerCase();
    return List.generate(_items.length, (i) => i)
        .where(
            (i) => (_items[i].result.dishName ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text.trim()) {
        setState(() => _searchQuery = _searchController.text.trim());
      }
    });
    _parseErrors = AiServiceSupabase.lastParseTechCardErrors;
    if (_parseErrors != null) AiServiceSupabase.lastParseTechCardErrors = null;
    final defaultSections = _isBar ? const ['bar'] : const ['all'];
    final rawItems = widget.cards
        .map((c) => _ReviewItem(
              result: c,
              originalDishName: c.dishName,
              category: _inferCategory(c.dishName ?? ''),
              sections: defaultSections,
              isSemiFinished: c.isSemiFinished ?? true,
            ))
        .toList();
    _items = _groupDuplicatesForReview(rawItems);
    // Не включать «ПФ» по умолчанию, если у всех ПФ уже есть префикс в названии.
    final pfItems = _items.where((i) => i.isSemiFinished).toList();
    if (pfItems.isNotEmpty) {
      final hasPfPrefix =
          RegExp(r'^пф\s|^п/ф\s|^п\.ф\.\s', caseSensitive: false);
      final allAlreadyHave = pfItems
          .every((i) => hasPfPrefix.hasMatch((i.result.dishName ?? '').trim()));
      if (allAlreadyHave) _ensurePfPrefix = false;
    }
    // Напоминание при каждом открытии экрана проверки импорта (не только при первом формате).
    if (widget.cards.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _showFirstTimeImportNotice());
    }
  }

  void _showFirstTimeImportNotice() {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('tech_cards_import_first_time_title') ??
            'Первый импорт формата'),
        content: Text(loc.t('tech_cards_import_first_time_message') ??
            'Проверьте правильность внесённых данных, при необходимости исправьте — это поможет обучить систему для следующих загрузок.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('ok') ?? 'OK'),
          ),
        ],
      ),
    );
  }

  /// Текст баннера об ошибках: с перечислением карточек, если есть названия.
  String _formatParseErrorsBanner(LocalizationService loc) {
    if (_parseErrors == null || _parseErrors!.isEmpty) return '';
    final names = _parseErrors!
        .map((e) => e.dishName?.trim())
        .where((n) => n != null && n.isNotEmpty)
        .toSet()
        .toList();
    if (names.isNotEmpty) {
      final template = loc
              .t('tech_cards_import_parse_errors_banner_with_names') ??
          'Обнаружены ошибки распознавания в карточках: %s. Проверьте их ниже.';
      return template.replaceFirst('%s', names.join(', '));
    }
    return loc.t('tech_cards_import_parse_errors_banner') ??
        'Обнаружены ошибки распознавания. Проверьте карточки ниже.';
  }

  String _inferCategory(String dishName) {
    final lower = dishName.toLowerCase();
    if (_isBar) {
      if (lower.contains('коктейл') ||
          lower.contains('cocktail') ||
          lower.contains('мохито') ||
          lower.contains('маргарит')) return 'alcoholic_cocktails';
      if (lower.contains('лимонад') ||
          lower.contains('сок') ||
          lower.contains('кола') ||
          lower.contains('тоник') ||
          lower.contains('soda') ||
          lower.contains('juice')) return 'non_alcoholic_drinks';
      if (lower.contains('кофе') ||
          lower.contains('чай') ||
          lower.contains('какао') ||
          lower.contains('coffee') ||
          lower.contains('tea') ||
          lower.contains('cocoa')) return 'hot_drinks';
      if (lower.contains('виски') ||
          lower.contains('ром') ||
          lower.contains('водка') ||
          lower.contains('вино') ||
          lower.contains('пиво') ||
          lower.contains('whiskey') ||
          lower.contains('rum') ||
          lower.contains('vodka') ||
          lower.contains('wine') ||
          lower.contains('beer')) return 'drinks_pure';
      if (lower.contains('орех') ||
          lower.contains('чипс') ||
          lower.contains('снек') ||
          lower.contains('nuts') ||
          lower.contains('chips') ||
          lower.contains('snack')) return 'snacks';
      if (lower.contains('закуск') ||
          lower.contains('appetizer') ||
          lower.contains('antipasti')) return 'zakuska';
    }
    if (lower.contains('соус') || lower.contains('sauce')) return 'sauce';
    if (lower.contains('овощ') || lower.contains('vegetable'))
      return 'vegetables';
    if (lower.contains('заготовк') ||
        lower.contains('preparation') ||
        lower.contains('подготовк')) return 'zagotovka';
    if (lower.contains('салат') || lower.contains('salad')) return 'salad';
    if (lower.contains('закуск') ||
        lower.contains('appetizer') ||
        lower.contains('antipasti')) return 'zakuska';
    if (lower.contains('мяс') ||
        lower.contains('meat') ||
        lower.contains('говядин') ||
        lower.contains('свинин') ||
        lower.contains('баран')) return 'meat';
    if (lower.contains('рыб') ||
        lower.contains('fish') ||
        lower.contains('море') ||
        lower.contains('seafood')) return 'seafood';
    if (lower.contains('птиц') ||
        lower.contains('poultry') ||
        lower.contains('куриц') ||
        lower.contains('индейк') ||
        lower.contains('утк') ||
        lower.contains('цыплят')) return 'poultry';
    if (lower.contains('гарнир') || lower.contains('side')) return 'side';
    if (lower.contains('подгарнир') || lower.contains('subside'))
      return 'subside';
    if (lower.contains('выпеч') ||
        lower.contains('bakery') ||
        lower.contains('хлеб') ||
        lower.contains('тест')) return 'bakery';
    if (lower.contains('десерт') ||
        lower.contains('dessert') ||
        lower.contains('крем') ||
        lower.contains('торт')) return 'dessert';
    if (lower.contains('декор') || lower.contains('decor')) return 'decor';
    if (lower.contains('суп') || lower.contains('soup')) return 'soup';
    if (lower.contains('напит') ||
        lower.contains('beverage') ||
        lower.contains('сок') ||
        lower.contains('компот')) return 'beverages';
    if (lower.contains('банкет') || lower.contains('banquet')) return 'banquet';
    if (lower.contains('кейтринг') || lower.contains('catering'))
      return 'catering';
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.store,
                            color: theme.colorScheme.primary, size: 22),
                        const SizedBox(width: 10),
                        Text(loc.t('ttk_section_select') ?? 'Выбор цеха',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        loc.t('ttk_section_hint') ??
                            'ТТК будет видна только поварам выбранных цехов.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isHidden
                              ? theme.colorScheme.errorContainer
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isHidden
                                ? theme.colorScheme.error.withValues(alpha: 0.4)
                                : theme.colorScheme.outline
                                    .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(children: [
                          Icon(Icons.visibility_off,
                              size: 18,
                              color: isHidden
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isHidden
                                  ? (loc.t('ttk_section_hidden') ?? 'Скрыто')
                                  : (loc.t('ttk_section_uncheck_hint') ??
                                      'Снимите все цеха чтобы скрыть'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isHidden
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
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
            originalDishName: item.originalDishName,
            category: item.category,
            sections: result,
            isSemiFinished: item.isSemiFinished,
            alreadySaved: item.alreadySaved,
          ));
    }
  }

  String _categoryLabel(String c, String lang) {
    const ru = {
      'sauce': 'Соус',
      'vegetables': 'Овощи',
      'zagotovka': 'Заготовка',
      'salad': 'Салат',
      'zakuska': 'Закуска',
      'meat': 'Мясо',
      'seafood': 'Рыба',
      'poultry': 'Птица',
      'side': 'Гарнир',
      'subside': 'Подгарнир',
      'bakery': 'Выпечка',
      'dessert': 'Десерт',
      'decor': 'Декор',
      'soup': 'Суп',
      'misc': 'Разное',
      'beverages': 'Напитки',
      'banquet': 'Банкет',
      'catering': 'Кейтеринг',
      'alcoholic_cocktails': 'Алкогольные коктейли',
      'non_alcoholic_drinks': 'Безалкогольные напитки',
      'hot_drinks': 'Горячие напитки',
      'drinks_pure': 'Напитки в чистом виде',
      'snacks': 'Снеки',
    };
    const en = {
      'sauce': 'Sauce',
      'vegetables': 'Vegetables',
      'zagotovka': 'Preparation',
      'salad': 'Salad',
      'zakuska': 'Appetizer',
      'meat': 'Meat',
      'seafood': 'Seafood',
      'poultry': 'Poultry',
      'side': 'Side dish',
      'subside': 'Sub-side',
      'bakery': 'Bakery',
      'dessert': 'Dessert',
      'decor': 'Decor',
      'soup': 'Soup',
      'misc': 'Misc',
      'beverages': 'Beverages',
      'banquet': 'Banquet',
      'catering': 'Catering',
      'alcoholic_cocktails': 'Alcoholic cocktails',
      'non_alcoholic_drinks': 'Non-alcoholic drinks',
      'hot_drinks': 'Hot drinks',
      'drinks_pure': 'Drinks (neat)',
      'snacks': 'Snacks',
    };
    return (lang == 'ru' ? ru : en)[c] ?? c;
  }

  /// Сумма выходов ингредиентов карточки (г).
  static double _ingredientsOutputSum(TechCardRecognitionResult result) {
    return result.ingredients.fold<double>(
      0,
      (s, i) => s + (i.outputGrams ?? i.netGrams ?? i.grossGrams ?? 0),
    );
  }

  /// Карточка может участвовать в подстройке отхода: есть ингредиенты с суммой > 0 и (нет выхода / выход не совпадает с суммой).
  /// Работает при любом формате импорта и любом количестве карточек.
  bool _canBenefitFromAdjustWaste(_ReviewItem item) {
    final sum = _ingredientsOutputSum(item.result);
    if (sum <= 0) return false;
    final yield = item.result.yieldGrams;
    if (yield == null || yield <= 0)
      return true; // формат без поля «Выход» — подстраиваем под сумму
    return (sum - yield).abs() > 1; // выход задан, но не совпадает
  }

  /// Показывать подсказку «подстроить % отхода», если в карточке задан выход и он не совпадает с суммой выходов ингредиентов.
  bool _shouldShowAdjustWasteHint(_ReviewItem item) {
    final yield = item.result.yieldGrams;
    if (yield == null || yield <= 0) return false;
    final sum = _ingredientsOutputSum(item.result);
    return sum > 0 && (sum - yield).abs() > 1;
  }

  String _formatAdjustWasteHint(_ReviewItem item, LocalizationService loc) {
    final yield = item.result.yieldGrams ?? 0;
    final sum = item.result.ingredients.fold<double>(
      0,
      (s, i) => s + (i.outputGrams ?? i.netGrams ?? i.grossGrams ?? 0),
    );
    final template = loc.t('tech_cards_import_adjust_waste_hint') ??
        'Выход в карточке %s г, сумма ингредиентов %s г. В редакторе можно подстроить % отхода под целевой выход.';
    return template
        .replaceFirst('%s', yield.toStringAsFixed(0))
        .replaceFirst('%s', sum.toStringAsFixed(0));
  }

  /// Подстроить % отхода под целевой выход для всех карточек (в любом формате, любое количество).
  /// Если в карточке нет поля «Выход» — целевым выходом считается сумма ингредиентов, затем в карточку записывается yieldGrams.
  void _adjustWasteForAllCards() {
    var changed = false;
    final newItems = <_ReviewItem>[];
    for (final item in _items) {
      if (!_canBenefitFromAdjustWaste(item)) {
        newItems.add(item);
        continue;
      }
      final sum = _ingredientsOutputSum(item.result);
      final target =
          item.result.yieldGrams != null && item.result.yieldGrams! > 0
              ? item.result.yieldGrams!
              : sum;
      if (target <= 0) {
        newItems.add(item);
        continue;
      }
      final adjusted = item.result.adjustWasteToMatchOutput(target);
      if (adjusted != null) {
        final hadNoYield =
            item.result.yieldGrams == null || item.result.yieldGrams! <= 0;
        final resultWithYield =
            hadNoYield ? adjusted.copyWith(yieldGrams: target) : adjusted;
        newItems.add(_ReviewItem(
          result: resultWithYield,
          originalDishName: item.originalDishName,
          category: item.category,
          sections: item.sections,
          isSemiFinished: item.isSemiFinished,
          alreadySaved: item.alreadySaved,
        ));
        changed = true;
      } else {
        newItems.add(item);
      }
    }
    if (changed) setState(() => _items = newItems);
  }

  static String _norm(String s) =>
      stripIikoPrefix(s).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Группирует дубликаты рядом во вкладке "На проверку":
  /// одинаковые названия (с учётом суффикса -1/-2) идут подряд, чтобы было удобно сравнивать.
  static List<_ReviewItem> _groupDuplicatesForReview(List<_ReviewItem> items) {
    if (items.length < 2) return items;
    String groupKey(_ReviewItem item) {
      final raw = (item.result.dishName ?? '').trim();
      if (raw.isEmpty) return '';
      final noSuffix = _stripDuplicateSuffix(raw);
      return item.isSemiFinished
          ? normalizeForPfMatching(noSuffix)
          : _norm(noSuffix);
    }

    final byKey = <String, List<_ReviewItem>>{};
    final order = <String>[];
    for (final item in items) {
      final key = groupKey(item);
      if (!byKey.containsKey(key)) {
        byKey[key] = <_ReviewItem>[];
        order.add(key);
      }
      byKey[key]!.add(item);
    }
    final grouped = <_ReviewItem>[];
    for (final key in order) {
      grouped.addAll(byKey[key] ?? const []);
    }
    return grouped;
  }

  /// Убирает суффикс вида `-1`, `-2`... если он стоит в конце названия.
  static String _stripDuplicateSuffix(String s) {
    final v = s.trim();
    return v.replaceFirst(RegExp(r'-\d+$'), '');
  }

  /// Топологическая сортировка: сначала листовые ТТК (без ПФ), потом с ПФ. При цикле — fallback.
  static List<_ReviewItem> _topologicalSortOrFallback(
    List<_ReviewItem> items,
    List<({String id, String name})> techCardsPf,
  ) {
    final availablePf = <String>{
      for (final t in techCardsPf) ...[
        _norm(t.name),
        if (normalizeForPfMatching(t.name).isNotEmpty)
          normalizeForPfMatching(t.name),
      ],
    };
    final itemToDeps = <int, Set<String>>{};
    for (var i = 0; i < items.length; i++) {
      final deps = <String>{};
      for (final ing in items[i].result.ingredients) {
        if (ing.ingredientType != 'semi_finished') continue;
        final n = normalizeForPfMatching(ing.productName);
        if (n.isNotEmpty) deps.add(n);
      }
      itemToDeps[i] = deps;
    }
    final itemToName = <int, String>{};
    for (var i = 0; i < items.length; i++) {
      final name = (items[i].result.dishName ?? '').trim();
      if (name.isNotEmpty) {
        itemToName[i] = normalizeForPfMatching(name);
        if (itemToName[i]!.isEmpty) itemToName[i] = _norm(name);
      }
    }
    final result = <_ReviewItem>[];
    var remaining = List<int>.generate(items.length, (i) => i);
    var stuck = false;
    while (remaining.isNotEmpty && !stuck) {
      final ready = remaining.where((i) {
        final deps = itemToDeps[i] ?? {};
        return deps.every((d) => availablePf.contains(d));
      }).toList();
      if (ready.isEmpty) {
        stuck = true;
        break;
      }
      for (final i in ready) {
        result.add(items[i]);
        final n = itemToName[i];
        if (n != null && n.isNotEmpty) availablePf.add(n);
      }
      remaining = remaining.where((i) => !ready.contains(i)).toList();
    }
    if (stuck || remaining.isNotEmpty) {
      return List<_ReviewItem>.from(items)
        ..sort((a, b) => (a.isSemiFinished == b.isSemiFinished)
            ? 0
            : (a.isSemiFinished ? -1 : 1));
    }
    return result;
  }

  /// Нечёткое совпадение: продукт в каталоге содержит название ингредиента как префикс.
  static bool _fuzzyMatch(String ingredientNorm, String catalogNorm) {
    if (ingredientNorm.isEmpty || catalogNorm.length < ingredientNorm.length)
      return false;
    if (catalogNorm == ingredientNorm) return true;
    return ingredientNorm.length >= 10 &&
        catalogNorm.startsWith(ingredientNorm) &&
        (ingredientNorm.length == catalogNorm.length ||
            catalogNorm[ingredientNorm.length] == ' ');
  }

  Future<void> _createAll() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) {
      devLog(
          '[ttk_save] _createAll: est=${est != null} emp=${emp != null} — return (no save)');
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(est == null
              ? (loc.t('ttk_import_no_establishment') ?? 'Выберите заведение')
              : (loc.t('ttk_import_no_employee') ??
                  'Войдите как сотрудник для сохранения ТТК')),
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final trialOnly = acc.isTrialOnlyWithoutPaid;

    if (!acc.hasProSubscription) {
      if (mounted) await showSubscriptionRequiredDialog(context);
      return;
    }

    if (trialOnly) {
      final used = await acc.fetchTrialTtkImportCardsUsed(est.id);
      final toCreate = _items.where((i) => !i.alreadySaved).length;
      if (used + toCreate > 10) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.t('trial_ttk_import_cap')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final productStore = context.read<ProductStoreSupabase>();
      // ВАЖНО: для маппинга ингредиентов по названию нужен кэш products.
      // loadNomenclature загружает только IDs/цены, но не сами продукты.
      await productStore.loadProducts();
      await productStore.loadNomenclature(est.dataEstablishmentId);
      final products =
          productStore.getNomenclatureProducts(est.dataEstablishmentId);
      final allTc =
          await svc.getTechCardsForEstablishment(est.dataEstablishmentId);
      final techCardsPf = allTc
          .where((tc) => tc.isSemiFinished)
          .map((tc) => (id: tc.id, name: tc.dishName))
          .toList();

      // Индексы для детекта «такой ТТК уже есть» (по названию).
      final existingDishByKey = <String, TechCard>{};
      final existingPfByKey = <String, TechCard>{};
      final existingDishKeys = <String>{};
      final existingPfKeys = <String>{};
      for (final tc in allTc) {
        final name = (tc.dishName).trim();
        if (name.isEmpty) continue;
        if (tc.isSemiFinished) {
          final k = normalizeForPfMatching(name);
          if (k.isEmpty) continue;
          existingPfByKey.putIfAbsent(k, () => tc);
          existingPfKeys.add(k);
        } else {
          final k = _norm(name);
          if (k.isEmpty) continue;
          existingDishByKey.putIfAbsent(k, () => tc);
          existingDishKeys.add(k);
        }
      }
      var productsForMapping = <({String id, String name})>[];
      for (final p in products) {
        productsForMapping.add((id: p.id, name: p.name));
        for (final n in p.names?.values ?? []) {
          final ns = n?.toString();
          if (ns != null && ns.trim().isNotEmpty && ns != p.name) {
            productsForMapping.add((id: p.id, name: ns));
          }
        }
      }
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
          final inProducts = productsForMapping.any((p) {
            final pNorm = _norm(p.name);
            return pNorm == norm || _fuzzyMatch(norm, pNorm);
          });
          final inPf = techCardsPf.any((t) =>
              _norm(t.name) == norm || normalizeForPfMatching(t.name) == norm);
          if (!inProducts && !inPf)
            productNamesToCreate.add(ing.productName.trim());
          if (ing.pricePerKg != null &&
              ing.pricePerKg! > 0 &&
              !priceFromDoc.containsKey(norm)) {
            priceFromDoc[norm] = ing.pricePerKg!;
          }
        }
      }

      final cardsToCreate = _items.where((i) => !i.alreadySaved).length;
      _saveTotal = cardsToCreate;
      _saveProgress = 0;
      if (mounted) setState(() {});

      // Создаём отсутствующие продукты в каталоге, подтягиваем КБЖУ, добавляем в номенклатуру
      for (final rawName in productNamesToCreate) {
        final normalizedName = stripIikoPrefix(rawName).trim();
        if (normalizedName.isEmpty) continue;
        final norm = _norm(normalizedName);
        if (productsForMapping.any((p) => _norm(p.name) == norm)) continue;

        // Не вызываем Nutrition API при массовом импорте — сохраняет 3–4 минуты при 20+ продуктах.
        // КБЖУ можно подтянуть потом из номенклатуры.
        final product = Product(
          id: const Uuid().v4(),
          name: normalizedName,
          category: 'manual',
          names: null,
          calories: null,
          protein: null,
          fat: null,
          carbs: null,
          containsGluten: null,
          containsLactose: null,
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
          productsForMapping = [
            ...productsForMapping,
            (id: savedProduct.id, name: savedProduct.name)
          ];
        } catch (e) {
          if (e.toString().contains('duplicate') ||
              e.toString().contains('already exists') ||
              e.toString().contains('unique')) {
            final existing = productStore.allProducts
                .where((p) => _norm(p.name) == norm)
                .toList();
            if (existing.isNotEmpty) {
              final existingProduct = existing.first;
              final docPrice = priceFromDoc[norm];
              // В duplicate-ветке продукт уже есть в общем каталоге.
              // Гарантируем привязку к номенклатуре текущего заведения.
              try {
                await productStore.addToNomenclature(
                  est.dataEstablishmentId,
                  existingProduct.id,
                  price: docPrice,
                  currency: defCur,
                );
              } catch (_) {
                // Ничего: запись может уже существовать, это безопасно.
              }
              productsForMapping = [
                ...productsForMapping,
                (id: existingProduct.id, name: existingProduct.name)
              ];
            }
          }
        }
      }

      final sorted = _topologicalSortOrFallback(_items, techCardsPf);

      int created = 0;
      final failed = <({String name, String error})>[];
      final failedItems = <_ReviewItem>[];
      var abortAfterDuplicateAction = false;
      for (final item in sorted) {
        if (item.alreadySaved)
          continue; // уже сохранена в систему через «Сохранить» в редакторе
        try {
          var resultToSave = item.result;
          if (_ensurePfPrefix && item.isSemiFinished) {
            final raw = (item.result.dishName ?? '').trim();
            if (raw.isNotEmpty) {
              resultToSave =
                  item.result.copyWith(dishName: ensurePfPrefix(raw));
            }
          }
          final proposedName = (resultToSave.dishName ?? '').trim();

          Future<TechCard> createOne(TechCardRecognitionResult r) async {
            return svc.createTechCardFromRecognitionResult(
              establishmentId: est.dataEstablishmentId,
              createdBy: emp.id,
              createdByName: emp.fullName,
              result: r,
              category: item.category,
              sections: _normalizeSections(item.sections),
              isSemiFinishedOverride: item.isSemiFinished,
              languageCode: lang,
              productsForMapping: productsForMapping,
              techCardsPfForMapping: techCardsPf,
              createdTechCardsByName: createdByName,
              productStore: productStore,
            );
          }

          final duplicateKey = item.isSemiFinished
              ? normalizeForPfMatching(proposedName)
              : _norm(proposedName);
          final existingTc = item.isSemiFinished
              ? existingPfByKey[duplicateKey]
              : existingDishByKey[duplicateKey];

          if (existingTc != null && existingTc.dishName.trim().isNotEmpty) {
            final action = await showDialog<_ImportDuplicateAction>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.t('ttk_duplicate_exists_in_system')),
                content: Text('"${existingTc.dishName.trim()}"'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: Text(loc.t('cancel') ?? 'Отмена'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx)
                        .pop(_ImportDuplicateAction.createDuplicate),
                    child: Text(loc.t('ttk_create_duplicate')),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx)
                        .pop(_ImportDuplicateAction.editExisting),
                    child: Text(loc.t('ttk_edit_existing')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx)
                        .pop(_ImportDuplicateAction.deleteExisting),
                    child: Text(
                      loc.t('delete'),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );

            if (action == null) {
              // Пользователь отменил действие — не создаём/не правим.
              continue;
            }

            if (action == _ImportDuplicateAction.createDuplicate) {
              final base = _stripDuplicateSuffix(proposedName);
              int n = 1;
              while (true) {
                final candidate = '$base-$n';
                final k = item.isSemiFinished
                    ? normalizeForPfMatching(candidate)
                    : _norm(candidate);
                final exists = item.isSemiFinished
                    ? existingPfKeys.contains(k)
                    : existingDishKeys.contains(k);
                if (!exists) {
                  var dup = resultToSave.copyWith(dishName: candidate);
                  if (_ensurePfPrefix && item.isSemiFinished) {
                    dup = dup.copyWith(dishName: ensurePfPrefix(candidate));
                  }

                  final createdTc = await createOne(dup);
                  final createdNameNorm = createdTc.dishName.trim();
                  if (createdTc.isSemiFinished) {
                    final k2 = normalizeForPfMatching(createdNameNorm);
                    if (k2.isNotEmpty) {
                      existingPfByKey[k2] = createdTc;
                      existingPfKeys.add(k2);
                    }
                  } else {
                    final k2 = _norm(createdNameNorm);
                    if (k2.isNotEmpty) {
                      existingDishByKey[k2] = createdTc;
                      existingDishKeys.add(k2);
                    }
                  }
                  created++;
                  break;
                }
                n++;
              }
            } else if (action == _ImportDuplicateAction.editExisting) {
              if (mounted) setState(() => _saving = false);
              await context.push('/tech-cards/${existingTc.id}');
              abortAfterDuplicateAction = true;
              break;
            } else if (action == _ImportDuplicateAction.deleteExisting) {
              if (mounted) setState(() => _saving = false);
              await svc.deleteTechCard(existingTc.id);
              if (mounted) {
                context.go('/tech-cards/${widget.department}?refresh=1',
                    extra: {'back': true});
              }
              abortAfterDuplicateAction = true;
              break;
            }
          } else {
            final createdTc = await createOne(resultToSave);
            final createdNameNorm = createdTc.dishName.trim();
            if (createdTc.isSemiFinished) {
              final k2 = normalizeForPfMatching(createdNameNorm);
              if (k2.isNotEmpty) {
                existingPfByKey[k2] = createdTc;
                existingPfKeys.add(k2);
              }
            } else {
              final k2 = _norm(createdNameNorm);
              if (k2.isNotEmpty) {
                existingDishByKey[k2] = createdTc;
                existingDishKeys.add(k2);
              }
            }
            created++;
          }
        } catch (e) {
          final name = (item.result.dishName ?? '').trim().isEmpty
              ? (loc.t('tech_cards_import_unnamed') ?? 'Без названия')
              : (item.result.dishName ?? '').trim();
          failed.add((name: name, error: e.toString()));
          failedItems.add(item);
          devLog('[ttk_import] Ошибка сохранения "$name": $e');
        }
        if (mounted) setState(() => _saveProgress = created);

        if (abortAfterDuplicateAction) break;
      }
      if (abortAfterDuplicateAction) return;

      if (created > 0 && trialOnly) {
        try {
          await acc.trialIncrementUsageOrThrow(
            establishmentId: est.id,
            kind: 'ttk_import_cards',
            delta: created,
          );
        } catch (e) {
          if (!mounted) return;
          final es = e.toString();
          if (es.contains('TRIAL_TTK_IMPORT_CAP')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc.t('trial_ttk_import_cap')),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          } else {
            rethrow;
          }
        }
      }

      // Обучение: обратный маппинг по скорректированным данным. Таймаут 10 с — при плохой сети не блокируем.
      final sig =
          widget.headerSignature ?? AiServiceSupabase.lastParseHeaderSignature;
      final sourceRows = widget.sourceRows ?? AiServiceSupabase.lastParsedRows;
      debugPrint(
          '[tt_parse] save: sig=${sig?.isEmpty ?? true ? "null/empty" : "ok"} sourceRows=${sourceRows?.length ?? 0}');
      if (sig != null && sig.isNotEmpty) {
        try {
          if (sourceRows != null && sourceRows.isNotEmpty) {
            final cardsForLearning = sorted
                .where((item) {
                  final corr = (item.result.dishName ?? '').trim();
                  final hasIng = item.result.ingredients.any((i) =>
                      (i.productName ?? '').trim().isNotEmpty &&
                      (i.grossGrams ?? 0) > 0);
                  final hasTech =
                      (item.result.technologyText ?? '').trim().length >= 20;
                  return corr.isNotEmpty || hasIng || hasTech;
                })
                .map((item) => (
                      dishName: (item.result.dishName ?? '').trim(),
                      originalDishName: item.originalDishName?.trim(),
                      ingredients: item.result.ingredients
                          .where((i) =>
                              (i.productName ?? '').trim().isNotEmpty &&
                              (i.grossGrams ?? 0) > 0)
                          .map((i) => (
                                productName: (i.productName ?? '').trim(),
                                grossWeight: i.grossGrams ?? 0,
                                netWeight: i.netGrams ?? i.grossGrams ?? 0,
                              ))
                          .toList(),
                      technologyText: item.result.technologyText?.trim(),
                    ))
                .where((c) =>
                    c.dishName.isNotEmpty ||
                    c.ingredients.isNotEmpty ||
                    (c.technologyText != null &&
                        c.technologyText!.length >= 20))
                .toList();
            if (cardsForLearning.isNotEmpty) {
              await AiServiceSupabase.learnColumnMappingFromCorrections(
                Supabase.instance.client,
                sourceRows,
                sig,
                cardsForLearning,
              ).timeout(const Duration(seconds: 10), onTimeout: () {
                AiServiceSupabase.lastLearningError = 'Таймаут (сеть)';
              });
            }
          }
          for (final item in sorted) {
            final orig = item.originalDishName?.trim() ?? '';
            final corr = (item.result.dishName ?? '').trim();
            if (orig.isNotEmpty && corr.isNotEmpty && orig != corr) {
              await AiServiceSupabase.saveLearningCorrection(
                headerSignature: sig,
                field: 'dish_name',
                originalValue: orig,
                correctedValue: corr,
                establishmentId: est.dataEstablishmentId,
              ).timeout(const Duration(seconds: 6), onTimeout: () {});
            }
          }
        } catch (_) {}
      }
      devLog('[ttk_save] done: created=$created failed=${failed.length}');
      if (created > 0) {
        // Сигнал для открытых экранов редактирования/таблиц ТТК,
        // чтобы они пересвязали вложенные ПФ без повторного открытия.
        if (mounted)
          context.read<TechCardsReconcileNotifier>().markTechCardsUpdated();
      }
      if (mounted) {
        setState(() => _saving = false);
        if (failed.isEmpty) {
          var msg =
              loc.t('tech_cards_import_created').replaceAll('%s', '$created');
          if (AiServiceSupabase.lastLearningSuccess != null) {
            msg += ' ${AiServiceSupabase.lastLearningSuccess!}';
          }
          if (AiServiceSupabase.lastLearningError != null) {
            msg +=
                ' ${loc.t('ttk_learn_error_hint') ?? '(Обучение не сохранилось)'}';
            final err = AiServiceSupabase.lastLearningError!;
            if (err.length <= 120) {
              msg += ' $err';
            } else {
              msg += ' ${err.substring(0, 117)}...';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: AiServiceSupabase.lastLearningError != null
                  ? const Duration(seconds: 8)
                  : (AiServiceSupabase.lastLearningSuccess != null
                      ? const Duration(seconds: 6)
                      : const Duration(seconds: 4)),
            ),
          );
          context.go('/tech-cards/${widget.department}?refresh=1',
              extra: {'back': true});
        } else {
          _items = failedItems;
          final firstErr = failed.isNotEmpty ? failed.first.error : '';
          final reason = firstErr.contains('RLS') ||
                  firstErr.contains('доступ') ||
                  firstErr.contains('права')
              ? ' (проверьте права/сотрудника)'
              : (firstErr.length > 80
                  ? ': ${firstErr.substring(0, 77)}...'
                  : (firstErr.isNotEmpty ? ': $firstErr' : ''));
          final msg = created > 0
              ? '${loc.t('tech_cards_import_created').replaceAll('%s', '$created')}. Не удалось ${failed.length}: ${failed.map((f) => f.name).join(', ')}. Исправьте и повторите.'
              : 'Не удалось сохранить: ${failed.map((f) => f.name).join(', ')}$reason';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 8)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  Future<void> _showEditDishNameDialog(int realIndex) async {
    final loc = context.read<LocalizationService>();
    final item = _items[realIndex];
    final controller = TextEditingController(text: item.result.dishName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('dish_name') ?? 'Название'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: loc.t('tech_cards_import_unnamed'),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (v) =>
                Navigator.of(ctx).pop<String>(v.trim().isEmpty ? null : v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop<String>(),
              child: Text(loc.t('cancel') ?? 'Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                Navigator.of(ctx).pop<String>(v.isEmpty ? null : v);
              },
              child: Text(loc.t('save') ?? 'Сохранить'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (!mounted || newName == null) return;
    setState(() {
      _items[realIndex] = _ReviewItem(
        result: item.result.copyWith(dishName: newName),
        originalDishName: item.originalDishName,
        category: item.category,
        sections: item.sections,
        isSemiFinished: item.isSemiFinished,
        alreadySaved: item.alreadySaved,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(
            '${loc.t('tech_cards_import_review_title')} (${_items.length})'),
        actions: [
          if (_importReviewHelpDismissed)
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: loc.t('tech_cards_import_hint_restore') ??
                  'Подсказка по импорту',
              onPressed: () => setState(() {
                _importReviewHelpDismissed = false;
                _importReviewHelpExpanded = true;
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          // Поиск по названию ТТК — сразу под шапкой, до сохранения
          if (_items.length > 1) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: loc.t('tech_cards_import_search_hint') ??
                      'Поиск по названию ТТК',
                  hintText: loc.t('tech_cards_import_search_hint') ??
                      'Введите часть названия...',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  (loc.t('tech_cards_import_search_count') ??
                          'Показано: %s из %s')
                      .replaceFirst('%s', '${_filteredIndices.length}')
                      .replaceFirst('%s', '${_items.length}'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
          if (!_importReviewHelpDismissed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.info_outline,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _importReviewHelpExpanded
                              ? (loc.t('tech_cards_import_review_hint') ?? '')
                              : (loc.t('tech_cards_import_review_check_banner') ??
                                  ''),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                        tooltip: _importReviewHelpExpanded
                            ? loc.t('ui_collapse')
                            : loc.t('ui_expand'),
                        icon: Icon(
                          _importReviewHelpExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 22,
                        ),
                        onPressed: () => setState(() =>
                            _importReviewHelpExpanded =
                                !_importReviewHelpExpanded),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                        tooltip: loc.t('close') ?? 'Закрыть',
                        icon: const Icon(Icons.close, size: 22),
                        onPressed: () => setState(
                            () => _importReviewHelpDismissed = true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_items.any((i) => i.isSemiFinished))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _ensurePfPrefix,
                          onChanged: (v) =>
                              setState(() => _ensurePfPrefix = v ?? true),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _ensurePfPrefix = !_ensurePfPrefix),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            loc.t('ttk_import_ensure_pf_prefix') ??
                                'Установить перед названием «ПФ»\n(если ещё нет)',
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _bulkIsSemiFinished == true,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _typeRevision++;
                                      _bulkIsSemiFinished = true;
                                      _items = _items
                                          .map((item) => _ReviewItem(
                                                result: item.result.copyWith(
                                                    isSemiFinished: true),
                                                originalDishName:
                                                    item.originalDishName,
                                                category: item.category,
                                                sections: item.sections,
                                                isSemiFinished: true,
                                                alreadySaved: item.alreadySaved,
                                              ))
                                          .toList();
                                    } else {
                                      _bulkIsSemiFinished =
                                          null; // сброс — дальше ручные правки
                                    }
                                  }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _saving
                            ? null
                            : () => setState(() {
                                  _typeRevision++;
                                  _bulkIsSemiFinished = true;
                                  _items = _items
                                      .map((item) => _ReviewItem(
                                            result: item.result
                                                .copyWith(isSemiFinished: true),
                                            originalDishName:
                                                item.originalDishName,
                                            category: item.category,
                                            sections: item.sections,
                                            isSemiFinished: true,
                                            alreadySaved: item.alreadySaved,
                                          ))
                                      .toList();
                                }),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(loc.t('ttk_import_all_pf') ?? 'Все ПФ'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _bulkIsSemiFinished == false,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() {
                                    if (v == true) {
                                      _typeRevision++;
                                      _bulkIsSemiFinished = false;
                                      _items = _items
                                          .map((item) => _ReviewItem(
                                                result: item.result.copyWith(
                                                    isSemiFinished: false),
                                                originalDishName:
                                                    item.originalDishName,
                                                category: item.category,
                                                sections: item.sections,
                                                isSemiFinished: false,
                                                alreadySaved: item.alreadySaved,
                                              ))
                                          .toList();
                                    } else {
                                      _bulkIsSemiFinished = null;
                                    }
                                  }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _saving
                            ? null
                            : () => setState(() {
                                  _typeRevision++;
                                  _bulkIsSemiFinished = false;
                                  _items = _items
                                      .map((item) => _ReviewItem(
                                            result: item.result.copyWith(
                                                isSemiFinished: false),
                                            originalDishName:
                                                item.originalDishName,
                                            category: item.category,
                                            sections: item.sections,
                                            isSemiFinished: false,
                                            alreadySaved: item.alreadySaved,
                                          ))
                                      .toList();
                                }),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                              loc.t('ttk_import_all_dishes') ?? 'Все блюда'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_parseErrors != null && _parseErrors!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 20, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatParseErrorsBanner(loc),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: ListView.builder(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _filteredIndices.length,
              itemBuilder: (context, index) {
                final realIndex = _filteredIndices[index];
                final item = _items[realIndex];
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _saving
                                    ? null
                                    : () => _showEditDishNameDialog(realIndex),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: theme.textTheme.titleMedium,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.85),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      final sig = widget.headerSignature ??
                                          AiServiceSupabase
                                              .lastParseHeaderSignature;
                                      final rows = widget.sourceRows ??
                                          AiServiceSupabase.lastParsedRows;
                                      final raw = await context.push<dynamic>(
                                        '/tech-cards/new',
                                        extra: {
                                          'result': _items[realIndex].result,
                                          'category':
                                              _items[realIndex].category,
                                          'sections': _normalizeSections(
                                              _items[realIndex].sections),
                                          'isSemiFinished':
                                              _items[realIndex].isSemiFinished,
                                          'typeRevision': _typeRevision,
                                          if (sig != null && sig.isNotEmpty)
                                            'headerSignature': sig,
                                          if (rows != null && rows.isNotEmpty)
                                            'sourceRows': rows,
                                        },
                                      );
                                      TechCardRecognitionResult? result;
                                      bool savedToSystem = false;
                                      if (raw is Map) {
                                        result = raw['result']
                                            as TechCardRecognitionResult?;
                                        savedToSystem =
                                            raw['savedToSystem'] == true;
                                      } else if (raw
                                          is TechCardRecognitionResult) {
                                        result = raw;
                                      }
                                      if (result != null && mounted) {
                                        final ai = context.read<AiService>();
                                        final est = context
                                            .read<AccountManagerSupabase>()
                                            .establishment;
                                        // При «Назад» (savedToSystem == false): сохраняем обучение по правке, затем переразбор — у всех карточек применяется маппинг
                                        if (!savedToSystem &&
                                            rows != null &&
                                            rows.isNotEmpty &&
                                            sig != null &&
                                            sig.isNotEmpty &&
                                            est?.dataEstablishmentId != null) {
                                          final orig = _items[realIndex]
                                                  .originalDishName
                                                  ?.trim() ??
                                              '';
                                          final corr =
                                              (result.dishName ?? '').trim();
                                          if (orig.isNotEmpty &&
                                              corr.isNotEmpty &&
                                              orig != corr &&
                                              est != null &&
                                              est.dataEstablishmentId != null) {
                                            await AiServiceSupabase
                                                .saveLearningCorrection(
                                              headerSignature: sig,
                                              field: 'dish_name',
                                              originalValue: orig,
                                              correctedValue: corr,
                                              establishmentId:
                                                  est.dataEstablishmentId!,
                                            );
                                          }
                                        }
                                        if (ai is AiServiceSupabase &&
                                            rows != null &&
                                            rows.isNotEmpty &&
                                            sig != null &&
                                            sig.isNotEmpty &&
                                            est?.dataEstablishmentId != null) {
                                          final reparsed = await ai
                                              .reparseRowsWithStoredLearning(
                                            rows,
                                            sig,
                                            est!.dataEstablishmentId,
                                          );
                                          if (mounted &&
                                              reparsed.isNotEmpty &&
                                              reparsed.length ==
                                                  _items.length) {
                                            setState(() {
                                              _items = reparsed
                                                  .asMap()
                                                  .entries
                                                  .map((e) {
                                                final idx = e.key;
                                                final r = e.value;
                                                final preservedType =
                                                    _items[idx].isSemiFinished;
                                                if (idx == realIndex) {
                                                  final newType =
                                                      result!.isSemiFinished ??
                                                          preservedType;
                                                  if (_bulkIsSemiFinished !=
                                                          null &&
                                                      newType !=
                                                          _bulkIsSemiFinished)
                                                    _bulkIsSemiFinished = null;
                                                  return _ReviewItem(
                                                    result: result!.copyWith(
                                                        isSemiFinished:
                                                            newType),
                                                    originalDishName:
                                                        _items[realIndex]
                                                            .originalDishName,
                                                    category: _items[realIndex]
                                                        .category,
                                                    sections: _items[realIndex]
                                                        .sections,
                                                    isSemiFinished: newType,
                                                    alreadySaved: savedToSystem,
                                                  );
                                                }
                                                return _ReviewItem(
                                                  result: r.copyWith(
                                                      isSemiFinished:
                                                          preservedType),
                                                  originalDishName: r.dishName,
                                                  category: _inferCategory(
                                                      r.dishName ?? ''),
                                                  sections:
                                                      _items[idx].sections,
                                                  isSemiFinished: preservedType,
                                                  alreadySaved:
                                                      _items[idx].alreadySaved,
                                                );
                                              }).toList();
                                            });
                                            return;
                                          }
                                        }
                                        if (result != null) {
                                          final r = result;
                                          setState(() {
                                            final newType = r.isSemiFinished ??
                                                _items[realIndex]
                                                    .isSemiFinished;
                                            if (_bulkIsSemiFinished != null &&
                                                newType != _bulkIsSemiFinished)
                                              _bulkIsSemiFinished = null;
                                            _items[realIndex] = _ReviewItem(
                                              result: r.copyWith(
                                                  isSemiFinished: newType),
                                              originalDishName:
                                                  _items[realIndex]
                                                      .originalDishName,
                                              category:
                                                  _items[realIndex].category,
                                              sections:
                                                  _items[realIndex].sections,
                                              isSemiFinished: newType,
                                              alreadySaved: savedToSystem,
                                            );
                                          });
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(loc.t('open')),
                            ),
                            if (item.alreadySaved)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: Text(
                                      loc.t('tech_cards_import_already_saved') ??
                                          'Уже сохранена',
                                      style: const TextStyle(fontSize: 12)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 0),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Подсказка подстроить % отхода, если выход из карточки не совпадает с суммой ингредиентов
                        if (_shouldShowAdjustWasteHint(item)) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _formatAdjustWasteHint(item, loc),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<String>(
                              value: _categoryOptions.contains(item.category)
                                  ? item.category
                                  : 'misc',
                              isDense: true,
                              items: _categoryOptions
                                  .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(_categoryLabel(c, lang))))
                                  .toList(),
                              onChanged: (v) => setState(() =>
                                  _items[realIndex] = _ReviewItem(
                                      result: item.result,
                                      originalDishName: item.originalDishName,
                                      category: v ?? item.category,
                                      sections: item.sections,
                                      isSemiFinished: item.isSemiFinished)),
                            ),
                            InkWell(
                              onTap: _saving
                                  ? null
                                  : () => _showSectionPicker(realIndex),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.store,
                                        size: 18,
                                        color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(_sectionsDisplayLabel(
                                        _normalizeSections(item.sections),
                                        loc)),
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
                                DropdownMenuItem(
                                    value: true,
                                    child: Text(loc.t('ttk_semi_finished'))),
                                DropdownMenuItem(
                                    value: false,
                                    child: Text(loc.t('ttk_dish'))),
                              ],
                              onChanged: (v) => setState(() {
                                final isPf = v ?? item.isSemiFinished;
                                if (_bulkIsSemiFinished != null &&
                                    isPf != _bulkIsSemiFinished)
                                  _bulkIsSemiFinished = null;
                                _items[realIndex] = _ReviewItem(
                                  result: item.result
                                      .copyWith(isSemiFinished: isPf),
                                  originalDishName: item.originalDishName,
                                  category: item.category,
                                  sections: item.sections,
                                  isSemiFinished: isPf,
                                  alreadySaved: item.alreadySaved,
                                );
                              }),
                            ),
                            Text(
                              loc
                                  .t('tech_cards_ingredients_count')
                                  .replaceAll('%s', '$count'),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                            value: _saveTotal > 0
                                ? (_saveProgress / _saveTotal).clamp(0.0, 1.0)
                                : null,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$_saveProgress / $_saveTotal',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!_saving && _items.any(_canBenefitFromAdjustWaste))
                        IconButton(
                          style: IconButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          tooltip: loc.t('tech_cards_import_adjust_waste_all'),
                          onPressed: _adjustWasteForAllCards,
                          icon: const Icon(Icons.tune),
                        ),
                      Expanded(
                        child: FilledButton(
                          onPressed:
                              _saving || _items.isEmpty ? null : _createAll,
                          child: _saving
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text(loc.t('tech_cards_import_create_all')),
                        ),
                      ),
                    ],
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
  final String? originalDishName;
  final String category;
  final List<String> sections;
  final bool isSemiFinished;

  /// true если карточка уже сохранена в систему через «Сохранить» в редакторе — при «Создать все» пропускаем.
  final bool alreadySaved;

  _ReviewItem({
    required this.result,
    this.originalDishName,
    required this.category,
    this.sections = const ['all'],
    this.isSemiFinished = true,
    this.alreadySaved = false,
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
            Icon(icon,
                size: 16,
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
