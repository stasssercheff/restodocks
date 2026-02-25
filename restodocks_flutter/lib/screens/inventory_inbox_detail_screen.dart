import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр инвентаризации из входящих: данные + кнопка «Сохранить» (Excel).
class InventoryInboxDetailScreen extends StatefulWidget {
  const InventoryInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<InventoryInboxDetailScreen> createState() => _InventoryInboxDetailScreenState();
}

class _InventoryInboxDetailScreenState extends State<InventoryInboxDetailScreen> {
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
    final doc = await InventoryDocumentService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      if (doc == null) _error = 'Документ не найден';
    });
  }

  Future<void> _saveToFile() async {
    final doc = _doc;
    final loc = context.read<LocalizationService>();
    if (doc == null) return;

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
          );
        }
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
    final rows = payload['rows'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inventory_blank_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Сохранить',
            onPressed: _saveToFile,
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
              loc.t('inventory_item_name'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildTable(theme, loc, rows),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalizationService loc, Map<String, dynamic> header) {
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

  Widget _buildTable(ThemeData theme, LocalizationService loc, List<dynamic> rows) {
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
