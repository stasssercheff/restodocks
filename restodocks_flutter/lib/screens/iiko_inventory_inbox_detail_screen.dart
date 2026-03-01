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
        backgroundColor: Colors.purple[50],
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

    return Container(
      width: double.infinity,
      color: Colors.purple.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(header['establishmentName'] as String? ?? '—',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('Дата: $dateStr  •  '
              'Сотрудник: ${header['employeeName'] ?? '—'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text('Заполнено: $filledRows из $totalRows позиций',
              style: TextStyle(fontSize: 12, color: Colors.purple[700])),
        ],
      ),
    );
  }
}

// ── Заголовок таблицы ─────────────────────────────────────────────────────────
class _TableHeader extends StatelessWidget {
  const _TableHeader();

  static const _b = BorderSide(color: Color(0xFFBBBBBB));
  static const _s = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF222222));

  Widget _hCell(String t, double w) => Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: const BoxDecoration(
          color: Color(0xFFEEEEEE),
          border: Border(right: _b, bottom: _b),
        ),
        child: Text(t, style: _s, textAlign: TextAlign.center),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(left: _b, top: _b),
          color: Color(0xFFEEEEEE)),
      child: Row(
        children: [
          _hCell('Группа', 100),
          _hCell('Код',    58),
          Expanded(child: _hCell('Наименование', double.infinity)),
          _hCell('Ед.', 44),
          _hCell('Итого', 72),
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

  static const _b = BorderSide(color: Color(0xFFDDDDDD));

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(3)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');

  Widget _cell(Widget child, {double? width, Color? bg}) => Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(right: _b, bottom: _b),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final name  = row['name']  as String? ?? '';
    final code  = row['code']  as String? ?? '';
    final unit  = row['unit']  as String? ?? '';
    final total = (row['total'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: const BoxDecoration(
          border: Border(left: _b)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Группа — iiko payload не хранит группу, оставляем пустой
            _cell(const SizedBox.shrink(), width: 100,
                bg: index.isEven
                    ? const Color(0xFFFAFAFA)
                    : null),
            // Код
            _cell(
              Text(code,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF444444)),
                  textAlign: TextAlign.center),
              width: 58,
            ),
            // Наименование — точно как в оригинале
            Expanded(
              child: _cell(
                Text(name,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
            // Ед.изм.
            _cell(
              Text(unit,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
              width: 44,
            ),
            // Итого — выделено жирным и фиолетовым
            _cell(
              Text(_fmt(total),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.purple[700]),
                  textAlign: TextAlign.center),
              width: 72,
              bg: Colors.purple.withOpacity(0.06),
            ),
          ],
        ),
      ),
    );
  }
}
