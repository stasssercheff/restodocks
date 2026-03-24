import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../../services/inventory_download.dart';
import '../../services/services.dart';
import '../../utils/number_format_utils.dart';
import '../../widgets/app_bar_home_button.dart';
import '../../widgets/scroll_to_top_app_bar_title.dart';
import '../salary_expense_screen.dart';

/// Экран «Расходы» для собственника: вкладки «ФЗП», «Заказы продуктов», «Списания».
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

enum _ExpensesTab { fzp, productOrders, writeoffs }

class _ExpensesScreenState extends State<ExpensesScreen> {
  _ExpensesTab _selectedTab = _ExpensesTab.fzp;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: ScrollToTopAppBarTitle(
          child: Text(loc.t('expenses') ?? 'Расходы'),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabChip(_ExpensesTab.fzp, loc.t('salary_tab_fzp') ?? 'ФЗП', loc),
                  const SizedBox(width: 8),
                  _buildTabChip(_ExpensesTab.productOrders, loc.t('expenses_tab_product_orders') ?? 'Заказы продуктов', loc),
                  const SizedBox(width: 8),
                  _buildTabChip(_ExpensesTab.writeoffs, loc.t('expenses_tab_writeoffs') ?? 'Списания', loc),
                ],
              ),
            ),
          ),
          Expanded(
            child: _selectedTab == _ExpensesTab.fzp
                ? const SalaryExpenseScreen(embedInScaffold: false)
                : _selectedTab == _ExpensesTab.productOrders
                    ? const _ProductOrdersTab()
                    : const _WriteoffsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(_ExpensesTab tab, String label, LocalizationService loc) {
    final isSelected = _selectedTab == tab;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _selectedTab = tab),
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }
}

class _ProductOrdersTab extends StatefulWidget {
  const _ProductOrdersTab();

  @override
  State<_ProductOrdersTab> createState() => _ProductOrdersTabState();
}

class _ProductOrdersTabState extends State<_ProductOrdersTab> {
  List<Map<String, dynamic>> _allOrders = [];
  bool _loading = true;
  String? _error;

  /// Диапазон дат: начало и конец (включительно).
  late DateTime _dateStart;
  late DateTime _dateEnd;

  /// Выбранные поставщики (пусто = все).
  Set<String> _selectedSupplierNames = {};

