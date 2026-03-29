import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/inventory_download.dart';
import '../services/screen_layout_preference_service.dart';
import '../utils/translit_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр списания из входящих.
class WriteoffInboxDetailScreen extends StatefulWidget {
  const WriteoffInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<WriteoffInboxDetailScreen> createState() =>
      _WriteoffInboxDetailScreenState();
}

class _WriteoffInboxDetailScreenState extends State<WriteoffInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductStoreSupabase>().loadProducts(force: true);
    });
  }

  String _localizedRowProductName(
    Map<String, dynamic> r,
    String lang,
    ProductStoreSupabase store,
  ) {
    final pid = r['productId']?.toString() ?? '';
    final fallback = r['productName']?.toString() ?? '';
    if (pid.isEmpty || pid.startsWith('pf_')) return fallback;
    for (final p in store.allProducts) {
      if (p.id == pid) return p.getLocalizedName(lang);
    }
    return fallback;
  }

  String _headerEmployee(String raw, bool translit) {
    if (raw == '—') return raw;
    return translit ? cyrillicToLatin(raw) : raw;
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
      if (doc == null)
        _error = context.read<LocalizationService>().t('document_not_found');
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
        final date =
            header['date'] ?? DateTime.now().toIso8601String().split('T').first;
        final cat = payload['category']?.toString() ?? 'writeoff';
        await saveFileBytes('writeoff_${cat}_$date.xlsx', bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.t('error') ?? 'Ошибка'}: $e')));
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
      final store = context.read<ProductStoreSupabase>();
      rows.sort((a, b) => _localizedRowProductName(a, saveLang, store)
          .toLowerCase()
          .compareTo(
              _localizedRowProductName(b, saveLang, store).toLowerCase()));
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final unitRaw = (r['unit']?.toString() ?? 'g').trim().toLowerCase();
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(_localizedRowProductName(r, saveLang, store)),
          TextCellValue(CulinaryUnits.displayName(unitRaw, saveLang)),
          DoubleCellValue((r['total'] as num?)?.toDouble() ?? 0),
        ]);
      }
      final comment = payload['comment']?.toString();
      if (comment != null && comment.isNotEmpty) {
        sheet.appendRow([]);
        sheet.appendRow([
          TextCellValue(loc.t('writeoff_comment') ?? 'Комментарий'),
          TextCellValue(comment)
        ]);
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
              Text(_error ?? loc.t('document_not_found'),
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => context.pop(),
                  child: Text(loc.t('back') ?? 'Назад')),
            ],
          ),
        ),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    var rows = (payload['rows'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final store = context.watch<ProductStoreSupabase>();
    final translit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
    final lang = loc.currentLanguageCode;
    rows.sort((a, b) => _localizedRowProductName(a, lang, store)
        .toLowerCase()
        .compareTo(_localizedRowProductName(b, lang, store).toLowerCase()));
    final comment = payload['comment']?.toString();
    final empHeader =
        _headerEmployee(header['employeeName']?.toString() ?? '—', translit);

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
            _headerRow(loc.t('inventory_establishment'),
                header['establishmentName'] ?? '—'),
            _headerRow(loc.t('inventory_employee'), empHeader),
            _headerRow(loc.t('inventory_date'), header['date'] ?? '—'),
            _headerRow(loc.t('writeoffs') ?? 'Списания',
                _categoryName(loc, payload['category']?.toString())),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                loc.t('writeoff_comment') ?? 'Комментарий',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
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
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest),
                  children: [
                    _cell(theme, '#', bold: true),
                    _cell(theme, loc.t('inventory_item_name'), bold: true),
                    _cell(theme, loc.t('inventory_unit'), bold: true),
                    _cell(theme, loc.t('inventory_excel_total'), bold: true),
                  ],
                ),
                ...rows.asMap().entries.map((e) {
                  final r = e.value;
                  final unitRaw =
                      (r['unit']?.toString() ?? 'g').trim().toLowerCase();
                  return TableRow(
                    children: [
                      _cell(theme, '${e.key + 1}'),
                      _cell(theme, _localizedRowProductName(r, lang, store)),
                      _cell(theme, CulinaryUnits.displayName(unitRaw, lang)),
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
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
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
        style: theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: bold ? FontWeight.w600 : null),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num)
      return v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(1);
    return v.toString();
  }
}
