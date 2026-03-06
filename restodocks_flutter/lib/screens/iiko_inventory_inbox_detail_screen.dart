import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/inventory_document_service.dart';
import '../services/inventory_download.dart';
import '../services/iiko_product_store.dart';
import '../services/iiko_xlsx_patcher.dart';
import '../services/localization_service.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр iiko-инвентаризации из входящих.
///
/// Отображение — как во вкладке «Номенклатура → iiko», но с колонкой «Итого».
/// Поддерживает многолистовые бланки: вкладки переключают листы.
/// Показывает все строки включая незаполненные (total == 0).
class IikoInventoryInboxDetailScreen extends StatefulWidget {
  const IikoInventoryInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<IikoInventoryInboxDetailScreen> createState() =>
      _IikoInventoryInboxDetailScreenState();
}

class _IikoInventoryInboxDetailScreenState
    extends State<IikoInventoryInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;
  String? _selectedSheet;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await InventoryDocumentService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      if (doc == null) _error = 'Документ не найден';
    });
  }

  // ── Скачивание в оригинальном формате бланка ──────────────────────────────

  Future<void> _saveToFile() async {
    final doc = _doc;
    if (doc == null) return;

    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header  = payload['header'] as Map<String, dynamic>? ?? {};
    final rows    = (payload['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Строим карту код → total (все строки с total > 0)
    final qtyByCode = <String, double>{};
    for (final r in rows) {
      final code  = (r['code'] as String?)?.trim() ?? '';
      final total = (r['total'] as num?)?.toDouble() ?? 0.0;
      if (code.isNotEmpty && total > 0) qtyByCode[code] = total;
    }

    final iikoStore = context.read<IikoProductStore>();
    await iikoStore.restoreBlankFromStorage();
    final origBytes = iikoStore.originalBlankBytes;
    final qtyCol    = iikoStore.originalQuantityColumnIndex ?? 5;

    final dateStr = header['date']?.toString() ?? '';
    final dateLabel = dateStr.isNotEmpty
        ? dateStr.replaceAll(RegExp(r'[T:]'), '-').substring(0, 10)
        : DateTime.now().toIso8601String().substring(0, 10);

    Uint8List outBytes;
    String fileName;

    if (origBytes != null) {
      // Байтовый патч — сохраняет форматирование всех листов
      outBytes = IikoXlsxPatcher.patch(
        origBytes:     origBytes,
        defaultQtyCol: qtyCol,
        sheetQtyCols:  iikoStore.sheetQtyColumns,
        qtyByCode:     qtyByCode,
      );
      fileName = header['fileName'] as String? ??
          'Инвентаризация_iiko_$dateLabel.xlsx';
    } else {
      outBytes = _buildFallback(rows, header);
      fileName = 'Инвентаризация_iiko_$dateLabel.xlsx';
    }

    try {
      await saveFileBytes(fileName, outBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e')),
        );
      }
    }
  }

  /// Запасной Excel если оригинальный бланк недоступен.
  Uint8List _buildFallback(
      List<Map<String, dynamic>> rows, Map<String, dynamic> header) {
    final loc = context.read<LocalizationService>();
    final excel = Excel.createExcel();
    final sheetName = loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko';
    final sheet = excel[sheetName];

    sheet.appendRow([
      TextCellValue('Код'),
      TextCellValue('Наименование'),
      TextCellValue('Ед.изм.'),
      TextCellValue('Остаток фактический'),
    ]);

    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0.0;
      if (total <= 0) continue;
      sheet.appendRow([
        TextCellValue(r['code']?.toString() ?? ''),
        TextCellValue(r['name']?.toString() ?? ''),
        TextCellValue(r['unit']?.toString() ?? ''),
        DoubleCellValue(total),
      ]);
    }

    excel.setDefaultSheet(sheetName);
    return Uint8List.fromList(excel.save()!);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
              Text(_error ?? 'Документ не найден',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Назад')),
            ],
          ),
        ),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header  = payload['header'] as Map<String, dynamic>? ?? {};
    final allRows = (payload['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Определяем листы
    final sheetNames = allRows
        .map((r) => r['sheetName'] as String?)
        .where((s) => s != null && s.isNotEmpty)
        .toSet()
        .toList()
        .cast<String>();
    final hasSheets = sheetNames.length > 1;

    final activeSheet = (hasSheets && sheetNames.contains(_selectedSheet))
        ? _selectedSheet!
        : (hasSheets ? sheetNames.first : null);

    final rows = (hasSheets && activeSheet != null)
        ? allRows.where((r) => r['sheetName'] == activeSheet).toList()
        : allRows;

    final filledCount = rows.where((r) => ((r['total'] as num?)?.toDouble() ?? 0.0) > 0).length;

    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Скачать xlsx',
            onPressed: _saveToFile,
          ),
        ],
      ),
      body: Column(
        children: [
          // Шапка документа
          _HeaderPanel(
            header: header,
            totalRows: rows.length,
            filledRows: filledCount,
          ),
          // Вкладки листов (если > 1)
          if (hasSheets)
            _InboxSheetTabBar(
              sheetNames: sheetNames,
              selected: activeSheet ?? sheetNames.first,
              onSelect: (s) => setState(() => _selectedSheet = s),
            ),
          // Шапка таблицы
          const _TableHeader(),
          // Строки — все, включая незаполненные
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text('Нет позиций',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (ctx, i) =>
                        _TableRow(row: rows[i], index: i),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Вкладки листов ────────────────────────────────────────────────────────────
class _InboxSheetTabBar extends StatelessWidget {
  const _InboxSheetTabBar({
    required this.sheetNames,
    required this.selected,
    required this.onSelect,
  });

  final List<String> sheetNames;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: sheetNames.map((name) {
            final isActive = name == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onSelect(name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? theme.colorScheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Шапка документа ──────────────────────────────────────────────────────────
class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({
    required this.header,
    required this.totalRows,
    required this.filledRows,
  });

  final Map<String, dynamic> header;
  final int totalRows;
  final int filledRows;

  @override
  Widget build(BuildContext context) {
    final dateRaw  = header['date'] as String? ?? '';
    DateTime? dt;
    try { dt = DateTime.parse(dateRaw).toLocal(); } catch (_) {}
    final dateStr = dt != null
        ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'
        : dateRaw;

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(header['establishmentName'] as String? ?? '—',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Дата: $dateStr  •  Сотрудник: ${header['employeeName'] ?? '—'}',
              style: TextStyle(fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 2),
          Text('Заполнено: $filledRows из $totalRows позиций',
              style: TextStyle(fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Заголовок таблицы ─────────────────────────────────────────────────────────
class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final bg     = theme.colorScheme.surfaceContainerHighest;
    final border = BorderSide(color: theme.dividerColor);
    final style  = TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface);

    Widget hCell(String t, double w) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border(right: border, bottom: border),
          ),
          child: Text(t, style: style, textAlign: TextAlign.center),
        );

    return Container(
      decoration: BoxDecoration(
          border: Border(left: border, top: border), color: bg),
      child: Row(
        children: [
          hCell('Группа', 100),
          hCell('Код',    58),
          Expanded(child: hCell('Наименование', double.infinity)),
          hCell('Ед.',    44),
          hCell('Итого',  72),
        ],
      ),
    );
  }
}

// ── Строка таблицы ────────────────────────────────────────────────────────────
class _TableRow extends StatelessWidget {
  const _TableRow({required this.row, required this.index});

  final Map<String, dynamic> row;
  final int index;

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(3)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final border = BorderSide(color: theme.dividerColor);

    Widget cell(Widget child, {double? width, Color? bg}) => Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border(right: border, bottom: border),
          ),
          child: child,
        );

    final name  = row['name']  as String? ?? '';
    final code  = row['code']  as String? ?? '';
    final unit  = row['unit']  as String? ?? '';
    final group = row['groupName'] as String? ?? '';
    final total = (row['total'] as num?)?.toDouble() ?? 0.0;
    final isEmpty = total == 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: border),
        color: isEmpty
            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.15)
            : null,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell(
              Text(group,
                  style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.5)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
              width: 100,
              bg: index.isEven
                  ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)
                  : null,
            ),
            cell(
              Text(code,
                  style: TextStyle(fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  textAlign: TextAlign.center),
              width: 58,
            ),
            Expanded(
              child: cell(Text(name,
                  style: TextStyle(
                      fontSize: 12,
                      color: isEmpty
                          ? theme.colorScheme.onSurface.withOpacity(0.5)
                          : null))),
            ),
            cell(
              Text(unit,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
              width: 44,
            ),
            cell(
              isEmpty
                  ? const SizedBox.shrink()
                  : Text(_fmt(total),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary),
                      textAlign: TextAlign.center),
              width: 72,
              bg: isEmpty
                  ? null
                  : theme.colorScheme.primaryContainer.withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }
}
