import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;

import '../utils/number_format_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'excel_style_ttk_table.dart';

import '../models/models.dart';
import '../widgets/app_bar_home_button.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/services.dart';
import '../services/excel_export_service.dart';

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen({super.key, this.department = 'kitchen', this.embedded = false});

  final String department;
  final bool embedded;

  @override
  State<TechCardsListScreen> createState() => _TechCardsListScreenState();
}

class _TechCardsListScreenState extends State<TechCardsListScreen> {
  List<TechCard> _list = [];
  bool _loading = true;
  bool _loadingExcel = false;
  String? _error;
  Set<String> _selectedTechCards = {}; // ID выбранных карточек
  bool _selectionMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Порядок категорий для отображения: кухня/банкет и бар
  static const _kitchenCategoryOrder = ['sauce', 'vegetables', 'salad', 'meat', 'seafood', 'side', 'subside', 'bakery', 'dessert', 'decor', 'soup', 'misc', 'beverages', 'banquet', 'catering'];
  static const _barCategoryOrder = ['alcoholic_cocktails', 'non_alcoholic_drinks', 'hot_drinks', 'drinks_pure', 'snacks', 'sauce', 'vegetables', 'salad', 'bakery', 'dessert', 'decor', 'misc', 'beverages'];

  List<({String category, List<TechCard> cards})> _groupByCategory(List<TechCard> cards) {
    final order = (widget.department == 'bar') ? _barCategoryOrder : _kitchenCategoryOrder;
    final grouped = <String, List<TechCard>>{};
    for (final tc in cards) {
      final cat = tc.category.isNotEmpty ? tc.category : 'misc';
      grouped.putIfAbsent(cat, () => []).add(tc);
    }
    final result = <({String category, List<TechCard> cards})>[];
    for (final cat in order) {
      final list = grouped.remove(cat);
      if (list != null && list.isNotEmpty) result.add((category: cat, cards: list));
    }
    for (final e in grouped.entries) {
      result.add((category: e.key, cards: e.value));
    }
    return result;
  }

  String _categoryLabel(String c, LocalizationService loc) {
    final lang = loc.currentLanguageCode;
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
      'alcoholic_cocktails': {'ru': 'Алкогольные коктейли', 'en': 'Alcoholic cocktails'},
      'non_alcoholic_drinks': {'ru': 'Безалкогольные напитки', 'en': 'Non-alcoholic drinks'},
      'hot_drinks': {'ru': 'Горячие напитки', 'en': 'Hot drinks'},
      'drinks_pure': {'ru': 'Напитки в чистом виде', 'en': 'Drinks (neat)'},
      'snacks': {'ru': 'Снеки', 'en': 'Snacks'},
      'banquet': {'ru': 'Банкет', 'en': 'Banquet'},
      'catering': {'ru': 'Кейтеринг', 'en': 'Catering'},
    };