  /// ID заказов, исключённых из итога (например, отправлены по ошибке). Сохраняется в SharedPreferences.
  Set<String> _excludedFromTotalOrderIds = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateStart = DateTime(now.year, now.month, 1);
    _dateEnd = DateTime(now.year, now.month + 1, 0);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        setState(() {
          _loading = false;
          _error = 'Заведение не выбрано';
        });
        return;
      }
      final docs = await OrderDocumentService().listForEstablishment(establishmentId);

      if (mounted) {
        final excluded = await _loadExcludedOrderIds(establishmentId);
        setState(() {
          _allOrders = docs;
          _excludedFromTotalOrderIds = excluded;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final dayStart = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
    final dayEnd = DateTime(_dateEnd.year, _dateEnd.month, _dateEnd.day, 23, 59, 59);
    return _allOrders.where((d) {
      final createdAt = DateTime.tryParse(d['created_at']?.toString() ?? '');
      if (createdAt == null) return false;
      if (createdAt.isBefore(dayStart) || createdAt.isAfter(dayEnd)) return false;
      if (_selectedSupplierNames.isNotEmpty) {
        final payload = d['payload'] as Map<String, dynamic>? ?? {};
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final supplier = (header['supplierName'] as String? ?? '').trim();
        if (!_selectedSupplierNames.contains(supplier)) return false;
      }
      return true;
    }).toList();
  }

  Set<String> get _uniqueSupplierNames {
    final names = <String>{};
    for (final d in _allOrders) {
      final payload = d['payload'] as Map<String, dynamic>? ?? {};
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      final s = (header['supplierName'] as String? ?? '').trim();
      if (s.isNotEmpty) names.add(s);
    }
    return names;
  }

  static const String _prefsKeyPrefix = 'expenses_orders_excluded_';

  Future<Set<String>> _loadExcludedOrderIds(String establishmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$establishmentId';
      final json = prefs.getString(key);
      if (json == null) return {};
      final list = jsonDecode(json) as List<dynamic>?;
      if (list == null) return {};
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _setOrderIncludedInTotal(String orderId, bool include) async {
    final id = orderId.toString();
    setState(() {
      if (include) {
        _excludedFromTotalOrderIds.remove(id);
      } else {
        _excludedFromTotalOrderIds.add(id);
      }
    });
    final account = context.read<AccountManagerSupabase>();
    final establishmentId = account.establishment?.id;
    if (establishmentId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$establishmentId';
      await prefs.setString(key, jsonEncode(_excludedFromTotalOrderIds.toList()));
    } catch (_) {}
  }

  Future<void> _showDateRangePicker(LocalizationService loc) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _dateStart, end: _dateEnd),
      helpText: loc.t('expenses_orders_date_range') ?? 'Диапазон дат',
    );
    if (range != null && mounted) {
      setState(() {
        _dateStart = DateTime(range.start.year, range.start.month, range.start.day);
        _dateEnd = DateTime(range.end.year, range.end.month, range.end.day);
      });
    }
  }

  Future<void> _showSupplierFilter(LocalizationService loc) async {
    final suppliers = _uniqueSupplierNames.toList()..sort();
    var showAll = _selectedSupplierNames.isEmpty;
    var selected = Set<String>.from(_selectedSupplierNames);
    if (showAll) selected = Set.from(suppliers);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(loc.t('expenses_orders_filter_suppliers') ?? 'Выбор поставщиков'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      title: Text(loc.t('expenses_orders_all_suppliers') ?? 'Все поставщики'),
                      value: showAll,
                      onChanged: (v) {
                        setDialogState(() {
                          showAll = v ?? true;
                          if (showAll) selected = {};
                        });
                      },
                    ),
                    const Divider(),
                    ...suppliers.map((s) => CheckboxListTile(
                      title: Text(s, overflow: TextOverflow.ellipsis),
                      value: showAll || selected.contains(s),
                      tristate: false,
                      onChanged: showAll ? null : (v) {
                        setDialogState(() {
                          if (v == true) {
                            selected.add(s);
                          } else {
                            selected.remove(s);
                          }
                        });
                      },
                    )),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(loc.t('cancel') ?? 'Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(showAll ? {} : selected),
                  child: Text(loc.t('apply') ?? 'Применить'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null && mounted) {
      setState(() => _selectedSupplierNames = result);
    }
  }

  /// Диалог выбора поставщиков для экспорта (не меняет состояние фильтра).
  Future<Set<String>?> _showSupplierPickerForExport(LocalizationService loc) async {
    final suppliers = _uniqueSupplierNames.toList()..sort();
    var showAll = true;
    var selected = <String>{};

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(loc.t('expenses_orders_export_suppliers') ?? 'Поставщики для выгрузки'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      title: Text(loc.t('expenses_orders_all_suppliers') ?? 'Все поставщики'),
                      value: showAll,
                      onChanged: (v) {
                        setDialogState(() {
                          showAll = v ?? true;
                          if (showAll) selected = {};
                        });
                      },
                    ),
                    const Divider(),
                    ...suppliers.map((s) => CheckboxListTile(
                      title: Text(s, overflow: TextOverflow.ellipsis),
                      value: showAll || selected.contains(s),
                      tristate: false,
                      onChanged: showAll ? null : (v) {
                        setDialogState(() {
                          if (v == true) {
                            selected.add(s);
                          } else {
                            selected.remove(s);
                          }
                        });
                      },
                    )),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: Text(loc.t('cancel') ?? 'Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(showAll ? {} : selected),
                  child: Text(loc.t('apply') ?? 'Применить'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportProductOrders() async {
    if (_allOrders.isEmpty) return;
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final currency = account.establishment?.defaultCurrency ?? 'VND';
    final dateFormat = DateFormat('dd.MM.yyyy');

    // 1. Выбор диапазона дат
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _dateStart, end: _dateEnd),
      helpText: loc.t('expenses_orders_export_date_range') ?? 'Диапазон дат для выгрузки',
    );
    if (range == null || !mounted) return;
    final exportStart = DateTime(range.start.year, range.start.month, range.start.day);
    final exportEnd = DateTime(range.end.year, range.end.month, range.end.day);

    // 2. Выбор поставщиков
    final exportSuppliers = await _showSupplierPickerForExport(loc);
    if (exportSuppliers == null || !mounted) return;

    // 3. Выбор языка
    final selectedLang = await showDialog<String>(
      context: context,
      builder: (ctx) => _ProductOrdersExportLanguageDialog(loc: loc),
    );
    if (selectedLang == null || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(loc.t('expenses_orders_export_loading') ?? 'Выгрузка...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final t = (String key) => loc.tForLanguage(selectedLang, key);
      final bytes = await OrderListExportService.buildProductOrdersExpenseExcelBytes(
        orders: _allOrders,
        dateStart: exportStart,
        dateEnd: exportEnd,
        selectedSupplierNames: exportSuppliers,
        t: t,
        currency: currency,
      );
      final fileName = 'product_orders_${dateFormat.format(exportStart)}_${dateFormat.format(exportEnd)}.xlsx';
      await saveFileBytes(fileName, bytes);

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            (loc.t('expenses_orders_export_saved') ?? 'Выгружено') + ': $fileName',
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            loc.t('expenses_orders_export_error') ?? 'Ошибка выгрузки: $e',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final currency = account.establishment?.defaultCurrency ?? 'VND';
    final currencySymbol = account.establishment?.currencySymbol ?? Establishment.currencySymbolFor(currency);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
            ],
          ),
        ),
      );
    }

    final filteredOrders = _filteredOrders;
    double totalSum = 0;
    for (final order in filteredOrders) {
      final orderId = order['id']?.toString() ?? '';
      if (_excludedFromTotalOrderIds.contains(orderId)) continue;
      final payload = order['payload'] as Map<String, dynamic>? ?? {};
      final grand = (payload['grandTotal'] as num?)?.toDouble();
      if (grand != null) totalSum += grand;
    }

    final dateFormat = DateFormat('dd.MM.yyyy');

    if (_allOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('product_order_received_empty') ?? 'Отправленные заказы будут отображаться здесь',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => _showDateRangePicker(loc),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.date_range, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          loc.t('expenses_orders_date_range') ?? 'Диапазон дат',
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                        Text(
                                          '${dateFormat.format(_dateStart)} — ${dateFormat.format(_dateEnd)}',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () => _showSupplierFilter(loc),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.store_outlined, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          loc.t('order_tab_suppliers') ?? 'Поставщики',
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                        Text(
                                          _selectedSupplierNames.isEmpty
                                              ? (loc.t('expenses_orders_all_suppliers') ?? 'Все')
                                              : '${_selectedSupplierNames.length} ${loc.t('expenses_orders_selected') ?? 'выбрано'}',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      icon: const Icon(Icons.download),
                      onPressed: _exportProductOrders,
                      tooltip: loc.t('expenses_orders_export_btn') ?? 'Выгрузить Excel',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off, size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          loc.t('expenses_orders_empty_filter') ?? 'Нет заказов за выбранный период и поставщиков',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filteredOrders.length,
              itemBuilder: (_, i) {
                final order = filteredOrders[i];
                final orderId = order['id']?.toString() ?? '';
                final payload = order['payload'] as Map<String, dynamic>? ?? {};
                final header = payload['header'] as Map<String, dynamic>? ?? {};
                final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();
                final dateStr = DateFormat('dd.MM.yyyy').format(createdAt);
                final employeeName = header['employeeName'] ?? '—';
                final supplier = header['supplierName'] ?? '—';
                final grandTotal = (payload['grandTotal'] as num?)?.toDouble();
                final sumStr = grandTotal != null
                    ? NumberFormatUtils.formatSum(grandTotal, currency)
                    : '—';
                final includedInTotal = !_excludedFromTotalOrderIds.contains(orderId);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => context.push('/inbox/order/${order['id']}'),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Tooltip(
                            message: loc.t('expenses_orders_include_in_total_hint') ?? 'Учитывать в итоге затрат',
                            child: SizedBox(
                              width: 40,
                              child: Checkbox(
                                value: includedInTotal,
                                onChanged: (v) {
                                  _setOrderIncludedInTotal(orderId, v ?? true);
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                fillColor: WidgetStateProperty.resolveWith((states) {
                                  if (!includedInTotal) return Theme.of(context).colorScheme.outline;
                                  return null;
                                }),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$dateStr · ${header['supplierName'] ?? '—'}', style: Theme.of(context).textTheme.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  '${loc.t('inbox_header_employee') ?? 'Сотрудник'}: $employeeName',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            sumStr,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        loc.t('salary_total_all') ?? 'Итого по всем',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${NumberFormatUtils.formatSum(totalSum, currency)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (filteredOrders.isNotEmpty) ...[
                    Builder(
                      builder: (_) {
                        final excludedCount = filteredOrders.where((o) => _excludedFromTotalOrderIds.contains(o['id']?.toString())).length;
                        if (excludedCount == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            (loc.t('expenses_orders_excluded_from_total') ?? 'Не включено в итог: %s').replaceAll('%s', '$excludedCount'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Вкладка «Списания» в Расходах: список списаний за период, выбор для итога, сумма затрат.
class _WriteoffsTab extends StatefulWidget {
  const _WriteoffsTab();

  @override
  State<_WriteoffsTab> createState() => _WriteoffsTabState();
}

class _WriteoffsTabState extends State<_WriteoffsTab> {
  List<Map<String, dynamic>> _allDocs = [];
  bool _loading = true;
  String? _error;
  late DateTime _dateStart;
  late DateTime _dateEnd;
  /// ID списаний, включённых в итог (пусто = все включены). Аналогично заказам — снятая галочка = исключить из итога.
  Set<String> _excludedFromTotalIds = {};
  static const String _prefsKeyPrefix = 'expenses_writeoffs_excluded_';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateStart = DateTime(now.year, now.month, 1);
    _dateEnd = DateTime(now.year, now.month + 1, 0);
    _load();
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final establishmentId = account.establishment?.id;
    if (establishmentId == null) {
      setState(() {
        _loading = false;
        _error = 'Заведение не выбрано';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await InventoryDocumentService().listForEstablishment(establishmentId);
      final docs = raw.where((d) {
        final p = d['payload'] as Map<String, dynamic>?;
        return p?['type']?.toString() == 'writeoff';
      }).toList();
      if (mounted) {
        final excluded = await _loadExcludedIds(establishmentId);
        setState(() {
          _allDocs = docs;
          _excludedFromTotalIds = excluded;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<Set<String>> _loadExcludedIds(String establishmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$establishmentId';
      final json = prefs.getString(key);
      if (json == null) return {};
      final list = jsonDecode(json) as List<dynamic>?;
      return list?.map((e) => e.toString()).toSet() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _setIncludedInTotal(String docId, bool include) async {
    final id = docId.toString();
    setState(() {
      if (include) {
        _excludedFromTotalIds.remove(id);
      } else {
        _excludedFromTotalIds.add(id);
      }
    });
    final establishmentId = context.read<AccountManagerSupabase>().establishment?.id;
    if (establishmentId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsKeyPrefix$establishmentId', jsonEncode(_excludedFromTotalIds.toList()));
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filteredDocs {
    final dayStart = DateTime(_dateStart.year, _dateStart.month, _dateStart.day);
    final dayEnd = DateTime(_dateEnd.year, _dateEnd.month, _dateEnd.day, 23, 59, 59);
    return _allDocs.where((d) {
      final createdAt = DateTime.tryParse(d['created_at']?.toString() ?? '');
      if (createdAt == null) return false;
      return !createdAt.isBefore(dayStart) && !createdAt.isAfter(dayEnd);
    }).toList();
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

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'RUB';
    final dateFormat = DateFormat('dd.MM.yyyy');

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredDocs;
    double totalSelected = 0;
    double totalPeriod = 0;
    for (final doc in filtered) {
      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
      final cost = (payload['costTotal'] as num?)?.toDouble();
      if (cost != null && cost > 0) totalPeriod += cost;
      if (!_excludedFromTotalIds.contains(doc['id']?.toString())) {
        if (cost != null && cost > 0) totalSelected += cost;
      }
    }

    if (_allDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.remove_circle_outline, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('expenses_writeoffs_empty') ?? 'Списания появятся здесь после отправки из экрана списаний',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  initialDateRange: DateTimeRange(start: _dateStart, end: _dateEnd),
                  helpText: loc.t('expenses_orders_date_range') ?? 'Диапазон дат',
                );
                if (range != null && mounted) {
                  setState(() {
                    _dateStart = DateTime(range.start.year, range.start.month, range.start.day);
                    _dateEnd = DateTime(range.end.year, range.end.month, range.end.day);
                  });
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.date_range, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.t('expenses_orders_date_range') ?? 'Диапазон дат',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${dateFormat.format(_dateStart)} — ${dateFormat.format(_dateEnd)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      loc.t('expenses_orders_empty_filter') ?? 'Нет за период',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final doc = filtered[i];
                      final docId = doc['id']?.toString() ?? '';
                      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
                      final header = payload['header'] as Map<String, dynamic>? ?? {};
                      final createdAt = DateTime.tryParse(doc['created_at']?.toString() ?? '') ?? DateTime.now();
                      final category = _categoryName(loc, payload['category']?.toString());
                      final employeeName = header['employeeName'] ?? '—';
                      final cost = (payload['costTotal'] as num?)?.toDouble();
                      final costStr = cost != null && cost > 0
                          ? NumberFormatUtils.formatSum(cost, payload['costCurrency']?.toString() ?? currency)
                          : '—';
                      final included = !_excludedFromTotalIds.contains(docId);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => context.push('/inbox/writeoff/$docId'),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Tooltip(
                                  message: loc.t('expenses_orders_include_in_total_hint') ?? 'Учитывать в итоге затрат',
                                  child: SizedBox(
                                    width: 40,
                                    child: Checkbox(
                                      value: included,
                                      onChanged: (v) => _setIncludedInTotal(docId, v ?? true),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${dateFormat.format(createdAt)} · $category',
                                        style: Theme.of(context).textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${loc.t('inbox_header_employee') ?? 'Сотрудник'}: $employeeName',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  costStr,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        loc.t('expenses_writeoffs_total_selected') ?? 'Итого по выбранным',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        NumberFormatUtils.formatSum(totalSelected, currency),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  if (filtered.isNotEmpty && totalPeriod != totalSelected)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        (loc.t('expenses_writeoffs_total_period') ?? 'За период: %s').replaceFirst('%s', NumberFormatUtils.formatSum(totalPeriod, currency)),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Диалог выбора языка для выгрузки заказов продуктов.
class _ProductOrdersExportLanguageDialog extends StatelessWidget {
  const _ProductOrdersExportLanguageDialog({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    String selectedLang = loc.currentLanguageCode;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(loc.t('expenses_orders_export_dialog_title') ?? 'Выгрузить заказы продуктов'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t('salary_export_lang') ?? 'Язык сохранения:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['ru', 'en', 'es'].map((code) {
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(selectedLang),
            child: Text(loc.t('expenses_orders_export_btn') ?? 'Выгрузить'),
          ),
        ],
      ),
    );
  }
}
