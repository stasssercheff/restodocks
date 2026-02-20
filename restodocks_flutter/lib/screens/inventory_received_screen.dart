import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/inventory_download.dart';
import '../services/services.dart';

/// Кабинет шеф-повара: полученные документы инвентаризации.
class InventoryReceivedScreen extends StatefulWidget {
  const InventoryReceivedScreen({super.key});

  @override
  State<InventoryReceivedScreen> createState() => _InventoryReceivedScreenState();
}

class _InventoryReceivedScreenState extends State<InventoryReceivedScreen> {
  List<Map<String, dynamic>> _docs = [];
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
    final account = AccountManagerSupabase();
    final employee = account.currentEmployee;
    if (employee == null) {
      setState(() {
        _loading = false;
        _error = 'Не авторизован';
      });
      return;
    }
    final list = await InventoryDocumentService().listForChef(employee.id);
    if (!mounted) return;
    setState(() {
      _docs = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inventory_received')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _buildBody(loc),
    );
  }

  Widget _buildBody(LocalizationService loc) {
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
            FilledButton(onPressed: _load, child: Text(loc.t('back'))),
          ],
        ),
      );
    }
    if (_docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('inventory_received_empty'),
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
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _docs.length,
              itemBuilder: (_, i) {
                final d = _docs[i];
                return _DocCard(
                  doc: d,
                  loc: loc,
                  onTap: () => _openDetail(context, d, loc),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Map<String, dynamic> doc, LocalizationService loc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _InventoryDocumentDetailScreen(doc: doc, loc: loc),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.loc, required this.onTap});

  final Map<String, dynamic> doc;
  final LocalizationService loc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payload = doc['payload'] as Map<String, dynamic>?;
    final header = payload?['header'] as Map<String, dynamic>? ?? {};
    final date = doc['created_at']?.toString().substring(0, 10) ?? '—';
    final establishmentName = header['establishmentName'] ?? '—';
    final employeeName = header['employeeName'] ?? '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text(date, style: Theme.of(context).textTheme.bodyMedium)),
              Expanded(flex: 2, child: Text(establishmentName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(employeeName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

}

class _InventoryDocumentDetailScreen extends StatelessWidget {
  const _InventoryDocumentDetailScreen({required this.doc, required this.loc});

  final Map<String, dynamic> doc;
  final LocalizationService loc;

  Future<void> _download(BuildContext context) async {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    try {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      var maxCols = 0;
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        if (quantities.length > maxCols) maxCols = quantities.length;
      }
      final headerCells = <CellValue>[
        TextCellValue(loc.t('inventory_excel_number')),
        TextCellValue(loc.t('inventory_item_name')),
        TextCellValue(loc.t('inventory_unit')),
        TextCellValue(loc.t('inventory_excel_total')),
      ];
      final fillLabel = loc.t('inventory_excel_fill_data');
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }
      sheet.appendRow(headerCells);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? (quantities[c] as num?)?.toDouble() ?? 0.0 : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet.appendRow(rowCells);
      }
      final aggregated = payload['aggregatedProducts'] as List<dynamic>? ?? [];
      if (aggregated.isNotEmpty) {
        sheet.appendRow([]);
        sheet.appendRow([TextCellValue(loc.t('inventory_pf_products_title'))]);
        sheet.appendRow([
          TextCellValue(loc.t('inventory_excel_number')),
          TextCellValue(loc.t('inventory_item_name')),
          TextCellValue(loc.t('inventory_pf_gross_g')),
          TextCellValue(loc.t('inventory_pf_net_g')),
        ]);
        for (var i = 0; i < aggregated.length; i++) {
          final p = aggregated[i] as Map<String, dynamic>;
          sheet.appendRow([
            IntCellValue(i + 1),
            TextCellValue((p['productName'] as String? ?? '').toString()),
            IntCellValue(((p['grossGrams'] as num?)?.toDouble() ?? 0).round()),
            IntCellValue(((p['netGrams'] as num?)?.toDouble() ?? 0).round()),
          ]);
        }
      }

      final out = excel.encode();
      if (out != null && out.isNotEmpty) {
        final date = header['date'] ?? DateTime.now().toIso8601String().split('T').first;
        await saveFileBytes('inventory_$date.xlsx', out);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл Excel сохранён')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = doc['payload'] as Map<String, dynamic>?;
    final header = payload?['header'] as Map<String, dynamic>? ?? {};
    final rows = payload?['rows'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(loc.t('inventory_blank_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Скачать',
            onPressed: () => _download(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(header),
            const SizedBox(height: 24),
            Text(
              loc.t('inventory_item_name'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildTable(context, rows),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> header) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(loc.t('inventory_establishment'), header['establishmentName'] ?? '—'),
        _headerRow(loc.t('inventory_employee'), header['employeeName'] ?? '—'),
        _headerRow(loc.t('inventory_date'), header['date'] ?? '—'),
        _headerRow(loc.t('inventory_time_start'), header['timeStart'] ?? '—'),
        _headerRow(loc.t('inventory_time_end'), header['timeEnd'] ?? '—'),
      ],
    );
  }

  Widget _headerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context, List<dynamic> rows) {
    final theme = Theme.of(context);

    return Table(
      border: TableBorder.all(color: theme.dividerColor),
      columnWidths: const {
        0: FlexColumnWidth(0.5),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(0.5),
        3: FlexColumnWidth(0.6),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _cell(theme, '#', bold: true),
            _cell(theme, loc.t('inventory_item_name'), bold: true),
            _cell(theme, loc.t('inventory_unit'), bold: true),
            _cell(theme, loc.t('inventory_total'), bold: true),
          ],
        ),
        ...rows.asMap().entries.map((e) {
          final r = e.value as Map<String, dynamic>;
          return TableRow(
            children: [
              _cell(theme, '${e.key + 1}'),
              _cell(theme, (r['productName'] ?? '').toString()),
              _cell(theme, (r['unit'] ?? '').toString()),
              _cell(theme, _fmt(r['total'])),
            ],
          );
        }),
      ],
    );
  }

  Widget _cell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: bold ? FontWeight.w600 : null,
        ),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return v.toString();
  }
}
