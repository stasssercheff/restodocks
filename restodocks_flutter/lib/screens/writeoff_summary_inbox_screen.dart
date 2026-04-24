import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/inbox_document.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Сводное списание за дату: итого по всем категориям (Персонал, Проработка, Порча, Брекераж, Отказ гостя).
class WriteoffSummaryInboxScreen extends StatelessWidget {
  const WriteoffSummaryInboxScreen({
    super.key,
    required this.documents,
    required this.dateLabel,
  });

  final List<InboxDocument> documents;
  final String dateLabel;

  static Map<String, dynamic> _aggregate(List<InboxDocument> docs) {
    final merged = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? firstHeader;

    for (final doc in docs) {
      final payload = doc.metadata as Map<String, dynamic>? ?? {};
      if (payload['type']?.toString() != 'writeoff') continue;
      firstHeader ??= payload['header'] as Map<String, dynamic>? ?? {};
      final rows = payload['rows'] as List<dynamic>? ?? [];

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final key = row['productId']?.toString() ?? '${row['productName']}_${row['unit']}';
        final total = (row['total'] as num?)?.toDouble() ?? 0.0;
        if (merged.containsKey(key)) {
          merged[key]!['total'] = (merged[key]!['total'] as double) + total;
        } else {
          merged[key] = {
            ...row,
            'total': total,
          };
        }
      }
    }

    return {
      'header': firstHeader ?? {},
      'rows': merged.values.toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final aggregated = _aggregate(documents);
    var rows = (aggregated['rows'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    rows.sort((a, b) => (a['productName']?.toString() ?? '').compareTo(b['productName']?.toString() ?? ''));

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('writeoff_summary')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download'),
            onPressed: () => _exportExcel(context, loc, aggregated),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                dateLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (rows.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    loc.t('writeoff_no_data'),
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Table(
                border: TableBorder.all(color: theme.dividerColor),
                columnWidths: const {
                  0: FlexColumnWidth(0.4),
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
                      _cell(theme, loc.t('inventory_excel_total'), bold: true),
                    ],
                  ),
                  ...rows.asMap().entries.map((e) {
                    final r = e.value;
                    return TableRow(
                      children: [
                        _cell(theme, '${e.key + 1}'),
                        _cell(theme, r['productName']?.toString() ?? ''),
                        _cell(theme, r['unit']?.toString() ?? ''),
                        _cell(theme, _fmt(r['total'])),
                      ],
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
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

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num) return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return v.toString();
  }

  Future<void> _exportExcel(BuildContext context, LocalizationService loc, Map<String, dynamic> aggregated) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Списание'];
      var rows = (aggregated['rows'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
      rows.sort((a, b) => (a['productName']?.toString() ?? '').compareTo(b['productName']?.toString() ?? ''));
      sheet.appendRow([
        TextCellValue(loc.t('inventory_excel_number')),
        TextCellValue(loc.t('inventory_item_name')),
        TextCellValue(loc.t('inventory_unit')),
        TextCellValue(loc.t('inventory_excel_total')),
      ]);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(r['productName']?.toString() ?? ''),
          TextCellValue(r['unit']?.toString() ?? ''),
          DoubleCellValue((r['total'] as num?)?.toDouble() ?? 0),
        ]);
      }
      excel.setDefaultSheet('Списание');
      final out = excel.encode();
      if (out != null && out.isNotEmpty) {
        final parts = dateLabel.split('.');
        final dateStr = parts.length == 3
            ? '${parts[2]}-${parts[1]}-${parts[0]}'
            : dateLabel.replaceAll('.', '-');
        final account = context.read<AccountManagerSupabase>();
        final est = account.establishment;
        if (est != null && account.isTrialOnlyWithoutPaid) {
          await account.trialIncrementDeviceSaveOrThrow(
            establishmentId: est.id,
            docKind: TrialDeviceSaveKinds.writeoff,
          );
        }
        await saveFileBytes('writeoff_summary_$dateStr.xlsx', out);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded'))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('error_generic', args: {'error': '$e'})),
          ),
        );
      }
    }
  }
}
