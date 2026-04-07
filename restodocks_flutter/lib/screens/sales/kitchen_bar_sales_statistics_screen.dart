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
import '../../utils/adaptive_time_picker.dart';
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
  List<({TimeOfDay start, TimeOfDay end})> _timeRanges = [
    (
      start: const TimeOfDay(hour: 10, minute: 0),
      end: const TimeOfDay(hour: 22, minute: 0),
    ),
  ];

  String? _filterSubValue;
  String? _filterTypeValue;
  String? _filterNameValue;
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
    final est = acc.establishment?.id ?? '';
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
            _timeFilter = j['time_filter'] as bool? ?? false;
            final tr = j['time_ranges'];
            if (tr is List && tr.isNotEmpty) {
              final parsed = <({TimeOfDay start, TimeOfDay end})>[];
              for (final e in tr) {
                if (e is Map) {
                  final s = _parseTimeStr(e['start']?.toString());
                  final en = _parseTimeStr(e['end']?.toString());
                  if (s != null && en != null) {
                    parsed.add((start: s, end: en));
                  }
                }
              }
              if (parsed.isNotEmpty && parsed.length <= 5) {
                _timeRanges = parsed;
              }
            }
          });
        }
      } catch (_) {}
    }
    await _reload();
  }

  Future<void> _saveStatisticsPrefs() async {
    final est =
        context.read<AccountManagerSupabase>().establishment?.id;
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
          'time_filter': _timeFilter,
          'time_ranges': [
            for (final r in _timeRanges)
              {
                'start': _timeToStr(r.start),
                'end': _timeToStr(r.end),
              },
          ],
        }),
      );
    } catch (_) {}
  }

  String _timeToStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay? _parseTimeStr(String? s) {
    if (s == null || !s.contains(':')) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0].trim());
    final m = int.tryParse(p[1].trim());
    if (h == null || m == null) return null;
    return TimeOfDay(
      hour: h.clamp(0, 23),
      minute: m.clamp(0, 59),
    );
  }

  Future<void> _reload() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment?.id;
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
      return kitchenBarTimeOfDayInAnyRange(local, _timeRanges);
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
        _pruneFiltersToAvailableData();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _pruneFiltersToAvailableData() {
    final subs = _uniqueSubdivisions().toSet();
    final types = _uniqueDishTypes().toSet();
    final names = _uniqueDishNames().toSet();
    if (_filterSubValue != null && !subs.contains(_filterSubValue)) {
      _filterSubValue = null;
    }
    if (_filterTypeValue != null && !types.contains(_filterTypeValue)) {
      _filterTypeValue = null;
    }
    if (_filterNameValue != null && !names.contains(_filterNameValue)) {
      _filterNameValue = null;
    }
  }

  List<String> _uniqueSubdivisions() {
    final s = _raw.map((r) => r.subdivisionLabel).toSet().toList();
    s.sort();
    return s;
  }

  List<String> _uniqueDishTypes() {
    final s = _raw.map((r) => r.dishTypeLabel).toSet().toList();
    s.sort();
    return s;
  }

  List<String> _uniqueDishNames() {
    final s = _raw.map((r) => r.dishName).toSet().toList();
    s.sort();
    return s;
  }

  List<KitchenBarSalesRow> get _filtered {
    var list = _raw.where((r) {
      if (_filterSubValue != null &&
          r.subdivisionLabel != _filterSubValue) {
        return false;
      }
      if (_filterTypeValue != null && r.dishTypeLabel != _filterTypeValue) {
        return false;
      }
      if (_filterNameValue != null && r.dishName != _filterNameValue) {
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
    final est = acc.establishment?.id ?? '';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment?.id ?? '';
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
                    loc.t('sales_period_label') ?? 'Период',
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
                          onSelected: (selected) {
                            if (!selected) return;
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
                      _saveStatisticsPrefs();
                      _reload();
                    },
                  ),
                  if (_timeFilter) ...[
                    for (var i = 0; i < _timeRanges.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final t = await showAdaptiveTimePicker(
                                    context,
                                    initialTime: _timeRanges[i].start,
                                  );
                                  if (t == null || !mounted) return;
                                  setState(() {
                                    final old = _timeRanges[i];
                                    _timeRanges = [
                                      for (var j = 0;
                                          j < _timeRanges.length;
                                          j++)
                                        if (j == i)
                                          (start: t, end: old.end)
                                        else
                                          _timeRanges[j],
                                    ];
                                  });
                                  await _saveStatisticsPrefs();
                                  _reload();
                                },
                                child: Text(
                                  MaterialLocalizations.of(context)
                                      .formatTimeOfDay(
                                    _timeRanges[i].start,
                                    alwaysUse24HourFormat: true,
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '—',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final t = await showAdaptiveTimePicker(
                                    context,
                                    initialTime: _timeRanges[i].end,
                                  );
                                  if (t == null || !mounted) return;
                                  setState(() {
                                    final old = _timeRanges[i];
                                    _timeRanges = [
                                      for (var j = 0;
                                          j < _timeRanges.length;
                                          j++)
                                        if (j == i)
                                          (start: old.start, end: t)
                                        else
                                          _timeRanges[j],
                                    ];
                                  });
                                  await _saveStatisticsPrefs();
                                  _reload();
                                },
                                child: Text(
                                  MaterialLocalizations.of(context)
                                      .formatTimeOfDay(
                                    _timeRanges[i].end,
                                    alwaysUse24HourFormat: true,
                                  ),
                                ),
                              ),
                            ),
                            if (_timeRanges.length > 1)
                              IconButton(
                                tooltip: loc.t('sales_time_remove_range'),
                                icon:
                                    const Icon(Icons.remove_circle_outline),
                                onPressed: () {
                                  setState(() {
                                    _timeRanges = [
                                      for (var j = 0;
                                          j < _timeRanges.length;
                                          j++)
                                        if (j != i) _timeRanges[j],
                                    ];
                                  });
                                  _saveStatisticsPrefs();
                                  _reload();
                                },
                              ),
                          ],
                        ),
                      ),
                    if (_timeRanges.length < 5)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _timeRanges = [
                                ..._timeRanges,
                                (
                                  start: const TimeOfDay(hour: 10, minute: 0),
                                  end: const TimeOfDay(hour: 22, minute: 0),
                                ),
                              ];
                            });
                            _saveStatisticsPrefs();
                          },
                          icon: const Icon(Icons.add),
                          label: Text(loc.t('sales_time_add_range')),
                        ),
                      ),
                  ],
                  ExpansionTile(
                    title: Text(loc.t('sales_columns_expand') ?? 'Колонки таблицы'),
                    children: [
                      CheckboxListTile(
                        title: Text(loc.t('sales_filter_subdivision') ?? ''),
                        value: _showSub,
                        onChanged: (v) {
                          setState(() => _showSub = v ?? true);
                          _saveStatisticsPrefs();
                        },
                      ),
                      CheckboxListTile(
                        title: Text(loc.t('sales_filter_dish_type') ?? ''),
                        value: _showType,
                        onChanged: (v) {
                          setState(() => _showType = v ?? true);
                          _saveStatisticsPrefs();
                        },
                      ),
                      if (seeFin) ...[
                        CheckboxListTile(
                          title: Text(loc.t('sales_col_cost') ?? ''),
                          value: _showCost,
                          onChanged: (v) {
                            setState(() => _showCost = v ?? true);
                            _saveStatisticsPrefs();
                          },
                        ),
                        CheckboxListTile(
                          title: Text(loc.t('sales_col_selling') ?? ''),
                          value: _showSelling,
                          onChanged: (v) {
                            setState(() => _showSelling = v ?? true);
                            _saveStatisticsPrefs();
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _filterSubValue,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_subdivision'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(loc.t('sales_filter_all') ?? 'Все'),
                      ),
                      ..._uniqueSubdivisions().map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _raw.isEmpty
                        ? null
                        : (v) => setState(() => _filterSubValue = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _filterTypeValue,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_dish_type'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(loc.t('sales_filter_all') ?? 'Все'),
                      ),
                      ..._uniqueDishTypes().map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _raw.isEmpty
                        ? null
                        : (v) => setState(() => _filterTypeValue = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    value: _filterNameValue,
                    decoration: InputDecoration(
                      labelText: loc.t('sales_filter_dish_name'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(loc.t('sales_filter_all') ?? 'Все'),
                      ),
                      ..._uniqueDishNames().map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                            e,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _raw.isEmpty
                        ? null
                        : (v) => setState(() => _filterNameValue = v),
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
