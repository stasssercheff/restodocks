import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Строка бланка инвентаризации: продукт из номенклатуры, единица, список количеств, итого.
class _InventoryRow {
  final Product product;
  final List<double> quantities;

  _InventoryRow({required this.product, required this.quantities});

  String productName(String lang) => product.getLocalizedName(lang);
  String get unit => product.unit ?? 'кг';
  double get total => quantities.fold(0.0, (a, b) => a + b);
}

/// Бланк инвентаризации: продукты автоматически подставляются из номенклатуры заведения.
/// Шапка (заведение, сотрудник, дата, время), таблица со статичными (#, Наименование, Мера)
/// и прокручиваемыми столбцами (Итого, Количество).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ScrollController _vScrollLeft = ScrollController();
  final ScrollController _vScrollRight = ScrollController();
  final List<_InventoryRow> _rows = [];
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    _vScrollLeft.addListener(_syncVLeftToRight);
    _vScrollRight.addListener(_syncVRightToLeft);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNomenclature());
  }

  /// Автоматическая подстановка продуктов из номенклатуры заведения
  Future<void> _loadNomenclature() async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    await store.loadProducts();
    await store.loadNomenclature(estId);
    if (!mounted) return;
    final products = store.getNomenclatureProducts(estId);
    setState(() {
      for (final p in products) {
        if (_rows.any((r) => r.product.id == p.id)) continue;
        _rows.add(_InventoryRow(product: p, quantities: [0.0]));
      }
    });
  }

  @override
  void dispose() {
    _vScrollLeft.removeListener(_syncVLeftToRight);
    _vScrollRight.removeListener(_syncVRightToLeft);
    _vScrollLeft.dispose();
    _vScrollRight.dispose();
    super.dispose();
  }

  void _syncVLeftToRight() {
    if (!_vScrollLeft.hasClients || !_vScrollRight.hasClients) return;
    if ((_vScrollLeft.offset - _vScrollRight.offset).abs() < 2) return;
    _vScrollRight.jumpTo(_vScrollLeft.offset);
  }

  void _syncVRightToLeft() {
    if (!_vScrollLeft.hasClients || !_vScrollRight.hasClients) return;
    if ((_vScrollRight.offset - _vScrollLeft.offset).abs() < 2) return;
    _vScrollLeft.jumpTo(_vScrollRight.offset);
  }

  int get _maxQuantityColumns =>
      _rows.isEmpty ? 1 : _rows.map((r) => r.quantities.length).reduce((a, b) => a > b ? a : b);

  void _addQuantityToRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    setState(() {
      _rows[rowIndex].quantities.add(0.0);
    });
  }

  void _addProduct(Product p) {
    setState(() {
      _rows.add(_InventoryRow(product: p, quantities: [0.0]));
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
    final saved = await docService.save(
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

    bool emailSent = false;
    try {
      final body = _buildEmailBody(payload);
      final res = await SupabaseService().client.functions.invoke(
        'send-inventory-email',
        body: {
          'to': chef.email,
          'subject': loc.t('inventory_email_subject'),
          'body': body,
        },
      );
      if (res.status == 200 && saved != null) {
        await docService.markEmailSent(saved['id'] as String);
        emailSent = true;
      }
    } catch (_) {
      /* Edge Function не настроена или ошибка — fallback на mailto */
    }

    if (!emailSent && mounted) {
      final body = _buildEmailBody(payload);
      final uri = Uri(
        scheme: 'mailto',
        path: chef.email,
        query: _mailtoQuery(
          subject: loc.t('inventory_email_subject'),
          body: body,
        ),
      );
      if (await canLaunchUrl(uri)) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          await launchUrl(uri);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${loc.t('inventory_document_saved')} ${loc.t('inventory_open_mail_manual')}',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_document_saved'))),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${loc.t('inventory_document_saved')} ${loc.t('inventory_email_sent')}',
          ),
        ),
      );
    }
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
      return {
        'productId': r.product.id,
        'productName': r.productName(lang),
        'unit': r.unit,
        'quantities': r.quantities,
        'total': r.total,
      };
    }).toList();
    return {'header': header, 'rows': rows};
  }

  String _buildEmailBody(Map<String, dynamic> payload) {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final sb = StringBuffer();
    sb.writeln('Бланк инвентаризации');
    sb.writeln('Заведение: ${header['establishmentName'] ?? ''}');
    sb.writeln('Сотрудник: ${header['employeeName'] ?? ''}');
    sb.writeln('Дата: ${header['date'] ?? ''}');
    sb.writeln('Время начала: ${header['timeStart'] ?? ''}');
    sb.writeln('Время окончания: ${header['timeEnd'] ?? ''}');
    sb.writeln('');
    sb.writeln('# | Наименование | Мера | Итого | Количество');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i] as Map<String, dynamic>;
      final name = r['productName'] ?? '';
      final unit = r['unit'] ?? '';
      final total = r['total'];
      final qty = (r['quantities'] as List<dynamic>?)?.join(' | ') ?? '';
      sb.writeln('${i + 1} | $name | $unit | $total | $qty');
    }
    return sb.toString();
  }

  String _mailtoQuery({required String subject, required String body}) {
    return 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
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

  Widget _buildHeader(
    LocalizationService loc,
    Establishment? establishment,
    Employee? employee,
  ) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              _headerChip(theme, Icons.store, loc.t('inventory_establishment'), establishment?.name ?? '—'),
              _headerChip(theme, Icons.person, loc.t('inventory_employee'), employee?.fullName ?? '—'),
              InkWell(
                onTap: () => _pickDate(context),
                borderRadius: BorderRadius.circular(8),
                child: _headerChip(
                  theme,
                  Icons.calendar_today,
                  loc.t('inventory_date'),
                  '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                ),
              ),
              _headerChip(
                theme,
                Icons.access_time,
                loc.t('inventory_time_fill'),
                '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'} → '
                '${_endTime != null ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}' : '...'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerChip(ThemeData theme, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }

  static const double _colNoWidth = 28;
  static const double _colUnitWidth = 48;
  static const double _colTotalWidth = 56;
  static const double _colQtyWidth = 64;

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _leftWidth(context),
          child: ListView(
            controller: _vScrollLeft,
            shrinkWrap: true,
            children: [
              _buildLeftHeader(loc),
              ...List.generate(_rows.length, (i) => _buildLeftRow(loc, i)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _colTotalWidth + _maxQuantityColumns * _colQtyWidth + 48,
              child: ListView(
                controller: _vScrollRight,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                children: [
                  _buildRightHeader(loc),
                  ...List.generate(_rows.length, (i) => _buildRightRow(loc, i)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftHeader(LocalizationService loc) {
    final theme = Theme.of(context);
    final nameW = _colNameWidth(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          SizedBox(width: nameW, child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1)),
          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
        ],
      ),
    );
  }

  Widget _buildLeftRow(LocalizationService loc, int index) {
    final theme = Theme.of(context);
    final row = _rows[index];
    final nameW = _colNameWidth(context);
    return InkWell(
      onLongPress: () {
        if (_completed) return;
        _removeRow(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          color: index.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
        ),
        child: Row(
          children: [
            SizedBox(width: _colNoWidth, child: Text('${index + 1}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            SizedBox(
              width: nameW,
              child: Text(
                row.productName(loc.currentLanguageCode),
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            SizedBox(width: _colUnitWidth, child: Text(row.unit, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildRightHeader(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          Expanded(child: Text(loc.t('inventory_quantity'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
        ],
      ),
    );
  }

  Widget _buildRightRow(LocalizationService loc, int rowIndex) {
    final theme = Theme.of(context);
    final row = _rows[rowIndex];
    final maxCols = _maxQuantityColumns;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        color: rowIndex.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          Container(
            width: _colTotalWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(_formatQty(row.total), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          ...List.generate(
            maxCols,
            (colIndex) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: SizedBox(
                width: _colQtyWidth - 2,
                child: colIndex < row.quantities.length
                    ? (_completed
                        ? Text(_formatQty(row.quantities[colIndex]), style: theme.textTheme.bodyMedium)
                        : _QtyCell(
                            value: row.quantities[colIndex],
                            onChanged: (v) => _setQuantity(rowIndex, colIndex, v),
                          ))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          if (!_completed)
            SizedBox(
              width: 28,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => _addQuantityToRow(rowIndex),
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
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  Widget _buildFooter(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (!_completed) ...[
              OutlinedButton.icon(
                onPressed: () => _showProductPicker(context, loc),
                icon: const Icon(Icons.add, size: 20),
                label: Text(loc.t('inventory_add_product')),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _completed ? null : () => _complete(context),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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
        SnackBar(content: Text('${loc.t('nomenclature')}: нет продуктов')),
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
