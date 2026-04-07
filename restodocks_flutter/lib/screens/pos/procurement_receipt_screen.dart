import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/order_list_units.dart';
import '../../widgets/app_bar_home_button.dart';

/// Приёмка поставки по документу заказа или вручную (вне системы).
class ProcurementReceiptScreen extends StatefulWidget {
  const ProcurementReceiptScreen({
    super.key,
    required this.department,
    this.orderDocumentId,
    this.manualOffSystem = false,
  });

  final String department;
  final String? orderDocumentId;
  final bool manualOffSystem;

  @override
  State<ProcurementReceiptScreen> createState() =>
      _ProcurementReceiptScreenState();
}

class _ReceiptLineEdit {
  _ReceiptLineEdit({
    required this.productId,
    required String productName,
    required this.unit,
    required this.orderedQty,
    required this.referencePricePerUnit,
    required this.received,
    required this.actualPrice,
    required this.discountPercent,
    this.nameReadOnly = false,
  }) : nameCtrl = TextEditingController(text: productName);

  final String? productId;
  final TextEditingController nameCtrl;
  final String unit;
  final double orderedQty;
  final double referencePricePerUnit;
  final TextEditingController received;
  final TextEditingController actualPrice;
  final TextEditingController discountPercent;
  final bool nameReadOnly;
}

