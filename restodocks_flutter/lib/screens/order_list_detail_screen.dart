import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/inventory_download.dart';
import '../services/order_document_service.dart';
import '../services/services.dart';

/// Просмотр/редактирование списка заказа: наименование, единица (редактируемая), количество. Комментарий. Сохранить список / Отправить (сохранить на устройство).
class OrderListDetailScreen extends StatefulWidget {
  const OrderListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  State<OrderListDetailScreen> createState() => _OrderListDetailScreenState();
}

class _OrderListDetailScreenState extends State<OrderListDetailScreen> {
  OrderList? _list;
  bool _loading = true;
  String? _establishmentId;
  final _commentCtrl = TextEditingController();
  List<TextEditingController> _qtyControllers = [];

  static String _unitLabel(String unitId, String lang) =>
      CulinaryUnits.displayName(unitId, lang);

  static const _unitIds = ['g', 'kg', 'ml', 'l', 'pcs', 'шт', 'pack', 'can', 'box'];

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() => _loading = false);
      return;
    }
    _establishmentId = est.id;
    final lists = await loadOrderLists(est.id);
    final found = lists.where((l) => l.id == widget.listId).firstOrNull;
    for (final c in _qtyControllers) {
      c.dispose();
    }
    _qtyControllers = found?.items.map((e) => TextEditingController(
      text: e.quantity > 0 ? e.quantity.toString() : '',
    )).toList() ?? [];
    setState(() {
      _list = found;
      _loading = false;
      if (found != null) _commentCtrl.text = found.comment;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateItem(int index, OrderListItem item) {
    if (_list == null) return;
    final newItems = List<OrderListItem>.from(_list!.items);
    if (index < 0 || index >= newItems.length) return;
    newItems[index] = item;
    setState(() => _list = _list!.copyWith(items: newItems));
  }

  void _updateComment() {
    if (_list == null) return;
    setState(() => _list = _list!.copyWith(comment: _commentCtrl.text));
  }

  Future<void> _saveWithQuantities() async {
    if (_list == null || _establishmentId == null) return;
    final loc = context.read<LocalizationService>();
    final now = DateTime.now();
    final dateStr = DateFormat('dd.MM.yyyy').format(now);
    final itemsWithQty = _list!.items.asMap().entries.map((e) {
      final q = e.key < _qtyControllers.length
          ? (double.tryParse(_qtyControllers[e.key].text.replaceFirst(',', '.')) ?? 0)
          : e.value.quantity;
      return e.value.copyWith(quantity: q);
    }).toList();
    final saved = _list!.copyWith(
      id: const Uuid().v4(),
      name: '${_list!.name} $dateStr',
      comment: _commentCtrl.text,
      savedAt: now,
      items: itemsWithQty,
    );
    final lists = await loadOrderLists(_establishmentId!);
    await saveOrderLists(_establishmentId!, [...lists, saved]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.t('order_list_save_with_quantities')} ✓')));
      context.go('/product-order');
    }
  }

  Future<void> _sendSaveToDevice() async {
    if (_list == null) return;
    final loc = context.read<LocalizationService>();
    final lang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_list_save_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LocalizationService.supportedLocales.map((locale) {
            return ListTile(
              title: Text(loc.getLanguageName(locale.languageCode)),
              onTap: () => Navigator.of(ctx).pop(locale.languageCode),
            );
          }).toList(),
        ),
      ),
    );
    if (lang == null || !mounted) return;

    // Загружаем продукты для перевода названий (если есть productId)
    final store = context.read<ProductStoreSupabase>();
    if (store.allProducts.isEmpty) await store.loadProducts();

    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0));
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue(_list!.name);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('${loc.tForLanguage(lang, 'order_list_supplier_name')}: ${_list!.supplierName}');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)).value = TextCellValue(loc.tForLanguage(lang, 'order_list_quantity'));
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)).value = TextCellValue(loc.tForLanguage(lang, 'order_list_unit'));
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3)).value = TextCellValue(loc.tForLanguage(lang, 'inventory_item_name'));
    for (var idx = 0; idx < _list!.items.length; idx++) {
      final item = _list!.items[idx];
      final q = idx < _qtyControllers.length
          ? (double.tryParse(_qtyControllers[idx].text.replaceFirst(',', '.')) ?? item.quantity)
          : item.quantity;
      final productName = (item.productId != null
              ? store.findProductById(item.productId!)?.getLocalizedName(lang)
              : null) ??
          item.productName;
      final r = idx + 4;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value = TextCellValue(q.toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value = TextCellValue(_unitLabel(item.unit, lang));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value = TextCellValue(productName);
    }
    var lastRow = _list!.items.length + 4;
    final commentText = _commentCtrl.text.trim();
    if (commentText.isNotEmpty) {
      lastRow++;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: lastRow)).value = TextCellValue('${loc.tForLanguage(lang, 'order_list_comment')}: $commentText');
    }
    final out = excel.encode();
    if (out == null) throw StateError('Excel encode failed');
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'order_${_list!.name.replaceAll(RegExp(r'[^\w\-.]'), '_')}_$dateStr.xlsx';
    await saveFileBytes(fileName, out);

    // Отправить шеф-повару во Входящие
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;
    if (establishment != null && employee != null) {
      final chefs = await account.getExecutiveChefsForEstablishment(establishment.id);
      if (chefs.isNotEmpty) {
        final itemsWithQty = <Map<String, dynamic>>[];
        for (var idx = 0; idx < _list!.items.length; idx++) {
          final item = _list!.items[idx];
          final q = idx < _qtyControllers.length
              ? (double.tryParse(_qtyControllers[idx].text.replaceFirst(',', '.')) ?? item.quantity)
              : item.quantity;
          final productName = (item.productId != null
                  ? store.findProductById(item.productId!)?.getLocalizedName(lang)
                  : null) ??
              item.productName;
          itemsWithQty.add({
            'productName': productName,
            'unit': item.unit,
            'quantity': q,
          });
        }
        final payload = {
          'header': {
            'establishmentName': establishment.name,
            'employeeName': employee.fullName,
            'supplierName': _list!.supplierName,
            'date': dateStr.replaceAll('-', '.'),
            'listName': _list!.name,
            'comment': _commentCtrl.text.trim(),
          },
          'rows': itemsWithQty,
        };
        await OrderDocumentService().save(
          establishmentId: establishment.id,
          createdByEmployeeId: employee.id,
          recipientChefId: chefs.first.id,
          recipientEmail: chefs.first.email,
          payload: payload,
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('order_list_save_to_device')}: $fileName')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()), title: Text(loc.t('product_order'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_list == null) {
      return Scaffold(
        appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/product-order')), title: Text(loc.t('product_order'))),
        body: const Center(child: Text('Список не найден')),
      );
    }
    final list = _list!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/product-order')),
        title: Text(list.name),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${loc.t('order_list_supplier_name')}: ${list.supplierName}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  Table(
                    border: TableBorder.all(color: Theme.of(context).dividerColor),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FixedColumnWidth(100),
                      2: FixedColumnWidth(100),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Text(loc.t('inventory_item_name'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            child: Text(loc.t('order_list_unit'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            child: Text(loc.t('order_list_quantity'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      ...list.items.asMap().entries.map((e) {
                        final i = e.key;
                        final item = e.value;
                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(item.productName, overflow: TextOverflow.ellipsis),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: DropdownButton<String>(
                                value: item.unit,
                                isDense: true,
                                isExpanded: true,
                                items: _unitIds.map((id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(_unitLabel(id, lang), style: const TextStyle(fontSize: 12)),
                                )).toList(),
                                onChanged: (v) {
                                  if (v != null) _updateItem(i, item.copyWith(unit: v));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                              child: i < _qtyControllers.length
                                  ? TextField(
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      style: const TextStyle(fontSize: 12),
                                      controller: _qtyControllers[i],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(loc.t('order_list_comment'), style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _commentCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Комментарий к заказу',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    onChanged: (_) => _updateComment(),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _saveWithQuantities,
                        child: Text(loc.t('order_list_save_with_quantities')),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: FilledButton(
                          onPressed: _sendSaveToDevice,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(loc.t('order_list_send')),
                        ),
                      ),
                    ],
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
