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
  const OrderListDetailScreen(
      {super.key, required this.listId, this.department = 'kitchen'});

  final String listId;
  final String department;

  @override
  State<OrderListDetailScreen> createState() => _OrderListDetailScreenState();
}

class _OrderListDetailScreenState extends State<OrderListDetailScreen> {
  OrderList? _list;
  bool _loading = true;
  String? _establishmentId;
  final _commentCtrl = TextEditingController();
  List<TextEditingController> _qtyControllers = [];

  static String _unitLabel(String unitId, String lang) => unitId == 'pkg'
      ? (lang == 'ru' ? 'упак.' : 'pkg')
      : LocalizationService().unitLabelForLanguage(unitId, lang);

  static List<String> _allowedUnitsForProduct(Product? p) {
    const base = [
      'g',
      'kg',
      'ml',
      'l',
      'pcs',
      'pack',
      'can',
      'box',
      'bunch',
      'slice',
      'clove',
      'tbsp',
      'tsp',
      'cup',
      'oz',
      'lb',
    ];
    final options = List<String>.from(base);
    if (p?.packageWeightGrams != null && p!.packageWeightGrams! > 0) {
      if (!options.contains('pkg')) options.add('pkg');
    }
    return options;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() => _loading = false);
      return;
    }
    _establishmentId = est.id;
    final store = context.read<ProductStoreSupabase>();
    await store.loadProducts();
    await store.loadNomenclature(est.dataEstablishmentId);
    final lists = await loadOrderLists(est.id, department: widget.department);
    var found = lists.where((l) => l.id == widget.listId).firstOrNull;
    if (found == null) {
      for (final dept in ['kitchen', 'bar', 'hall']) {
        if (dept == widget.department) continue;
        final alt = await loadOrderLists(est.id, department: dept);
        found = alt.where((l) => l.id == widget.listId).firstOrNull;
        if (found != null) break;
      }
    }
    for (final c in _qtyControllers) {
      c.dispose();
    }
    _qtyControllers = found?.items
            .map((e) => TextEditingController(
                  text: e.quantity > 0 ? e.quantity.toString() : '',
                ))
            .toList() ??
        [];
    setState(() {
      _list = found;
      _loading = false;
      // Загружаем комментарий только из шаблона (savedAt == null).
      // Сохранённые заказы (savedAt != null) — это архив, комментарий для
      // новой отправки всегда начинается пустым, чтобы не тянуть старый текст.
      _commentCtrl.text =
          (found != null && found.savedAt == null) ? found.comment : '';
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('error_short') ?? 'Ошибка')));
      return;
    }
    final now = DateTime.now();
    final dateStr = DateFormat('dd.MM.yyyy').format(now);
    final itemsWithQty = _list!.items
        .asMap()
        .entries
        .map((e) {
          final q = e.key < _qtyControllers.length
              ? (double.tryParse(
                      _qtyControllers[e.key].text.replaceFirst(',', '.')) ??
                  0)
              : e.value.quantity;
          return e.value.copyWith(quantity: q);
        })
        .where((item) => item.quantity > 0)
        .toList();
    final dept = _list!.department;
    final saved = _list!.copyWith(
      id: const Uuid().v4(),
      name: '${_list!.name} $dateStr',
      comment: _commentCtrl.text,
      savedAt: now,
      createdByEmployeeId: employee.id,
      createdByEmployeeName: employee.fullName,
      items: itemsWithQty,
    );
    final lists = await loadOrderLists(_establishmentId!, department: dept);
    await saveOrderLists(_establishmentId!, [...lists, saved],
        department: dept);

    // Сохранить во входящие (шефу и собственнику) — цены подставляются на сервере через Edge Function
    final orderForDateStr = saved.orderForDate != null
        ? DateFormat('yyyy-MM-dd').format(saved.orderForDate!)
        : null;
    final header = {
      'supplierName': saved.supplierName,
      'employeeName': employee.fullName,
      'establishmentName': establishment.name,
      'createdAt': now.toIso8601String(),
      'orderForDate': orderForDateStr,
      'department': saved.department,
    };
    final itemsPayload = itemsWithQty
        .map((item) => {
              'productId': item.productId,
              'productName': item.productName,
              'unit': item.unit,
              'quantity': item.quantity,
            })
        .toList();
    final orderDoc = await OrderDocumentService().saveWithServerPrices(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      header: header,
      items: itemsPayload,
      comment: saved.comment,
      sourceLang: loc.currentLanguageCode,
    );

    if (mounted) {
      if (orderDoc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${loc.t('error_short')}: ${loc.t('order_save_inbox_error')}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      AppToastService.show('${loc.t('order_list_save_with_quantities')} ✓');
      _commentCtrl.clear();
      // pop вместо go, чтобы разрешить await в OrderListsScreen и сразу показать новый заказ
      if (context.canPop()) context.pop();
    }
  }

  List<OrderListItem> _getItemsWithQuantities() {
    if (_list == null) return [];
    return _list!.items
        .asMap()
        .entries
        .map((e) {
          final q = e.key < _qtyControllers.length
              ? (double.tryParse(
                      _qtyControllers[e.key].text.replaceFirst(',', '.')) ??
                  0)
              : e.value.quantity;
          return e.value.copyWith(quantity: q);
        })
        .where((item) => item.quantity > 0)
        .toList();
  }

  Future<List<OrderListItem>> _getItemsWithLocalizedNames(String lang) async {
    final store = context.read<ProductStoreSupabase>();
    final estId = _establishmentId;
    if (estId != null) await store.loadNomenclature(estId);
    final nomProducts =
        estId != null ? store.getNomenclatureProducts(estId) : <Product>[];
    return _getItemsWithQuantities().map((item) {
      final name = item.productId != null
          ? (nomProducts
                  .where((p) => p.id == item.productId)
                  .firstOrNull
                  ?.getLocalizedName(lang) ??
              item.productName)
          : item.productName;
      return item.copyWith(productName: name);
    }).toList();
  }

  String _displayItemName(OrderListItem item, String lang) {
    final store = context.read<ProductStoreSupabase>();
    if (item.productId != null && item.productId!.isNotEmpty) {
      final product = store.allProducts.where((p) => p.id == item.productId).firstOrNull;
      if (product != null) return product.getLocalizedName(lang);
    }
    return item.productName;
  }

  /// Сохранить текущий заказ во входящие (шефу и собственнику). Возвращает true при успехе.
  /// Цены подставляются на сервере через Edge Function.
  Future<bool> _saveOrderToInbox() async {
    if (_list == null || _establishmentId == null) return false;
    final account = context.read<AccountManagerSupabase>();
    final employee = account.currentEmployee;
    final establishment = account.establishment;
    if (employee == null || establishment == null) return false;
    final itemsWithQty = _getItemsWithQuantities();
    final now = DateTime.now();
    final orderForDateStr = _list!.orderForDate != null
        ? DateFormat('yyyy-MM-dd').format(_list!.orderForDate!)
        : null;
    final header = {
      'supplierName': _list!.supplierName,
      'employeeName': employee.fullName,
      'establishmentName': establishment.name,
      'createdAt': now.toIso8601String(),
      'orderForDate': orderForDateStr,
    };
    final itemsPayload = itemsWithQty
        .map((item) => {
              'productId': item.productId,
              'productName': item.productName,
              'unit': item.unit,
              'quantity': item.quantity,
            })
        .toList();
    final orderDoc = await OrderDocumentService().saveWithServerPrices(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      header: header,
      items: itemsPayload,
      comment: _list!.comment,
      sourceLang: context.read<LocalizationService>().currentLanguageCode,
    );
    return orderDoc != null;
  }

  Future<void> _showExportSheet() async {
    if (_list == null) return;
    final account = context.read<AccountManagerSupabase>();
    final companyName = account.establishment?.name ?? '—';
    final loc = context.read<LocalizationService>();

    // Диалог выбора языка документа
    final exportLang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_export_language_title')),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('order_export_language_subtitle')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LangButton(
                    flag: '🇷🇺',
                    label: loc.t('order_export_language_ru'),
                    onTap: () => Navigator.of(ctx).pop('ru')),
                _LangButton(
                    flag: '🇺🇸',
                    label: loc.t('order_export_language_en'),
                    onTap: () => Navigator.of(ctx).pop('en')),
                _LangButton(
                    flag: '🇪🇸',
                    label: loc.t('order_export_language_es'),
                    onTap: () => Navigator.of(ctx).pop('es')),
                _LangButton(
                    flag: '🇮🇹',
                    label: loc.t('order_export_language_it') ?? 'Italiano',
                    onTap: () => Navigator.of(ctx).pop('it')),
                _LangButton(
                    flag: '🇹🇷',
                    label: loc.t('order_export_language_tr') ?? 'Türkçe',
                    onTap: () => Navigator.of(ctx).pop('tr')),
                _LangButton(
                    flag: '🇰🇿',
                    label: loc.t('order_export_language_kk') ?? 'Қазақша',
                    onTap: () => Navigator.of(ctx).pop('kk')),
              ],
            ),
          ],
        ),
      ),
    );
    if (exportLang == null || !mounted) return;

    final itemsWithNames = await _getItemsWithLocalizedNames(exportLang);
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => OrderExportSheet(
        list: _list!,
        itemsWithQuantities: itemsWithNames,
        companyName: companyName,
        loc: loc,
        exportLang: exportLang,
        commentSourceLang: loc.currentLanguageCode,
        itemsSourceLang: loc.currentLanguageCode,
        onSaved: (msg) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg))),
        onExportToInbox: () async {
          final ok = await _saveOrderToInbox();
          if (mounted && !ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    '${loc.t('error_short')}: ${loc.t('order_save_inbox_error')}'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
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
          leading: appBarBackButton(context),
          title: Text(loc.t('product_order')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_list == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('product_order')),
        ),
        body: Center(child: Text(loc.t('order_not_found'))),
      );
    }
    final list = _list!;
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(list.name),
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
                  if ((list.contactPerson ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${loc.t('supplier_contact_person') ?? 'Контактное лицо'}: ${list.contactPerson}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: list.orderForDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() =>
                              _list = _list!.copyWith(orderForDate: picked));
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        list.orderForDate != null
                            ? DateFormat('dd.MM.yyyy')
                                .format(list.orderForDate!)
                            : loc.t('order_list_when'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Table(
                    border:
                        TableBorder.all(color: Theme.of(context).dividerColor),
                    columnWidths: const {
                      0: FlexColumnWidth(60),
                      1: FlexColumnWidth(15),
                      2: FlexColumnWidth(25),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Text(loc.t('inventory_item_name'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                            child: Text(loc.t('order_list_unit'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                            child: Text(loc.t('order_list_quantity'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      ...list.items.asMap().entries.map((e) {
                        final i = e.key;
                        final item = e.value;
                        final store = context.read<ProductStoreSupabase>();
                        final product = item.productId != null
                            ? store.allProducts
                                .where((p) => p.id == item.productId)
                                .firstOrNull
                            : null;
                        final allowedUnits = _allowedUnitsForProduct(product);
                        final currentUnit = allowedUnits.contains(item.unit)
                            ? item.unit
                            : allowedUnits.first;
                        return TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Text(_displayItemName(item, lang),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              child: DropdownButton<String>(
                                value: currentUnit,
                                isDense: true,
                                isExpanded: true,
                                items: allowedUnits
                                    .map((id) => DropdownMenuItem(
                                          value: id,
                                          child: Text(_unitLabel(id, lang),
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null)
                                    _updateItem(i, item.copyWith(unit: v));
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              child: i < _qtyControllers.length
                                  ? TextField(
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
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
                  Text(loc.t('order_list_comment'),
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _commentCtrl,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: loc.t('order_comment_hint'),
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

class _LangButton extends StatelessWidget {
  const _LangButton({
    required this.flag,
    required this.label,
    required this.onTap,
  });

  final String flag;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