    return categoryTranslations[c]?[lang] ?? c;
  }

  double _calculateCostPerKg(TechCard tc) {
    if (tc.ingredients.isEmpty || tc.yield <= 0) return 0.0;
    final totalCost = tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
    return (totalCost / tc.yield) * 1000;
  }

  /// Себестоимость за порцию (для блюд): totalCost * portionWeight / yield.
  double _calculateCostPerPortion(TechCard tc) {
    if (tc.ingredients.isEmpty || tc.yield <= 0 || tc.portionWeight <= 0) return 0.0;
    final totalCost = tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
    return totalCost * tc.portionWeight / tc.yield;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null) {
        setState(() { _loading = false; _error = 'no_establishment'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final all = await svc.getTechCardsForEstablishment(est.dataEstablishmentId);
      List<TechCard> list;
      if (widget.department == 'banquet-catering') {
        list = all.where((tc) =>
            tc.category == 'banquet' || tc.category == 'catering').toList();
      } else if (widget.department == 'bar') {
        list = all.where((tc) =>
            tc.category == 'beverages' ||
            tc.sections.contains('bar') ||
            tc.sections.contains('all')).toList();
      } else if (widget.department == 'hall') {
        list = []; // Зал не имеет своих ТТК
      } else {
        // Кухня: повара и сотрудники подразделения видят все ТТК (блюда и ПФ) в режиме просмотра
        list = all.where((tc) =>
            tc.category != 'beverages' ||
            tc.sections.contains('all')).toList();
      }
      if (mounted) {
        setState(() { _list = list; _loading = false; });
        _ensureTechCardTranslations(svc, list);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _ensureTechCardTranslations(TechCardServiceSupabase svc, List<TechCard> cards) async {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (lang == 'ru') return;
    final missing = cards.where(
      (tc) => !(tc.dishNameLocalized?.containsKey(lang) == true &&
               (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false)),
    ).toList();
    for (final tc in missing) {
      if (!mounted) break;
      try {
        final translated = await svc.translateTechCardName(tc.id, tc.dishName, lang)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (translated != null && mounted) {
          final idx = _list.indexWhere((c) => c.id == tc.id);
          if (idx >= 0) {
            final updated = _list[idx].copyWith(
              dishNameLocalized: {...(_list[idx].dishNameLocalized ?? {}), lang: translated},
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
            SnackBar(content: Text(loc.t('ttk_exported').replaceFirst('%s', techCard.dishName))),
          );
        }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
        );
      }
    }
  }

  /// Экспорт выбранных ТТК
  Future<void> _exportSelectedTechCards() async {
    final selectedCards = _list.where((card) => _selectedTechCards.contains(card.id)).toList();
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
          SnackBar(content: Text(loc.t('ttk_exported_selected').replaceFirst('%s', '${selectedCards.length}'))),
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
          SnackBar(content: Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
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
          SnackBar(content: Text(loc.t('ttk_exported_all').replaceFirst('%s', '${_list.length}'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('ttk_export_error').replaceFirst('%s', '$e'))),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _createFromPhoto(BuildContext context, LocalizationService loc) async {
    final imageService = ImageService();
    final xFile = await imageService.pickImageFromGallery();
    if (xFile == null || !mounted) return;
    final bytes = await imageService.xFileToBytes(xFile);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    final ai = context.read<AiService>();
    final result = await ai.recognizeTechCardFromImage(bytes);
    if (!mounted) return;
    if (result == null || (result.dishName == null && result.ingredients.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ai_tech_card_recognize_empty'))),
      );
      return;
    }
    context.push('/tech-cards/new', extra: result);
  }

  Future<void> _createFromExcel(BuildContext context, LocalizationService loc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('file_not_selected'))));
      return;
    }
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('file_read_failed'))));
      return;
    }
    final uBytes = Uint8List.fromList(bytes);
    setState(() => _loadingExcel = true);
    try {
      // Сначала ИИ: понимает таблицы с десятками/сотнями ТТК, русские столбцы, разный порядок колонок.
      var list = await context.read<AiService>().parseTechCardsFromExcel(uBytes);
      if (list.isEmpty) {
        list = _parseSimpleExcelNames(uBytes);
      }
      if (!mounted) return;
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('ai_tech_card_excel_format_hint'))),
        );
        return;
      }
      if (list.length == 1 && list.first.ingredients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('ai_tech_card_loaded_names').replaceAll('%s', '${list.length}'))),
        );
      }
      if (list.length == 1) {
        context.push('/tech-cards/new', extra: list.single);
      } else {
        context.push('/tech-cards/import-review', extra: list);
      }
    } finally {
      if (mounted) setState(() => _loadingExcel = false);
    }
  }

  /// Простой разбор Excel: столбец A или B — названия ПФ/блюд.
  static List<TechCardRecognitionResult> _parseSimpleExcelNames(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes.toList());
      final sheetName = excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
      if (sheetName == null) return [];
      final sheet = excel.tables[sheetName]!;
      final list = <TechCardRecognitionResult>[];
      for (var r = 0; r < sheet.maxRows; r++) {
        String name = _excelCellToStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value).trim();
        if (name.isEmpty && sheet.maxColumns > 1) {
          name = _excelCellToStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value).trim();
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
    final canEdit = accountManager.currentEmployee?.canEditChecklistsAndTechCards ?? false;
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
        title: Text(_selectionMode ? loc.t('ttk_select_count').replaceFirst('%s', '${_selectedTechCards.length}') : loc.t('tech_cards')),
        actions: [
          // Счетчик ТТК
          if (!_selectionMode) Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
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
          ),
          ...?[
            if (canEdit)
              AbsorbPointer(
                absorbing: _loading,
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.add, color: _loading ? Theme.of(context).disabledColor : null),
                  tooltip: loc.t('create_tech_card'),
                  onSelected: (value) async {
                    if (value == 'new') {
                      context.push(widget.department == 'bar' ? '/tech-cards/new?department=bar' : '/tech-cards/new');
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new', child: Text(loc.t('create_tech_card'))),
                  ],
                ),
              ),
          ].where((_) => true), // чтобы actions не был null
          // Кнопка экспорта
          PopupMenuButton<String>(
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
                                title: Text(techCard.getDisplayNameInLists(l.currentLanguageCode)),
                                subtitle: Text(techCard.isSemiFinished ? l.t('ttk_semi_finished') : l.t('ttk_dish_label')),
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
                    ? loc.t('ttk_export_selected').replaceFirst('%s', '${_selectedTechCards.length}')
                    : loc.t('ttk_export_selected_short')),
              ),
              PopupMenuItem(
                value: 'all',
                child: Text(loc.t('ttk_export_all')),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
        ],
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
                        const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(height: 16),
                        Text(loc.t('loading_excel')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _loading ? null : () => context.push(widget.department == 'bar' ? '/tech-cards/new?department=bar' : '/tech-cards/new'),
              child: const Icon(Icons.add),
              tooltip: loc.t('create_tech_card'),
            )
          : null,
    );
  }

  Widget _buildBody(LocalizationService loc, bool canEdit, bool showCost) {
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
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(loc.t('tech_cards'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(loc.t('tech_cards_empty'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    // Разделяем список на ПФ и Блюда и фильтруем по поиску
    final query = _searchController.text.trim().toLowerCase();
    List<TechCard> filterBySearch(List<TechCard> list) {
      if (query.isEmpty) return list;
      final loc = context.read<LocalizationService>();
      final lang = loc.currentLanguageCode;
      return list.where((tc) => tc.getDisplayNameInLists(lang).toLowerCase().contains(query)).toList();
    }
    final semiFinishedCards = filterBySearch(_list.where((tc) => tc.isSemiFinished).toList());
    final dishCards = filterBySearch(_list.where((tc) => !tc.isSemiFinished).toList());

    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final showBranchFilter = (emp?.hasRole('executive_chef') == true || emp?.hasRole('sous_chef') == true) &&
        acc.establishment?.isMain == true;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          if (showBranchFilter)
            FutureBuilder<List<Establishment>>(
              future: acc.getBranchesForEstablishment(acc.establishment!.id),
              builder: (ctx, snap) {
                if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                final branches = snap.data!;
                return Consumer<TtkBranchFilterService>(
                  builder: (_, branchFilter, __) {
                    final selId = branchFilter.selectedBranchId;
                    final label = selId == null
                        ? loc.t('main_establishment_short')
                        : branches.where((b) => b.id == selId).map((b) => b.name).firstOrNull ?? selId;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          FilterChip(
                            avatar: const Icon(Icons.account_tree, size: 18),
                            label: Text(label),
                            selected: selId != null,
                            onSelected: (_) => _showTtkBranchFilterPicker(context, loc, acc, branches),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          TabBar(
            tabs: [
              Tab(text: loc.t('ttk_tab_pf')),
              Tab(text: loc.t('ttk_tab_dishes')),
            ],
          ),
          // Поиск по названию
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
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
                          setState(() {});
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTechCardsTable(semiFinishedCards, loc, canEdit, showCost, isDishesTab: false),
                _buildTechCardsTable(dishCards, loc, canEdit, showCost, isDishesTab: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Компактная таблица с шапкой и группировкой по категориям.
  /// isDishesTab: для блюд — себестоимость за порцию, для ПФ — стоимость за кг.
  Widget _buildTechCardsTable(List<TechCard> techCards, LocalizationService loc, bool canEdit, bool showCost, {bool isDishesTab = false}) {
    final lang = loc.currentLanguageCode;
    const colCatWidth = 76.0;
    const colCostWidth = 56.0; // шире для себестоимости (десятичные)
    const colActionsWidth = 62.0; // «Просмотр» целиком
    final est = context.read<AccountManagerSupabase>().establishment;
    final costSym = est?.currencySymbol ?? Establishment.currencySymbolFor(est?.defaultCurrency ?? 'VND');
    final groups = _groupByCategory(techCards);
    final costLabel = showCost
        ? (isDishesTab ? loc.t('ttk_col_cost_per_portion').replaceFirst('%s', costSym) : '$costSym/${loc.t('kg')}')
        : '—';

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _TableHeaderDelegate(
              colCatWidth: colCatWidth,
              colCostWidth: colCostWidth,
              colActionsWidth: colActionsWidth,
              color: Theme.of(context).colorScheme.primaryContainer,
              onColor: Theme.of(context).colorScheme.onPrimaryContainer,
              labelName: loc.t('ttk_col_name'),
              labelCat: loc.t('column_category'),
              labelCost: costLabel,
              labelView: loc.t('ttk_col_view'),
            ),
          ),
          ...groups.expand((g) => [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  _categoryLabel(g.category, loc),
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
                  colCatWidth: colCatWidth,
                  colCostWidth: colCostWidth,
                  colActionsWidth: colActionsWidth,
                  costSym: costSym,
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
    required double colCatWidth,
    required double colCostWidth,
    required double colActionsWidth,
    required String costSym,
  }) {
    final tc = techCards[index];
    final selected = _selectedTechCards.contains(tc.id);
    final name = tc.getDisplayNameInLists(lang);
    final cat = _categoryLabel(tc.category, loc);
    final cost = showCost
        ? (isDishesTab
            ? '${NumberFormatUtils.formatDecimal(_calculateCostPerPortion(tc))} $costSym'
            : NumberFormatUtils.formatInt(_calculateCostPerKg(tc)))
        : '—';
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5)
          : null,
      child: InkWell(
        onTap: () {
          if (_selectionMode) {
            _toggleTechCardSelection(tc.id);
          } else {
            final path = canEdit ? '/tech-cards/${tc.id}' : '/tech-cards/${tc.id}?view=1';
            context.push(path);
          }
        },
        onLongPress: canEdit && !_selectionMode
            ? () => context.push('/tech-cards/${tc.id}?view=1')
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
                width: colCatWidth,
                child: Text(
                  cat.length > 6 ? '${cat.substring(0, 5)}…' : cat,
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
                width: colCostWidth,
                child: Text(
                  cost,
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
                        onPressed: () => context.push('/tech-cards/${tc.id}?view=1'),
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
  Widget _buildWideTable(List<TechCard> techCards, LocalizationService loc, String lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1000),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer),
            columns: [
              DataColumn(label: Text(loc.t('ttk_col_name'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('ttk_col_category'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('ttk_col_cost_per_kg'), style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(techCards.length, (i) {
              final tc = techCards[i];
              return DataRow(
                selected: _selectedTechCards.contains(tc.id),
                cells: [
                  DataCell(Text(tc.getDisplayNameInLists(lang))),
                  DataCell(Text(_categoryLabel(tc.category, loc))),
                  DataCell(Text(NumberFormatUtils.formatInt(_calculateCostPerKg(tc)))),
                ],
                onSelectChanged: _selectionMode ? null : (_) => context.push('/tech-cards/${tc.id}'),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Делегат для липкой шапки таблицы ТТК (Название | Категория | ₽/кг | Просмотр).
class _TableHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TableHeaderDelegate({
    required this.colCatWidth,
    required this.colCostWidth,
    required this.colActionsWidth,
    required this.color,
    required this.onColor,
    required this.labelName,
    required this.labelCat,
    required this.labelCost,
    required this.labelView,
  });

  final double colCatWidth;
  final double colCostWidth;
  final double colActionsWidth;
  final Color color;
  final Color onColor;
  final String labelName;
  final String labelCat;
  final String labelCost;
  final String labelView;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: onColor);
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(labelName, style: style),
          ),
          SizedBox(
            width: colCatWidth,
            child: Text(labelCat, style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: colCostWidth,
            child: Text(labelCost, style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: colActionsWidth,
            child: Text(labelView, style: style, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TableHeaderDelegate oldDelegate) {
    return oldDelegate.colCatWidth != colCatWidth ||
        oldDelegate.colCostWidth != colCostWidth ||
        oldDelegate.colActionsWidth != colActionsWidth ||
        oldDelegate.color != color ||
        oldDelegate.onColor != onColor ||
        oldDelegate.labelName != labelName ||
        oldDelegate.labelCat != labelCat ||
        oldDelegate.labelCost != labelCost ||
        oldDelegate.labelView != labelView;
  }
}
