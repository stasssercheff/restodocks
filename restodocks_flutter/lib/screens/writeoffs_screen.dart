import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../core/subscription_entitlements.dart';
import '../mixins/auto_save_mixin.dart';
import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../utils/employee_display_utils.dart';
import '../widgets/app_bar_home_button.dart';

String _unitDisplay(String? unit, String lang) {
  const ruToId = {
    'г': 'g',
    'кг': 'kg',
    'мл': 'ml',
    'л': 'l',
    'шт': 'pcs',
    'штука': 'pcs',
    'штуки': 'pcs',
    'штук': 'pcs',
  };
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
  generic, // Просто «списание» (Pro без выбора типа)
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
  /// Переопределение единицы (г/шт и т.д.) — null = продукт/ТТК по умолчанию
  final String? unitOverride;

  _WriteoffRow({this.product, this.techCard, List<double>? quantities, this.unitOverride})
      : quantities = quantities ?? [0.0, 0.0],
        assert(product != null || techCard != null);

  bool get isProduct => product != null;
  double get total => quantities.fold(0.0, (a, b) => a + b);

  String displayName(String lang) {
    if (product != null) return product!.getLocalizedName(lang);
    return techCard!.getDisplayNameInLists(lang);
  }

  String get unit {
    if (unitOverride != null && unitOverride!.isNotEmpty) return unitOverride!;
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
  final ValueNotifier<int> _savedListVersion = ValueNotifier(0);
  bool _loading = true;
  List<Map<String, dynamic>> _savedWriteoffs = [];
  bool _savedListLoading = false;
  List<Product> _cachedProducts = [];
  List<TechCard> _cachedTechCards = [];
  bool _showSavedList = false;

  @override
  String get draftKey => 'writeoffs';

  @override
  bool get restoreDraftAfterLoad => true;

  List<_WriteoffRow> _rowsFor(WriteoffCategory cat) =>
      _rowsByCategory[cat] ??= [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ultra = SubscriptionEntitlements.from(
      context.read<AccountManagerSupabase>().establishment,
    ).hasUltraLevelFeatures;
    if (!ultra) {
      var changed = false;
      for (final c in WriteoffCategory.values) {
        if (c == WriteoffCategory.generic) continue;
        final list = _rowsByCategory[c];
        if (list != null && list.isNotEmpty) {
          _rowsFor(WriteoffCategory.generic).addAll(list);
          list.clear();
          changed = true;
        }
      }
      if (_selectedCategory != WriteoffCategory.generic) {
        _selectedCategory = WriteoffCategory.generic;
        changed = true;
      }
      if (changed) _rowsVersion.value++;
    } else if (_selectedCategory == WriteoffCategory.generic) {
      _selectedCategory = WriteoffCategory.staff;
    }
  }

  @override
  void dispose() {
    _rowsVersion.dispose();
    _savedListVersion.dispose();
    super.dispose();
  }

  Future<void> _loadSavedWriteoffs() async {
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    if (estId == null) return;
    setState(() => _savedListLoading = true);
    try {
      final raw = await InventoryDocumentService().listForEstablishment(estId);
      _savedWriteoffs = raw.where((d) {
        final p = d['payload'] as Map<String, dynamic>?;
        return p?['type']?.toString() == 'writeoff';
      }).toList();
    } finally {
      if (mounted) setState(() => _savedListLoading = false);
    }
  }

  @override
  Map<String, dynamic> getCurrentState() {
    final ultra = SubscriptionEntitlements.from(
      context.read<AccountManagerSupabase>().establishment,
    ).hasUltraLevelFeatures;
    if (!ultra) {
      return {
        'selectedCategory': WriteoffCategory.generic.name,
        'rowsByCategory': {
          WriteoffCategory.generic.name: _rowsFor(WriteoffCategory.generic)
              .map((r) => {
                    'productId': r.product?.id,
                    'techCardId': r.techCard?.id,
                    'quantities': r.quantities,
                    'unitOverride': r.unitOverride,
                  })
              .toList(),
        },
      };
    }
    return {
      'selectedCategory': _selectedCategory.name,
      'rowsByCategory': _rowsByCategory.map((cat, rows) => MapEntry(
        cat.name,
        rows.map((r) => {
          'productId': r.product?.id,
          'techCardId': r.techCard?.id,
          'quantities': r.quantities,
          'unitOverride': r.unitOverride,
        }).toList(),
      )),
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    final dataEstId = context.read<AccountManagerSupabase>().establishment?.dataEstablishmentId;
    if (dataEstId == null) return;

    final ultra = SubscriptionEntitlements.from(
      context.read<AccountManagerSupabase>().establishment,
    ).hasUltraLevelFeatures;
    final catName = data['selectedCategory'] as String? ??
        (ultra ? 'staff' : 'generic');
    _selectedCategory = WriteoffCategory.values.firstWhere(
      (c) => c.name == catName,
      orElse: () => ultra ? WriteoffCategory.staff : WriteoffCategory.generic,
    );

    final raw = data['rowsByCategory'] as Map<String, dynamic>?;
    if (raw == null) return;

    final products = _cachedProducts;
    final techCards = _cachedTechCards;

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
        final unitOverride = m['unitOverride'] as String?;
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
          _rowsFor(cat).add(_WriteoffRow(product: p, techCard: tc, quantities: List<double>.from(qtyList), unitOverride: unitOverride));
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
    final dataEstId = account.establishment?.dataEstablishmentId;
    if (dataEstId != null) {
      final results = await Future.wait([
        productStore.loadNomenclatureProductsDirect(dataEstId),
        tcSvc.getTechCardsForEstablishment(dataEstId),
      ]);
      _cachedProducts = results[0] as List<Product>;
      _cachedTechCards = results[1] as List<TechCard>;
    }
    if (mounted) {
      await restoreDraftNow();
      await _loadSavedWriteoffs();
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
    if (colIndex < 0) return;
    final row = rows[rowIndex];
    while (row.quantities.length <= colIndex) row.quantities.add(0.0);
    row.quantities[colIndex] = value.clamp(0.0, 99999.0);
    // Динамическое создание ячейки: при вводе в последнюю — добавляем новую
    if (colIndex == row.quantities.length - 1 && value > 0) {
      row.quantities.add(0.0);
    }
    _rowsVersion.value++;
    setState(() {});
  }

  void _onLastCellFocused(WriteoffCategory cat, int rowIndex) {
    final rows = _rowsFor(cat);
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final row = rows[rowIndex];
    row.quantities.add(0.0);
    _rowsVersion.value++;
    setState(() {});
  }

  void _setUnit(WriteoffCategory cat, int rowIndex, String unit) {
    final rows = _rowsFor(cat);
    if (rowIndex < 0 || rowIndex >= rows.length) return;
    final row = rows[rowIndex];
    final baseUnit = row.product != null ? (row.product!.unit ?? 'g') : 'pcs';
    rows[rowIndex] = _WriteoffRow(
      product: row.product,
      techCard: row.techCard,
      quantities: List<double>.from(row.quantities),
      unitOverride: unit == baseUnit ? null : unit,
    );
    _rowsVersion.value++;
    setState(() {});
    _saveNow();
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
    final emp = account.currentEmployee;
    final products = _cachedProducts;
    final visibleTc = emp == null
        ? _cachedTechCards
        : _cachedTechCards.where((tc) => emp.canSeeTechCard(tc.sections)).toList();

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
          _addRow(cat, product: p, techCard: null);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
        onSelectTechCard: (tc) {
          _addRow(cat, product: null, techCard: tc);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    );
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

    // Язык при сохранении в систему — текущий язык приложения (выбор языка только при экспорте в файл)
    final lang = loc.currentLanguageCode;

    // Комментарий (сохраняется в документе, переводится при экспорте)
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
    // Для списаний — всегда валидный получатель: шеф или создатель (чтобы документ попал во Входящие)
    final recipientId = chef?.id ?? employee.id;
    final recipientEmail = chef?.email ?? '';

    final payload = _buildPayload(
      establishment: establishment,
      employee: employee,
      category: cat,
      rows: rows,
      lang: lang,
      loc: loc,
    );
    if (comment.isNotEmpty) {
      payload['comment'] = comment;
      payload['commentSourceLang'] = loc.currentLanguageCode;
    }
    final costTotal = _computeCostTotal(rows);
    if (costTotal > 0) {
      payload['costTotal'] = costTotal;
      payload['costCurrency'] = establishment.defaultCurrency;
    }

    final docService = InventoryDocumentService();
    final docSaved = await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: recipientId,
      recipientEmail: recipientEmail,
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('writeoff_saved_to_list') ?? 'Сохранено на экран')),
      );
      final rows = _rowsFor(cat);
      rows.removeWhere((r) => r.total > 0);
      _rowsVersion.value++;
      _savedListVersion.value++;
      setState(() {});
    }
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required WriteoffCategory category,
    required List<_WriteoffRow> rows,
    required String lang,
    required LocalizationService loc,
  }) {
    final header = {
      'establishmentName': establishment.name,
      'employeeName':
          employeeNameWithPositionLine(employee, loc, establishment: establishment),
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

  /// Сумма затрат по списанию (только продукты с ценой; ПФ не учитываются).
  double _computeCostTotal(List<_WriteoffRow> rows) {
    double sum = 0;
    for (final r in rows) {
      if (r.product == null) continue;
      final p = _cachedProducts.where((e) => e.id == r.product!.id).firstOrNull;
      if (p == null) continue;
      final pricePerKg = p.computedPricePerKg ?? p.basePrice;
      if (pricePerKg == null || pricePerKg <= 0) continue;
      final grams = CulinaryUnits.toGrams(
        r.total,
        r.unit,
        gramsPerPiece: p.gramsPerPiece,
      );
      if (grams <= 0) continue;
      sum += (grams / 1000.0) * pricePerKg;
    }
    return sum;
  }

  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    try {
      final excel = Excel.createExcel();
      var sheetName = loc.t('writeoff_excel_sheet');
      if (sheetName.isEmpty || sheetName == 'writeoff_excel_sheet') {
        sheetName = 'Write-off';
      }
      final sheet = excel[sheetName];
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
      excel.setDefaultSheet(sheetName);
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
      case WriteoffCategory.generic:
        return loc.t('writeoff_category_simple') ?? 'Списание';
    }
  }

  Widget _buildSavedList(LocalizationService loc) {
    if (_savedListLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final fmtDate = (DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final doc in _savedWriteoffs) {
      final createdAt = doc['created_at'] != null
          ? (DateTime.tryParse(doc['created_at'].toString()) ?? DateTime.now()).toLocal()
          : DateTime.now();
      final dateKey = fmtDate(createdAt);
      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
      final cat = payload['category']?.toString() ?? 'staff';
      grouped.putIfAbsent(dateKey, () => {});
      grouped[dateKey]!.putIfAbsent(cat, () => []);
      grouped[dateKey]![cat]!.add(doc);
    }
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    if (dateKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('writeoff_saved_empty') ?? 'Нет сохранённых списаний',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSavedWriteoffs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: dateKeys.expand((dateKey) {
          final cats = grouped[dateKey]!;
          final catOrder = [
            'generic',
            'staff',
            'workingThrough',
            'spoilage',
            'breakage',
            'guestRefusal',
          ];
          return [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                dateKey,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...catOrder.where((c) => cats.containsKey(c)).expand((cat) {
              final docs = cats[cat]!..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
              return docs.map((doc) {
                final payload = doc['payload'] as Map<String, dynamic>? ?? {};
                final header = payload['header'] as Map<String, dynamic>? ?? {};
                final emp = header['employeeName'] ?? '—';
                final rows = payload['rows'] as List<dynamic>? ?? [];
                final totalItems = rows.length;
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_tabLabel(WriteoffCategory.values.firstWhere(
                    (c) => c.code == cat,
                    orElse: () => WriteoffCategory.staff,
                  ), loc)),
                  subtitle: Text('$emp • $totalItems ${loc.t('inventory_pos') ?? 'поз.'}'),
                  onTap: () => context.push('/inbox/writeoff/${doc['id']}'),
                );
              });
            }),
          ];
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final ultra = SubscriptionEntitlements.from(
      context.watch<AccountManagerSupabase>().establishment,
    ).hasUltraLevelFeatures;
    final cat = ultra ? _selectedCategory : WriteoffCategory.generic;

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
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: false, label: Text(loc.t('writeoff_create') ?? 'Создать')),
                      ButtonSegment(value: true, label: Text(loc.t('writeoff_saved') ?? 'Сохранённые')),
                    ],
                    selected: {_showSavedList},
                    onSelectionChanged: (s) async {
                      final show = s.first;
                      setState(() => _showSavedList = show);
                      if (show) await _loadSavedWriteoffs();
                    },
                  ),
                ),
                if (!_showSavedList) ...[
                  if (ultra)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: DropdownButtonFormField<WriteoffCategory>(
                            value: _selectedCategory,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            isExpanded: true,
                            alignment: Alignment.center,
                            selectedItemBuilder: (context) =>
                                WriteoffCategory.values
                                    .where((c) => c != WriteoffCategory.generic)
                                    .map((c) => Center(child: Text(_tabLabel(c, loc))))
                                    .toList(),
                            items: WriteoffCategory.values
                                .where((c) => c != WriteoffCategory.generic)
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(_tabLabel(c, loc)),
                                    ))
                                .toList(),
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
                        category: cat,
                        rows: _rowsFor(cat),
                        onAdd: () => _showItemPicker(cat),
                        onSetQuantity: (ri, ci, v) => _setQuantity(cat, ri, ci, v),
                        onSetUnit: (ri, u) => _setUnit(cat, ri, u),
                        onLastCellFocused: (ri) => _onLastCellFocused(cat, ri),
                        onRemove: (i) => _removeRow(cat, i),
                        onSave: () => _save(cat),
                        loc: loc,
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _savedListVersion,
                      builder: (_, __, ___) => _buildSavedList(loc),
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
const double _colUnitCellWidth = 56; // для дропдауна выбора единицы
const double _colTotalWidth = 56;
const double _colQtyWidth = 64; // для отображения 4 знаков
const double _colGap = 6;
const double _colDeleteWidth = 40;