class _ProcurementReceiptScreenState extends State<ProcurementReceiptScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _orderDoc;
  final _supplierCtrl = TextEditingController();
  List<_ReceiptLineEdit> _lines = [];
  bool _saving = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    for (final l in _lines) {
      l.nameCtrl.dispose();
      l.received.dispose();
      l.actualPrice.dispose();
      l.discountPercent.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (widget.manualOffSystem || widget.orderDocumentId == null) {
      setState(() {
        _loading = false;
        _lines = [
          _ReceiptLineEdit(
            productId: null,
            productName: '',
            unit: 'kg',
            orderedQty: 0,
            referencePricePerUnit: 0,
            received: TextEditingController(),
            actualPrice: TextEditingController(),
            discountPercent: TextEditingController(text: '0'),
            nameReadOnly: false,
          ),
        ];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await OrderDocumentService().getById(widget.orderDocumentId!);
      if (!mounted) return;
      if (doc == null) {
        setState(() {
          _loading = false;
          _error = 'not_found';
        });
        return;
      }
      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      final items = payload['items'] as List<dynamic>? ?? [];
      _supplierCtrl.text = (header['supplierName'] ?? '').toString();

      final newLines = <_ReceiptLineEdit>[];
      for (final it in items) {
        if (it is! Map) continue;
        final pid = it['productId']?.toString();
        final name = (it['productName'] ?? '').toString();
        final unit = (it['unit'] ?? 'kg').toString();
        final q = (it['quantity'] as num?)?.toDouble() ?? 0;
        final ref = (it['pricePerUnit'] as num?)?.toDouble() ?? 0;
        newLines.add(
          _ReceiptLineEdit(
            productId: pid,
            productName: name,
            unit: unit,
            orderedQty: q,
            referencePricePerUnit: ref,
            received: TextEditingController(),
            actualPrice: TextEditingController(),
            discountPercent: TextEditingController(text: '0'),
            nameReadOnly: true,
          ),
        );
      }
      setState(() {
        _orderDoc = doc;
        _lines = newLines;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  double _parse(String s) =>
      double.tryParse(s.replaceFirst(',', '.').trim()) ?? 0;

  double _lineTotal(_ReceiptLineEdit l) {
    final rec = _parse(l.received.text);
    final price = _parse(l.actualPrice.text);
    final disc = _parse(l.discountPercent.text).clamp(0, 100);
    final factor = 1 - disc / 100;
    return rec * price * factor;
  }

  double get _totalOrdered {
    final it = _orderDoc;
    if (it != null) {
      final payload = it['payload'] as Map<String, dynamic>? ?? {};
      final items = payload['items'] as List<dynamic>? ?? [];
      double s = 0;
      for (final x in items) {
        if (x is Map && x['lineTotal'] != null) {
          s += (x['lineTotal'] as num).toDouble();
        }
      }
      if (s > 0) return s;
    }
    double s = 0;
    for (final l in _lines) {
      s += l.orderedQty * l.referencePricePerUnit;
    }
    return s;
  }

  double get _totalReceived {
    double s = 0;
    for (final l in _lines) {
      s += _lineTotal(l);
    }
    return s;
  }

  String _priceVsCard(double actual, double ref) {
    if (ref <= 0) return 'same';
    if (actual < ref * 0.999) return 'lower';
    if (actual > ref * 1.001) return 'higher';
    return 'same';
  }

  Future<void> _submit() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;

    final supplierName = _supplierCtrl.text.trim();
    if (supplierName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('procurement_receipt_supplier_required'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final store = context.read<ProductStoreSupabase>();
      await store.loadProducts();
      await store.loadNomenclature(est.dataEstablishmentId);

        final itemsPayload = <Map<String, dynamic>>[];
      for (final l in _lines) {
        final rec = _parse(l.received.text);
        final actPrice = _parse(l.actualPrice.text);
        final disc = _parse(l.discountPercent.text).clamp(0, 100);
        if (rec <= 0) continue;
        final vs = _priceVsCard(actPrice, l.referencePricePerUnit);
        final pname = l.nameCtrl.text.trim();
        itemsPayload.add({
          'productId': l.productId,
          'productName': pname.isEmpty ? '—' : pname,
          'unit': l.unit,
          'orderedQuantity': l.orderedQty,
          'referencePricePerUnit': l.referencePricePerUnit,
          'receivedQuantity': rec,
          'actualPricePerUnit': actPrice,
          'discountPercent': disc,
          'lineTotal': rec * actPrice * (1 - disc / 100),
          'priceVsCard': vs,
        });
      }

      if (itemsPayload.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('procurement_receipt_lines_required'))),
          );
        }
        setState(() => _saving = false);
        return;
      }

      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final rec = _parse(l.received.text);
        if (rec <= 0 || l.productId == null || l.productId!.isEmpty) continue;
        final product = store.allProducts
            .where((p) => p.id == l.productId)
            .firstOrNull;
        final grams = orderListQuantityToGrams(rec, l.unit, product);
        if (grams > 0) {
          await PosStockService.instance.applyImportDelta(
            establishmentId: est.id,
            productId: l.productId!,
            deltaGrams: grams,
          );
        }
      }

      final header = {
        'supplierName': supplierName,
        'employeeName': emp.fullName,
        'establishmentName': est.name,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'department': widget.department,
        'receipt': true,
        'orderedGrandTotal': _totalOrdered,
        'receivedGrandTotal': _totalReceived,
      };

      final payload = {
        'header': header,
        'items': itemsPayload,
        'grandTotal': _totalReceived,
      };

      final ok = await ProcurementReceiptService.instance.saveViaEdge(
        establishmentId: est.id,
        createdByEmployeeId: emp.id,
        payload: payload,
        sourceOrderDocumentId: widget.orderDocumentId,
      );

      if (widget.manualOffSystem && ok != null) {
        await _ensureSupplierTemplate(
          establishmentId: est.id,
          supplierName: supplierName,
          items: itemsPayload,
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      if (ok != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('procurement_receipt_saved'))),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('procurement_receipt_save_error')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _ensureSupplierTemplate({
    required String establishmentId,
    required String supplierName,
    required List<Map<String, dynamic>> items,
  }) async {
    final lists = await loadOrderLists(establishmentId,
        department: widget.department);
    if (lists.any((s) =>
        !s.isSavedWithQuantities &&
        s.supplierName.toLowerCase() == supplierName.toLowerCase())) {
      return;
    }
    final orderItems = items
        .map(
          (m) => OrderListItem(
            productId: m['productId'] as String?,
            productName: (m['productName'] as String?) ?? '',
            unit: (m['unit'] as String?) ?? 'kg',
            quantity: 0,
          ),
        )
        .toList();
    final draft = OrderList(
      id: const Uuid().v4(),
      name: supplierName,
      supplierName: supplierName,
      items: orderItems,
      department: widget.department,
    );
    await saveOrderLists(establishmentId, [...lists, draft],
        department: widget.department);
  }

  void _addEmptyLine() {
    setState(() {
        _lines.add(
        _ReceiptLineEdit(
          productId: null,
          productName: '',
          unit: 'kg',
          orderedQty: 0,
          referencePricePerUnit: 0,
          received: TextEditingController(),
          actualPrice: TextEditingController(),
          discountPercent: TextEditingController(text: '0'),
          nameReadOnly: false,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final currency =
        context.watch<AccountManagerSupabase>().establishment?.defaultCurrency ??
            'RUB';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('procurement_receipt_title')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('procurement_receipt_title')),
        ),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('procurement_receipt_title')),
      ),
      floatingActionButton: widget.manualOffSystem
          ? FloatingActionButton(
              onPressed: _addEmptyLine,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _supplierCtrl,
              decoration: InputDecoration(
                labelText: loc.t('procurement_receipt_supplier'),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _lines.length,
              itemBuilder: (_, i) {
                final l = _lines[i];
                final ref = l.referencePricePerUnit;
                final act = _parse(l.actualPrice.text);
                final color = ref <= 0
                    ? null
                    : (act < ref * 0.999
                        ? Colors.green
                        : (act > ref * 1.001 ? Colors.red : null));
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (l.nameReadOnly)
                          Text(
                            '${i + 1}. ${l.nameCtrl.text.isEmpty ? "—" : l.nameCtrl.text}',
                            style: Theme.of(context).textTheme.titleSmall,
                          )
                        else
                          TextField(
                            controller: l.nameCtrl,
                            decoration: InputDecoration(
                              labelText: loc.t('product_name'),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${loc.t('procurement_receipt_ordered')}: ${l.orderedQty} ${l.unit}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '${loc.t('procurement_receipt_ref_price')}: $ref $currency',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: l.received,
                                decoration: InputDecoration(
                                  labelText:
                                      loc.t('procurement_receipt_received_qty'),
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
                                ],
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: l.actualPrice,
                                style: TextStyle(color: color),
                                decoration: InputDecoration(
                                  labelText:
                                      loc.t('procurement_receipt_actual_price'),
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.,]')),
                                ],
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: l.discountPercent,
                                decoration: InputDecoration(
                                  labelText:
                                      loc.t('procurement_receipt_discount'),
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '${loc.t('procurement_receipt_line_total')}: ${NumberFormat('#0.##', 'ru').format(_lineTotal(l))} $currency',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${loc.t('procurement_receipt_total_ordered')}: ${NumberFormat('#0.##', 'ru').format(_totalOrdered)} $currency',
                ),
                Text(
                  '${loc.t('procurement_receipt_total_received')}: ${NumberFormat('#0.##', 'ru').format(_totalReceived)} $currency',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(loc.t('procurement_receipt_submit')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
