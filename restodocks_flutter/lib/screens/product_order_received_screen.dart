import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/inventory_download.dart';
import '../services/services.dart';

/// Полученные и отправленные заказы продуктов: просмотр и скачивание.
class ProductOrderReceivedScreen extends StatefulWidget {
  const ProductOrderReceivedScreen({super.key});

  @override
  State<ProductOrderReceivedScreen> createState() => _ProductOrderReceivedScreenState();
}

class _ProductOrderReceivedScreenState extends State<ProductOrderReceivedScreen> {
  List<Map<String, dynamic>> _orders = [];
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
    try {
      final account = context.read<AccountManagerSupabase>();
      final chefId = account.currentEmployee?.id;
      if (chefId == null) {
        setState(() {
          _loading = false;
          _error = 'Не авторизован';
        });
        return;
      }

      final docs = await OrderDocumentService().listForChef(chefId);

      if (mounted) {
        setState(() {
          _orders = docs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishmentName = account.establishment?.name ?? '—';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('product_order')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: _buildBody(loc, establishmentName),
    );
  }

  Widget _buildBody(LocalizationService loc, String establishmentName) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('product_order_received_empty') ?? 'Отправленные заказы будут отображаться здесь',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text(loc.t('inbox_header_date') ?? 'Дата', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_section') ?? 'Цех', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_employee') ?? 'Сотрудник', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_supplier') ?? 'Поставщик', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final order = _orders[i];
                return _OrderCard(
                  order: order,
                  establishmentName: establishmentName,
                  loc: loc,
                  onTap: () => _showOrderDetails(context, order, loc),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> doc, LocalizationService loc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final createdAt = DateTime.tryParse(doc['created_at']?.toString() ?? '') ?? DateTime.now();
    final employeeName = header['employeeName'] ?? '—';
    final establishmentName = header['establishmentName'] ?? '—';
    final supplierName = header['supplierName'] ?? '—';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.t('order_details') ?? 'Детали заказа', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _detailRow(ctx, loc.t('inbox_header_date') ?? 'Дата', DateFormat('dd.MM.yyyy HH:mm').format(createdAt)),
              _detailRow(ctx, loc.t('inbox_header_section') ?? 'Цех', establishmentName),
              _detailRow(ctx, loc.t('inbox_header_employee') ?? 'Сотрудник', employeeName),
              _detailRow(ctx, loc.t('inbox_header_supplier') ?? 'Поставщик', supplierName),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildOrderTable(ctx, loc, rows),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(loc.t('download') ?? 'Скачать'),
                onPressed: () => _downloadOrder(doc, loc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildOrderTable(BuildContext context, LocalizationService loc, List<dynamic> rows) {
    final theme = Theme.of(context);
    return Table(
      border: TableBorder.all(color: theme.dividerColor),
      columnWidths: const {0: FlexColumnWidth(2), 1: FixedColumnWidth(80), 2: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _tableCell(theme, loc.t('inventory_item_name'), bold: true),
            _tableCell(theme, loc.t('order_list_unit'), bold: true),
            _tableCell(theme, loc.t('order_list_quantity'), bold: true),
          ],
        ),
        ...rows.map((r) {
          final m = r as Map<String, dynamic>;
          return TableRow(
            children: [
              _tableCell(theme, (m['productName'] ?? '').toString()),
              _tableCell(theme, (m['unit'] ?? '').toString()),
              _tableCell(theme, _fmtNum(m['quantity'])),
            ],
          );
        }),
      ],
    );
  }

  Widget _tableCell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return v.toString();
  }

  Future<void> _downloadOrder(Map<String, dynamic> doc, LocalizationService loc) async {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    try {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([TextCellValue(header['listName'] ?? 'Заказ')]);
      sheet.appendRow([TextCellValue('${loc.t('inbox_header_supplier') ?? 'Поставщик'}: ${header['supplierName'] ?? '—'}')]);
      sheet.appendRow([TextCellValue('${loc.t('inbox_header_date') ?? 'Дата'}: ${header['date'] ?? '—'}')]);
      sheet.appendRow([TextCellValue('${loc.t('inbox_header_employee') ?? 'Сотрудник'}: ${header['employeeName'] ?? '—'}')]);
      sheet.appendRow([]);

      sheet.appendRow([
        TextCellValue(loc.t('inventory_item_name')),
        TextCellValue(loc.t('order_list_unit')),
        TextCellValue(loc.t('order_list_quantity')),
      ]);
      for (final r in rows) {
        final m = r as Map<String, dynamic>;
        final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
        sheet.appendRow([
          TextCellValue((m['productName'] ?? '').toString()),
          TextCellValue((m['unit'] ?? '').toString()),
          DoubleCellValue(qty),
        ]);
      }

      final out = excel.encode();
      if (out != null && out.isNotEmpty) {
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(doc['created_at']?.toString() ?? '') ?? DateTime.now());
        await saveFileBytes('order_$dateStr.xlsx', out);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл Excel сохранён')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.establishmentName,
    required this.loc,
    required this.onTap,
  });

  final Map<String, dynamic> order;
  final String establishmentName;
  final LocalizationService loc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payload = order['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();
    final dateStr = DateFormat('dd.MM.yyyy').format(createdAt);
    final employeeName = header['employeeName'] ?? '—';
    final supplier = header['supplierName'] ?? '—';
    final estName = header['establishmentName'] ?? establishmentName;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text(dateStr, style: Theme.of(context).textTheme.bodyMedium)),
              Expanded(flex: 2, child: Text(estName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(employeeName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(supplier, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
