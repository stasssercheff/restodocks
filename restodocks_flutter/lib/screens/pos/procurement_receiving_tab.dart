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

  /// Пока false — без явных дат в фильтре: вчера, сегодня и завтра (заказ и/или привоз).
  bool _useCustomDateFilters = false;
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

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Вчера, сегодня, завтра — для раннего привоза или задержки.
  bool _dateInDefaultThreeDayWindow(DateTime? dt) {
    if (dt == null) return false;
    final day = _dayOnly(dt);
    final now = DateTime.now();
    final start = _dayOnly(now).subtract(const Duration(days: 1));
    final end = _dayOnly(now).add(const Duration(days: 1));
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool _matchesDefaultThreeDayWindow(Map<String, dynamic> doc) {
    final od = _parseOrderDate(doc);
    final dd = _parseDeliveryDate(doc);
    if (_dateInDefaultThreeDayWindow(dd)) return true;
    if (_dateInDefaultThreeDayWindow(od)) return true;
    return false;
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
    if (_useCustomDateFilters) {
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
    } else {
      list = list.where(_matchesDefaultThreeDayWindow).toList();
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

  Future<void> _pickDate(bool delivery, bool isStart) async {
    final initial = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() {
      _useCustomDateFilters = true;
      if (delivery) {
        if (isStart) {
          _deliveryDateFrom = d;
        } else {
          _deliveryDateTo = d;
        }
      } else {
        if (isStart) {
          _orderDateFrom = d;
        } else {
          _orderDateTo = d;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final df = DateFormat('dd.MM.yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            loc.t('pos_procurement_receiving_hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.t('pos_procurement_filter_supplier'),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<String?>(
                      isExpanded: true,
                      value: _supplierFilter,
                      hint: Text(loc.t('pos_procurement_filter_all')),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(loc.t('pos_procurement_filter_all')),
                        ),
                        ..._supplierNamesSorted.map(
                          (n) => DropdownMenuItem(value: n, child: Text(n)),
                        ),
                      ],
                      onChanged: (v) => setState(() => _supplierFilter = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _pickDate(false, true),
                child: Text(
                  _orderDateFrom != null
                      ? '${loc.t('pos_procurement_filter_order_from')} ${df.format(_orderDateFrom!)}'
                      : loc.t('pos_procurement_filter_order_from'),
                ),
              ),
              TextButton(
                onPressed: () => _pickDate(false, false),
                child: Text(
                  _orderDateTo != null
                      ? '${loc.t('pos_procurement_filter_order_to')} ${df.format(_orderDateTo!)}'
                      : loc.t('pos_procurement_filter_order_to'),
                ),
              ),
              TextButton(
                onPressed: () => _pickDate(true, true),
                child: Text(
                  _deliveryDateFrom != null
                      ? '${loc.t('pos_procurement_filter_delivery_from')} ${df.format(_deliveryDateFrom!)}'
                      : loc.t('pos_procurement_filter_delivery_from'),
                ),
              ),
              TextButton(
                onPressed: () => _pickDate(true, false),
                child: Text(
                  _deliveryDateTo != null
                      ? '${loc.t('pos_procurement_filter_delivery_to')} ${df.format(_deliveryDateTo!)}'
                      : loc.t('pos_procurement_filter_delivery_to'),
                ),
              ),
              IconButton(
                tooltip: loc.t('pos_procurement_filter_clear'),
                onPressed: () => setState(() {
                  _supplierFilter = null;
                  _orderDateFrom = null;
                  _orderDateTo = null;
                  _deliveryDateFrom = null;
                  _deliveryDateTo = null;
                  _useCustomDateFilters = false;
                }),
                icon: const Icon(Icons.clear_all),
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
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push(
                    '/procurement-receipt?department=${widget.department}&manual=1',
                  ),
                  icon: const Icon(Icons.add_task_outlined),
                  label: Text(loc.t('pos_procurement_receiving_create')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/procurement-receipt?department=${widget.department}&manual=1&photo=1',
                  ),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(loc.t('pos_procurement_receiving_create_photo')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
