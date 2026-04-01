import 'dart:convert';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../../services/account_manager_supabase.dart';
import '../../services/inventory_download.dart';
import '../../services/kitchen_bar_sales_service.dart';
import '../../services/localization_service.dart';
import '../../services/sales_financial_visibility_service.dart';
import '../../utils/pos_order_department.dart';
import '../../widgets/app_bar_home_button.dart';

bool salesStatisticsCanSeeFinancials(Employee e, String establishmentId) {
  if (e.hasRole('owner') && !e.isViewOnlyOwner) return true;
  if (e.department == 'management' &&
      SalesFinancialVisibilityService.instance
          .allowManagementFinancials(establishmentId)) {
    return true;
  }
  return false;
}

/// Статистика продаж по закрытым счетам POS.
class KitchenBarSalesStatisticsScreen extends StatefulWidget {
  const KitchenBarSalesStatisticsScreen({super.key, required this.department});

  final String department;

  @override
  State<KitchenBarSalesStatisticsScreen> createState() =>
      _KitchenBarSalesStatisticsScreenState();
}

class _KitchenBarSalesStatisticsScreenState
    extends State<KitchenBarSalesStatisticsScreen> {
  KitchenBarSalesPeriodKind _periodKind = KitchenBarSalesPeriodKind.month;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _timeFilter = false;
  TimeOfDay _timeStart = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _timeEnd = const TimeOfDay(hour: 22, minute: 0);

  final _filterSub = TextEditingController();
  final _filterType = TextEditingController();
  final _filterName = TextEditingController();
  _QtySort _qtySort = _QtySort.none;

  List<KitchenBarSalesRow> _raw = [];
  bool _loading = false;
  String? _error;

  bool _showSub = true;
  bool _showType = true;
  bool _showCost = true;
  bool _showSelling = true;

  static String _prefsKey(String est) => 'restodocks_sales_stat_prefs_$est';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment?.dataEstablishmentId ?? '';
    if (est.isNotEmpty) {
      await SalesFinancialVisibilityService.instance.initializeForEstablishment(est);
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey(est));
        if (raw != null) {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          setState(() {
            _showSub = j['show_sub'] as bool? ?? true;
            _showType = j['show_type'] as bool? ?? true;
            _showCost = j['show_cost'] as bool? ?? true;
            _showSelling = j['show_selling'] as bool? ?? true;
          });
        }
      } catch (_) {}
    }
    await _reload();
  }

  Future<void> _saveColumnPrefs() async {
    final est =
        context.read<AccountManagerSupabase>().establishment?.dataEstablishmentId;
    if (est == null || est.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey(est),
        jsonEncode({
          'show_sub': _showSub,
          'show_type': _showType,
          'show_cost': _showCost,
          'show_selling': _showSelling,
        }),
      );
    } catch (_) {}
  }

  Future<void> _reload() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment?.dataEstablishmentId;
    final lang = Localizations.localeOf(context).languageCode;
    if (est == null || est.isEmpty) {
      setState(() => _error = 'Нет заведения');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final (startL, endL) = kitchenBarSalesResolvePeriod(
      kind: _periodKind,
      nowLocal: now,
      customStart: _customStart,
      customEnd: _customEnd,
    );
    final startUtc = startL.toUtc();
    final endUtc = endL.toUtc();

    bool paidInTimeWindow(DateTime local) {
      return kitchenBarTimeOfDayInRange(
        local,
        start: _timeStart,
        end: _timeEnd,
      );
    }

    try {
      final rows = await KitchenBarSalesService.instance.aggregate(
        establishmentId: est,
        routeDepartment: widget.department == 'bar' ? 'bar' : 'kitchen',
        rangeStartUtc: startUtc,
        rangeEndUtc: endUtc,
        paidAtLocalFilter: _timeFilter ? paidInTimeWindow : null,
        langCode: lang,
      );
      if (!mounted) return;
      setState(() {
        _raw = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<KitchenBarSalesRow> get _filtered {
    final subQ = _filterSub.text.trim().toLowerCase();
    final typeQ = _filterType.text.trim().toLowerCase();
    final nameQ = _filterName.text.trim().toLowerCase();
    var list = _raw.where((r) {
      if (subQ.isNotEmpty && !r.subdivisionLabel.toLowerCase().contains(subQ)) {
        return false;
      }
      if (typeQ.isNotEmpty && !r.dishTypeLabel.toLowerCase().contains(typeQ)) {
        return false;
      }
      if (nameQ.isNotEmpty && !r.dishName.toLowerCase().contains(nameQ)) {
        return false;
      }
      return true;
    }).toList();
    switch (_qtySort) {
      case _QtySort.asc:
        list.sort((a, b) => a.quantity.compareTo(b.quantity));
        break;
      case _QtySort.desc:
        list.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case _QtySort.none:
        break;
    }
    return list;
  }

  Future<void> _exportExcel() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment?.dataEstablishmentId ?? '';
    if (emp == null || est.isEmpty) return;
    final seeFin = salesStatisticsCanSeeFinancials(emp, est);
    final showCost = seeFin && _showCost;
    final showSell = seeFin && _showSelling;

    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    var c = 0;
    int headerRow = 0;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
      ..value = TextCellValue(loc.t('sales_col_no') ?? '№');
    if (_showSub) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
        ..value = TextCellValue(loc.t('sales_filter_subdivision') ?? '');
    }
    if (_showType) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
        ..value = TextCellValue(loc.t('sales_filter_dish_type') ?? '');
    }
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
      ..value = TextCellValue(loc.t('dish_name') ?? '');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
      ..value = TextCellValue(loc.t('sales_sort_qty') ?? '');
    if (showCost) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
        ..value = TextCellValue(loc.t('sales_col_cost') ?? '');
    }
    if (showSell) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: headerRow))
        ..value = TextCellValue(loc.t('sales_col_selling') ?? '');
    }

    final data = _filtered;
    final fmt = NumberFormat('#0.##', 'ru');
    final fmtMoney = NumberFormat('#0.00', 'ru');
    for (var i = 0; i < data.length; i++) {
      final r = data[i];
      c = 0;
      final row = i + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
        ..value = IntCellValue(i + 1);
      if (_showSub) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
          ..value = TextCellValue(r.subdivisionLabel);
      }
      if (_showType) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
          ..value = TextCellValue(r.dishTypeLabel);
      }
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
        ..value = TextCellValue(r.dishName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
        ..value = TextCellValue(fmt.format(r.quantity));
      if (showCost) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
          ..value = TextCellValue(fmtMoney.format(r.costTotal));
      }
      if (showSell) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: row))
          ..value = TextCellValue(fmtMoney.format(r.sellingTotal));
      }
    }

    final totalCost = data.fold<double>(0, (s, r) => s + r.costTotal);
    final totalSell = data.fold<double>(0, (s, r) => s + r.sellingTotal);
    final tRow = data.length + 2;
    c = 0;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: tRow))
      ..value = TextCellValue(loc.t('sales_total_row') ?? 'Итого');
    if (_showSub) c++;
    if (_showType) c++;
    c++;
    c++;
    if (showCost) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: tRow))
        ..value = TextCellValue(fmtMoney.format(totalCost));
    }
    if (showSell) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c++, rowIndex: tRow))
        ..value = TextCellValue(fmtMoney.format(totalSell));
    }

    final out = excel.encode();
    if (out == null) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fn = 'sales_${widget.department}_$dateStr.xlsx';
    await saveFileBytes(fn, out);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.t('sales_export_saved') ?? 'Excel')),
    );
  }

  @override
  void dispose() {
    _filterSub.dispose();
    _filterType.dispose();
    _filterName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment?.dataEstablishmentId ?? '';
    final seeFin = emp != null && salesStatisticsCanSeeFinancials(emp, est);
    final dept = widget.department == 'bar' ? 'bar' : 'kitchen';
    final titleKey = posDepartmentLabelKeyForRoute(dept);
    final deptTitle = titleKey != null ? loc.t(titleKey) : dept;

    final data = _filtered;
    final fmt = NumberFormat('#0.##', 'ru');
    final fmtM = NumberFormat('#0.00', 'ru');

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('sales_statistics') ?? ''} — $deptTitle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            onPressed: data.isEmpty ? null : _exportExcel,
            tooltip: loc.t('sales_export_excel'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  Text(
                    'Период',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in KitchenBarSalesPeriodKind.values)
                        ChoiceChip(
                          label: Text(_periodLabel(loc, k)),
                          selected: _periodKind == k,
                          onSelected: (_) {
                            setState(() => _periodKind = k);
                            _reload();
                          },
                        ),
                    ],
                  ),
                  if (_periodKind == KitchenBarSalesPeriodKind.custom) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final a = await showDatePicker(
                                context: context,
                                initialDate: _customStart ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (a != null) setState(() => _customStart = a);
                            },
                            child: Text(
                              _customStart == null
                                  ? '…'
                                  : DateFormat.yMd().format(_customStart!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final a = await showDatePicker(
                                context: context,
                                initialDate: _customEnd ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (a != null) setState(() => _customEnd = a);
                            },
                            child: Text(
                              _customEnd == null
                                  ? '…'
                                  : DateFormat.yMd().format(_customEnd!),
                            ),
                          ),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('OK'),
                    ),
                  ],
                  SwitchListTile(
                    title: Text(loc.t('sales_time_window') ?? ''),
                    subtitle: Text(loc.t('sales_time_window_hint') ?? ''),
                    value: _timeFilter,
                    onChanged: (v) {
                      setState(() => _timeFilter = v);
                      _reload();
                    },
                  ),
                  if (_timeFilter)
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            title: Text(
                              MaterialLocalizations.of(context).formatTimeOfDay(
                                _timeStart,
                                alwaysUse24HourFormat: true,
                              ),
                            ),
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _timeStart,
                              );
                              if (t != null) {
                                setState(() => _timeStart = t);
                                _reload();
                              }
                            },
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            title: Text(
                              MaterialLocalizations.of(context).formatTimeOfDay(
                                _timeEnd,
                                alwaysUse24HourFormat: true,
                              ),
                            ),
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _timeEnd,
                              );
                              if (t != null) {
                                setState(() => _timeEnd = t);
                                _reload();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ExpansionTile(
                    title: Text('Колонки таблицы'),
                    children: [
                      CheckboxListTile(
                        title: Text(loc.t('sales_filter_subdivision') ?? ''),
                        value: _showSub,
                        onChanged: (v) {
                          setState(() => _showSub = v ?? true);
                          _saveColumnPrefs();
                        },
                      ),
                      CheckboxListTile(
                        title: Text(loc.t('sales_filter_dish_type') ?? ''),
                        value: _showType,
                        onChanged: (v) {
                          setState(() => _showType = v ?? true);
                          _saveColumnPrefs();
                        },
                      ),
                      if (seeFin) ...[
                        CheckboxListTile(
                          title: Text(loc.t('sales_col_cost') ?? ''),
                          value: _showCost,
                          onChanged: (v) {
                            setState(() => _showCost = v ?? true);
                            _saveColumnPrefs();
                          },
                        ),
                        CheckboxListTile(
                          title: Text(loc.t('sales_col_selling') ?? ''),
                          value: _showSelling,
                          onChanged: (v) {
                            setState(() => _showSelling = v ?? true);
                            _saveColumnPrefs();
                          },
                        ),
                      ],
                    ],
                  ),
                  TextField(
                    controller: _filterSub,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_subdivision'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _filterType,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_dish_type'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _filterName,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_dish_name'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  Row(
                    children: [
                      Text('${loc.t('sales_sort_qty')}:'),
                      DropdownButton<_QtySort>(
                        value: _qtySort,
                        items: [
                          DropdownMenuItem(
                            value: _QtySort.none,
                            child: Text('—'),
                          ),
                          DropdownMenuItem(
                            value: _QtySort.asc,
                            child: Text('↑'),
                          ),
                          DropdownMenuItem(
                            value: _QtySort.desc,
                            child: Text('↓'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _qtySort = v);
                        },
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(loc.t('refresh')),
                  ),
                  const SizedBox(height: 16),
                  if (data.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        loc.t('sales_no_data') ?? '',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text(loc.t('sales_col_no') ?? '№')),
                          if (_showSub)
                            DataColumn(
                              label: Text(loc.t('sales_filter_subdivision') ?? ''),
                            ),
                          if (_showType)
                            DataColumn(
                              label: Text(loc.t('sales_filter_dish_type') ?? ''),
                            ),
                          DataColumn(label: Text(loc.t('dish_name') ?? '')),
                          DataColumn(label: Text(loc.t('sales_sort_qty') ?? '')),
                          if (seeFin && _showCost)
                            DataColumn(label: Text(loc.t('sales_col_cost') ?? '')),
                          if (seeFin && _showSelling)
                            DataColumn(
                              label: Text(loc.t('sales_col_selling') ?? ''),
                            ),
                        ],
                        rows: [
                          for (var i = 0; i < data.length; i++)
                            DataRow(
                              cells: [
                                DataCell(Text('${i + 1}')),
                                if (_showSub)
                                  DataCell(Text(data[i].subdivisionLabel)),
                                if (_showType)
                                  DataCell(Text(data[i].dishTypeLabel)),
                                DataCell(Text(data[i].dishName)),
                                DataCell(Text(fmt.format(data[i].quantity))),
                                if (seeFin && _showCost)
                                  DataCell(Text(fmtM.format(data[i].costTotal))),
                                if (seeFin && _showSelling)
                                  DataCell(Text(fmtM.format(data[i].sellingTotal))),
                              ],
                            ),
                          DataRow(
                            cells: [
                              DataCell(Text(loc.t('sales_total_row') ?? '')),
                              if (_showSub) const DataCell(SizedBox.shrink()),
                              if (_showType) const DataCell(SizedBox.shrink()),
                              const DataCell(SizedBox.shrink()),
                              const DataCell(SizedBox.shrink()),
                              if (seeFin && _showCost)
                                DataCell(Text(
                                  fmtM.format(data.fold<double>(
                                      0, (s, r) => s + r.costTotal)),
                                )),
                              if (seeFin && _showSelling)
                                DataCell(Text(
                                  fmtM.format(data.fold<double>(
                                      0, (s, r) => s + r.sellingTotal)),
                                )),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  String _periodLabel(LocalizationService loc, KitchenBarSalesPeriodKind k) {
    switch (k) {
      case KitchenBarSalesPeriodKind.custom:
        return loc.t('sales_period_custom') ?? '';
      case KitchenBarSalesPeriodKind.shiftDay:
        return loc.t('sales_period_shift') ?? '';
      case KitchenBarSalesPeriodKind.week:
        return loc.t('sales_period_week') ?? '';
      case KitchenBarSalesPeriodKind.month:
        return loc.t('sales_period_month') ?? '';
      case KitchenBarSalesPeriodKind.quarter:
        return loc.t('sales_period_quarter') ?? '';
      case KitchenBarSalesPeriodKind.halfYear:
        return loc.t('sales_period_half_year') ?? '';
      case KitchenBarSalesPeriodKind.year:
        return loc.t('sales_period_year') ?? '';
    }
  }
}

enum _QtySort { none, asc, desc }
