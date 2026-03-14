import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../mixins/auto_save_mixin.dart';
import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

String _unitDisplay(String? unit, String lang) {
  const ruToId = {'г': 'g', 'кг': 'kg', 'мл': 'ml', 'л': 'l', 'шт': 'pcs', 'штуки': 'pcs'};
  final u = (unit ?? 'g').trim().toLowerCase();
  final id = ruToId[u] ?? u;
  return CulinaryUnits.displayName(id, lang);
}

/// Категории списания
enum WriteoffCategory {
  staff, // Персонал
  workingThrough, // Проработка
  spoilage, // Порча
  breakage, // Брекераж
  guestRefusal, // Отказ гостя
}

extension WriteoffCategoryExt on WriteoffCategory {
  String get code => name;
}

/// Результат выбора в пикере (продукт или ТТК)
class _WriteoffPickedItem {
  final Product? product;
  final TechCard? techCard;
  _WriteoffPickedItem({this.product, this.techCard});
}

/// Строка списания: продукт или ТТК + ячейки количества (как в бланке инвентаризации)
class _WriteoffRow {
  final Product? product;
  final TechCard? techCard;
  final List<double> quantities;

  _WriteoffRow({this.product, this.techCard, List<double>? quantities})
      : quantities = quantities ?? [0.0, 0.0],
        assert(product != null || techCard != null);

  bool get isProduct => product != null;
  double get total => quantities.fold(0.0, (a, b) => a + b);

  String displayName(String lang) {
    if (product != null) return product!.getLocalizedName(lang);
    return techCard!.getDisplayNameInLists(lang);
  }

  String get unit {
    if (product != null) return product!.unit ?? 'g';
    return 'pcs'; // ТТК — порции
  }
}

class WriteoffsScreen extends StatefulWidget {
  const WriteoffsScreen({super.key});

  @override
  State<WriteoffsScreen> createState() => _WriteoffsScreenState();
}

