import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';

/// Строка бланка: продукт из номенклатуры, полуфабрикат (ТТК) или свободная строка (например, с чека).
class _InventoryRow {
  final Product? product;
  final TechCard? techCard;
  /// Свободная строка (распознанный чек): когда product и techCard оба null.
  final String? freeName;
  final String? freeUnit;
  final List<double> quantities;

  _InventoryRow({
    this.product,
    this.techCard,
    this.freeName,
    this.freeUnit,
    required this.quantities,
  })  : assert(product != null || techCard != null || (freeName != null && freeName.isNotEmpty)),
        assert(product == null || techCard == null);

  bool get isPf => techCard != null;
  bool get isFree => product == null && techCard == null;

  String productName(String lang) {
    if (product != null) return product!.getLocalizedName(lang);
    if (techCard != null) return '${techCard!.getLocalizedDishName(lang)} (ПФ)';
    return freeName ?? '';
  }

  String get unit => product?.unit ?? freeUnit ?? 'g';
  String unitDisplay(String lang) =>
      isPf ? 'порц.' : CulinaryUnits.displayName(unit.toLowerCase(), lang);

  double get total => quantities.fold(0.0, (a, b) => a + b);
}

enum _InventorySort { alphabet, lastAdded }

/// Фильтр по типу строк: все, только продукты, только ПФ.
enum _InventoryBlockFilter { all, productsOnly, pfOnly }

