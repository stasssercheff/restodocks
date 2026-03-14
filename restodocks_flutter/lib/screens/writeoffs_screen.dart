import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

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

/// Строка списания: продукт или ТТК + количество
class _WriteoffRow {
  final Product? product;
  final TechCard? techCard;
  double quantity;

  _WriteoffRow({this.product, this.techCard, required this.quantity})
      : assert(product != null || techCard != null);

  bool get isProduct => product != null;
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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<WriteoffCategory, List<_WriteoffRow>> _rowsByCategory = {};
  bool _loading = true;

  List<_WriteoffRow> _rowsFor(WriteoffCategory cat) =>
      _rowsByCategory[cat] ??= [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    if (mounted) setState(() => _loading = false);
  }

  void _addRow(WriteoffCategory cat, {Product? product, TechCard? techCard}) {
    if (product == null && techCard == null) return;
    setState(() {
      _rowsFor(cat).add(_WriteoffRow(
        product: product,
        techCard: techCard,
        quantity: 0,
      ));
    });
  }

  void _setQuantity(WriteoffCategory cat, int index, double value) {
    final rows = _rowsFor(cat);
    if (index < 0 || index >= rows.length) return;
    setState(() => rows[index].quantity = value.clamp(0.0, 99999.0));
  }

  void _removeRow(WriteoffCategory cat, int index) {
    setState(() {
      final rows = _rowsFor(cat);
      if (index >= 0 && index < rows.length) rows.removeAt(index);
    });
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _WriteoffItemPickerSheet(
        loc: loc,
        products: products,
        techCards: visibleTc,
        onSelectProduct: (p) {
          _addRow(cat, product: p);
          Navigator.of(ctx).pop();
        },
        onSelectTechCard: (tc) {
          _addRow(cat, techCard: tc);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _save(WriteoffCategory cat) async {
    final loc = context.read<LocalizationService>();
    final rows = _rowsFor(cat)
        .where((r) => r.quantity > 0)
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
      setState(() {
        final rows = _rowsFor(cat);
        rows.removeWhere((r) => r.quantity > 0);
      });
    }
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required WriteoffCategory category,
    required List<_WriteoffRow> rows,
    required String lang,
  }) {
    final loc = context.read<LocalizationService>();
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'department': employee.department,
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'timeEnd': DateFormat('HH:mm').format(DateTime.now()),
    };
    final payloadRows = rows.map((r) => {
      'productId': r.product?.id ?? 'pf_${r.techCard!.id}',
      'productName': r.displayName(lang),
      'unit': r.unit,
      'total': r.quantity,
      'quantities': [r.quantity],
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
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      final rows = payload['rows'] as List<dynamic>? ?? [];
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: WriteoffCategory.values
              .map((c) => Tab(text: _tabLabel(c, loc)))
              .toList(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: WriteoffCategory.values.map((cat) {
                return _WriteoffTabContent(
                  category: cat,
                  rows: _rowsFor(cat),
                  onAdd: () => _showItemPicker(cat),
                  onSetQuantity: (i, v) => _setQuantity(cat, i, v),
                  onRemove: (i) => _removeRow(cat, i),
                  onSave: () => _save(cat),
                  loc: loc,
                );
              }).toList(),
            ),
    );
  }
}

class _WriteoffTabContent extends StatelessWidget {
  const _WriteoffTabContent({
    required this.category,
    required this.rows,
    required this.onAdd,
    required this.onSetQuantity,
    required this.onRemove,
    required this.onSave,
    required this.loc,
  });

  final WriteoffCategory category;
  final List<_WriteoffRow> rows;
  final VoidCallback onAdd;
  final void Function(int index, double value) onSetQuantity;
  final void Function(int index) onRemove;
  final VoidCallback onSave;
  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = loc.currentLanguageCode;

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
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(r.displayName(lang)),
                        subtitle: Text('${r.unit}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 80,
                              child: _QuantityField(
                                value: r.quantity,
                                onChanged: (v) => onSetQuantity(i, v),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onRemove(i),
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
                    onPressed: rows.any((r) => r.quantity > 0) ? onSave : null,
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

class _QuantityField extends StatefulWidget {
  const _QuantityField({required this.value, required this.onChanged});

  final double value;
  final void Function(double) onChanged;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value > 0 ? widget.value.toString() : '');
  }

  @override
  void didUpdateWidget(_QuantityField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_ctrl.text.contains(RegExp(r'[0-9]'))) {
      _ctrl.text = widget.value > 0 ? widget.value.toString() : '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
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
    required this.onSelectProduct,
    required this.onSelectTechCard,
  });

  final LocalizationService loc;
  final List<Product> products;
  final List<TechCard> techCards;
  final void Function(Product) onSelectProduct;
  final void Function(TechCard) onSelectTechCard;

  @override
  State<_WriteoffItemPickerSheet> createState() => _WriteoffItemPickerSheetState();
}

class _WriteoffItemPickerSheetState extends State<_WriteoffItemPickerSheet> {
  int _segment = 0; // 0=Продукт, 1=ТТК ПФ, 2=ТТК Блюдо
  String _query = '';

  List<Product> get _filteredProducts {
    if (_query.isEmpty) return widget.products;
    final q = _query.toLowerCase();
    final lang = widget.loc.currentLanguageCode;
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.getLocalizedName(lang).toLowerCase().contains(q))
        .toList();
  }

  List<TechCard> get _filteredTechCards {
    final pf = _segment == 1;
    final dish = _segment == 2;
    var list = widget.techCards;
    if (pf) list = list.where((t) => t.isSemiFinished).toList();
    if (dish) list = list.where((t) => !t.isSemiFinished).toList();
    if (_query.isEmpty) return list;
    final q = _query.toLowerCase();
    final lang = widget.loc.currentLanguageCode;
    return list
        .where((t) =>
            t.getDisplayNameInLists(lang).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.loc.currentLanguageCode;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
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
          Expanded(
            child: _segment == 0
                ? ListView.builder(
                    controller: scrollController,
                    itemCount: _filteredProducts.length,
                    itemBuilder: (_, i) {
                      final p = _filteredProducts[i];
                      return ListTile(
                        title: Text(p.getLocalizedName(lang)),
                        subtitle: Text(p.category),
                        onTap: () => widget.onSelectProduct(p),
                      );
                    },
                  )
                : ListView.builder(
                    controller: scrollController,
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
      ),
    );
  }
}
