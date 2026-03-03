import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
  /// Переводы названий продуктов: оригинальное имя -> переведённое
  final Map<String, String> _translatedNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _translatedNames.clear();
    });
    final doc = await InventoryDocumentService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      if (doc == null) _error = 'Документ не найден';
    });
    if (doc != null) {
      _loadTranslations(doc);
    }
  }

  Future<void> _loadTranslations(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final sourceLang = (payload['sourceLang'] as String?)?.trim().isNotEmpty == true
        ? payload['sourceLang'] as String
        : 'ru';
    if (targetLang == sourceLang) return;

    final rows = payload['rows'] as List<dynamic>? ?? [];
    final docId = doc['id']?.toString() ?? widget.documentId;

    try {
      final translationSvc = context.read<TranslationService>();
      // Собираем уникальные имена, чтобы не переводить одно и то же дважды
      final seen = <String>{};
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = (r['productName'] as String? ?? '').trim();
        if (name.isEmpty || seen.contains(name)) continue;
        seen.add(name);
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.inventory,
          entityId: docId,
          fieldName: 'product_${name.toLowerCase().replaceAll(' ', '_')}',
          text: name,
          from: sourceLang,
          to: targetLang,
        );
        if (translated != null && translated != name && mounted) {
          setState(() => _translatedNames[name] = translated);
        }
      }
    } catch (_) {}
  }

  /// Возвращает строки, отсортированные по (переведённому) названию А-Я
  List<Map<String, dynamic>> _sortedRows(List<dynamic> rows) {
    final list = rows.map((e) => e as Map<String, dynamic>).toList();
    list.sort((a, b) {
      final nameA = (_translatedNames[(a['productName'] as String? ?? '')] ?? (a['productName'] as String? ?? '')).toLowerCase();
      final nameB = (_translatedNames[(b['productName'] as String? ?? '')] ?? (b['productName'] as String? ?? '')).toLowerCase();
      return nameA.compareTo(nameB);
    });
    return list;
  }

  Future<void> _saveToFile({bool withPrice = false}) async {
    final doc = _doc;
    final loc = context.read<LocalizationService>();
    if (doc == null) return;

    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final aggregated = payload['aggregatedProducts'] as List<dynamic>? ?? [];

    Map<String, double>? pricePerProduct;
    String? establishmentId;
    if (withPrice) {
      establishmentId = doc['establishment_id'] as String?;
      if (establishmentId != null) {
        final store = context.read<ProductStoreSupabase>();
        await store.loadNomenclature(establishmentId);
        pricePerProduct = {};
        for (final r in rows) {
          final pid = (r as Map<String, dynamic>)['productId'] as String?;
          if (pid != null && !pid.startsWith('pf_') && !pid.startsWith('free_')) {
            final priceInfo = store.getEstablishmentPrice(pid, establishmentId);
            if (priceInfo != null && priceInfo.$1 != null) {
              pricePerProduct[pid] = priceInfo.$1!;
            }
          }
        }
      }
    }

    try {
      var maxCols = 0;
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        if (quantities.length > maxCols) maxCols = quantities.length;
      }
      if (maxCols < 1) maxCols = 1;

      final excel = Excel.createExcel();
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final sumLabel = loc.t('inventory_excel_sum') ?? 'Сумма';
      final fillLabel = loc.t('inventory_excel_fill_data');

      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        if (withPrice) TextCellValue(sumLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }

      // ЛИСТ 1: Продукты + ПФ с итогами + перерасчёт ПФ в брутто
      final sheet1 = excel['Продукты + ПФ'];
      sheet1.appendRow(headerCells);

      // Сортируем и переводим названия для Excel так же, как в UI
      final rowsSorted = _sortedRows(rows);
      var rowNum = 1;
      double totalSumAll = 0;
      for (var i = 0; i < rowsSorted.length; i++) {
        final r = rowsSorted[i];
        final originalName = r['productName'] as String? ?? '';
        final name = _translatedNames[originalName] ?? originalName;
        final unit = r['unit'] as String? ?? '';
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        double rowSum = 0;
        if (withPrice && pricePerProduct != null && establishmentId != null) {
          final pid = r['productId'] as String?;
          if (pid != null && !pid.startsWith('pf_') && !pid.startsWith('free_')) {
            final price = pricePerProduct[pid];
            if (price != null && price > 0) {
              final totalKg = total / 1000;
              rowSum = totalKg * price;
              totalSumAll += rowSum;
            }
          }
        }
        final rowCells = <CellValue>[
          IntCellValue(rowNum++),
          TextCellValue(name),
          TextCellValue(unit),
          if (withPrice) DoubleCellValue(rowSum),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? (quantities[c] as num?)?.toDouble() ?? 0.0 : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet1.appendRow(rowCells);
      }
      if (withPrice && totalSumAll > 0) {
        final totalLabelFinal = loc.t('inventory_excel_total_sum') ?? 'Итого:';
        final totalRow = <CellValue>[
          TextCellValue(''),
          TextCellValue(totalLabelFinal),
          TextCellValue(''),
        ];
        if (withPrice) totalRow.add(DoubleCellValue(totalSumAll));
        totalRow.add(DoubleCellValue(0));
        for (var c = 0; c < maxCols; c++) totalRow.add(TextCellValue(''));
        sheet1.appendRow(totalRow);
      }

      if (aggregated.isNotEmpty) {
        sheet1.appendRow([]);
        sheet1.appendRow([TextCellValue(loc.t('inventory_pf_products_title'))]);
        sheet1.appendRow([
          TextCellValue(numLabel),
          TextCellValue(nameLabel),
          TextCellValue(loc.t('inventory_pf_gross_g')),
          TextCellValue(loc.t('inventory_pf_net_g')),
        ]);
        final groupedProducts = <String, Map<String, dynamic>>{};
        for (final p in aggregated) {
          final name = (p['productName'] as String? ?? '').trim();
          final gross = (p['grossGrams'] as num?)?.toDouble() ?? 0.0;
          final net = (p['netGrams'] as num?)?.toDouble() ?? 0.0;
          if (groupedProducts.containsKey(name)) {
            groupedProducts[name]!['grossGrams'] = (groupedProducts[name]!['grossGrams'] as double) + gross;
            groupedProducts[name]!['netGrams'] = (groupedProducts[name]!['netGrams'] as double) + net;
          } else {
            groupedProducts[name] = {'productName': name, 'grossGrams': gross, 'netGrams': net};
          }
        }
        final groupedList = groupedProducts.values.toList()
          ..sort((a, b) {
            final nameA = (_translatedNames[a['productName'] as String? ?? ''] ?? (a['productName'] as String? ?? '')).toLowerCase();
            final nameB = (_translatedNames[b['productName'] as String? ?? ''] ?? (b['productName'] as String? ?? '')).toLowerCase();
            return nameA.compareTo(nameB);
          });
        for (var i = 0; i < groupedList.length; i++) {
          final p = groupedList[i];
          final originalName = (p['productName'] as String? ?? '');
          final displayName = _translatedNames[originalName] ?? originalName;
          sheet1.appendRow([
            IntCellValue(i + 1),
            TextCellValue(displayName),
            IntCellValue((p['grossGrams'] as double).round()),
            IntCellValue((p['netGrams'] as double).round()),
          ]);
        }
      }

      // ЛИСТ 2: Все продукты включая данные из ПФ
      final sheet2 = excel['Все продукты с ПФ'];
      sheet2.appendRow(headerCells);

      final allProducts = <String, Map<String, dynamic>>{};
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        if (allProducts.containsKey(name)) {
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + total;
          final existingQ = existing['quantities'] as List<double>;
          for (var c = 0; c < quantities.length && c < existingQ.length; c++) {
            existingQ[c] += (quantities[c] as num?)?.toDouble() ?? 0.0;
          }
        } else {
          allProducts[name] = {
            'productName': name,
            'unit': unit,
            'total': total,
            'quantities': List<double>.from(quantities.map((q) => (q as num?)?.toDouble() ?? 0.0)),
          };
        }
      }
      for (final p in aggregated) {
        final name = (p['productName'] as String?)?.trim() ?? '';
        final grossGrams = (p['grossGrams'] as num?)?.toDouble() ?? 0.0;
        if (allProducts.containsKey(name)) {
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + grossGrams;
          final quantities = existing['quantities'] as List<double>;
          if (quantities.isNotEmpty) {
            quantities[0] += grossGrams;
          } else {
            quantities.add(grossGrams);
          }
        } else {
          allProducts[name] = {
            'productName': name,
            'unit': 'g',
            'total': grossGrams,
            'quantities': [grossGrams],
          };
        }
      }

      final sortedProducts = allProducts.values.toList()
        ..sort((a, b) {
          final nameA = (_translatedNames[a['productName'] as String? ?? ''] ?? (a['productName'] as String? ?? '')).toLowerCase();
          final nameB = (_translatedNames[b['productName'] as String? ?? ''] ?? (b['productName'] as String? ?? '')).toLowerCase();
          return nameA.compareTo(nameB);
        });
      for (var i = 0; i < sortedProducts.length; i++) {
        final p = sortedProducts[i];
        final originalName = p['productName'] as String;
        final name = _translatedNames[originalName] ?? originalName;
        final unit = p['unit'] as String;
        final total = p['total'] as double;
        final quantities = p['quantities'] as List<double>;
        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          rowCells.add(DoubleCellValue(c < quantities.length ? quantities[c] : 0.0));
        }
        sheet2.appendRow(rowCells);
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
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final sortedRows = _sortedRows(rows);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('inventory_blank_title')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Сохранить',
            onSelected: (v) => _saveToFile(withPrice: v == 'with_price'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'no_price', child: Text(loc.t('inventory_export_no_price') ?? 'Без цены')),
              PopupMenuItem(value: 'with_price', child: Text(loc.t('inventory_export_with_price') ?? 'С ценой')),
            ],
          ),
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
            _buildTable(theme, loc, sortedRows),
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

  Widget _buildTable(ThemeData theme, LocalizationService loc, List<Map<String, dynamic>> rows) {
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
          final r = e.value;
          final originalName = (r['productName'] ?? '').toString();
          final displayName = _translatedNames[originalName] ?? originalName;
          return TableRow(
            children: [
              _cell(theme, '${e.key + 1}'),
              _cell(theme, displayName),
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
