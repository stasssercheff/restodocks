import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/inventory_document_service.dart';
import '../services/inventory_download.dart';
import '../services/iiko_product_store.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр iiko-инвентаризации из входящих.
///
/// Отображение — как во вкладке «Номенклатура → iiko», но с колонкой «Итого».
/// Кнопка «Скачать» — генерирует файл в точно той же форме что был загружен
/// (берёт оригинальный бланк из localStorage через [IikoProductStore]).
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

    final payload   = doc['payload'] as Map<String, dynamic>? ?? {};
    final header    = payload['header'] as Map<String, dynamic>? ?? {};
    final rows      = (payload['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Строим карту код → total
    final qtyByCode = <String, double>{};
    for (final r in rows) {
      final code  = (r['code'] as String?)?.trim() ?? '';
      final total = (r['total'] as num?)?.toDouble() ?? 0.0;
      if (code.isNotEmpty && total > 0) qtyByCode[code] = total;
    }

    // Пробуем восстановить оригинальный бланк из localStorage
    final iikoStore = context.read<IikoProductStore>();
    await iikoStore.restoreBlankFromStorage();
    final origBytes = iikoStore.originalBlankBytes;
    final qtyCol    = iikoStore.originalQuantityColumnIndex ?? 5;

    Uint8List outBytes;
    String fileName;
    final dateStr = header['date']?.toString() ?? '';
    final dateLabel = dateStr.isNotEmpty
        ? dateStr.replaceAll(RegExp(r'[T:]'), '-').substring(0, 10)
        : DateTime.now().toIso8601String().substring(0, 10);

    if (origBytes != null) {
      // Оригинальный бланк найден — вписываем только итого в нужную колонку
      outBytes = _fillOriginal(origBytes, qtyCol, qtyByCode);
      fileName = header['fileName'] as String? ??
          'Инвентаризация_iiko_$dateLabel.xlsx';
    } else {
      // Запасной вариант — создаём новый файл
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

  /// Берёт оригинальный xlsx, заполняет колонку [qtyCol] по коду строки.
  Uint8List _fillOriginal(
      Uint8List orig, int qtyCol, Map<String, double> qtyByCode) {
    final excel     = Excel.decodeBytes(orig.toList());
    final sheetName = excel.tables.keys.first;
    final sheet     = excel.tables[sheetName]!;

    // Находим колонку с кодами
    int codeCol = 2;
    for (var r = 0; r < sheet.maxRows && r < 20; r++) {
      for (var c = 0; c < (sheet.maxColumns > 10 ? 10 : sheet.maxColumns); c++) {
        final v = _cellStr(sheet, r, c).toLowerCase();
        if (v == 'код' || v == 'code') { codeCol = c; break; }
      }
    }

    for (var r = 0; r < sheet.maxRows; r++) {
      final code = _cellStr(sheet, r, codeCol).trim();
      if (code.isEmpty) continue;
      final qty = qtyByCode[code];
      if (qty != null) {
        sheet
            .cell(CellIndex.indexByColumnRow(
                columnIndex: qtyCol, rowIndex: r))
            .value = DoubleCellValue(qty);
      }
    }

    return Uint8List.fromList(excel.save()!);
  }

  String _cellStr(Sheet sheet, int row, int col) {
    try {
      final v = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;
      if (v == null) return '';
      if (v is TextCellValue) return v.value.text ?? '';
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) return v.value.toString();
      return v.toString();
    } catch (_) {
      return '';
    }
  }

  /// Запасной Excel если оригинальный бланк недоступен.
  Uint8List _buildFallback(
      List<Map<String, dynamic>> rows, Map<String, dynamic> header) {
    final excel = Excel.createExcel();
    const sheetName = 'Инвентаризация iiko';
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
    final rows    = (payload['rows'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    // Только заполненные строки
    final filledRows = rows
        .where((r) => ((r['total'] as num?)?.toDouble() ?? 0.0) > 0)
        .toList();

    // Группируем по группе (если есть) — iiko payload не хранит groupName,
    // поэтому просто отображаем плоский список
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: const Text('Инвентаризация iiko'),
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
          _HeaderPanel(header: header, totalRows: rows.length,
              filledRows: filledRows.length),
          // Шапка таблицы
          _TableHeader(),
          // Строки
          Expanded(
            child: filledRows.isEmpty
                ? const Center(
                    child: Text('Нет заполненных позиций',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filledRows.length,
                    itemBuilder: (ctx, i) =>
                        _TableRow(row: filledRows[i], index: i),
                  ),
          ),
        ],
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
    final total = (row['total'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: BoxDecoration(border: Border(left: border)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell(const SizedBox.shrink(), width: 100,
                bg: index.isEven
                    ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)
                    : null),
            cell(
              Text(code,
                  style: TextStyle(fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.6)),
                  textAlign: TextAlign.center),
              width: 58,
            ),
            Expanded(
              child: cell(Text(name, style: const TextStyle(fontSize: 12))),
            ),
            cell(
              Text(unit,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
              width: 44,
            ),
            // Итого — акцент цветом primary темы
            cell(
              Text(_fmt(total),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary),
                  textAlign: TextAlign.center),
              width: 72,
              bg: theme.colorScheme.primaryContainer.withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }
}