class _WriteoffsScreenState extends State<WriteoffsScreen>
    with AutoSaveMixin<WriteoffsScreen> {
  WriteoffCategory _selectedCategory = WriteoffCategory.staff;
  final Map<WriteoffCategory, List<_WriteoffRow>> _rowsByCategory = {};
  final ValueNotifier<int> _rowsVersion = ValueNotifier(0);
  bool _loading = true;

  @override
  String get draftKey => 'writeoffs';

  @override
  bool get restoreDraftAfterLoad => true;

  List<_WriteoffRow> _rowsFor(WriteoffCategory cat) =>
      _rowsByCategory[cat] ??= [];

  @override
  void dispose() {
    _rowsVersion.dispose();
    super.dispose();
  }

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'selectedCategory': _selectedCategory.name,
      'rowsByCategory': _rowsByCategory.map((cat, rows) => MapEntry(
        cat.name,
        rows.map((r) => {
          'productId': r.product?.id,
          'techCardId': r.techCard?.id,
          'quantities': r.quantities,
        }).toList(),
      )),
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    final productStore = context.read<ProductStoreSupabase>();
    final tcSvc = context.read<TechCardServiceSupabase>();
    final dataEstId = context.read<AccountManagerSupabase>().establishment?.dataEstablishmentId;
    if (dataEstId == null) return;

    final catName = data['selectedCategory'] as String? ?? 'staff';
    _selectedCategory = WriteoffCategory.values.firstWhere(
      (c) => c.name == catName,
      orElse: () => WriteoffCategory.staff,
    );

    final raw = data['rowsByCategory'] as Map<String, dynamic>?;
    if (raw == null) return;

    await productStore.loadProducts();
    await productStore.loadNomenclature(dataEstId);
    final techCards = await tcSvc.getTechCardsForEstablishment(dataEstId);
    final products = productStore.getNomenclatureProducts(dataEstId);

    for (final entry in raw.entries) {
      WriteoffCategory? cat;
      for (final c in WriteoffCategory.values) {
        if (c.name == entry.key) { cat = c; break; }
      }
      if (cat == null) continue;

      final rowsList = entry.value as List<dynamic>? ?? [];
      for (final rowMap in rowsList) {
        final m = rowMap as Map<String, dynamic>? ?? {};
        final productId = m['productId'] as String?;
        final techCardId = m['techCardId'] as String?;
        final qtyList = (m['quantities'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0];
        Product? p;
        TechCard? tc;
        if (productId != null) {
          for (final x in products) {
            if (x.id == productId) { p = x; break; }
          }
        }
        if (techCardId != null) {
          for (final x in techCards) {
            if (x.id == techCardId) { tc = x; break; }
          }
        }
        if (p != null || tc != null) {
          _rowsFor(cat).add(_WriteoffRow(product: p, techCard: tc, quantities: List<double>.from(qtyList)));
        }
      }
    }
    if (mounted) {
      _rowsVersion.value++;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureData());
  }

  void _saveNow() => saveImmediately();

  Future<void> _ensureData() async {
    setState(() => _loading = true);
    final account = context.read<AccountManagerSupabase>();
    final productStore = context.read<ProductStoreSupabase>();
    final tcSvc = context.read<TechCardServiceSupabase>();
    final est = account.establishment;
    final dataEstId = est?.dataEstablishmentId;
    if (dataEstId != null) {
      await productStore.loadProducts();
      await productStore.loadNomenclature(dataEstId);
      await tcSvc.getTechCardsForEstablishment(dataEstId);
    }
    if (mounted) {
      await restoreDraftNow();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addRow(WriteoffCategory cat, {Product? product, TechCard? techCard}) {
    if (product == null && techCard == null) return;
    final rows = List<_WriteoffRow>.from(_rowsFor(cat));
    rows.add(_WriteoffRow(
      product: product,
      techCard: techCard,
      quantities: [0.0, 0.0],
    ));
    _rowsByCategory[cat] = rows;
    _rowsVersion.value++;
    setState(() {});
    _saveNow();
  }

  void _setQuantity(WriteoffCategory cat, int rowIndex, int colIndex, double value) {
    final rows = _rowsFor(cat);
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final row = rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.quantities.length) return;
    row.quantities[colIndex] = value.clamp(0.0, 99999.0);
    _rowsVersion.value++;
    setState(() {});
    _saveNow();
  }

  void _addQuantityCell(WriteoffCategory cat, int rowIndex) {
    final rows = _rowsFor(cat);
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    rows[rowIndex].quantities.add(0.0);
    _rowsVersion.value++;
    setState(() {});
    _saveNow();
  }

  int _maxQuantityColumns(WriteoffCategory cat) {
    final rows = _rowsFor(cat);
    if (rows.isEmpty) return 2;
    return rows.map((r) => r.quantities.length).fold<int>(2, (a, b) => a > b ? a : b);
  }

  void _removeRow(WriteoffCategory cat, int index) {
    final rows = _rowsFor(cat);
    if (index >= 0 && index < rows.length) rows.removeAt(index);
    _rowsVersion.value++;
    setState(() {});
    _saveNow();
  }

  Future<void> _showItemPicker(WriteoffCategory cat) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final productStore = context.read<ProductStoreSupabase>();
    final tcSvc = context.read<TechCardServiceSupabase>();
    final dataEstId = account.establishment?.dataEstablishmentId;
    if (dataEstId == null) return;

    final products = productStore.getNomenclatureProducts(dataEstId);
    final techCards = await tcSvc.getTechCardsForEstablishment(dataEstId);
    final emp = account.currentEmployee;
    final visibleTc = emp == null
        ? techCards
        : techCards.where((tc) => emp.canSeeTechCard(tc.sections)).toList();

    if (!mounted) return;
    final picked = await showModalBottomSheet<_WriteoffPickedItem>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => _WriteoffItemPickerSheet(
          loc: loc,
          products: products,
          techCards: visibleTc,
          scrollController: scrollController,
          onSelectProduct: (p) => Navigator.of(ctx).pop(_WriteoffPickedItem(product: p)),
          onSelectTechCard: (tc) => Navigator.of(ctx).pop(_WriteoffPickedItem(techCard: tc)),
        ),
      ),
    );
    if (picked != null && mounted) {
      _addRow(cat, product: picked.product, techCard: picked.techCard);
    }
  }

  Future<void> _save(WriteoffCategory cat) async {
    final loc = context.read<LocalizationService>();
    final rows = _rowsFor(cat)
        .where((r) => r.total > 0)
        .toList();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('writeoff_empty_hint') ?? 'Добавьте позиции с количеством')),
      );
      return;
    }

    // 1. Выбор языка
    String selectedLang = loc.currentLanguageCode;
    final langResult = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(loc.t('writeoff_save_lang_title') ?? 'Язык сохранения'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('inventory_export_lang') ?? 'Язык сохранения:',
                style: Theme.of(ctx2).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: LocalizationService.productLanguageCodes.map((code) {
                  return ChoiceChip(
                    label: Text(loc.getLanguageName(code)),
                    selected: selectedLang == code,
                    onSelected: (_) => setState(() => selectedLang = code),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selectedLang),
              child: Text(loc.t('save') ?? 'Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (langResult == null || !mounted) return;

    // 2. Комментарий (сохраняется в документе, переводится при экспорте)
    String comment = '';
    if (mounted) {
      comment = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: Text(loc.t('writeoff_comment_title') ?? 'Комментарий'),
            content: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: loc.t('writeoff_comment_hint') ?? 'Введите комментарий (необязательно)',
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(''),
                child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: Text(loc.t('save') ?? 'Сохранить'),
              ),
            ],
          );
        },
      ) ?? '';
    }

    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;
    if (establishment == null || employee == null) return;

    final chefs = await account.getExecutiveChefsForEstablishment(establishment.id);
    final chef = chefs.isNotEmpty ? chefs.first : null;

    final payload = _buildPayload(
      establishment: establishment,
      employee: employee,
      category: cat,
      rows: rows,
      lang: langResult,
    );
    if (comment.isNotEmpty) {
      payload['comment'] = comment;
      payload['commentSourceLang'] = loc.currentLanguageCode;
    }

    final docService = InventoryDocumentService();
    final docSaved = await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: chef?.id ?? '',
      recipientEmail: chef?.email ?? '',
      payload: payload,
    );

    if (docSaved == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.t('inventory_document_save_error') ?? 'Не удалось сохранить.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // 3. Сохранение Excel
    if (mounted) {
      try {
        final bytes = _buildExcelBytes(payload, loc);
        if (bytes != null && bytes.isNotEmpty) {
          final date = payload['header']?['date'] ?? DateTime.now().toIso8601String().split('T').first;
          final catStr = cat.code;
          await saveFileBytes('writeoff_${catStr}_$date.xlsx', bytes);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Документ сохранён')),
          );
        }
      } catch (_) {}
      // Очистить заполненные строки после успешного сохранения
      final rows = _rowsFor(cat);
      rows.removeWhere((r) => r.total > 0);
      _rowsVersion.value++;
      setState(() {});
    }
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required WriteoffCategory category,
    required List<_WriteoffRow> rows,
    required String lang,
  }) {
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'department': employee.department,
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'timeEnd': DateFormat('HH:mm').format(DateTime.now()),
    };
    final sorted = List<_WriteoffRow>.from(rows)
      ..sort((a, b) => a.displayName(lang).toLowerCase().compareTo(b.displayName(lang).toLowerCase()));
    final payloadRows = sorted.map((r) => {
      'productId': r.product?.id ?? 'pf_${r.techCard!.id}',
      'productName': r.displayName(lang),
      'unit': r.unit,
      'total': r.total,
      'quantities': r.quantities,
    }).toList();
    return {
      'type': 'writeoff',
      'category': category.code,
      'header': header,
      'rows': payloadRows,
      'sourceLang': lang,
    };
  }

  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Списание'];
      var rows = (payload['rows'] as List<dynamic>? ?? []).map((e) => e as Map<String, dynamic>).toList();
      rows = rows..sort((a, b) => (a['productName']?.toString() ?? '').toLowerCase().compareTo((b['productName']?.toString() ?? '').toLowerCase()));
      sheet.appendRow([
        TextCellValue(loc.t('inventory_excel_number') ?? '#'),
        TextCellValue(loc.t('inventory_item_name') ?? 'Наименование'),
        TextCellValue(loc.t('inventory_unit') ?? 'Ед.'),
        TextCellValue(loc.t('inventory_excel_total') ?? 'Количество'),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(r['productName']?.toString() ?? ''),
          TextCellValue(r['unit']?.toString() ?? ''),
          DoubleCellValue((r['total'] as num?)?.toDouble() ?? 0),
        ]);
      }
      final comment = payload['comment']?.toString();
      if (comment != null && comment.isNotEmpty) {
        sheet.appendRow([]);
        sheet.appendRow([TextCellValue(loc.t('writeoff_comment') ?? 'Комментарий'), TextCellValue(comment)]);
      }
      excel.setDefaultSheet('Списание');
      final out = excel.encode();
      return out;
    } catch (_) {
      return null;
    }
  }

  String _tabLabel(WriteoffCategory cat, LocalizationService loc) {
    switch (cat) {
      case WriteoffCategory.staff:
        return loc.t('writeoff_category_staff') ?? 'Персонал';
      case WriteoffCategory.workingThrough:
        return loc.t('writeoff_category_working') ?? 'Проработка';
      case WriteoffCategory.spoilage:
        return loc.t('writeoff_category_spoilage') ?? 'Порча';
      case WriteoffCategory.breakage:
        return loc.t('writeoff_category_breakage') ?? 'Брекераж';
      case WriteoffCategory.guestRefusal:
        return loc.t('writeoff_category_guest_refusal') ?? 'Отказ гостя';
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('writeoffs') ?? 'Списания'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: DropdownButtonFormField<WriteoffCategory>(
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        isExpanded: true,
                        alignment: Alignment.center,
                        selectedItemBuilder: (context) => WriteoffCategory.values
                            .map((c) => Center(child: Text(_tabLabel(c, loc))))
                            .toList(),
                        items: WriteoffCategory.values.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(_tabLabel(c, loc)),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedCategory = v);
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _rowsVersion,
                    builder: (_, __, ___) => _WriteoffTabContent(
              category: _selectedCategory,
              rows: _rowsFor(_selectedCategory),
              maxCols: _maxQuantityColumns(_selectedCategory),
              onAdd: () => _showItemPicker(_selectedCategory),
              onSetQuantity: (ri, ci, v) => _setQuantity(_selectedCategory, ri, ci, v),
              onAddQuantityCell: (ri) => _addQuantityCell(_selectedCategory, ri),
              onRemove: (i) => _removeRow(_selectedCategory, i),
              onSave: () => _save(_selectedCategory),
              loc: loc,
            ),
                  ),
                ),
              ],
            ),
    );
  }
}

