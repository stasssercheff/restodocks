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

/// Бланк инвентаризации по макету: шапка (заведение, сотрудник, дата, время), таблица с
/// фиксированными столбцами (#, Наименование, Мера, Итого) и добавляемыми столбцами Количество.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ScrollController _vScrollLeft = ScrollController();
  final ScrollController _vScrollRight = ScrollController();
  final List<_InventoryRow> _rows = [];
  int _quantityColumnCount = 1;
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

  void _addQuantityColumn() {
    setState(() {
      _quantityColumnCount++;
      for (final r in _rows) {
        while (r.quantities.length < _quantityColumnCount) {
          r.quantities.add(0.0);
        }
      }
    });
  }

  void _addProduct(Product p) {
    setState(() {
      final qty = List<double>.filled(_quantityColumnCount, 0.0);
      _rows.add(_InventoryRow(product: p, quantities: qty));
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerField(
            label: loc.t('inventory_establishment'),
            hint: loc.t('inventory_establishment_hint'),
            value: establishment?.name ?? '—',
          ),
          const SizedBox(height: 12),
          _headerField(
            label: loc.t('inventory_employee'),
            hint: loc.t('inventory_employee_hint'),
            value: employee?.fullName ?? '—',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _headerField(
                  label: loc.t('inventory_date'),
                  hint: loc.t('inventory_date_hint'),
                  value: '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                  onTap: () => _pickDate(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _headerField(
                  label: loc.t('inventory_time_start'),
                  value: _startTime != null
                      ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
                      : '—',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _headerField(
                  label: loc.t('inventory_time_end'),
                  value: _endTime != null
                      ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
                      : '—',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerField({
    required String label,
    required String value,
    String? hint,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
            ),
            if (hint != null)
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  static const double _colNoWidth = 36;
  static const double _colNameWidth = 180;
  static const double _colUnitWidth = 72;
  static const double _colTotalWidth = 80;
  static const double _colQtyWidth = 88;
  static const double _leftWidth = _colNoWidth + _colNameWidth + _colUnitWidth + _colTotalWidth;

  Widget _buildTable(LocalizationService loc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _leftWidth,
          child: ListView(
            controller: _vScrollLeft,
            shrinkWrap: true,
            children: [
              _buildLeftHeader(loc),
              ...List.generate(_rows.length, (i) => _buildLeftRow(loc, i)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _quantityColumnCount * _colQtyWidth + 56,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium)),
          SizedBox(width: _colNameWidth, child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium)),
          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit'), style: theme.textTheme.labelMedium)),
          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total'), style: theme.textTheme.labelMedium)),
        ],
      ),
    );
  }

  Widget _buildLeftRow(LocalizationService loc, int index) {
    final theme = Theme.of(context);
    final row = _rows[index];
    return InkWell(
      onLongPress: () {
        if (_completed) return;
        _removeRow(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
          color: index.isEven ? null : theme.colorScheme.surfaceContainerLowest,
        ),
        child: Row(
          children: [
            SizedBox(width: _colNoWidth, child: Text('${index + 1}', style: theme.textTheme.bodyMedium)),
            SizedBox(
              width: _colNameWidth,
              child: Text(
                row.productName(loc.currentLanguageCode),
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            SizedBox(width: _colUnitWidth, child: Text(row.unit, style: theme.textTheme.bodySmall)),
            SizedBox(
              width: _colTotalWidth,
              child: Text(
                _formatQty(row.total),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightHeader(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          ...List.generate(
            _quantityColumnCount,
            (i) => SizedBox(
              width: _colQtyWidth,
              child: Text(
                '${loc.t('inventory_quantity')} ${i + 1}',
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: _completed
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _addQuantityColumn,
                    tooltip: loc.t('inventory_add_column'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightRow(LocalizationService loc, int rowIndex) {
    final theme = Theme.of(context);
    final row = _rows[rowIndex];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: rowIndex.isEven ? null : theme.colorScheme.surfaceContainerLowest,
      ),
      child: Row(
        children: [
          ...List.generate(
            row.quantities.length,
            (colIndex) => SizedBox(
              width: _colQtyWidth,
              child: _completed
                  ? Text(_formatQty(row.quantities[colIndex]), style: theme.textTheme.bodyMedium)
                  : _QtyCell(
                      value: row.quantities[colIndex],
                      onChanged: (v) => _setQuantity(rowIndex, colIndex, v),
                    ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  Widget _buildFooter(LocalizationService loc) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_completed) ...[
            OutlinedButton.icon(
              onPressed: () => _showProductPicker(context, loc),
              icon: const Icon(Icons.add),
              label: Text(loc.t('inventory_add_product')),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _completed ? null : () => _complete(context),
            child: Text(loc.t('inventory_complete')),
          ),
        ],
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
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(),
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
    final theme = Theme.of(context);
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
