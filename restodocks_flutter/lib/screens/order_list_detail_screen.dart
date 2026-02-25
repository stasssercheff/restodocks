import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/order_export_sheet.dart';

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
    // Загружаем номенклатуру с ценами для расчёта итоговой суммы заказа
    final store = context.read<ProductStoreSupabase>();
    await store.loadNomenclature(est.id);
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
    final account = context.read<AccountManagerSupabase>();
    final employee = account.currentEmployee;
    final establishment = account.establishment;
    if (employee == null || establishment == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_short') ?? 'Ошибка')));
      return;
    }
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

    // Сохранить во входящие (шефу и собственнику) с ценами и итогами
    final store = context.read<ProductStoreSupabase>();
    final orderForDateStr = saved.orderForDate != null ? DateFormat('yyyy-MM-dd').format(saved.orderForDate!) : null;
    final header = {
      'supplierName': saved.supplierName,
      'employeeName': employee.fullName,
      'establishmentName': establishment.name,
      'createdAt': now.toIso8601String(),
      'orderForDate': orderForDateStr,
    };
    double grandTotal = 0;
    final itemsPayload = <Map<String, dynamic>>[];
    for (final item in itemsWithQty) {
      double pricePerKg = 0;
      if (item.productId != null) {
        final ep = store.getEstablishmentPrice(item.productId!, establishment.id);
        pricePerKg = ep?.$1 ?? 0;
      }
      double pricePerUnit = pricePerKg;
      if (item.unit == 'g' || item.unit == 'г') {
        pricePerUnit = pricePerKg / 1000;
      } else if (item.unit != 'kg' && item.unit != 'кг') {
        pricePerUnit = pricePerKg;
      }
      final lineTotal = item.quantity * pricePerUnit;
      grandTotal += lineTotal;
      itemsPayload.add({
        'productName': item.productName,
        'unit': item.unit,
        'quantity': item.quantity,
        'pricePerUnit': pricePerUnit,
        'lineTotal': lineTotal,
      });
    }
    final payload = {
      'header': header,
      'items': itemsPayload,
      'grandTotal': grandTotal,
      'comment': saved.comment,
    };
    final orderDoc = await OrderDocumentService().save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      payload: payload,
    );

    if (mounted) {
      if (orderDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${loc.t('error_short') ?? 'Ошибка'}: не удалось сохранить заказ во входящие. Проверьте подключение.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.t('order_list_save_with_quantities')} ✓')));
      context.go('/product-order');
    }
  }

  List<OrderListItem> _getItemsWithQuantities() {
    if (_list == null) return [];
    return _list!.items.asMap().entries.map((e) {
      final q = e.key < _qtyControllers.length
          ? (double.tryParse(_qtyControllers[e.key].text.replaceFirst(',', '.')) ?? 0)
          : e.value.quantity;
      return e.value.copyWith(quantity: q);
    }).toList();
  }

  List<OrderListItem> _getItemsWithLocalizedNames(String lang) {
    final store = context.read<ProductStoreSupabase>();
    return _getItemsWithQuantities().map((item) {
      final name = item.productId != null
          ? (store.findProductById(item.productId!)?.getLocalizedName(lang) ?? item.productName)
          : item.productName;
      return item.copyWith(productName: name);
    }).toList();
  }

  void _showExportSheet() {
    if (_list == null) return;
    final account = context.read<AccountManagerSupabase>();
    final companyName = account.establishment?.name ?? '—';
    final loc = context.read<LocalizationService>();
    final store = context.read<ProductStoreSupabase>();
    if (store.allProducts.isEmpty) store.loadProducts();
    final itemsWithNames = _getItemsWithLocalizedNames(loc.currentLanguageCode);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => OrderExportSheet(
        list: _list!,
        itemsWithQuantities: itemsWithNames,
        companyName: companyName,
        loc: loc,
        onSaved: (msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('product_order')),
          actions: [appBarHomeButton(context)],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_list == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('product_order')),
          actions: [appBarHomeButton(context)],
        ),
        body: const Center(child: Text('Список не найден')),
      );
    }
    final list = _list!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${loc.t('order_export_order_for')}: ', style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: list.orderForDate ?? DateTime.now().add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _list = _list!.copyWith(orderForDate: picked));
                          }
                        },
                        child: Text(
                          list.orderForDate != null
                              ? DateFormat('dd.MM.yyyy').format(list.orderForDate!)
                              : '${loc.t('order_export_order_for')}...',
                        ),
                      ),
                    ],
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
                          onPressed: _showExportSheet,
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
