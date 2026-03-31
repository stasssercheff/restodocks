import 'dart:typed_data';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/inbox_document.dart';
import '../models/translation.dart';
import '../services/inventory_download.dart';
import '../services/iiko_product_store.dart';
import '../services/iiko_xlsx_patcher.dart';
import '../services/iiko_xlsx_sanitizer.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Объединение бланков инвентаризации из входящих.
/// Шеф/барменеджер/менеджер зала выбирает несколько бланков, объединяет их
/// (итого = сумма количеств по всем выбранным), сохраняет Excel.
class InventoryMergeScreen extends StatefulWidget {
  const InventoryMergeScreen({
    super.key,
    required this.documents,
  });

  /// Список бланков инвентаризации (standard + iiko), отсортируем по дате сохранения
  final List<InboxDocument> documents;

  @override
  State<InventoryMergeScreen> createState() => _InventoryMergeScreenState();
}

class _InventoryMergeScreenState extends State<InventoryMergeScreen> {
  final Set<String> _selectedIds = {};
  bool _loading = false;

  List<InboxDocument> get _sortedDocs {
    final list = List<InboxDocument>.from(widget.documents);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _sortedDocs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_sortedDocs.map((d) => d.id));
      }
    });
  }

  Future<void> _mergeAndSave() async {
    if (_selectedIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_loc.t('inventory_merge_select_least') ?? 'Выберите минимум один бланк')),
        );
      }
      return;
    }

    final selected = _sortedDocs.where((d) => _selectedIds.contains(d.id)).toList();
    final standards = selected.where((d) => d.type == DocumentType.inventory).toList();
    final iikoList = selected.where((d) => d.type == DocumentType.iikoInventory).toList();
    final writeoffList = selected.where((d) => d.type == DocumentType.writeoff).toList();

    final typeCount = (standards.isNotEmpty ? 1 : 0) + (iikoList.isNotEmpty ? 1 : 0) + (writeoffList.isNotEmpty ? 1 : 0);
    if (typeCount > 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_loc.t('inventory_merge_same_type') ?? 'Объединяйте только бланки одного типа'),
          ),
        );
      }
      return;
    }

    if (standards.isNotEmpty) {
      await _mergeStandardAndSave(standards);
    } else if (iikoList.isNotEmpty) {
      await _mergeIikoAndSave(iikoList);
    } else if (writeoffList.isNotEmpty) {
      await _mergeWriteoffAndSave(writeoffList);
    }
  }

  Future<void> _mergeWriteoffAndSave(List<InboxDocument> docs) async {
    setState(() => _loading = true);
    String selectedLang = _loc.currentLanguageCode;

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(_loc.t('inventory_merge_lang_title') ?? 'Язык сохранения'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _loc.t('inventory_export_lang') ?? 'Язык сохранения:',
                style: Theme.of(ctx2).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: LocalizationService.productLanguageCodes.map((code) {
                  return ChoiceChip(
                    label: Text(_loc.getLanguageName(code)),
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
              child: Text(_loc.t('inventory_merge_save') ?? 'Объединить и сохранить'),
            ),
          ],
        ),
      ),
    );

    setState(() => _loading = false);
    if (result == null || !mounted) return;

    final merged = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? firstHeader;
    String? firstCategory;

    for (final doc in docs) {
      final payload = doc.metadata as Map<String, dynamic>? ?? {};
      firstHeader ??= payload['header'] as Map<String, dynamic>? ?? {};
      firstCategory ??= payload['category']?.toString();
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
            'quantities': [total],
          };
        }
      }
    }

    final payload = {
      'type': 'writeoff',
      'category': firstCategory ?? 'staff',
      'header': {
        ...?firstHeader,
        'date': firstHeader?['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'employeeName': docs.map((d) => d.employeeName).join(', '),
      },
      'rows': merged.values.toList(),
      'sourceLang': result,
      'mergeMetadata': _buildMergeMetadata(docs),
    };

    try {
      final excel = Excel.createExcel();
      final sheet = excel['Списание'];
      sheet.appendRow([
        TextCellValue(_loc.t('inventory_excel_number')),
        TextCellValue(_loc.t('inventory_item_name')),
        TextCellValue(_loc.t('inventory_unit')),
        TextCellValue(_loc.t('inventory_excel_total')),
      ]);
      final sorted = merged.values.toList();
      sorted.sort((a, b) => (a['productName']?.toString() ?? '').compareTo(b['productName']?.toString() ?? ''));
      for (var i = 0; i < sorted.length; i++) {
        final r = sorted[i];
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(r['productName']?.toString() ?? ''),
          TextCellValue(r['unit']?.toString() ?? ''),
          DoubleCellValue(r['total'] as double),
        ]);
      }
      excel.setDefaultSheet('Списание');
      final out = excel.encode();
      if (out != null && out.isNotEmpty) {
        final header = payload['header'] as Map<String, dynamic>?;
        final dateStr = header?['date']?.toString() ?? DateTime.now().toIso8601String().split('T').first;
        await saveFileBytes('writeoff_merged_$dateStr.xlsx', out);
        await _saveMergedToInbox(payload);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  LocalizationService get _loc => context.read<LocalizationService>();

  /// Стандартный бланк: можно выбрать язык сохранения.
  Future<void> _mergeStandardAndSave(List<InboxDocument> docs) async {
    setState(() => _loading = true);

    String selectedLang = _loc.currentLanguageCode;

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(_loc.t('inventory_merge_lang_title') ?? 'Язык сохранения'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loc.t('inventory_export_lang') ?? 'Язык сохранения:',
                style: Theme.of(ctx2).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: LocalizationService.productLanguageCodes.map((code) {
                  return ChoiceChip(
                    label: Text(_loc.getLanguageName(code)),
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
              child: Text(_loc.t('inventory_export_excel') ?? 'Сохранить Excel'),
            ),
          ],
        ),
      ),
    );

    setState(() => _loading = false);
    if (result == null || !mounted) return;

    final mergedPayload = _mergeStandardPayloads(docs);
    await _saveStandardExcel(mergedPayload, saveLang: result, sourceDocs: docs);
  }

  Map<String, dynamic> _mergeStandardPayloads(List<InboxDocument> docs) {
    final first = docs.first.metadata as Map<String, dynamic>? ?? {};
    final header = Map<String, dynamic>.from(first['header'] as Map<String, dynamic>? ?? {});
    header['date'] = header['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    header['timeStart'] = docs.map((d) {
      final h = (d.metadata as Map?)?['header'] as Map?;
      return h?['timeStart']?.toString() ?? '';
    }).where((s) => s.isNotEmpty).join(', ');
    header['timeEnd'] = docs.map((d) {
      final h = (d.metadata as Map?)?['header'] as Map?;
      return h?['timeEnd']?.toString() ?? '';
    }).where((s) => s.isNotEmpty).join(', ');
    header['employeeName'] = docs.map((d) => d.employeeName).where((s) => s.isNotEmpty).join(', ');

    final mergedRows = <String, Map<String, dynamic>>{};
    final mergedAggregated = <String, Map<String, dynamic>>{};

    for (final doc in docs) {
      final payload = doc.metadata as Map<String, dynamic>? ?? {};
      final rows = payload['rows'] as List<dynamic>? ?? [];
      final aggregated = payload['aggregatedProducts'] as List<dynamic>? ?? [];

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final key = row['productId']?.toString() ?? '${row['productName']}_${row['unit']}';
        final total = (row['total'] as num?)?.toDouble() ?? 0.0;
        final quantities = (row['quantities'] as List<dynamic>? ?? []).map((q) => (q as num?)?.toDouble() ?? 0.0).toList();

        if (mergedRows.containsKey(key)) {
          final existing = mergedRows[key]!;
          existing['total'] = (existing['total'] as double) + total;
          final existQ = existing['quantities'] as List<double>;
          for (var i = 0; i < quantities.length; i++) {
            if (i < existQ.length) {
              existQ[i] += quantities[i];
            } else {
              existQ.add(quantities[i]);
            }
          }
        } else {
          mergedRows[key] = {
            ...row,
            'total': total,
            'quantities': List<double>.from(quantities),
          };
        }
      }

      for (final p in aggregated) {
        final agg = p as Map<String, dynamic>;
        final name = (agg['productName'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final gross = (agg['grossGrams'] as num?)?.toDouble() ?? 0.0;
        final net = (agg['netGrams'] as num?)?.toDouble() ?? 0.0;
        if (mergedAggregated.containsKey(name)) {
          mergedAggregated[name]!['grossGrams'] = (mergedAggregated[name]!['grossGrams'] as double) + gross;
          mergedAggregated[name]!['netGrams'] = (mergedAggregated[name]!['netGrams'] as double) + net;
        } else {
          mergedAggregated[name] = {'productName': name, 'grossGrams': gross, 'netGrams': net};
        }
      }
    }

    final out = <String, dynamic>{
      'header': header,
      'rows': mergedRows.values.toList(),
      'aggregatedProducts': mergedAggregated.values.toList(),
      'sourceLang': first['sourceLang'] ?? 'ru',
    };
    // Как у одиночного бланка: тип «выборочная» только если все исходные — выборочные.
    final allSelective = docs.every((d) =>
        (d.metadata as Map?)?['type']?.toString() == 'selective_inventory');
    if (allSelective) {
      out['type'] = 'selective_inventory';
    }
    return out;
  }

  /// Метаданные объединения для сохранения во входящих
  Map<String, dynamic> _buildMergeMetadata(List<InboxDocument> sourceDocs) {
    final account = context.read<AccountManagerSupabase>();
    final merger = account.currentEmployee;
    return {
      'mergedBy': merger?.fullName ?? '—',
      'mergedById': merger?.id ?? '',
      'mergedAt': DateTime.now().toUtc().toIso8601String(),
      'sourceDocuments': sourceDocs.map((d) => {
        'id': d.id,
        'employeeName': d.employeeName,
        'createdAt': d.createdAt.toUtc().toIso8601String(),
        'title': d.title,
      }).toList(),
    };
  }

  /// Сохранить объединённую инвентаризацию во входящие (inventory_documents).
  Future<void> _saveMergedToInbox(Map<String, dynamic> payload) async {
    final account = context.read<AccountManagerSupabase>();
    final merger = account.currentEmployee;
    final estId = account.establishment?.id;
    if (merger == null || estId == null) return;
    final docService = InventoryDocumentService();
    await docService.save(
      establishmentId: estId,
      createdByEmployeeId: merger.id,
      recipientChefId: merger.id,
      recipientEmail: merger.email,
      payload: payload,
    );
  }

  Future<void> _saveStandardExcel(
    Map<String, dynamic> payload, {
    required String saveLang,
    required List<InboxDocument> sourceDocs,
  }) async {
    final loc = _loc;
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final sourceLang = (payload['sourceLang'] as String?)?.trim().isNotEmpty == true
        ? payload['sourceLang'] as String
        : 'ru';

    final namesForSave = <String, String>{};
    if (sourceLang != saveLang) {
      try {
        final translationSvc = context.read<TranslationService>();
        final seen = <String>{};
        for (final r in rows) {
          final name = (r is Map ? (r['productName'] as String?) ?? '' : '').toString().trim();
          if (name.isEmpty || seen.contains(name)) continue;
          seen.add(name);
          final translated = await translationSvc.translate(
            entityType: TranslationEntityType.inventory,
            entityId: 'merge',
            fieldName: 'product_${name.toLowerCase().replaceAll(' ', '_')}',
            text: name,
            from: sourceLang,
            to: saveLang,
          );
          if (translated != null && translated != name) namesForSave[name] = translated;
        }
      } catch (_) {}
    }

    try {
      var maxCols = 1;
      for (final r in rows) {
        final q = (r as Map)['quantities'] as List? ?? [];
        if (q.length > maxCols) maxCols = q.length;
      }

      final excel = Excel.createExcel();
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final fillLabel = loc.t('inventory_excel_fill_data');

      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }

      final sheet = excel['Объединённая инвентаризация'];
      sheet.appendRow(headerCells);

      final sortedRows = rows.map((e) => e as Map<String, dynamic>).toList();
      sortedRows.sort((a, b) {
        final nameA = (namesForSave[a['productName'] ?? ''] ?? (a['productName'] ?? '')).toString().toLowerCase();
        final nameB = (namesForSave[b['productName'] ?? ''] ?? (b['productName'] ?? '')).toString().toLowerCase();
        return nameA.compareTo(nameB);
      });

      var rowNum = 1;
      for (final r in sortedRows) {
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        final name = namesForSave[r['productName'] ?? ''] ?? (r['productName'] ?? '').toString();
        final unit = (r['unit'] ?? '').toString();
        final quantities = (r['quantities'] as List<dynamic>? ?? []).map((q) => (q as num?)?.toDouble() ?? 0.0).toList();
        final rowCells = <CellValue>[
          IntCellValue(rowNum++),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          rowCells.add(DoubleCellValue(c < quantities.length ? quantities[c] : 0.0));
        }
        sheet.appendRow(rowCells);
      }

      excel.setDefaultSheet('Объединённая инвентаризация');
      final out = excel.encode();
      if (out != null && out.isNotEmpty) {
        final date = header['date'] ?? DateTime.now().toIso8601String().split('T').first;
        await saveFileBytes('inventory_merged_$date.xlsx', out);
        if (mounted) {
          final inboxPayload = Map<String, dynamic>.from(payload);
          inboxPayload['mergeMetadata'] = _buildMergeMetadata(sourceDocs);
          inboxPayload['header'] = Map<String, dynamic>.from(header);
          (inboxPayload['header'] as Map<String, dynamic>)['employeeName'] =
              context.read<AccountManagerSupabase>().currentEmployee?.fullName ?? '—';
          await _saveMergedToInbox(inboxPayload);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  /// iiko: выбор бланка из загруженных, мини-превью, данные в «Итого»/«Остаток фактический».
  Future<void> _mergeIikoAndSave(List<InboxDocument> docs) async {
    setState(() => _loading = true);

    // Суммируем по коду, сохраняем оригинальные имена и единицы (тот же язык, те же коды)
    final merged = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? firstHeader;

    for (final doc in docs) {
      final payload = doc.metadata as Map<String, dynamic>? ?? {};
      firstHeader ??= payload['header'] as Map<String, dynamic>? ?? {};
      final rows = payload['rows'] as List<dynamic>? ?? [];

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final code = (row['code'] as String?)?.trim() ?? '';
        if (code.isEmpty) continue;
        final total = (row['total'] as num?)?.toDouble() ?? 0.0;
        if (merged.containsKey(code)) {
          merged[code]!['total'] = (merged[code]!['total'] as double) + total;
        } else {
          merged[code] = {...row, 'total': total};
        }
      }
    }

    final qtyByCode = <String, double>{};
    for (final e in merged.entries) {
      final total = (e.value['total'] as num?)?.toDouble() ?? 0.0;
      if (total > 0 && e.key.isNotEmpty) qtyByCode[e.key] = total;
    }

    final iikoStore = context.read<IikoProductStore>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    await iikoStore.restoreBlankFromStorage(establishmentId: estId);
    setState(() => _loading = false);

    // Выбор бланка: если 1 версия — выгрузка сразу; если несколько — диалог с мини-превью
    final selected = await _showIikoBlankChoiceDialog(iikoStore);
    if (selected == null || !mounted) return;

    setState(() => _loading = true);

    Uint8List outBytes;
    if (selected.$1 != null) {
      outBytes = IikoXlsxPatcher.patch(
        origBytes: selected.$1!,
        defaultQtyCol: selected.$2,
        sheetQtyCols: selected.$3 ?? const {},
        qtyByCode: qtyByCode,
      );
    } else {
      // Fallback: простой Excel
      final excel = Excel.createExcel();
      final sheet = excel['Объединённая iiko'];
      sheet.appendRow([
        TextCellValue('Код'),
        TextCellValue('Наименование'),
        TextCellValue('Ед.изм.'),
        TextCellValue('Итого'),
      ]);
      final sorted = merged.values.toList();
      sorted.sort((a, b) => ((a['name'] ?? '') as String).compareTo((b['name'] ?? '') as String));
      for (final r in sorted) {
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (total <= 0) continue;
        sheet.appendRow([
          TextCellValue(r['code']?.toString() ?? ''),
          TextCellValue(r['name']?.toString() ?? ''),
          TextCellValue(r['unit']?.toString() ?? ''),
          DoubleCellValue(total),
        ]);
      }
      excel.setDefaultSheet('Объединённая iiko');
      final encoded = excel.encode();
      outBytes = encoded != null ? Uint8List.fromList(encoded) : Uint8List(0);
    }

    final dateStr = firstHeader?['date']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10);
    final dateLabel = dateStr.replaceAll(RegExp(r'[T:]'), '-').substring(0, 10);
    final fileName = 'Инвентаризация_iiko_merged_$dateLabel.xlsx';

    setState(() => _loading = false);

    if (outBytes.isNotEmpty) {
      await saveFileBytes(fileName, outBytes);
      if (mounted) {
        final inboxHeader = Map<String, dynamic>.from(firstHeader ?? {});
        inboxHeader['employeeName'] = account.currentEmployee?.fullName ?? '—';
        inboxHeader['date'] = dateStr;
        final inboxPayload = <String, dynamic>{
          'type': 'iiko_inventory',
          'header': inboxHeader,
          'rows': merged.values.toList(),
          'mergeMetadata': _buildMergeMetadata(docs),
        };
        await _saveMergedToInbox(inboxPayload);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  /// Выбор бланка iiko: если 1 версия — без диалога, выгрузка сразу; если несколько — диалог с мини-превью.
  /// Без выбора языка — сохранение исключительно по загруженным наименованиям на том же языке.
  Future<(Uint8List?, int, Map<String, int>?)?> _showIikoBlankChoiceDialog(IikoProductStore iikoStore) async {
    final loc = _loc;
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return null;

    setState(() => _loading = true);
    final metaList = await iikoStore.listBlanksForMerge(estId);
    final blanks = <({String label, Uint8List bytes, int qtyCol, Map<String, int> sheetQtyCols})>[];

    for (var i = 0; i < metaList.length; i++) {
      final m = metaList[i];
      final path = m['storage_path'] as String?;
      if (path == null || path.isEmpty) continue;
      final bytes = await iikoStore.downloadBlankByPath(path);
      if (bytes == null || bytes.isEmpty || !mounted) continue;
      final qtyCol = (m['qty_col_index'] as num?)?.toInt() ?? 5;
      final sheetQtyColsRaw = m['sheet_qty_cols'];
      Map<String, int> sheetQtyCols = {};
      if (sheetQtyColsRaw is Map) {
        sheetQtyCols = Map<String, int>.from(
          (sheetQtyColsRaw as Map).map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 5)),
        );
      }
      final uploadedAt = m['uploaded_at']?.toString();
      final dt = uploadedAt != null
          ? (DateTime.tryParse(uploadedAt)?.toLocal() ?? DateTime.now())
          : DateTime.now();
      final label = DateFormat('dd.MM.yyyy HH:mm').format(dt);
      blanks.add((label: label, bytes: bytes, qtyCol: qtyCol, sheetQtyCols: sheetQtyCols));
    }
    // Если нет версий за 3 месяца — используем загруженный бланк (originalBlankBytes)
    if (blanks.isEmpty && iikoStore.originalBlankBytes != null) {
      blanks.add((
        label: loc.t('inventory_merge_blank_loaded') ?? 'Загруженный бланк',
        bytes: iikoStore.originalBlankBytes!,
        qtyCol: iikoStore.originalQuantityColumnIndex ?? 5,
        sheetQtyCols: iikoStore.sheetQtyColumns,
      ));
    }
    setState(() => _loading = false);

    if (!mounted) return null;
    if (blanks.isEmpty) return null; // Без сообщения — просто отмена

    // Если 1 бланк — выбор не нужен, выгрузка сразу из него
    if (blanks.length == 1) {
      final b = blanks.single;
      return (b.bytes, b.qtyCol, b.sheetQtyCols);
    }

    final result = await showDialog<(Uint8List, int, Map<String, int>)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('inventory_merge_blank_choice') ?? 'Выберите бланк'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('inventory_merge_blank_hint') ?? 'Данные будут записаны в колонку «Итого»/«Остаток фактический» выбранного бланка. Сохранение исключительно по загруженным наименованиям на том же языке.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...blanks.map((b) => _buildBlankPreviewTile(
                label: b.label,
                bytes: b.bytes,
                onSelect: () => Navigator.of(ctx).pop((b.bytes, b.qtyCol, b.sheetQtyCols)),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );

    if (result != null) return (result.$1, result.$2, result.$3);
    return null;
  }

  /// Мини-превью бланка: имена листов + первые строки первого листа.
  Widget _buildBlankPreviewTile({
    required String label,
    required Uint8List bytes,
    required VoidCallback onSelect,
  }) {
    final preview = _buildXlsxPreview(bytes);
    return Card(
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_chart, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    child: Text(
                      preview,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Парсит xlsx и возвращает текст для превью (первые 6 строк первого листа).
  String? _buildXlsxPreview(Uint8List bytes) {
    try {
      final san = IikoXlsxSanitizer.sanitizeForExcelPackage(bytes);
      final excel = Excel.decodeBytes(san.toList());
      final names = excel.tables.keys.toList();
      if (names.isEmpty) return null;
      final sheet = excel.tables[names.first];
      if (sheet == null) return null;
      final sb = StringBuffer();
      sb.writeln('Листы: ${names.take(3).join(", ")}${names.length > 3 ? "..." : ""}');
      for (var r = 0; r < sheet.maxRows && r < 6; r++) {
        final cells = <String>[];
        for (var c = 0; c < (sheet.maxColumns > 8 ? 8 : sheet.maxColumns); c++) {
          final v = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value;
          final s = (v == null ? '' : (v is TextCellValue ? v.value : v.toString()).toString()).trim();
          cells.add(s.isEmpty ? '—' : (s.length > 12 ? '${s.substring(0, 12)}…' : s));
        }
        sb.writeln(cells.join(' | '));
      }
      return sb.toString();
    } catch (_) {
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    final loc = _loc;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');
    final docs = _sortedDocs;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('inventory_merge_title') ?? 'Объединить бланки'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            FilledButton.icon(
              onPressed: docs.isEmpty ? null : _mergeAndSave,
              icon: const Icon(Icons.merge),
              label: Text(loc.t('inventory_merge_save') ?? 'Объединить и сохранить'),
            ),
        ],
      ),
      body: docs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    loc.t('inventory_merge_empty') ?? 'Нет бланков инвентаризации во входящих',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.t('inventory_merge_hint') ?? 'Выберите бланки по дате и времени сохранения. Итоговые количества будут суммированы.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loc.t('inventory_merge_iiko_hint') ?? 'iiko: сохраняется в том же бланке, тот же язык, те же коды. Стандарт: можно выбрать язык сохранения.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  value: _selectedIds.length == docs.length,
                  tristate: true,
                  onChanged: (_) => _selectAll(),
                  title: Text(loc.t('inventory_merge_select_all') ?? 'Выбрать все'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final isSelected = _selectedIds.contains(doc.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(doc.id),
                          secondary: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(doc.icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                          title: Text(doc.getLocalizedTitle(loc)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(doc.employeeName),
                              Text(
                                dateFormat.format(doc.createdAt),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
