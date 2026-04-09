import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// Вкладка «Приём поставок»: заказы из «Заказ продуктов» (order_documents) с фильтрами.
class ProcurementReceivingTab extends StatefulWidget {
  const ProcurementReceivingTab({super.key, required this.department});

  final String department;

  @override
  State<ProcurementReceivingTab> createState() =>
      _ProcurementReceivingTabState();
}

class _ProcurementReceivingTabState extends State<ProcurementReceivingTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _rawDocs = [];
  final _productSearchCtrl = TextEditingController();
  String? _supplierFilter;
  DateTime? _orderDateFrom;
  DateTime? _orderDateTo;
  DateTime? _deliveryDateFrom;
  DateTime? _deliveryDateTo;
  /// Режимы фильтра дат: order_range | delivery_range.
  String _dateFilterMode = 'order_range';
  List<String> _templateSupplierNames = [];

  @override
  void dispose() {
    _productSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final estId = acc.establishment?.id;
    if (estId == null) {
      setState(() {
        _loading = false;
        _rawDocs = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await OrderDocumentService().listForEstablishment(estId);
      var templateNames = <String>[];
      try {
        final templates =
            await loadOrderLists(estId, department: widget.department);
        final set = <String>{};
        for (final t in templates) {
          final n = t.supplierName.trim();
          if (n.isNotEmpty) set.add(n);
        }
        templateNames = set.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rawDocs = _dedupeByPayload(list);
        _templateSupplierNames = templateNames;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _dedupeByPayload(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final doc in raw) {
      final p = doc['payload'];
      if (p is! Map) continue;
      final key = jsonEncode(p);
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(doc);
    }
    return out;
  }

  bool _docMatchesDepartment(Map<String, dynamic> doc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final dept = (header['department'] ?? 'kitchen').toString().toLowerCase();
    return dept == widget.department.toLowerCase();
  }

  DateTime? _parseOrderDate(Map<String, dynamic> doc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final s = header['createdAt']?.toString();
    if (s != null) {
      final d = DateTime.tryParse(s);
      if (d != null) return d;
    }
    final c = doc['created_at']?.toString();
    return c != null ? DateTime.tryParse(c) : null;
  }

  DateTime? _parseDeliveryDate(Map<String, dynamic> doc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final s = header['orderForDate']?.toString();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _supplierName(Map<String, dynamic> doc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    return (header['supplierName'] ?? '—').toString();
  }

  bool _matchesProductSearch(Map<String, dynamic> doc, String q) {
    if (q.isEmpty) return true;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    for (final it in items) {
      if (it is! Map) continue;
      final name = (it['productName'] ?? '').toString().toLowerCase();
      if (name.contains(q)) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _rawDocs.where(_docMatchesDepartment).toList();
    final q = _productSearchCtrl.text.trim().toLowerCase();
    if (_supplierFilter != null && _supplierFilter!.isNotEmpty) {
      list = list.where((d) => _supplierName(d) == _supplierFilter).toList();
    }
    if (q.isNotEmpty) {
      list = list.where((d) => _matchesProductSearch(d, q)).toList();
    }
    if (_dateFilterMode == 'order_range') {
      if (_orderDateFrom != null) {
        list = list.where((d) {
          final dt = _parseOrderDate(d);
          if (dt == null) return false;
          return !dt.isBefore(DateTime(_orderDateFrom!.year,
              _orderDateFrom!.month, _orderDateFrom!.day));
        }).toList();
      }
      if (_orderDateTo != null) {
        final end = DateTime(_orderDateTo!.year, _orderDateTo!.month,
            _orderDateTo!.day, 23, 59, 59);
        list = list.where((d) {
          final dt = _parseOrderDate(d);
          if (dt == null) return false;
          return !dt.isAfter(end);
        }).toList();
      }
    } else if (_dateFilterMode == 'delivery_range') {
      if (_deliveryDateFrom != null) {
        list = list.where((d) {
          final dt = _parseDeliveryDate(d);
          if (dt == null) return false;
          return !dt.isBefore(DateTime(_deliveryDateFrom!.year,
              _deliveryDateFrom!.month, _deliveryDateFrom!.day));
        }).toList();
      }
      if (_deliveryDateTo != null) {
        final end = DateTime(_deliveryDateTo!.year, _deliveryDateTo!.month,
            _deliveryDateTo!.day, 23, 59, 59);
        list = list.where((d) {
          final dt = _parseDeliveryDate(d);
          if (dt == null) return false;
          return !dt.isAfter(end);
        }).toList();
      }
    }
    list.sort((a, b) {
      final ta = _parseOrderDate(a) ?? DateTime(0);
      final tb = _parseOrderDate(b) ?? DateTime(0);
      return tb.compareTo(ta);
    });
    return list;
  }

  List<String> get _supplierNamesSorted {
    final s = <String>{};
    for (final n in _templateSupplierNames) {
      if (n.isNotEmpty) s.add(n);
    }
    for (final d in _rawDocs.where(_docMatchesDepartment)) {
      final name = _supplierName(d);
      if (name.isNotEmpty && name != '—') s.add(name);
    }
    final list = s.toList();
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _pickOrderDateRange() async {
    DateTimeRange? initial;
    if (_orderDateFrom != null && _orderDateTo != null) {
      initial = DateTimeRange(
        start: _orderDateFrom!,
        end: _orderDateTo!,
      );
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initial,
      builder: _buildCompactRangePicker,
    );
    if (range == null || !mounted) return;
    setState(() {
      _orderDateFrom = range.start;
      _orderDateTo = range.end;
    });
  }

  Future<void> _pickDeliveryDateRange() async {
    DateTimeRange? initial;
    if (_deliveryDateFrom != null && _deliveryDateTo != null) {
      initial = DateTimeRange(
        start: _deliveryDateFrom!,
        end: _deliveryDateTo!,
      );
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initial,
      builder: _buildCompactRangePicker,
    );
    if (range == null || !mounted) return;
    setState(() {
      _deliveryDateFrom = range.start;
      _deliveryDateTo = range.end;
    });
  }

  Future<void> _selectDateMode(String mode) async {
    setState(() {
      _dateFilterMode = mode;
      if (mode == 'order_range') {
        _deliveryDateFrom = null;
        _deliveryDateTo = null;
      } else if (mode == 'delivery_range') {
        _orderDateFrom = null;
        _orderDateTo = null;
      }
    });
    if (mode == 'order_range') {
      await _pickOrderDateRange();
      return;
    }
    await _pickDeliveryDateRange();
  }

  Widget _buildCompactRangePicker(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        datePickerTheme: theme.datePickerTheme.copyWith(
          rangePickerHeaderHeadlineStyle:
              theme.textTheme.headlineSmall?.copyWith(fontSize: 26),
          rangePickerHeaderHelpStyle:
              theme.textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
        inputDecorationTheme: (theme.inputDecorationTheme).copyWith(
          hintStyle: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.1,
          ),
        ),
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final df = DateFormat('dd.MM.yyyy');
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final headerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            loc.t('pos_procurement_receiving_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: _supplierFilter,
                decoration: InputDecoration(
                  labelText: loc.t('pos_procurement_filter_supplier'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(loc.t('pos_procurement_filter_all')),
                  ),
                  ..._supplierNamesSorted
                      .map((n) => DropdownMenuItem(value: n, child: Text(n))),
                ],
                onChanged: (v) => setState(() => _supplierFilter = v),
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('pos_procurement_filter_period'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _selectDateMode('order_range'),
                      child: Text(
                        loc.currentLanguageCode == 'ru'
                            ? 'Заказ дата'
                            : loc.t('pos_procurement_filter_mode_order'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _selectDateMode('delivery_range'),
                      child: Text(
                        loc.currentLanguageCode == 'ru'
                            ? 'Привоз дата'
                            : loc.t('pos_procurement_filter_mode_delivery'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _supplierFilter = null;
                    _orderDateFrom = null;
                    _orderDateTo = null;
                    _deliveryDateFrom = null;
                    _deliveryDateTo = null;
                    _dateFilterMode = 'order_range';
                  }),
                  icon: const Icon(Icons.clear_all, size: 20),
                  label: Text(loc.t('pos_procurement_filter_clear')),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _productSearchCtrl,
            decoration: InputDecoration(
              hintText: loc.t('pos_procurement_filter_product'),
              prefixIcon: const Icon(Icons.search, size: 22),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push(
                '/procurement-receipt?department=${widget.department}&manual=1',
              ),
              icon: const Icon(Icons.add_task_outlined),
              label: Text(loc.t('pos_procurement_receiving_create')),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLandscape)
          SizedBox(
            height: 260,
            child: SingleChildScrollView(child: headerContent),
          )
        else
          headerContent,
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 48),
                            Center(
                              child: Text(
                                loc.t('pos_procurement_receiving_empty'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final doc = _filtered[i];
                            final id = doc['id']?.toString() ?? '';
                            final od = _parseOrderDate(doc);
                            final dd = _parseDeliveryDate(doc);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(
                                  _supplierName(doc),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    if (od != null)
                                      '${loc.t('inbox_header_date')}: ${df.format(od)}',
                                    if (dd != null)
                                      '${loc.t('pos_procurement_delivery_for')}: ${df.format(dd)}',
                                  ].join(' · '),
                                  maxLines: 2,
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push(
                                  '/procurement-receipt?department=${widget.department}&orderDocumentId=$id',
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
