import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
    required this.orderedQty,
    required this.referencePricePerUnit,
    required this.received,
    required this.actualPrice,
    required this.discountPercent,
    this.nameReadOnly = false,
  }) : nameCtrl = TextEditingController(text: productName);

  String? productId;
  final TextEditingController nameCtrl;
  String unit;
  final double orderedQty;
  double referencePricePerUnit;
  final TextEditingController received;
  final TextEditingController actualPrice;
  final TextEditingController discountPercent;
  final bool nameReadOnly;
}

class _PhotoParseLineDraft {
  _PhotoParseLineDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    this.pricePerUnit,
  });

  String name;
  double quantity;
  String unit;
  double? pricePerUnit;
}

class _PhotoParseDraft {
  _PhotoParseDraft({
    required this.supplierName,
    required this.lines,
  });

  String supplierName;
  List<_PhotoParseLineDraft> lines;
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
  bool _photoRecognizing = false;
  bool _photoFlowInitialized = false;

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
      if (widget.manualOffSystem && !_photoFlowInitialized) {
        final location = GoRouterState.of(context).location;
        final fromPhoto =
            (Uri.tryParse(location)?.queryParameters['photo'] ?? '') == '1';
        if (fromPhoto) {
          _photoFlowInitialized = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _startPhotoRecognitionFlow());
        }
      }
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

  _ReceiptLineEdit _createEmptyLine() => _ReceiptLineEdit(
        productId: null,
        productName: '',
        unit: 'kg',
        orderedQty: 0,
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

  static const _newProductUnits = [
    'g',
    'kg',
    'ml',
    'l',
    'pcs',
    'pack',
    'can',
    'box',
    'bottle',
  ];

  Future<void> _createNewNomenclatureProduct(int lineIndex) async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final store = context.read<ProductStoreSupabase>();
    final est = acc.establishment;
    final nomEstId = est?.productsEstablishmentId;
    if (nomEstId == null) return;

    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    var unitChoice = 'kg';

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
                    value: _newProductUnits.contains(unitChoice)
                        ? unitChoice
                        : 'kg',
                    decoration: InputDecoration(
                      labelText: loc.t('order_list_unit'),
                      border: const OutlineInputBorder(),
                    ),
                    items: _newProductUnits
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

  String _guessSupplierName(String? rawText) {
    if (rawText == null || rawText.trim().isEmpty) return '';
    final lines = rawText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(8)
        .toList();
    for (final line in lines) {
      if (line.length < 3 || line.length > 40) continue;
      if (RegExp(r'\d').hasMatch(line)) continue;
      if (line.contains(':')) continue;
      return line;
    }
    return '';
  }

  Future<ImageSource?> _pickPhotoSource(LocalizationService loc) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(loc.t('procurement_receipt_photo_take')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(loc.t('procurement_receipt_photo_gallery')),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showPhotoPreviewDialog(
      LocalizationService loc, _PhotoParseDraft draft) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('procurement_receipt_photo_preview_title')),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${loc.t('procurement_receipt_supplier')}: ${draft.supplierName.isEmpty ? '—' : draft.supplierName}',
              ),
              const SizedBox(height: 12),
              Text(
                loc
                    .t('procurement_receipt_photo_recognized_lines')
                    .replaceAll('%s', '${draft.lines.length}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: draft.lines.length,
                  itemBuilder: (_, i) {
                    final l = draft.lines[i];
                    final price =
                        l.pricePerUnit != null ? ' · ${l.pricePerUnit}' : '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${i + 1}. ${l.name} · ${l.quantity} ${l.unit}$price',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.t('procurement_receipt_fix')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('procurement_receipt_continue')),
          ),
        ],
      ),
    );
  }

  Future<_PhotoParseDraft?> _showPhotoEditDialog(
      LocalizationService loc, _PhotoParseDraft draft) async {
    final supplierCtrl = TextEditingController(text: draft.supplierName);
    final rows = draft.lines
        .map(
          (e) => (
            name: TextEditingController(text: e.name),
            qty: TextEditingController(text: _formatQtyForField(e.quantity)),
            unit: TextEditingController(text: e.unit),
            price: TextEditingController(
              text: e.pricePerUnit == null
                  ? ''
                  : _formatPriceForField(e.pricePerUnit!),
            ),
          ),
        )
        .toList();
    final result = await showDialog<_PhotoParseDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('procurement_receipt_fix')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: supplierCtrl,
                  decoration: InputDecoration(
                    labelText: loc.t('procurement_receipt_supplier'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < rows.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: rows[i].name,
                          decoration: InputDecoration(
                            labelText: loc.t('product_name'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: rows[i].qty,
                          decoration: InputDecoration(
                            labelText:
                                loc.t('procurement_receipt_received_qty'),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: rows[i].unit,
                          decoration: InputDecoration(
                            labelText: loc.t('order_list_unit'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: rows[i].price,
                          decoration: InputDecoration(
                            labelText:
                                loc.t('procurement_receipt_actual_price'),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final updatedLines = <_PhotoParseLineDraft>[];
              for (final row in rows) {
                final name = row.name.text.trim();
                if (name.isEmpty) continue;
                final qty = _parse(row.qty.text);
                final unit =
                    row.unit.text.trim().isEmpty ? 'kg' : row.unit.text.trim();
                final price = _parse(row.price.text);
                updatedLines.add(
                  _PhotoParseLineDraft(
                    name: name,
                    quantity: qty <= 0 ? 1 : qty,
                    unit: unit,
                    pricePerUnit: price > 0 ? price : null,
                  ),
                );
              }
              Navigator.of(ctx).pop(
                _PhotoParseDraft(
                  supplierName: supplierCtrl.text.trim(),
                  lines: updatedLines,
                ),
              );
            },
            child: Text(loc.t('procurement_receipt_continue')),
          ),
        ],
      ),
    );
    supplierCtrl.dispose();
    for (final row in rows) {
      row.name.dispose();
      row.qty.dispose();
      row.unit.dispose();
      row.price.dispose();
    }
    return result;
  }

  void _applyPhotoDraft(_PhotoParseDraft draft) {
    final newLines = <_ReceiptLineEdit>[];
    for (final line in draft.lines) {
      newLines.add(
        _ReceiptLineEdit(
          productId: null,
          productName: line.name,
          unit: line.unit,
          orderedQty: 0,
          referencePricePerUnit: 0,
          received:
              TextEditingController(text: _formatQtyForField(line.quantity)),
          actualPrice: TextEditingController(
            text: line.pricePerUnit == null
                ? ''
                : _formatPriceForField(line.pricePerUnit!),
          ),
          discountPercent: TextEditingController(text: '0'),
          nameReadOnly: false,
        ),
      );
    }
    if (newLines.isEmpty) {
      newLines.add(_createEmptyLine());
    }
    while (newLines.length < 2) {
      newLines.add(_createEmptyLine());
    }
    if (mounted) {
      for (final l in _lines) {
        _disposeLine(l);
      }
      setState(() {
        if (draft.supplierName.isNotEmpty) {
          _supplierCtrl.text = draft.supplierName;
        }
        _lines = newLines;
        _syncManualTrailingEmptyInPlace();
      });
    }
  }

  Future<void> _startPhotoRecognitionFlow() async {
    if (!widget.manualOffSystem || _photoRecognizing) return;
    final loc = context.read<LocalizationService>();
    final source = await _pickPhotoSource(loc);
    if (source == null || !mounted) return;
    setState(() => _photoRecognizing = true);
    try {
      final imageService = ImageService();
      final XFile? photo = source == ImageSource.camera
          ? await imageService.takePhotoWithCamera()
          : await imageService.pickImageFromGallery();
      if (photo == null || !mounted) return;
      final bytes = await imageService.xFileToBytes(photo);
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final ai = context.read<AiService>();
      final result = await ai.recognizeReceipt(bytes);
      if (!mounted) return;
      if (result == null || result.lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_receipt_scan_empty'))),
        );
        return;
      }
      final draft = _PhotoParseDraft(
        supplierName: _guessSupplierName(result.rawText),
        lines: result.lines
            .where((e) => e.productName.trim().isNotEmpty)
            .map(
              (e) => _PhotoParseLineDraft(
                name: e.productName.trim(),
                quantity: e.quantity > 0 ? e.quantity : 1,
                unit: (e.unit ?? 'kg').trim().isEmpty ? 'kg' : e.unit!.trim(),
                pricePerUnit: e.price,
              ),
            )
            .toList(),
      );
      if (draft.lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_receipt_scan_empty'))),
        );
        return;
      }
      final proceed = await _showPhotoPreviewDialog(loc, draft);
      if (!mounted || proceed == null) return;
      if (proceed) {
        _applyPhotoDraft(draft);
      } else {
        final edited = await _showPhotoEditDialog(loc, draft);
        if (edited != null && edited.lines.isNotEmpty) {
          _applyPhotoDraft(edited);
        }
      }
    } finally {
      if (mounted) setState(() => _photoRecognizing = false);
    }
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

      final priceLines = _collectPriceChangeLines(store, est);
      final approveOnDevice =
          ProcurementPriceApprovalService.canApproveOnReceiptDevice(
        emp,
        widget.department,
      );

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

  Widget _buildReceiptTable(LocalizationService loc, String currency) {
    final thStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final nf = NumberFormat('#0.##', 'ru');
    final onField =
        widget.manualOffSystem ? _onManualChanged : () => setState(() {});

    Widget cell(Widget w) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: w,
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1000),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
          ),
          columnWidths: const {
            0: FixedColumnWidth(32),
            1: FlexColumnWidth(2.4),
            2: FixedColumnWidth(72),
            3: FixedColumnWidth(84),
            4: FixedColumnWidth(72),
            5: FixedColumnWidth(84),
            6: FixedColumnWidth(88),
            7: FixedColumnWidth(56),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              children: [
                cell(Text(loc.t('procurement_receipt_col_no'), style: thStyle)),
                cell(Text(loc.t('product_name'), style: thStyle)),
                cell(
                    Text(loc.t('procurement_receipt_ordered'), style: thStyle)),
                cell(Text(loc.t('procurement_receipt_ref_price'),
                    style: thStyle)),
                cell(Text(loc.t('procurement_receipt_received_qty'),
                    style: thStyle)),
                cell(Text(loc.t('procurement_receipt_actual_price'),
                    style: thStyle)),
                cell(Text(loc.t('procurement_receipt_line_total'),
                    style: thStyle)),
                cell(Text(loc.t('procurement_receipt_discount'),
                    style: thStyle)),
              ],
            ),
            ...List.generate(
              _lines.length,
              (i) => _tableDataRow(
                i,
                loc,
                currency,
                cell,
                onField,
                nf,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableRow _tableDataRow(
    int i,
    LocalizationService loc,
    String currency,
    Widget Function(Widget) cell,
    VoidCallback onField,
    NumberFormat nf,
  ) {
    final l = _lines[i];
    final ref = l.referencePricePerUnit;
    final act = _parse(l.actualPrice.text);
    final Color? priceColor = ref <= 0
        ? null
        : (act < ref * 0.999
            ? Colors.green
            : (act > ref * 1.001 ? Colors.red : null));

    return TableRow(
      children: [
        cell(
          Text(
            '${i + 1}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        cell(
          l.nameReadOnly
              ? Text(
                  l.nameCtrl.text.isEmpty ? '—' : l.nameCtrl.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : widget.manualOffSystem
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: l.nameCtrl,
                            decoration: const InputDecoration(isDense: true),
                            style: Theme.of(context).textTheme.bodySmall,
                            onChanged: (_) => onField(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search, size: 22),
                          tooltip: loc.t('procurement_pick_product'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => _pickNomenclatureProduct(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 22),
                          tooltip: loc.t('procurement_product_new'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () => _createNewNomenclatureProduct(i),
                        ),
                      ],
                    )
                  : TextField(
                      controller: l.nameCtrl,
                      decoration: const InputDecoration(isDense: true),
                      style: Theme.of(context).textTheme.bodySmall,
                      onChanged: (_) => onField(),
                    ),
        ),
        cell(
          Text(
            '${nf.format(l.orderedQty)} ${_localizedUnit(loc, l.unit)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        cell(
          Text(
            ref > 0 ? '${nf.format(ref)} $currency' : '—',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        cell(
          TextField(
            controller: l.received,
            decoration: const InputDecoration(isDense: true),
            style: Theme.of(context).textTheme.bodySmall,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            onChanged: (_) => onField(),
          ),
        ),
        cell(
          TextField(
            controller: l.actualPrice,
            style: TextStyle(
              color: priceColor,
              fontSize: 13,
            ),
            decoration: const InputDecoration(isDense: true),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
            ],
            onChanged: (_) => onField(),
          ),
        ),
        cell(
          Text(
            '${nf.format(_lineTotal(l))} $currency',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.right,
          ),
        ),
        cell(
          TextField(
            controller: l.discountPercent,
            decoration: const InputDecoration(isDense: true),
            style: Theme.of(context).textTheme.bodySmall,
            keyboardType: TextInputType.number,
            onChanged: (_) => onField(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
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

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('procurement_receipt_title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: widget.manualOffSystem
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _supplierCtrl,
                              decoration: InputDecoration(
                                labelText:
                                    loc.t('procurement_receipt_supplier'),
                                border: const OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.words,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _showSupplierPicker,
                            icon: const Icon(Icons.list_alt),
                            tooltip: loc.t('procurement_pick_supplier'),
                          ),
                        ],
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
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
          ),
          Expanded(
            child: _buildReceiptTable(loc, currency),
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
                if (widget.manualOffSystem) ...[
                  OutlinedButton.icon(
                    onPressed:
                        _photoRecognizing ? null : _startPhotoRecognitionFlow,
                    icon: _photoRecognizing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(loc.t('procurement_receipt_fill_from_photo')),
                  ),
                  const SizedBox(height: 8),
                ],
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
