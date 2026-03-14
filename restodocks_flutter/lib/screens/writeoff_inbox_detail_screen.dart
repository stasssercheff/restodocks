import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр списания из входящих.
class WriteoffInboxDetailScreen extends StatefulWidget {
  const WriteoffInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<WriteoffInboxDetailScreen> createState() => _WriteoffInboxDetailScreenState();
}

class _WriteoffInboxDetailScreenState extends State<WriteoffInboxDetailScreen> {
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
    if (doc != null) {
      final estId = context.read<AccountManagerSupabase>().establishment?.id;
      context.read<InboxViewedService>().addViewed(estId, widget.documentId);
    }
  }

  String _categoryName(LocalizationService loc, String? code) {
    switch (code) {
      case 'staff':
        return loc.t('writeoff_category_staff') ?? 'Персонал';
      case 'workingThrough':
        return loc.t('writeoff_category_working') ?? 'Проработка';
      case 'spoilage':
        return loc.t('writeoff_category_spoilage') ?? 'Порча';
      case 'breakage':
        return loc.t('writeoff_category_breakage') ?? 'Брекераж';
      case 'guestRefusal':
        return loc.t('writeoff_category_guest_refusal') ?? 'Отказ гостя';
      default:
        return code ?? '—';
    }
  }

  Future<void> _showSaveLanguageAndExport() async {
    final loc = context.read<LocalizationService>();
    final payload = _doc?['payload'] as Map<String, dynamic>? ?? {};
    String selectedLang = loc.currentLanguageCode;

    final result = await showDialog<String>(
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
              child: Text(loc.t('inventory_export_excel') ?? 'Сохранить Excel'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final bytes = _buildExcelBytes(payload, result);
      if (bytes != null && bytes.isNotEmpty) {
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final date = header['date'] ?? DateTime.now().toIso8601String().split('T').first;
        final cat = payload['category']?.toString() ?? 'writeoff';
        await saveFileBytes('writeoff_${cat}_$date.xlsx', bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  List<int>? _buildExcelBytes(Map<String, dynamic> payload, String saveLang) {
    try {
      final loc = context.read<LocalizationService>();
      final excel = Excel.createExcel();
      final sheet = excel['Списание'];
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      var rows = payload['rows'] as List<dynamic>? ?? [];
      sheet.appendRow([
        TextCellValue(loc.t('inventory_excel_number') ?? '#'),
        TextCellValue(loc.t('inventory_item_name') ?? 'Наименование'),
        TextCellValue(loc.t('inventory_unit') ?? 'Ед.'),
        TextCellValue(loc.t('inventory_excel_total') ?? 'Количество'),
      ]);
      rows = rows.map((e) => e as Map<String, dynamic>).toList();
      rows.sort((a, b) => (a['productName']?.toString() ?? '').compareTo(b['productName']?.toString() ?? ''));
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
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
      return excel.encode();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context)),
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
    var rows = (payload['rows'] as List<dynamic>? ?? []).map((e) => e as Map<String, dynamic>).toList();
    rows.sort((a, b) => (a['productName']?.toString() ?? '').compareTo(b['productName']?.toString() ?? ''));
    final comment = payload['comment']?.toString();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('writeoffs') ?? 'Списания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Сохранить',
            onPressed: _showSaveLanguageAndExport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(loc.t('inventory_establishment'), header['establishmentName'] ?? '—'),
            _headerRow(loc.t('inventory_employee'), header['employeeName'] ?? '—'),
            _headerRow(loc.t('inventory_date'), header['date'] ?? '—'),
            _headerRow(loc.t('writeoffs') ?? 'Списания', _categoryName(loc, payload['category']?.toString())),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                loc.t('writeoff_comment') ?? 'Комментарий',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(comment, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            Text(
              loc.t('inventory_item_name') ?? 'Наименование',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
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

  Widget _headerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
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
}
