import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'excel_style_ttk_table.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/services.dart';
import '../services/excel_export_service.dart';

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen({super.key});

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

  String _categoryLabel(String c, LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final Map<String, Map<String, String>> categoryTranslations = {
      'sauce': {'ru': 'Соус', 'en': 'Sauce'},
      'vegetables': {'ru': 'Овощи', 'en': 'Vegetables'},
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
    };

    return categoryTranslations[c]?[lang] ?? c;
  }

  double _calculateCostPerKg(TechCard tc) {
    if (tc.ingredients.isEmpty || tc.yield <= 0) return 0.0;

    // Суммируем стоимости всех ингредиентов
    final totalCost = tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

    // Стоимость за кг = общая стоимость / выход в кг
    return (totalCost / tc.yield) * 1000;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() { _loading = false; _error = 'Нет заведения'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final list = await svc.getTechCardsForEstablishment(est.id);
      if (mounted) setState(() { _list = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Экспорт одной ТТК
  Future<void> _exportSingleTechCard(TechCard techCard) async {
    try {
      await ExcelExportService().exportSingleTechCard(techCard);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ТТК "${techCard.dishName}" успешно экспортирована')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  /// Экспорт выбранных ТТК
  Future<void> _exportSelectedTechCards() async {
    final selectedCards = _list.where((card) => _selectedTechCards.contains(card.id)).toList();
    if (selectedCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну ТТК')),
      );
      return;
    }

    try {
      await ExcelExportService().exportSelectedTechCards(selectedCards);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Выбранные ТТК (${selectedCards.length} шт.) успешно экспортированы')),
        );
        setState(() {
          _selectedTechCards.clear();
          _selectionMode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  /// Экспорт всех ТТК
  Future<void> _exportAllTechCards() async {
    if (_list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет ТТК для экспорта')),
      );
      return;
    }

    try {
      await ExcelExportService().exportAllTechCards(_list);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Все ТТК (${_list.length} шт.) успешно экспортированы')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
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

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context.watch<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
                tooltip: 'Отмена выбора',
              )
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(_selectionMode ? 'Выберите ТТК (${_selectedTechCards.length})' : loc.t('tech_cards')),
        actions: [
          // Счетчик ТТК
          if (!_selectionMode) Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${_list.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
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
                      context.push('/tech-cards/new');
                    } else if (value == 'photo') {
                      await _createFromPhoto(context, loc);
                    } else if (value == 'excel') {
                      await _createFromExcel(context, loc);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'new', child: Text(loc.t('create_tech_card'))),
                    PopupMenuItem(
                      value: 'photo',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loc.t('ai_tech_card_from_photo')),
                          const SizedBox(width: 8),
                          Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'excel',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(loc.t('ai_tech_card_from_excel')),
                          const SizedBox(width: 8),
                          Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ].where((_) => true), // чтобы actions не был null
        ],
        actions: [
          if (canEdit)
            AbsorbPointer(
              absorbing: _loading,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.add, color: _loading ? Theme.of(context).disabledColor : null),
                tooltip: loc.t('create_tech_card'),
                onSelected: (value) async {
                  if (value == 'new') {
                    context.push('/tech-cards/new');
                  } else if (value == 'photo') {
                    await _createFromPhoto(context, loc);
                  } else if (value == 'excel') {
                    await _createFromExcel(context, loc);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'new', child: Text(loc.t('create_tech_card'))),
                  PopupMenuItem(
                    value: 'photo',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loc.t('ai_tech_card_from_photo')),
                        const SizedBox(width: 8),
                        Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loc.t('ai_tech_card_from_excel')),
                        const SizedBox(width: 8),
                        Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Кнопка экспорта
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Экспорт в Excel',
            onSelected: (value) async {
              switch (value) {
                case 'single':
                  // Показать диалог выбора ТТК для экспорта одной
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Выберите ТТК для экспорта'),
                      content: SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: ListView.builder(
                          itemCount: _list.length,
                          itemBuilder: (context, index) {
                            final techCard = _list[index];
                            return ListTile(
                              title: Text(techCard.dishName),
                              subtitle: Text(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо'),
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
                          child: const Text('Отмена'),
                        ),
                      ],
                    ),
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
              const PopupMenuItem(
                value: 'single',
                child: Text('Экспорт одной ТТК'),
              ),
              PopupMenuItem(
                value: 'selected',
                child: Text(_selectionMode ? 'Экспорт выбранных (${_selectedTechCards.length})' : 'Экспорт выбранных'),
              ),
              const PopupMenuItem(
                value: 'all',
                child: Text('Экспорт всех ТТК'),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(loc),
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
              onPressed: _loading ? null : () => context.push('/tech-cards/new'),
              child: const Icon(Icons.add),
              tooltip: loc.t('create_tech_card'),
            )
          : null,
    );
  }

  Widget _buildBody(LocalizationService loc) {
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

    // Разделяем список на ПФ и Блюда
    final semiFinishedCards = _list.where((tc) => tc.isSemiFinished).toList();
    final dishCards = _list.where((tc) => !tc.isSemiFinished).toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'ПФ'),
              Tab(text: 'Блюда'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTechCardsTable(semiFinishedCards, loc),
                _buildTechCardsTable(dishCards, loc),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechCardsTable(List<TechCard> techCards, LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1000), // Та же ширина как при создании
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer),
              columns: [
                DataColumn(label: Text('Название', style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Категория', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Стоимость за кг', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: List.generate(techCards.length, (i) {
                final tc = techCards[i];
                return DataRow(
                  selected: _selectedTechCards.contains(tc.id),
                  cells: [
                    DataCell(Text(tc.getDisplayNameInLists(lang))),
                    DataCell(Text(_categoryLabel(tc.category, loc))),
                    DataCell(Text(_calculateCostPerKg(tc).toStringAsFixed(0))),
                  ],
                  onSelectChanged: _selectionMode ? null : (_) => context.push('/tech-cards/${tc.id}'),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