const int _kMinQtyCols = 2;

class _WriteoffTabContent extends StatelessWidget {
  const _WriteoffTabContent({
    required this.category,
    required this.rows,
    required this.onAdd,
    required this.onSetQuantity,
    required this.onSetUnit,
    required this.onLastCellFocused,
    required this.onRemove,
    required this.onSave,
    required this.loc,
  });

  final WriteoffCategory category;
  final List<_WriteoffRow> rows;
  final VoidCallback onAdd;
  final void Function(int rowIndex, int colIndex, double value) onSetQuantity;
  final void Function(int rowIndex, String unit) onSetUnit;
  final void Function(int rowIndex) onLastCellFocused;
  final void Function(int index) onRemove;
  final VoidCallback onSave;
  final LocalizationService loc;

  int get _maxQtyCols => rows.isEmpty ? _kMinQtyCols : rows.map((r) => r.quantities.length).reduce((a, b) => a > b ? a : b);

  /// Ширина фиксированной части: #, Наименование, Мера, Итого (без движения при скролле)
  double _leftWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final base = (w * 0.42).clamp(140.0, 220.0);
    return base + _colGap + _colTotalWidth;
  }

  double _colNameWidth(BuildContext context) =>
      _leftWidth(context) - _colNoWidth - _colGap - _colUnitCellWidth - _colGap - _colTotalWidth;

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = loc.currentLanguageCode;
    final maxCols = _maxQtyCols;
    final leftW = _leftWidth(context);
    final colNameW = _colNameWidth(context);

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
                    // Шапка: фиксировано слева (#, Наименование, Мера, Итого) | скролл справа (1, 2, ... Удалить)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: leftW,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                              bottom: BorderSide(color: theme.dividerColor),
                            ),
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                              SizedBox(width: _colGap),
                              SizedBox(width: colNameW, child: Text(loc.t('inventory_item_name') ?? 'Наименование', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              SizedBox(width: _colGap),
                              SizedBox(width: _colUnitCellWidth, child: Text(loc.t('inventory_unit') ?? 'Ед.', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                              SizedBox(width: _colGap),
                              SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total') ?? 'Итого', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: theme.dividerColor)),
                                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                              ),
                              child: Row(
                                children: [
                                  for (var c = 0; c < maxCols; c++) ...[
                                    if (c > 0) SizedBox(width: _colGap),
                                    SizedBox(width: _colQtyWidth, child: Center(child: Text('${c + 1}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)))),
                                  ],
                                  SizedBox(width: _colGap),
                                  SizedBox(width: _colDeleteWidth),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final rowNum = i + 1;
                          return _WriteoffRowTile(
                            key: ValueKey('row_${r.product?.id ?? r.techCard?.id}_$i'),
                            row: r,
                            rowIndex: i,
                            rowNumber: rowNum,
                            leftWidth: leftW,
                            colNameWidth: colNameW,
                            formatQty: _formatQty,
                            onSetQuantity: onSetQuantity,
                            onSetUnit: onSetUnit,
                            onLastCellFocused: onLastCellFocused,
                            onRemove: onRemove,
                            loc: loc,
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

/// Выбор единицы измерения: г, кг, мл, л, шт (если продукт с gramsPerPiece), упак. (если packageWeightGrams).
class _WriteoffUnitDropdown extends StatelessWidget {
  const _WriteoffUnitDropdown({
    required this.row,
    required this.lang,
    required this.theme,
    required this.onChanged,
  });

  final _WriteoffRow row;
  final String lang;
  final ThemeData theme;
  final void Function(String) onChanged;

  static List<String> _baseUnits(UnitSystem unitSystem) =>
      unitSystem == UnitSystem.imperial
          ? <String>['oz', 'lb', 'fl_oz', 'gal']
          : <String>['g', 'kg', 'ml', 'l'];

  static List<String> _allowedUnits(_WriteoffRow r, UnitSystem unitSystem) {
    if (r.techCard != null) {
      return unitSystem == UnitSystem.imperial
          ? ['pcs', 'oz', 'lb']
          : ['pcs', 'g', 'kg'];
    } // ТТК — порции, можно взвесить
    final p = r.product;
    if (p == null) return _baseUnits(unitSystem);
    final options = List<String>.from(_baseUnits(unitSystem));
    final hasGpp = p.gramsPerPiece != null && p.gramsPerPiece! > 0;
    if (hasGpp) options.add('pcs'); // без дублей
    final hasPkg = p.packageWeightGrams != null && p.packageWeightGrams! > 0;
    if (hasPkg) {
      options.add('pkg');
      options.add('btl');
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final options = _allowedUnits(row, unitPrefs.unitSystem);
    final current = row.unit.trim().toLowerCase();
    final match = options.where((u) => u.toLowerCase() == current).firstOrNull;
    final displayValue = match ?? options.first;
    return DropdownButtonHideUnderline(
      child: Center(
        child: DropdownButton<String>(
          value: displayValue,
          isDense: true,
          isExpanded: false, // компактно: стрелка рядом с текстом
          alignment: Alignment.center,
          icon: const Icon(Icons.arrow_drop_down, size: 18),
          iconSize: 18,
          items: options.map((u) => DropdownMenuItem(
            value: u,
            child: Text(
              u == 'pkg' ? (lang == 'ru' ? 'упак.' : 'pkg')
                  : u == 'btl' ? (lang == 'ru' ? 'бутылка' : 'bottle')
                  : _unitDisplay(u, lang),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          )).toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

/// Строка списания: фиксировано слева (продукт, мера, итого), ячейки количества скроллятся влево-вправо.
class _WriteoffRowTile extends StatefulWidget {
  const _WriteoffRowTile({
    super.key,
    required this.row,
    required this.rowIndex,
    required this.rowNumber,
    required this.leftWidth,
    required this.colNameWidth,
    required this.formatQty,
    required this.onSetQuantity,
    required this.onSetUnit,
    required this.onLastCellFocused,
    required this.onRemove,
    required this.loc,
  });

  final _WriteoffRow row;
  final int rowIndex;
  final int rowNumber;
  final double leftWidth;
  final double colNameWidth;
  final String Function(double) formatQty;
  final void Function(int, int, double) onSetQuantity;
  final void Function(int, String) onSetUnit;
  final void Function(int) onLastCellFocused;
  final void Function(int) onRemove;
  final LocalizationService loc;

  @override
  State<_WriteoffRowTile> createState() => _WriteoffRowTileState();
}

class _WriteoffRowTileState extends State<_WriteoffRowTile> {
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    void doScroll() {
      if (_hScroll.hasClients) {
        _hScroll.animateTo(
          _hScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      doScroll();
      Future.delayed(const Duration(milliseconds: 350), doScroll);
    });
  }

  @override
  void didUpdateWidget(_WriteoffRowTile old) {
    super.didUpdateWidget(old);
    if (old.row.quantities.length < widget.row.quantities.length) {
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final qtyCols = row.quantities.length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: widget.leftWidth,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                  bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                ),
                color: widget.rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: _colNoWidth, child: Text('${widget.rowNumber}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                  SizedBox(width: _colGap),
                  Expanded(
                    child: Text(
                      row.displayName(widget.loc.currentLanguageCode),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                  SizedBox(width: _colGap),
                  SizedBox(
                    width: _colUnitCellWidth,
                    child: _WriteoffUnitDropdown(
                      row: row,
                      lang: widget.loc.currentLanguageCode,
                      theme: theme,
                      onChanged: (u) => widget.onSetUnit(widget.rowIndex, u),
                    ),
                  ),
                  SizedBox(width: _colGap),
                  Container(
                    width: _colTotalWidth,
                    alignment: Alignment.center,
                    child: Text(widget.formatQty(row.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (d) {
                if (!_hScroll.hasClients) return;
                final next = (_hScroll.offset - d.delta.dx).clamp(0.0, _hScroll.position.maxScrollExtent);
                _hScroll.jumpTo(next);
              },
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
                    color: widget.rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ...List.generate(qtyCols, (c) {
                        final isLast = c == qtyCols - 1;
                        final qty = c < row.quantities.length ? row.quantities[c] : 0.0;
                        return Padding(
                          padding: EdgeInsets.only(right: c < qtyCols - 1 ? _colGap : _colGap),
                          child: SizedBox(
                            width: _colQtyWidth,
                            child: _QuantityField(
                              value: qty,
                              onChanged: (v) => widget.onSetQuantity(widget.rowIndex, c, v),
                              onFocusLast: isLast ? () => widget.onLastCellFocused(widget.rowIndex) : null,
                            ),
                          ),
                        );
                      }),
                      SizedBox(width: _colDeleteWidth, child: IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => widget.onRemove(widget.rowIndex), padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                    ],
                  ),
                ),
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
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        isDense: true,
        counterText: '',
      ),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
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

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Expanded(
            child: _segment == 0
                ? ListView.builder(
                    controller: scrollController,
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
