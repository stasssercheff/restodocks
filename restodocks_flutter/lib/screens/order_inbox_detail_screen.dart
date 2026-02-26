import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../services/inventory_download.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр заказа продуктов из входящих: данные с ценами и итогом, сохранение PDF/Excel.
class OrderInboxDetailScreen extends StatefulWidget {
  const OrderInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<OrderInboxDetailScreen> createState() => _OrderInboxDetailScreenState();
}

class _OrderInboxDetailScreenState extends State<OrderInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final doc = await OrderDocumentService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      if (doc == null) _error = 'Документ не найден';
    });
  }

  Future<void> _showSaveFormatDialog() async {
    final doc = _doc;
    final loc = context.read<LocalizationService>();
    if (doc == null) return;

    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final dateStr = header['createdAt'] != null
        ? DateFormat('yyyy-MM-dd').format(DateTime.tryParse(header['createdAt'].toString()) ?? DateTime.now())
        : DateFormat('yyyy-MM-dd').format(DateTime.now());
    final supplier = (header['supplierName'] ?? 'order').toString().replaceAll(RegExp(r'[^\w\-.\s]'), '_');

    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('download') ?? 'Сохранить'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF'),
              onTap: () => Navigator.of(ctx).pop('pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel'),
              onTap: () => Navigator.of(ctx).pop('excel'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;

    try {
      if (format == 'pdf') {
        final bytes = await OrderListExportService.buildOrderPdfBytesFromPayload(
          payload: payload,
          t: loc.t,
        );
        await saveFileBytes('order_${supplier}_$dateStr.pdf', bytes);
      } else {
        final bytes = await OrderListExportService.buildOrderExcelBytesFromPayload(
          payload: payload,
          t: loc.t,
        );
        await saveFileBytes('order_${supplier}_$dateStr.xlsx', bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Документ не найден', style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back') ?? 'Назад')),
            ],
          ),
        ),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    final grandTotal = (payload['grandTotal'] as num?)?.toDouble() ?? 0;
    final comment = (payload['comment'] as String?)?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('product_order')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Сохранить',
            onPressed: _showSaveFormatDialog,
          ),
          appBarHomeButton(context),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(loc, header),
            const SizedBox(height: 24),
            Text(
              loc.t('order_export_list') ?? 'Список',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildTable(theme, loc, items, grandTotal),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${loc.t('order_list_comment')}: $comment',
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalizationService loc, Map<String, dynamic> header) {
    final createdAt = header['createdAt'] != null ? DateTime.tryParse(header['createdAt'].toString()) : null;
    final orderFor = header['orderForDate'] != null ? DateTime.tryParse(header['orderForDate'].toString()) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(loc.t('inbox_header_employee') ?? 'Кто отправил', header['employeeName'] ?? '—'),
        _row(loc.t('order_export_date_time') ?? 'Дата отправки', createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt) : '—'),
        _row(loc.t('order_export_to') ?? 'Поставщик', header['supplierName'] ?? '—'),
        _row(loc.t('order_export_from') ?? 'Заведение', header['establishmentName'] ?? '—'),
        _row(loc.t('order_export_order_for') ?? 'На дату', orderFor != null ? DateFormat('dd.MM.yyyy').format(orderFor) : '—'),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTable(ThemeData theme, LocalizationService loc, List<dynamic> items, double grandTotal) {
    return Table(
      border: TableBorder.all(color: theme.dividerColor),
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(0.5),
        3: FlexColumnWidth(0.5),
        4: FlexColumnWidth(0.7),
        5: FlexColumnWidth(0.7),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _cell(theme, loc.t('order_export_no') ?? '#', bold: true),
            _cell(theme, loc.t('inventory_item_name'), bold: true),
            _cell(theme, loc.t('order_list_unit'), bold: true),
            _cell(theme, loc.t('order_list_quantity'), bold: true),
            _cell(theme, loc.t('order_list_unit_price') ?? 'Цена за ед.', bold: true),
            _cell(theme, loc.t('order_list_line_total') ?? 'Сумма', bold: true),
          ],
        ),
        ...items.asMap().entries.map((e) {
          final item = e.value as Map<String, dynamic>;
          return TableRow(
            children: [
              _cell(theme, '${e.key + 1}'),
              _cell(theme, (item['productName'] ?? '').toString()),
              _cell(theme, (item['unit'] ?? '').toString()),
              _cell(theme, _fmtNum(item['quantity'])),
              _cell(theme, _fmtNum(item['pricePerUnit'])),
              _cell(theme, _fmtNum(item['lineTotal'])),
            ],
          );
        }),
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _cell(theme, '', bold: true),
            _cell(theme, loc.t('order_list_grand_total') ?? 'Итого:', bold: true),
            _cell(theme, '', bold: true),
            _cell(theme, '', bold: true),
            _cell(theme, '', bold: true),
            _cell(theme, _fmtNum(grandTotal), bold: true),
          ],
        ),
      ],
    );
  }

  Widget _cell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null),
      ),
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      if (v == v.truncateToDouble()) return v.toInt().toString();
      return v.toStringAsFixed(2);
    }
    return v.toString();
  }
}