// Ширины колонок как в бланке инвентаризации
const double _colNoWidth = 28;
const double _colUnitWidth = 48;
const double _colTotalWidth = 56;
const double _colQtyWidth = 48;
const double _colGap = 6;
const double _colDeleteWidth = 40;

class _WriteoffTabContent extends StatelessWidget {
  const _WriteoffTabContent({
    required this.category,
    required this.rows,
    required this.maxCols,
    required this.onAdd,
    required this.onSetQuantity,
    required this.onAddQuantityCell,
    required this.onRemove,
    required this.onSave,
    required this.loc,
  });

  final WriteoffCategory category;
  final List<_WriteoffRow> rows;
  final int maxCols;
  final VoidCallback onAdd;
  final void Function(int rowIndex, int colIndex, double value) onSetQuantity;
  final void Function(int rowIndex) onAddQuantityCell;
  final void Function(int index) onRemove;
  final VoidCallback onSave;
  final LocalizationService loc;

  double _leftWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scrollWidth = maxCols * (_colQtyWidth + _colGap) + _colDeleteWidth;
    return (w - scrollWidth).clamp(180.0, 320.0);
  }

  double _colNameWidth(BuildContext context) =>
      _leftWidth(context) - _colNoWidth - _colGap - _colUnitWidth - _colGap - _colTotalWidth - _colGap;

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = loc.currentLanguageCode;
    final leftW = _leftWidth(context);

    return Column(
      children: [
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        loc.t('writeoff_add_items_hint') ?? 'Добавьте продукт или ТТК',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Шапка: # | Наименование | Мера | Итого | 1 | 2 | 3 | ...
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: theme.dividerColor)),
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                          SizedBox(width: _colGap),
                          SizedBox(width: _colNameWidth(context), child: Text(loc.t('inventory_item_name') ?? 'Наименование', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: _colGap),
                          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit') ?? 'Ед.', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: _colGap),
                          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total') ?? 'Итого', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                          SizedBox(width: _colGap),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (var c = 0; c < maxCols; c++) ...[
                                    if (c > 0) SizedBox(width: _colGap),
                                    SizedBox(width: _colQtyWidth, child: Center(child: Text('${c + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)))),
                                  ],
                                  SizedBox(width: _colDeleteWidth),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final rowNum = i + 1;
                          return _WriteoffDataRow(
                            row: r,
                            rowIndex: i,
                            rowNumber: rowNum,
                            maxCols: maxCols,
                            leftWidth: leftW,
                            formatQty: _formatQty,
                            onSetQuantity: onSetQuantity,
                            onAddQuantityCell: onAddQuantityCell,
                            onRemove: onRemove,
                            loc: loc,
                            isLastRow: i == rows.length - 1,
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text(loc.t('writeoff_add') ?? 'Добавить'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: rows.any((r) => r.total > 0) ? onSave : null,
                    icon: const Icon(Icons.save),
                    label: Text(loc.t('save') ?? 'Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WriteoffDataRow extends StatelessWidget {
  const _WriteoffDataRow({
    required this.row,
    required this.rowIndex,
    required this.rowNumber,
    required this.maxCols,
    required this.leftWidth,
    required this.formatQty,
    required this.onSetQuantity,
    required this.onAddQuantityCell,
    required this.onRemove,
    required this.loc,
    required this.isLastRow,
  });

  final _WriteoffRow row;
  final int rowIndex;
  final int rowNumber;
  final int maxCols;
  final double leftWidth;
  final String Function(double) formatQty;
  final void Function(int, int, double) onSetQuantity;
  final void Function(int) onAddQuantityCell;
  final void Function(int) onRemove;
  final LocalizationService loc;
  final bool isLastRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qtyCols = row.quantities.length;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        color: rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Фиксированная левая часть
          SizedBox(
            width: leftWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                  SizedBox(width: _colGap),
                  Expanded(
                    child: Text(
                      row.displayName(loc.currentLanguageCode),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: _colGap),
                  SizedBox(width: _colUnitWidth, child: Text(_unitDisplay(row.unit, loc.currentLanguageCode), style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                  SizedBox(width: _colGap),
                  SizedBox(width: _colTotalWidth, child: Center(child: Text(formatQty(row.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)))),
                  SizedBox(width: _colGap),
                ],
              ),
            ),
          ),
          // Скроллируемые ячейки количества + удалить
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var c = 0; c < qtyCols; c++) ...[
                    if (c > 0) SizedBox(width: _colGap),
                    SizedBox(
                      width: _colQtyWidth,
                      child: Center(
                        child: _QuantityField(
                          key: ValueKey('qty_${rowIndex}_$c'),
                          value: row.quantities[c],
                          onChanged: (v) => onSetQuantity(rowIndex, c, v),
                          onFocusLast: c == qtyCols - 1 ? () => onAddQuantityCell(rowIndex) : null,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: _colDeleteWidth, child: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => onRemove(rowIndex), padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityField extends StatefulWidget {
  const _QuantityField({
    required this.value,
    required this.onChanged,
    this.onFocusLast,
    super.key,
  });

  final double value;
  final void Function(double) onChanged;
  final VoidCallback? onFocusLast;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late TextEditingController _ctrl;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value > 0 ? widget.value.toString() : '');
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus && widget.onFocusLast != null) {
      widget.onFocusLast!();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_QuantityField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_ctrl.text.contains(RegExp(r'[0-9]'))) {
      _ctrl.text = widget.value > 0 ? widget.value.toString() : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        isDense: true,
      ),
      onChanged: (v) {
        final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
        widget.onChanged(n);
      },
    );
  }
}

class _WriteoffItemPickerSheet extends StatefulWidget {
  const _WriteoffItemPickerSheet({
    required this.loc,
    required this.products,
    required this.techCards,
    this.scrollController,
    required this.onSelectProduct,
    required this.onSelectTechCard,
  });

  final LocalizationService loc;
  final List<Product> products;
  final List<TechCard> techCards;
  final ScrollController? scrollController;
  final void Function(Product) onSelectProduct;
  final void Function(TechCard) onSelectTechCard;

  @override
  State<_WriteoffItemPickerSheet> createState() => _WriteoffItemPickerSheetState();
}

class _WriteoffItemPickerSheetState extends State<_WriteoffItemPickerSheet> {
  int _segment = 0; // 0=Продукт, 1=ТТК ПФ, 2=ТТК Блюдо
  String _query = '';

  List<Product> get _filteredProducts {
    final lang = widget.loc.currentLanguageCode;
    var list = widget.products;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.getLocalizedName(lang).toLowerCase().contains(q))
          .toList();
    }
    list = List<Product>.from(list)
      ..sort((a, b) => a.getLocalizedName(lang).toLowerCase().compareTo(b.getLocalizedName(lang).toLowerCase()));
    return list;
  }

  List<TechCard> get _filteredTechCards {
    final lang = widget.loc.currentLanguageCode;
    final pf = _segment == 1;
    final dish = _segment == 2;
    var list = widget.techCards;
    if (pf) list = list.where((t) => t.isSemiFinished).toList();
    if (dish) list = list.where((t) => !t.isSemiFinished).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((t) =>
              t.getDisplayNameInLists(lang).toLowerCase().contains(q))
          .toList();
    }
    list = List<TechCard>.from(list)
      ..sort((a, b) => a.getDisplayNameInLists(lang).toLowerCase().compareTo(b.getDisplayNameInLists(lang).toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.loc.currentLanguageCode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text(widget.loc.t('writeoff_type_product') ?? 'Продукт')),
                  ButtonSegment(value: 1, label: Text(widget.loc.t('writeoff_type_pf') ?? 'ТТК ПФ')),
                  ButtonSegment(value: 2, label: Text(widget.loc.t('writeoff_type_dish') ?? 'ТТК Блюдо')),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  labelText: widget.loc.t('search'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: _segment == 0
              ? ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _filteredProducts.length,
                  itemBuilder: (_, i) {
                    final p = _filteredProducts[i];
                    return ListTile(
                      title: Text(p.getLocalizedName(lang)),
                      onTap: () => widget.onSelectProduct(p),
                    );
                  },
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  itemCount: _filteredTechCards.length,
                  itemBuilder: (_, i) {
                    final t = _filteredTechCards[i];
                    return ListTile(
                      title: Text(t.getDisplayNameInLists(lang)),
                      subtitle: Text(t.isSemiFinished
                          ? (widget.loc.t('writeoff_type_pf') ?? 'ПФ')
                          : (widget.loc.t('writeoff_type_dish') ?? 'Блюдо')),
                      onTap: () => widget.onSelectTechCard(t),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