/// Бланк инвентаризации: продукты из номенклатуры и полуфабрикаты (ПФ) в одном документе.
/// Шапка (заведение, сотрудник, дата, время), таблица (#, Наименование, Мера, Итого, Количество).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ScrollController _hScroll = ScrollController();
  final List<_InventoryRow> _rows = [];
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _completed = false;
  _InventorySort _sortMode = _InventorySort.lastAdded;
  _InventoryBlockFilter _blockFilter = _InventoryBlockFilter.all;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNomenclature());
  }

  /// Индексы строк-продуктов и свободных (номенклатура + с чека), отсортированы по выбранному режиму.
  List<int> get _productIndices {
    final indices = List.generate(_rows.length, (i) => i).where((i) => !_rows[i].isPf).toList();
    if (_sortMode == _InventorySort.alphabet) {
      final lang = context.read<LocalizationService>().currentLanguageCode;
      indices.sort((a, b) => _rows[a].productName(lang).toLowerCase().compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => b.compareTo(a));
    }
    return indices;
  }

  /// Индексы строк-ПФ (из ТТК), отсортированы по выбранному режиму.
  List<int> get _pfIndices {
    final indices = List.generate(_rows.length, (i) => i).where((i) => _rows[i].isPf).toList();
    if (_sortMode == _InventorySort.alphabet) {
      final lang = context.read<LocalizationService>().currentLanguageCode;
      indices.sort((a, b) => _rows[a].productName(lang).toLowerCase().compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => b.compareTo(a));
    }
    return indices;
  }

  /// Порядок отображения: сначала продукты, потом ПФ (для обратной совместимости с нумерацией в Excel).
  List<int> get _displayOrder => [..._productIndices, ..._pfIndices];

  /// Автоматическая подстановка: номенклатура заведения + полуфабрикаты (ТТК с типом ПФ).
  Future<void> _loadNomenclature() async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    await store.loadProducts();
    await store.loadNomenclature(estId);
    final techCards = await techCardSvc.getTechCardsForEstablishment(estId);
    if (!mounted) return;
    final products = store.getNomenclatureProducts(estId);
    final pfOnly = techCards.where((tc) => tc.isSemiFinished).toList();
    setState(() {
      for (final p in products) {
        if (_rows.any((r) => r.product?.id == p.id)) continue;
        _rows.add(_InventoryRow(product: p, techCard: null, quantities: [0.0]));
      }
      for (final tc in pfOnly) {
        if (_rows.any((r) => r.techCard?.id == tc.id)) continue;
        _rows.add(_InventoryRow(product: null, techCard: tc, quantities: [0.0]));
      }
    });
  }

  /// Добавить строки из распознанного чека (ИИ).
  void _addReceiptLines(List<ReceiptLine> lines) {
    setState(() {
      for (final line in lines) {
        if (line.productName.trim().isEmpty) continue;
        final qty = line.quantity > 0 ? line.quantity : 1.0;
        final unit = (line.unit ?? 'g').trim().isEmpty ? 'g' : (line.unit ?? 'g');
        _rows.add(_InventoryRow(
          product: null,
          techCard: null,
          freeName: line.productName.trim(),
          freeUnit: unit,
          quantities: [qty],
        ));
      }
    });
  }

  Future<void> _scanReceipt(BuildContext context, LocalizationService loc) async {
    if (_completed) return;
    final imageService = ImageService();
    final xFile = await imageService.pickImageFromGallery();
    if (xFile == null || !mounted) return;
    final bytes = await imageService.xFileToBytes(xFile);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    final ai = context.read<AiService>();
    final result = await ai.recognizeReceipt(bytes);
    if (!mounted) return;
    if (result == null || result.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('inventory_receipt_scan_empty'))),
      );
      return;
    }
    _addReceiptLines(result.lines);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.t('inventory_receipt_scan_added').replaceAll('%s', '${result.lines.length}'))),
    );
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  int get _maxQuantityColumns {
    if (_rows.isEmpty) return 1;
    return _rows.map((r) => r.isPf ? 1 : r.quantities.length).reduce((a, b) => a > b ? a : b);
  }

  void _addQuantityToRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    if (_rows[rowIndex].isPf) return; // только продукты и свободные строки
    setState(() {
      _rows[rowIndex].quantities.add(0.0);
    });
  }

  void _addColumnToAll() {
    setState(() {
      for (final r in _rows) {
        if (!r.isPf) r.quantities.add(0.0);
      }
    });
  }

  void _addProduct(Product p) {
    setState(() {
      _rows.add(_InventoryRow(product: p, techCard: null, quantities: [0.0]));
    });
  }

  void _setQuantity(int rowIndex, int colIndex, double value) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.quantities.length) return;
    setState(() {
      row.quantities[colIndex] = value;
    });
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: Locale(loc.currentLanguageCode),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _complete(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('inventory_complete_confirm')),
        content: Text(loc.t('inventory_complete_confirm_detail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('inventory_complete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (establishment == null || employee == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_no_chef'))),
        );
      }
      return;
    }

    final chefs = await account.getExecutiveChefsForEstablishment(establishment.id);
    if (chefs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_no_chef'))),
        );
      }
      return;
    }

    final chef = chefs.first;
    final endTime = TimeOfDay.now();
    final payload = _buildPayload(
      establishment: establishment,
      employee: employee,
      endTime: endTime,
      lang: loc.currentLanguageCode,
    );
    final docService = InventoryDocumentService();
    await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: chef.id,
      recipientEmail: chef.email,
      payload: payload,
    );

    if (mounted) {
      setState(() {
        _endTime = endTime;
        _completed = true;
      });
    }

    // Генерация Excel и скачивание без почтового клиента
    try {
      final bytes = _buildExcelBytes(payload, loc);
      if (bytes != null && bytes.isNotEmpty && mounted) {
        await _downloadExcel(bytes, payload, loc);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('inventory_document_saved')} (Excel: ${e.toString()})')),
        );
      }
    }
  }

  /// Столбцы Excel: номер, наименование, мера, итоговое количество, данные при заполнении (1, 2, ...)
  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final maxCols = _maxQuantityColumns;
    try {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final fillLabel = loc.t('inventory_excel_fill_data');
      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }
      sheet.appendRow(headerCells);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total.toDouble()),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? (quantities[c] as num?)?.toDouble() ?? 0.0 : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet.appendRow(rowCells);
      }
      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadExcel(List<int> bytes, Map<String, dynamic> payload, LocalizationService loc) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ?? DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.xlsx';
    await saveFileBytes(fileName, bytes);
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required TimeOfDay endTime,
    required String lang,
  }) {
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'timeStart': _startTime != null
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
          : null,
      'timeEnd': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
    final rows = _rows.map((r) {
      final id = r.product != null
          ? r.product!.id
          : r.techCard != null
              ? 'pf_${r.techCard!.id}'
              : 'free_${_rows.indexOf(r)}';
      return {
        'productId': id,
        'productName': r.productName(lang),
        'unit': r.unitDisplay(lang),
        'quantities': r.quantities,
        'total': r.total,
      };
    }).toList();
    return {'header': header, 'rows': rows};
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inventory_blank_title')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(loc, establishment, employee),
          const Divider(height: 1),
          Expanded(
            child: _buildTable(loc),
          ),
          const Divider(height: 1),
          _buildFooter(loc),
        ],
      ),
    );
  }

  /// Компактная шапка: на узком экране (телефон) фильтры выносятся во вторую строку, чтобы не обрезались.
  Widget _buildHeader(
    LocalizationService loc,
    Establishment? establishment,
    Employee? employee,
  ) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final filterDropdown = !_completed && _rows.isNotEmpty
        ? DropdownButtonHideUnderline(
            child: DropdownButton<_InventoryBlockFilter>(
              value: _blockFilter,
              isExpanded: narrow,
              isDense: true,
              icon: const Icon(Icons.filter_list, size: 18),
              items: [
                DropdownMenuItem(value: _InventoryBlockFilter.all, child: Text(loc.t('inventory_filter_all'), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: _InventoryBlockFilter.productsOnly, child: Text(loc.t('inventory_block_products'), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: _InventoryBlockFilter.pfOnly, child: Text(loc.t('inventory_block_pf'), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _blockFilter = v ?? _InventoryBlockFilter.all),
            ),
          )
        : null;
    final sortDropdown = !_completed && _rows.isNotEmpty
        ? DropdownButtonHideUnderline(
            child: DropdownButton<_InventorySort>(
              value: _sortMode,
              isExpanded: narrow,
              isDense: true,
              icon: const Icon(Icons.sort, size: 18),
              items: [
                DropdownMenuItem(value: _InventorySort.alphabet, child: Text(loc.t('inventory_sort_alphabet'), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: _InventorySort.lastAdded, child: Text(loc.t('inventory_sort_last_added'), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _sortMode = v ?? _InventorySort.lastAdded),
            ),
          )
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: narrow
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          establishment?.name ?? '—',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => _pickDate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (filterDropdown != null && sortDropdown != null) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showFiltersSortSheet(context, loc),
                        icon: const Icon(Icons.filter_list, size: 18),
                        label: Text(loc.t('inventory_filters_sort'), style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  Icon(Icons.store, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      establishment?.name ?? '—',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => _pickDate(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (filterDropdown != null) ...[
                    const SizedBox(width: 6),
                    SizedBox(width: 130, child: filterDropdown),
                    const SizedBox(width: 4),
                    SizedBox(width: 120, child: sortDropdown),
                  ],
                ],
              ),
      ),
    );
  }

  void _showFiltersSortSheet(BuildContext context, LocalizationService loc) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(loc.t('inventory_filters_sort'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                Text(loc.t('inventory_filter_label'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                ..._InventoryBlockFilter.values.map((v) {
                  final label = v == _InventoryBlockFilter.all
                      ? loc.t('inventory_filter_all')
                      : v == _InventoryBlockFilter.productsOnly
                          ? loc.t('inventory_block_products')
                          : loc.t('inventory_block_pf');
                  return ListTile(
                    dense: true,
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    leading: Radio<_InventoryBlockFilter>(
                      value: v,
                      groupValue: _blockFilter,
                      onChanged: (val) => setState(() => _blockFilter = val ?? _blockFilter),
                    ),
                    onTap: () => setState(() => _blockFilter = v),
                  );
                }),
                const SizedBox(height: 8),
                Text(loc.t('inventory_sort_label'), style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                ..._InventorySort.values.map((v) {
                  final label = v == _InventorySort.alphabet ? loc.t('inventory_sort_alphabet') : loc.t('inventory_sort_last_added');
                  return ListTile(
                    dense: true,
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    leading: Radio<_InventorySort>(
                      value: v,
                      groupValue: _sortMode,
                      onChanged: (val) => setState(() => _sortMode = val ?? _sortMode),
                    ),
                    onTap: () => setState(() => _sortMode = v),
                  );
                }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(loc.t('close')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const double _colNoWidth = 28;
  static const double _colUnitWidth = 48;
  static const double _colTotalWidth = 56;
  static const double _colQtyWidth = 64;
  static const double _colGap = 10;

  double _leftWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w * 0.42).clamp(140.0, 200.0);
  }

  double _colNameWidth(BuildContext context) =>
      _leftWidth(context) - _colNoWidth - _colUnitWidth;

  Widget _buildTable(LocalizationService loc) {
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('inventory_empty_hint'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _showProductPicker(context, loc),
                icon: const Icon(Icons.add),
                label: Text(loc.t('inventory_add_product')),
              ),
            ],
          ),
        ),
      );
    }
    final leftW = _leftWidth(context);
    final screenW = MediaQuery.of(context).size.width;
    final rightW = _colTotalWidth + _colGap + _maxQuantityColumns * (_colQtyWidth + _colGap) + 48;
    final totalW = (leftW + rightW).clamp(screenW, double.infinity);
    return Scrollbar(
      thumbVisibility: true,
      controller: _hScroll,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _hScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: totalW),
            child: SizedBox(
              width: totalW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeaderRow(loc),
                  if (_blockFilter != _InventoryBlockFilter.pfOnly && _productIndices.isNotEmpty) ...[
                    _buildSectionHeader(loc, loc.t('inventory_block_products')),
                    ..._productIndices.asMap().entries.map((e) => _buildDataRow(loc, e.value, e.key + 1)),
                  ],
                  if (_blockFilter != _InventoryBlockFilter.productsOnly && _pfIndices.isNotEmpty) ...[
                    _buildSectionHeader(loc, loc.t('inventory_block_pf')),
                    ..._pfIndices.asMap().entries.map((e) {
                      final rowNum = _blockFilter == _InventoryBlockFilter.pfOnly ? e.key + 1 : _productIndices.length + e.key + 1;
                      return _buildDataRow(loc, e.value, rowNum);
                    }),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(LocalizationService loc, String title) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    final nameW = _colNameWidth(context);
    final qtyColsW = _maxQuantityColumns * (_colQtyWidth + _colGap) + 28;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: nameW, child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1)),
          const SizedBox(width: _colGap),
          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: qtyColsW, child: Text(loc.t('inventory_quantity'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildDataRow(LocalizationService loc, int actualIndex, int rowNumber) {
    final theme = Theme.of(context);
    final row = _rows[actualIndex];
    final nameW = _colNameWidth(context);
    final maxCols = _maxQuantityColumns;
    final qtyCols = row.isPf ? 1 : row.quantities.length;
    return InkWell(
      onLongPress: () {
        if (_completed) return;
        _removeRow(actualIndex);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          color: rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            SizedBox(width: _colGap),
            SizedBox(
              width: nameW,
              child: Text(
                row.productName(loc.currentLanguageCode),
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            SizedBox(width: _colGap),
            SizedBox(width: _colUnitWidth, child: Text(row.unitDisplay(loc.currentLanguageCode), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
            SizedBox(width: _colGap),
            Container(
              width: _colTotalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_formatQty(row.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: _colGap),
            ...List.generate(
              maxCols,
              (colIndex) => Padding(
                padding: EdgeInsets.only(right: colIndex < maxCols - 1 ? _colGap : 0),
                child: SizedBox(
                  width: _colQtyWidth,
                  child: colIndex < qtyCols
                      ? (_completed
                          ? Text(_formatQty(row.quantities[colIndex]), style: theme.textTheme.bodyMedium)
                          : _QtyCell(
                              value: row.quantities[colIndex],
                              onChanged: (v) => _setQuantity(actualIndex, colIndex, v),
                            ))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
            if (!_completed && !row.isPf)
              SizedBox(
                width: 28,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _addQuantityToRow(actualIndex),
                  tooltip: loc.t('inventory_add_column_hint'),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  /// Компактный нижний блок: не перекрывает таблицу, минимум высоты.
  Widget _buildFooter(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!_completed) ...[
              IconButton.filledTonal(
                onPressed: () => _showProductPicker(context, loc),
                icon: const Icon(Icons.add, size: 20),
                tooltip: loc.t('inventory_add_product'),
                style: IconButton.styleFrom(padding: const EdgeInsets.all(10), minimumSize: const Size(40, 40)),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                onPressed: () => _scanReceipt(context, loc),
                icon: const Icon(Icons.document_scanner_outlined, size: 20),
                tooltip: loc.t('inventory_scan_receipt'),
                style: IconButton.styleFrom(padding: const EdgeInsets.all(10), minimumSize: const Size(40, 40)),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: loc.t('inventory_add_column_hint'),
                child: IconButton.filledTonal(
                  onPressed: _rows.isEmpty ? null : _addColumnToAll,
                  icon: const Icon(Icons.add_chart, size: 20),
                  tooltip: loc.t('inventory_add_column'),
                  style: IconButton.styleFrom(padding: const EdgeInsets.all(10), minimumSize: const Size(40, 40)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _completed ? null : () => _complete(context),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                child: Text(loc.t('inventory_complete')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductPicker(BuildContext context, LocalizationService loc) async {
    final productStore = context.read<ProductStoreSupabase>();
    await productStore.loadProducts();
    if (!mounted) return;

    final products = productStore.allProducts;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('nomenclature')}: ${loc.t('no_products')}')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ProductPickerSheet(
        products: products,
        loc: loc,
        onSelect: (p) {
          _addProduct(p);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

class _QtyCell extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;

  const _QtyCell({required this.value, required this.onChanged});

  @override
  State<_QtyCell> createState() => _QtyCellState();
}

class _QtyCellState extends State<_QtyCell> {
  late TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue(widget.value));
  }

  @override
  void didUpdateWidget(_QtyCell old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _controller.text = _displayValue(widget.value);
    }
  }

  String _displayValue(double v) {
    if (v == 0) return '';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      onChanged: (s) {
        final v = double.tryParse(s.replaceFirst(',', '.')) ?? 0;
        widget.onChanged(v);
      },
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<Product> products;
  final LocalizationService loc;
  final void Function(Product) onSelect;

  const _ProductPickerSheet({
    required this.products,
    required this.loc,
    required this.onSelect,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';
  List<Product> get _filtered {
    if (_query.isEmpty) return widget.products;
    final q = _query.toLowerCase();
    final lang = widget.loc.currentLanguageCode;
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.getLocalizedName(lang).toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: widget.loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final p = _filtered[i];
                return ListTile(
                  title: Text(p.getLocalizedName(widget.loc.currentLanguageCode)),
                  subtitle: Text('${p.category} · ${p.unit ?? '—'}'),
                  onTap: () => widget.onSelect(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
