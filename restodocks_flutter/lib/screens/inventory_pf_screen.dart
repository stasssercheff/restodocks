import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';

/// Строка: полуфабрикат (ТТК) + количество порций
class _PfRow {
  final TechCard techCard;
  double quantity; // порций

  _PfRow({required this.techCard, required this.quantity});
}

/// Агрегированный продукт (брутто + нетто) для Excel
class _AggregatedProduct {
  final String productId;
  final String productName;
  double grossGrams;
  double netGrams;

  _AggregatedProduct({
    required this.productId,
    required this.productName,
    required this.grossGrams,
    required this.netGrams,
  });
}

/// Бланк инвентаризации полуфабрикатов: список ТТК, ввод количества порций,
/// обратный перерасчёт в продукты (брутто/нетто) и выгрузка в Excel.
class InventoryPfScreen extends StatefulWidget {
  const InventoryPfScreen({super.key});

  @override
  State<InventoryPfScreen> createState() => _InventoryPfScreenState();
}

class _InventoryPfScreenState extends State<InventoryPfScreen> {
  final ScrollController _hScroll = ScrollController();
  final List<_PfRow> _rows = [];
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _completed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTechCards());
  }

  Future<void> _loadTechCards() async {
    final account = context.read<AccountManagerSupabase>();
    final svc = context.read<TechCardServiceSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    final list = await svc.getTechCardsForEstablishment(estId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      for (final tc in list) {
        if (_rows.any((r) => r.techCard.id == tc.id)) continue;
        _rows.add(_PfRow(techCard: tc, quantity: 0));
      }
    });
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _setQuantity(int index, double value) {
    if (index < 0 || index >= _rows.length) return;
    setState(() => _rows[index].quantity = value.clamp(0.0, 99999.0));
  }

  /// Обратный перерасчёт: агрегированные продукты по всем выбранным ПФ
  Map<String, _AggregatedProduct> _aggregateProducts(String lang) {
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final tcById = <String, TechCard>{};
    for (final r in _rows) {
      tcById[r.techCard.id] = r.techCard;
    }
    final result = <String, _AggregatedProduct>{};

    void addIngredients(List<TTIngredient> ingredients, double factor) {
      for (final ing in ingredients) {
        if (ing.productId != null && ing.productName.isNotEmpty) {
          final key = ing.productId!;
          final gross = ing.grossWeight * factor;
          final net = ing.netWeight * factor;
          if (result.containsKey(key)) {
            result[key]!.grossGrams += gross;
            result[key]!.netGrams += net;
          } else {
            result[key] = _AggregatedProduct(
              productId: key,
              productName: ing.productName,
              grossGrams: gross,
              netGrams: net,
            );
          }
        } else if (ing.sourceTechCardId != null) {
          // Полуфабрикат: раскрываем
          final nested = tcById[ing.sourceTechCardId!];
          if (nested != null) {
            final nestedYield = nested.yield > 0 ? nested.yield : nested.totalNetWeight;
            if (nestedYield > 0) {
              final nestedFactor = (ing.netWeight * factor) / nestedYield;
              addIngredients(nested.ingredients, nestedFactor);
            }
          }
        }
      }
    }

    for (final r in _rows) {
      if (r.quantity <= 0) continue;
      final tc = r.techCard;
      final yield = tc.yield > 0 ? tc.yield : tc.totalNetWeight;
      if (yield <= 0) continue;
      final factor = r.quantity * tc.portionWeight / yield;
      addIngredients(tc.ingredients, factor);
    }

    return result;
  }

  Future<void> _pickDate(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: Locale(loc.currentLanguageCode),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _complete(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    final withQuantity = _rows.where((r) => r.quantity > 0).toList();
    if (withQuantity.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('inventory_pf_empty_hint'))));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('inventory_pf_complete_confirm')),
        content: Text(loc.t('inventory_complete_confirm_detail')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.t('inventory_complete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (establishment == null || employee == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('inventory_no_chef'))));
      return;
    }

    final endTime = TimeOfDay.now();
    final lang = loc.currentLanguageCode;
    final chefs = await account.getExecutiveChefsForEstablishment(establishment.id);
    final chef = chefs.isNotEmpty ? chefs.first : null;
    final payload = _buildPayload(establishment: establishment, employee: employee, endTime: endTime, lang: lang);
    final docService = InventoryDocumentService();
    await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: chef?.id ?? '',
      recipientEmail: chef?.email ?? '',
      payload: payload,
    );

    if (mounted) {
      setState(() {
        _endTime = endTime;
        _completed = true;
      });
    }

    try {
      final bytes = _buildExcelBytes(payload, loc);
      if (bytes != null && bytes.isNotEmpty && mounted) {
        await _downloadExcel(bytes, payload, loc);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('inventory_excel_downloaded'))));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.t('inventory_document_saved')} (Excel: $e)')));
    }
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required TimeOfDay endTime,
    required String lang,
  }) {
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'timeStart': _startTime != null
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
          : null,
      'timeEnd': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
    final pfList = _rows.where((r) => r.quantity > 0).map((r) => {
      'dishName': r.techCard.getLocalizedDishName(lang),
      'quantity': r.quantity,
    }).toList();
    final agg = _aggregateProducts(lang).values.toList();
    agg.sort((a, b) => a.productName.compareTo(b.productName));
    final products = agg.map((p) => {
      'productId': p.productId,
      'productName': p.productName,
      'grossGrams': p.grossGrams,
      'netGrams': p.netGrams,
    }).toList();
    return {'header': header, 'pfList': pfList, 'products': products};
  }

  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    try {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      final lang = loc.currentLanguageCode;

      // Часть 1: список полуфабрикатов с количеством
      sheet.appendRow([
        TextCellValue(loc.t('inventory_pf_list_title')),
      ]);
      sheet.appendRow([
        TextCellValue(loc.t('inventory_pf_dish')),
        TextCellValue(loc.t('inventory_pf_quantity')),
      ]);
      final pfList = payload['pfList'] as List<dynamic>? ?? [];
      for (final p in pfList) {
        final m = p as Map<String, dynamic>;
        sheet.appendRow([
          TextCellValue((m['dishName'] as String? ?? '').toString()),
          DoubleCellValue((m['quantity'] as num?)?.toDouble() ?? 0),
        ]);
      }
      sheet.appendRow([]);

      // Часть 2: таблица продуктов (номер, продукт, брутто гр, нетто гр)
      sheet.appendRow([
        TextCellValue(loc.t('inventory_pf_products_title')),
      ]);
      sheet.appendRow([
        TextCellValue(loc.t('inventory_excel_number')),
        TextCellValue(loc.t('inventory_item_name')),
        TextCellValue(loc.t('inventory_pf_gross_g')),
        TextCellValue(loc.t('inventory_pf_net_g')),
      ]);
      final products = payload['products'] as List<dynamic>? ?? [];
      for (var i = 0; i < products.length; i++) {
        final p = products[i] as Map<String, dynamic>;
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue((p['productName'] as String? ?? '').toString()),
          IntCellValue(((p['grossGrams'] as num?)?.toDouble() ?? 0).round()),
          IntCellValue(((p['netGrams'] as num?)?.toDouble() ?? 0).round()),
        ]);
      }

      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadExcel(List<int> bytes, Map<String, dynamic> payload, LocalizationService loc) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ?? DateTime.now().toIso8601String().split('T').first;
    await saveFileBytes('inventory_pf_$date.xlsx', bytes);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('inventory_pf_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(loc, establishment, employee),
                const Divider(height: 1),
                Expanded(child: _buildTable(loc)),
                const Divider(height: 1),
                _buildFooter(loc),
              ],
            ),
    );
  }

  Widget _buildHeader(
    LocalizationService loc,
    Establishment? establishment,
    Employee? employee,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _headerChip(theme, Icons.store, loc.t('inventory_establishment'), establishment?.name ?? '—'),
              _headerChip(theme, Icons.person, loc.t('inventory_employee'), employee?.fullName ?? '—'),
              InkWell(
                onTap: () => _pickDate(context),
                borderRadius: BorderRadius.circular(8),
                child: _headerChip(
                  theme,
                  Icons.calendar_today,
                  loc.t('inventory_date'),
                  '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                ),
              ),
              _headerChip(
                theme,
                Icons.access_time,
                loc.t('inventory_time_fill'),
                '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'} → '
                    '${_endTime != null ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}' : '...'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerChip(ThemeData theme, IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable(LocalizationService loc) {
    final lang = loc.currentLanguageCode;
    final theme = Theme.of(context);

    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(loc.t('inventory_pf_empty_tech_cards'), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(loc.t('inventory_pf_empty_hint'), style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      controller: _hScroll,
      child: SingleChildScrollView(
        controller: _hScroll,
        padding: const EdgeInsets.all(16),
        child: Table(
          border: TableBorder.all(width: 0.5, color: Colors.grey),
          columnWidths: const {
            0: FlexColumnWidth(0.5),
            1: FlexColumnWidth(2.5),
            2: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withOpacity(0.3)),
              children: [
                _cell(loc.t('inventory_excel_number'), bold: true),
                _cell(loc.t('inventory_pf_dish'), bold: true),
                _cell(loc.t('inventory_pf_quantity'), bold: true),
              ],
            ),
            ..._rows.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              return TableRow(
                children: [
                  _cell('${i + 1}'),
                  _cell(r.techCard.getLocalizedDishName(lang)),
                  TableCell(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: _completed
                          ? Text(r.quantity.toStringAsFixed(r.quantity == r.quantity.truncateToDouble() ? 0 : 1), style: const TextStyle(fontSize: 13))
                          : _QuantityField(
                              value: r.quantity,
                              suffix: loc.t('inventory_pf_portions'),
                              onChanged: (v) => _setQuantity(i, v),
                            ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, {bool bold = false}) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : null)),
      ),
    );
  }

  Widget _buildFooter(LocalizationService loc) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            onPressed: _completed ? null : () { _complete(context); },
            icon: const Icon(Icons.check_circle),
            label: Text(loc.t('inventory_complete')),
          ),
        ],
      ),
    );
  }
}

class _QuantityField extends StatefulWidget {
  const _QuantityField({required this.value, required this.suffix, required this.onChanged});

  final double value;
  final String suffix;
  final void Function(double v) onChanged;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value > 0 ? widget.value.toString() : '');
  }

  @override
  void didUpdateWidget(covariant _QuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_ctrl.selection.isValid) {
      _ctrl.text = widget.value > 0 ? widget.value.toString() : '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.suffix,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (v) {
        final n = double.tryParse(v.replaceFirst(',', '.'));
        widget.onChanged(n ?? 0);
      },
    );
  }
}
