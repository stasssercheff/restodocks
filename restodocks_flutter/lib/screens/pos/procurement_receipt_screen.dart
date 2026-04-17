import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/order_list_units.dart';
import '../../utils/supplier_contact_validation.dart';
import '../../widgets/app_bar_home_button.dart';
import '../../widgets/nomenclature_product_picker_dialog.dart';

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
    required double initialOrderedQty,
    required this.referencePricePerUnit,
    required this.received,
    required this.actualPrice,
    required this.discountPercent,
    this.nameReadOnly = false,
  })  : orderedQty = initialOrderedQty,
        nameCtrl = TextEditingController(text: productName);

  String? productId;
  final TextEditingController nameCtrl;
  String unit;
  double orderedQty;
  double referencePricePerUnit;
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
  final _supplierContactCtrl = TextEditingController();
  final _supplierEmailCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();
  List<OrderList> _supplierTemplates = [];
  List<_ReceiptLineEdit> _lines = [];
  bool _saving = false;
  /// Дата фактической приёмки (вне системы), опционально.
  DateTime? _externalReceiptDate;

  String get _nomenclatureDepartment =>
      widget.department == 'bar' ? 'bar' : 'kitchen';

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _supplierContactCtrl.dispose();
    _supplierEmailCtrl.dispose();
    _supplierPhoneCtrl.dispose();
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
      final acc = context.read<AccountManagerSupabase>();
      final estId = acc.establishment?.id;
      var templates = <OrderList>[];
      if (estId != null) {
        try {
          templates =
              await loadOrderLists(estId, department: widget.department);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _supplierTemplates = templates;
        _lines = [_createEmptyLine(), _createEmptyLine()];
        _syncManualTrailingEmptyInPlace();
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
            initialOrderedQty: q,
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

  _ReceiptLineEdit _createEmptyLine() => _ReceiptLineEdit(
        productId: null,
        productName: '',
        unit: context.read<UnitSystemPreferenceService>().isImperial ? 'lb' : 'kg',
        initialOrderedQty: 0,
        referencePricePerUnit: 0,
        received: TextEditingController(),
        actualPrice: TextEditingController(),
        discountPercent: TextEditingController(text: '0'),
        nameReadOnly: false,
      );

  void _disposeLine(_ReceiptLineEdit l) {
    l.nameCtrl.dispose();
    l.received.dispose();
    l.actualPrice.dispose();
    l.discountPercent.dispose();
  }

  bool _isLineEmpty(_ReceiptLineEdit l) {
    final name = l.nameCtrl.text.trim().isEmpty;
    final rec = _parse(l.received.text);
    final price = _parse(l.actualPrice.text);
    final disc = _parse(l.discountPercent.text);
    return name && rec <= 0 && price <= 0 && disc <= 0;
  }

  bool _lineHasMeaningfulContent(_ReceiptLineEdit l) {
    if (l.nameCtrl.text.trim().isNotEmpty) return true;
    if (_parse(l.received.text) > 0) return true;
    if (_parse(l.actualPrice.text) > 0) return true;
    if (_parse(l.discountPercent.text) > 0.0001) return true;
    return false;
  }

  void _syncManualTrailingEmptyInPlace() {
    if (!widget.manualOffSystem) return;
    while (_lines.length < 2) {
      _lines.add(_createEmptyLine());
    }
    if (_lineHasMeaningfulContent(_lines.last)) {
      _lines.add(_createEmptyLine());
    }
    while (_lines.length > 2 &&
        _isLineEmpty(_lines.last) &&
        _isLineEmpty(_lines[_lines.length - 2])) {
      final removed = _lines.removeLast();
      _disposeLine(removed);
    }
  }

  void _onManualChanged() {
    setState(_syncManualTrailingEmptyInPlace);
  }

  String _localizedUnit(LocalizationService loc, String unit) {
    final code = loc.currentLanguageCode.toLowerCase();
    final lang = code.startsWith('ru') ? 'ru' : 'en';
    return CulinaryUnits.displayName(unit, lang);
  }

  bool _isConvertibleWeightOrVolume(String unit) {
    final u = unit.toLowerCase().trim();
    return u == 'kg' ||
        u == 'g' ||
        u == 'г' ||
        u == 'кг' ||
        u == 'lb' ||
        u == 'oz' ||
        u == 'ml' ||
        u == 'мл' ||
        u == 'l' ||
        u == 'л' ||
        u == 'fl_oz' ||
        u == 'gal';
  }

  String _normalizeUnit(String unit) {
    final u = unit.toLowerCase().trim();
    return switch (u) {
      'г' => 'g',
      'кг' => 'kg',
      'мл' => 'ml',
      'л' => 'l',
      _ => u,
    };
  }

  static const _weightUnits = {'g', 'kg', 'oz', 'lb'};
  static const _volumeUnits = {'ml', 'l', 'fl_oz', 'gal'};

  void _convertLineUnit(_ReceiptLineEdit line, String newUnit) {
    final old = line.unit.toLowerCase().trim();
    final nu = newUnit.toLowerCase().trim();
    final o = _normalizeUnit(old);
    final n = _normalizeUnit(nu);
    if (o == n) {
      line.unit = n;
      return;
    }
    final sameDomain =
        (_weightUnits.contains(o) && _weightUnits.contains(n)) ||
            (_volumeUnits.contains(o) && _volumeUnits.contains(n));
    if (!sameDomain) return;
    final oldPerUnit = CulinaryUnits.toGrams(1, o);
    final newPerUnit = CulinaryUnits.toGrams(1, n);
    if (oldPerUnit <= 0 || newPerUnit <= 0) return;
    final factorQty = oldPerUnit / newPerUnit;
    final factorPrice = newPerUnit / oldPerUnit;

    line.unit = n;

    final r = _parse(line.received.text);
    if (r > 0) {
      line.received.text = _formatQtyForField(r * factorQty);
    }
    if (line.orderedQty > 0) {
      line.orderedQty *= factorQty;
    }
    if (line.referencePricePerUnit > 0) {
      line.referencePricePerUnit *= factorPrice;
    }
    final ap = _parse(line.actualPrice.text);
    if (ap > 0) {
      line.actualPrice.text = _formatPriceForField(ap * factorPrice);
    }
  }

  Future<void> _pickExternalReceiptDate(LocalizationService loc) async {
    final now = DateTime.now();
    final initial = _externalReceiptDate ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (d != null && mounted) {
      setState(() => _externalReceiptDate = d);
    }
  }

  bool get _manualNewSupplier {
    if (!widget.manualOffSystem) return false;
    final n = _supplierCtrl.text.trim();
    if (n.isEmpty) return false;
    return !_supplierTemplates.any(
      (s) => s.supplierName.toLowerCase() == n.toLowerCase(),
    );
  }

  Future<void> _showSupplierPicker() async {
    final loc = context.read<LocalizationService>();
    final names = _supplierTemplates.map((e) => e.supplierName).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final filtered = q.isEmpty
                ? names
                : names
                    .where((n) => n.toLowerCase().contains(q.toLowerCase()))
                    .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              maxChildSize: 0.9,
              minChildSize: 0.35,
              builder: (_, scrollCtrl) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: loc.t('search'),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setSt(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(filtered[i]),
                        onTap: () => Navigator.pop(ctx, filtered[i]),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _supplierCtrl.text = picked);
    }
  }

  Future<void> _pickNomenclatureProduct(int lineIndex) async {
    final acc = context.read<AccountManagerSupabase>();
    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    final est = acc.establishment;
    final nomEstId = est?.productsEstablishmentId;
    if (nomEstId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    List<Product> products = [];
    try {
      await store.loadProducts();
      products = await store.loadNomenclatureProductsDirect(
        nomEstId,
        department: _nomenclatureDepartment,
      );
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${loc.t('nomenclature')}: ${loc.t('no_products')}',
          ),
        ),
      );
      return;
    }
    final dynamic result = await showDialog<dynamic>(
      context: context,
      builder: (ctx) => NomenclatureProductPickerDialog(
        products: products,
        lang: loc.currentLanguageCode,
      ),
    );
    if (!mounted) return;
    if (result == '__new__') {
      await _createNewNomenclatureProduct(lineIndex);
      return;
    }
    if (result is Product) {
      final e = acc.establishment;
      if (e == null) return;
      _applyProductFromNomenclature(
        lineIndex,
        result,
        store,
        e.productsEstablishmentId,
        loc.currentLanguageCode,
      );
    }
  }

  void _applyProductFromNomenclature(
    int lineIndex,
    Product p,
    ProductStoreSupabase store,
    String productsEstablishmentId,
    String lang,
  ) {
    final line = _lines[lineIndex];
    final ref =
        store.getEstablishmentPrice(p.id, productsEstablishmentId)?.$1 ?? 0;
    setState(() {
      line.productId = p.id;
      line.nameCtrl.text = p.getLocalizedName(lang);
      line.unit = p.unit ?? 'kg';
      line.referencePricePerUnit = ref;
    });
    _onManualChanged();
  }

  List<String> _newProductUnits(UnitSystem unitSystem) {
    final base = unitSystem == UnitSystem.imperial
        ? <String>['oz', 'lb', 'fl_oz', 'gal']
        : <String>['g', 'kg', 'ml', 'l'];
    return [...base, 'pcs', 'pack', 'can', 'box', 'bottle'];
  }

  Future<void> _createNewNomenclatureProduct(int lineIndex) async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final store = context.read<ProductStoreSupabase>();
    final est = acc.establishment;
    final nomEstId = est?.productsEstablishmentId;
    if (nomEstId == null) return;

    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final unitPrefs = context.read<UnitSystemPreferenceService>();
    final productUnits = _newProductUnits(unitPrefs.unitSystem);
    var unitChoice = unitPrefs.isImperial ? 'lb' : 'kg';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Text(loc.t('procurement_create_product_title')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: loc.t('product_name'),
                      border: const OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: productUnits.contains(unitChoice)
                        ? unitChoice
                        : productUnits.first,
                    decoration: InputDecoration(
                      labelText: loc.t('order_list_unit'),
                      border: const OutlineInputBorder(),
                    ),
                    items: productUnits
                        .map(
                          (id) => DropdownMenuItem(
                            value: id,
                            child: Text(
                              CulinaryUnits.displayName(
                                id,
                                loc.currentLanguageCode.startsWith('ru')
                                    ? 'ru'
                                    : 'en',
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setSt(() => unitChoice = v ?? unitChoice),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    decoration: InputDecoration(
                      labelText: loc.t('procurement_create_product_price_hint'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.t('save')),
              ),
            ],
          );
        },
      ),
    );

    final name = nameCtrl.text.trim();
    final price = double.tryParse(
      priceCtrl.text.replaceFirst(',', '.').trim(),
    );
    nameCtrl.dispose();
    priceCtrl.dispose();

    if (ok != true || !mounted) return;
    if (name.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final product = Product(
        id: const Uuid().v4(),
        name: name,
        category: 'misc',
        unit: unitChoice,
      );
      final saved = await store.addProduct(product);
      await store.addToNomenclature(
        nomEstId,
        saved.id,
        price: price,
        currency: est!.defaultCurrency,
      );
      await store.loadNomenclatureForce(nomEstId);
      if (!mounted) return;
      _applyProductFromNomenclature(
        lineIndex,
        saved,
        store,
        nomEstId,
        loc.currentLanguageCode,
      );
      if (price != null && _lines[lineIndex].actualPrice.text.trim().isEmpty) {
        setState(() {
          _lines[lineIndex].actualPrice.text = _formatPriceForField(price);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  String _formatPriceForField(double p) {
    if (p == p.roundToDouble()) return '${p.round()}';
    return p.toString();
  }

  String _formatQtyForField(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return value.toString();
  }

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

  /// Строки, где фактическая цена за ед. (с учётом скидки) отличается от цены в номенклатуре.
  List<Map<String, dynamic>> _collectPriceChangeLines(
    ProductStoreSupabase store,
    Establishment est,
  ) {
    final nomId = est.productsEstablishmentId;
    final currency = est.defaultCurrency ?? 'RUB';
    final out = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final rec = _parse(l.received.text);
      if (rec <= 0) continue;
      final pid = l.productId;
      if (pid == null || pid.isEmpty) continue;
      final actPrice = _parse(l.actualPrice.text);
      final disc = _parse(l.discountPercent.text).clamp(0, 100);
      final effectiveNew = actPrice * (1 - disc / 100);
      if (effectiveNew <= 0) continue;
      final old = store.getEstablishmentPrice(pid, nomId)?.$1;
      if (old != null && (old - effectiveNew).abs() <= 0.001) continue;
      out.add({
        'productId': pid,
        'productName':
            l.nameCtrl.text.trim().isEmpty ? '—' : l.nameCtrl.text.trim(),
        'unit': l.unit,
        'oldPricePerUnit': old,
        'newPricePerUnit': effectiveNew,
        'currency': currency,
      });
    }
    return out;
  }

  /// Возвращает список productId для обновления; пустой — не обновлять цены.
  Future<List<String>> _showPriceApprovalDialog(
    List<Map<String, dynamic>> lines,
  ) async {
    final loc = context.read<LocalizationService>();
    final selected = <String>{
      for (final l in lines)
        if (l['productId'] != null) l['productId'].toString(),
    };
    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSt) {
            return AlertDialog(
              title: Text(loc.t('procurement_receipt_price_confirm_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.t('procurement_receipt_price_confirm_hint')),
                    const SizedBox(height: 8),
                    ...lines.map((line) {
                      final pid = line['productId']?.toString() ?? '';
                      final oldP = line['oldPricePerUnit'];
                      final newP = line['newPricePerUnit'];
                      final oldStr = oldP == null ? '—' : oldP.toString();
                      final newStr = newP == null ? '—' : newP.toString();
                      return CheckboxListTile(
                        value: selected.contains(pid),
                        onChanged: (v) {
                          setSt(() {
                            if (v == true) {
                              selected.add(pid);
                            } else {
                              selected.remove(pid);
                            }
                          });
                        },
                        title: Text(line['productName']?.toString() ?? '—'),
                        subtitle: Text('$oldStr → $newStr'),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, <String>[]),
                  child: Text(loc.t('procurement_receipt_price_skip')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected.toList()),
                  child: Text(loc.t('procurement_receipt_price_apply')),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? <String>[];
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

    if (widget.manualOffSystem && _manualNewSupplier) {
      if (!isValidSupplierEmail(_supplierEmailCtrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('supplier_invalid_email'))),
        );
        return;
      }
      if (!isValidSupplierPhone(_supplierPhoneCtrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('supplier_invalid_phone'))),
        );
        return;
      }
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
            SnackBar(
                content: Text(loc.t('procurement_receipt_lines_required'))),
          );
        }
        setState(() => _saving = false);
        return;
      }

      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final rec = _parse(l.received.text);
        if (rec <= 0 || l.productId == null || l.productId!.isEmpty) continue;
        final product =
            store.allProducts.where((p) => p.id == l.productId).firstOrNull;
        final grams = orderListQuantityToGrams(rec, l.unit, product);
        if (grams > 0) {
          await PosStockService.instance.applyImportDelta(
            establishmentId: est.id,
            productId: l.productId!,
            deltaGrams: grams,
          );
        }
      }

      final header = <String, dynamic>{
        'supplierName': supplierName,
        'employeeName': emp.fullName,
        'establishmentName': est.name,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'department': widget.department,
        'receipt': true,
        'orderedGrandTotal': _totalOrdered,
        'receivedGrandTotal': _totalReceived,
        if (widget.manualOffSystem) 'pendingManagementApproval': true,
        if (widget.manualOffSystem && _externalReceiptDate != null)
          'externalReceiptDate': DateTime.utc(
            _externalReceiptDate!.year,
            _externalReceiptDate!.month,
            _externalReceiptDate!.day,
          ).toIso8601String(),
      };

      final payload = {
        'header': header,
        'items': itemsPayload,
        'grandTotal': _totalReceived,
      };

      final priceLines = _collectPriceChangeLines(store, est);
      final approveOnDevice =
          ProcurementPriceApprovalService.canApproveOnReceiptDevice(
        emp,
        widget.department,
      );

      for (final l in _lines) {
        final pid = l.productId;
        if (pid == null || pid.isEmpty) continue;
        final p = store.allProducts.where((x) => x.id == pid).firstOrNull;
        if (p == null) continue;
        final uCard = (p.unit ?? '').toLowerCase().trim();
        final uLine = l.unit.toLowerCase().trim();
        if (uCard == uLine) continue;
        if (uCard == 'г' && uLine == 'g') continue;
        if (uCard == 'g' && uLine == 'г') continue;
        await store.updateProduct(p.copyWith(unit: l.unit));
      }

      final Map<String, dynamic>? ok;
      if (!approveOnDevice && priceLines.isNotEmpty) {
        ok = await ProcurementReceiptService.instance.saveViaEdge(
          establishmentId: est.id,
          createdByEmployeeId: emp.id,
          payload: payload,
          sourceOrderDocumentId: widget.orderDocumentId,
          priceApprovalLines: priceLines,
          nomenclatureEstablishmentId: est.productsEstablishmentId,
        );
      } else {
        ok = await ProcurementReceiptService.instance.saveViaEdge(
          establishmentId: est.id,
          createdByEmployeeId: emp.id,
          payload: payload,
          sourceOrderDocumentId: widget.orderDocumentId,
        );
      }

      if (widget.manualOffSystem && ok != null) {
        await _ensureSupplierTemplate(
          establishmentId: est.id,
          supplierName: supplierName,
          items: itemsPayload,
          contactPerson: _manualNewSupplier
              ? (_supplierContactCtrl.text.trim().isEmpty
                  ? null
                  : _supplierContactCtrl.text.trim())
              : null,
          email: _manualNewSupplier
              ? normalizedSupplierEmailOrNull(_supplierEmailCtrl.text)
              : null,
          phone: _manualNewSupplier
              ? normalizedSupplierPhoneOrNull(_supplierPhoneCtrl.text)
              : null,
        );
      }

      if (!mounted) return;
      setState(() => _saving = false);
      if (ok != null) {
        if (approveOnDevice && priceLines.isNotEmpty) {
          final pick = await _showPriceApprovalDialog(priceLines);
          if (pick.isNotEmpty) {
            final pickSet = pick.toSet();
            for (final line in priceLines) {
              final pid = line['productId'] as String?;
              if (pid == null || !pickSet.contains(pid)) continue;
              final newP = (line['newPricePerUnit'] as num?)?.toDouble();
              if (newP == null) continue;
              await store.setEstablishmentPrice(
                est.productsEstablishmentId,
                pid,
                newP,
                line['currency'] as String? ?? est.defaultCurrency ?? 'RUB',
              );
            }
          }
        }
        if (!mounted) return;
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
    String? contactPerson,
    String? email,
    String? phone,
  }) async {
    final lists =
        await loadOrderLists(establishmentId, department: widget.department);
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

    final idx = lists.indexWhere(
      (s) =>
          !s.isSavedWithQuantities &&
          s.supplierName.toLowerCase() == supplierName.toLowerCase(),
    );

    if (idx >= 0) {
      final existing = lists[idx];
      final merged = List<OrderListItem>.from(existing.items);
      for (final oi in orderItems) {
        if (oi.productId != null &&
            oi.productId!.isNotEmpty &&
            !merged.any((x) => x.productId == oi.productId)) {
          merged.add(oi);
        } else if ((oi.productId == null || oi.productId!.isEmpty) &&
            oi.productName.trim().isNotEmpty &&
            !merged.any(
              (x) =>
                  x.productName.toLowerCase() == oi.productName.toLowerCase(),
            )) {
          merged.add(oi);
        }
      }
      lists[idx] = existing.copyWith(
        items: merged,
        contactPerson: contactPerson ?? existing.contactPerson,
        email: email ?? existing.email,
        phone: phone ?? existing.phone,
      );
    } else {
      final draft = OrderList(
        id: const Uuid().v4(),
        name: supplierName,
        supplierName: supplierName,
        contactPerson: contactPerson,
        email: email,
        phone: phone,
        items: orderItems,
        department: widget.department,
      );
      lists.add(draft);
    }
    await saveOrderLists(establishmentId, lists, department: widget.department);
  }

  /// Короткие подписи колонок на узком экране (одна строка, без разрыва слова).
  String _tableHeaderLabel(
    LocalizationService loc,
    bool narrow,
    String fullKey,
    String shortRu,
    String shortEn,
  ) {
    if (!narrow) return loc.t(fullKey);
    final lang = loc.currentLanguageCode.toLowerCase();
    if (lang.startsWith('ru')) return shortRu;
    if (lang.startsWith('en')) return shortEn;
    return loc.t(fullKey);
  }

  Widget _tableHeaderCell(
    LocalizationService loc,
    bool narrow,
    String fullKey,
    String shortRu,
    String shortEn,
    TextStyle? thStyle,
  ) {
    final full = loc.t(fullKey);
    final text = _tableHeaderLabel(loc, narrow, fullKey, shortRu, shortEn);
    final w = Text(
      text,
      style: thStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    if (full != text) {
      return Tooltip(message: full, child: w);
    }
    return w;
  }

  static const EdgeInsets _denseInputPadding =
      EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  InputDecoration _denseFieldDecoration(BuildContext context) {
    return InputDecoration(
      isDense: true,
      contentPadding: _denseInputPadding,
      border: const OutlineInputBorder(),
      isCollapsed: false,
    );
  }

  Widget _buildReceiptTable(
    LocalizationService loc,
    UnitSystemPreferenceService unitPrefs,
    String currency,
  ) {
    final thStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final nf = NumberFormat('#0.##', 'ru');
    final onField =
        widget.manualOffSystem ? _onManualChanged : () => setState(() {});

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final thStyleUse = thStyle?.copyWith(fontSize: narrow ? 10 : 12);
        final hPad = narrow ? 2.0 : 8.0;
        final vPad = narrow ? 2.0 : 6.0;
        // Одна FlexColumnWidth забирала всё до minWidth — колонка «Наимен.» растягивалась.
        // Фиксированная ширина (~в 2× уже прежнего flex-остатка при minW 720/1040).
        final nameColW = narrow ? 110.0 : 160.0;
        final tableMinW = narrow
            ? 22.0 + nameColW + 44 + 52 + 56 + 52 + 56 + 56 + 36
            : 32.0 + nameColW + 56 + 72 + 84 + 72 + 84 + 88 + 56;
        final minW = math.max(tableMinW, constraints.maxWidth);

        Widget cell(Widget w) => Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              child: w,
            );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minW),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
              ),
              columnWidths: {
                0: FixedColumnWidth(narrow ? 22 : 32),
                1: FixedColumnWidth(nameColW),
                2: FixedColumnWidth(narrow ? 44 : 56),
                3: FixedColumnWidth(narrow ? 52 : 72),
                4: FixedColumnWidth(narrow ? 56 : 84),
                5: FixedColumnWidth(narrow ? 52 : 72),
                6: FixedColumnWidth(narrow ? 56 : 84),
                7: FixedColumnWidth(narrow ? 56 : 88),
                8: FixedColumnWidth(narrow ? 36 : 56),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  children: [
                    cell(_tableHeaderCell(loc, narrow, 'procurement_receipt_col_no',
                        '№', '№', thStyleUse)),
                    cell(_tableHeaderCell(
                        loc, narrow, 'product_name', 'Наимен.', 'Name', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_col_unit', 'Ед.', 'U.', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_ordered', 'Заказ', 'Ord.', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_ref_price', 'Карточка', 'Ref.', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_received_qty', 'Принято', 'Recv', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_actual_price', 'Цена', 'Price', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_line_total', 'Сумма', 'Sum', thStyleUse)),
                    cell(_tableHeaderCell(loc, narrow,
                        'procurement_receipt_discount', 'Ск.%', 'Disc.%', thStyleUse)),
                  ],
                ),
                ...List.generate(
                  _lines.length,
                  (i) => _tableDataRow(
                    i,
                    loc,
                    unitPrefs,
                    currency,
                    cell,
                    onField,
                    nf,
                    narrow,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _kgGDropdownValue(_ReceiptLineEdit l) {
    final u = _normalizeUnit(l.unit);
    if (_weightUnits.contains(u)) return u;
    if (_volumeUnits.contains(u)) return u;
    return 'kg';
  }

  List<String> _lineUnitOptions(UnitSystem unitSystem, _ReceiptLineEdit l) {
    final u = _normalizeUnit(l.unit);
    if (_weightUnits.contains(u)) {
      return unitSystem == UnitSystem.imperial
          ? <String>['lb', 'oz']
          : <String>['kg', 'g'];
    }
    if (_volumeUnits.contains(u)) {
      return unitSystem == UnitSystem.imperial
          ? <String>['gal', 'fl_oz']
          : <String>['l', 'ml'];
    }
    return const <String>[];
  }

  TableRow _tableDataRow(
    int i,
    LocalizationService loc,
    UnitSystemPreferenceService unitPrefs,
    String currency,
    Widget Function(Widget) cell,
    VoidCallback onField,
    NumberFormat nf,
    bool narrow,
  ) {
    final l = _lines[i];
    final ref = l.referencePricePerUnit;
    final act = _parse(l.actualPrice.text);
    final Color? priceColor = ref <= 0
        ? null
        : (act < ref * 0.999
            ? Colors.green
            : (act > ref * 1.001 ? Colors.red : null));

    final scrollPad = EdgeInsets.only(
      bottom: 140,
      top: 72,
      left: 12,
      right: 12,
    );
    final rowStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: narrow ? 12 : null,
        );
    final iconBtnStyle = IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(30, 30),
      padding: const EdgeInsets.all(2),
    );

    return TableRow(
      children: [
        cell(
          Text(
            '${i + 1}',
            textAlign: TextAlign.center,
            style: rowStyle,
          ),
        ),
        cell(
          l.nameReadOnly
              ? Text(
                  l.nameCtrl.text.isEmpty ? '—' : l.nameCtrl.text,
                  softWrap: true,
                  style: rowStyle,
                )
              : widget.manualOffSystem
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: l.nameCtrl,
                            decoration: _denseFieldDecoration(context),
                            style: rowStyle,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: null,
                            scrollPadding: scrollPad,
                            onChanged: (_) => onField(),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.search, size: narrow ? 17 : 22),
                          tooltip: loc.t('procurement_pick_product'),
                          style: iconBtnStyle,
                          onPressed: () => _pickNomenclatureProduct(i),
                        ),
                        IconButton(
                          icon: Icon(Icons.add_circle_outline,
                              size: narrow ? 17 : 22),
                          tooltip: loc.t('procurement_product_new'),
                          style: iconBtnStyle,
                          onPressed: () => _createNewNomenclatureProduct(i),
                        ),
                      ],
                    )
                  : TextField(
                      controller: l.nameCtrl,
                      decoration: _denseFieldDecoration(context),
                      style: rowStyle,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 1,
                      maxLines: null,
                      scrollPadding: scrollPad,
                      onChanged: (_) => onField(),
                    ),
        ),
        cell(
          _isConvertibleWeightOrVolume(l.unit)
              ? DropdownButton<String>(
                  isDense: true,
                  isExpanded: true,
                  itemHeight: narrow ? 40 : kMinInteractiveDimension,
                  value: _kgGDropdownValue(l),
                  items: _lineUnitOptions(unitPrefs.unitSystem, l)
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(_localizedUnit(loc, u), style: rowStyle),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _convertLineUnit(l, v));
                    onField();
                  },
                )
              : Text(
                  _localizedUnit(loc, l.unit),
                  style: rowStyle,
                ),
        ),
        cell(
          Text(
            nf.format(l.orderedQty),
            style: rowStyle,
          ),
        ),
        cell(
          Text(
            ref > 0 ? '${nf.format(ref)} $currency' : '—',
            style: rowStyle,
          ),
        ),
        cell(
          TextField(
            controller: l.received,
            decoration: _denseFieldDecoration(context),
            style: rowStyle,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            scrollPadding: scrollPad,
            onChanged: (_) => onField(),
          ),
        ),
        cell(
          TextField(
            controller: l.actualPrice,
            style: TextStyle(
              color: priceColor,
              fontSize: narrow ? 12 : 13,
            ),
            decoration: _denseFieldDecoration(context),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            scrollPadding: scrollPad,
            onChanged: (_) => onField(),
          ),
        ),
        cell(
          Text(
            '${nf.format(_lineTotal(l))} $currency',
            style: rowStyle,
            textAlign: TextAlign.right,
          ),
        ),
        cell(
          TextField(
            controller: l.discountPercent,
            decoration: _denseFieldDecoration(context),
            style: rowStyle,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            scrollPadding: scrollPad,
            onChanged: (_) => onField(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final currency = context
            .watch<AccountManagerSupabase>()
            .establishment
            ?.defaultCurrency ??
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

    final mq = MediaQuery.of(context);
    final narrowScreen = mq.size.shortestSide < 560;
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final hdrPad = EdgeInsets.symmetric(
      horizontal: narrowScreen ? 8 : 12,
      vertical: narrowScreen ? 6 : 12,
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('procurement_receipt_title')),
        toolbarHeight: narrowScreen ? 48 : kToolbarHeight,
      ),
      body: Column(
        children: [
          Padding(
            padding: hdrPad,
            child: widget.manualOffSystem
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _supplierCtrl,
                              decoration: InputDecoration(
                                labelText:
                                    loc.t('procurement_receipt_supplier'),
                                border: const OutlineInputBorder(),
                                isDense: narrowScreen,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: narrowScreen ? 8 : 12,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: narrowScreen ? 14 : 16,
                              ),
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filledTonal(
                            onPressed: _showSupplierPicker,
                            icon: Icon(
                              Icons.list_alt,
                              size: narrowScreen ? 20 : 24,
                            ),
                            style: IconButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.all(8),
                            ),
                            tooltip: loc.t('procurement_pick_supplier'),
                          ),
                        ],
                      ),
                      SizedBox(height: narrowScreen ? 6 : 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _pickExternalReceiptDate(loc),
                          borderRadius: BorderRadius.circular(4),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText:
                                  loc.t('procurement_external_receipt_date'),
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              _externalReceiptDate != null
                                  ? DateFormat.yMMMd(
                                      Localizations.localeOf(context)
                                          .toString(),
                                    ).format(_externalReceiptDate!)
                                  : loc.t(
                                      'procurement_external_receipt_date_hint'),
                              style: TextStyle(
                                fontSize: narrowScreen ? 13 : 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_manualNewSupplier) ...[
                        const SizedBox(height: 10),
                        Text(
                          loc.t('procurement_supplier_new_hint'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _supplierContactCtrl,
                          decoration: InputDecoration(
                            labelText: loc.t('supplier_contact_person'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _supplierEmailCtrl,
                          decoration: InputDecoration(
                            labelText: loc.t('order_list_contact_email'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _supplierPhoneCtrl,
                          decoration: InputDecoration(
                            labelText: loc.t('order_list_contact_phone'),
                            border: const OutlineInputBorder(),
                            isDense: true,
                            counterText: '',
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: 15,
                        ),
                      ],
                    ],
                  )
                : TextField(
                    controller: _supplierCtrl,
                    decoration: InputDecoration(
                      labelText: loc.t('procurement_receipt_supplier'),
                      border: const OutlineInputBorder(),
                      isDense: narrowScreen,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: narrowScreen ? 8 : 12,
                      ),
                    ),
                    style: TextStyle(fontSize: narrowScreen ? 14 : 16),
                    textCapitalization: TextCapitalization.words,
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: _buildReceiptTable(loc, unitPrefs, currency),
            ),
          ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(
              narrowScreen ? 12 : 16,
              keyboardOpen ? 6 : 10,
              narrowScreen ? 12 : 16,
              keyboardOpen ? 10 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${loc.t('procurement_receipt_total_ordered')}: ${NumberFormat('#0.##', 'ru').format(_totalOrdered)} $currency',
                  style: TextStyle(fontSize: keyboardOpen ? 12 : 14),
                ),
                Text(
                  '${loc.t('procurement_receipt_total_received')}: ${NumberFormat('#0.##', 'ru').format(_totalReceived)} $currency',
                  style: TextStyle(fontSize: keyboardOpen ? 12 : 14),
                ),
                SizedBox(height: keyboardOpen ? 6 : 10),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: keyboardOpen ? 10 : 14,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
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
