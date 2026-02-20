import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Шаг 2: добавление продуктов в список заказа (для конкретного поставщика). У каждого продукта задаётся единица измерения.
class OrderListProductsScreen extends StatefulWidget {
  const OrderListProductsScreen({super.key, required this.draft});

  final OrderList draft;

  @override
  State<OrderListProductsScreen> createState() => _OrderListProductsScreenState();
}

class _OrderListProductsScreenState extends State<OrderListProductsScreen> {
  late OrderList _list;

  @override
  void initState() {
    super.initState();
    _list = widget.draft;
  }

  static String _unitLabel(String unitId, String lang) =>
      CulinaryUnits.displayName(unitId, lang);

  static List<String> get _unitIds => [
        'g', 'kg', 'ml', 'l', 'pcs', 'шт', 'pack', 'can', 'box',
      ];

  Future<void> _addProduct() async {
    final acc = context.read<AccountManagerSupabase>();
    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    final estId = acc.establishment?.id;
    if (estId == null) return;
    if (store.allProducts.isEmpty) await store.loadProducts();
    final products = store.getProducts();
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('ttk_no_other_pf'))));
      return;
    }
    final product = await showDialog<Product>(
      context: context,
      builder: (ctx) => _ProductSelectDialog(
        products: products,
        lang: loc.currentLanguageCode,
      ),
    );
    if (product == null || !mounted) return;
    String unit = 'g';
    final unitResult = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = unit;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(product.getLocalizedName(loc.currentLanguageCode)),
            content: DropdownButtonFormField<String>(
              value: selected,
              decoration: InputDecoration(
                labelText: loc.t('order_list_unit'),
                border: const OutlineInputBorder(),
              ),
              items: _unitIds.map((id) => DropdownMenuItem(
                value: id,
                child: Text(_unitLabel(id, loc.currentLanguageCode)),
              )).toList(),
              onChanged: (v) => setState(() => selected = v ?? selected),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(selected),
                child: Text(loc.t('save')),
              ),
            ],
          ),
        );
      },
    );
    unit = unitResult ?? unit;
    if (!mounted) return;
    setState(() {
      _list = _list.copyWith(
        items: [
          ..._list.items,
          OrderListItem(
            productId: product.id,
            productName: product.getLocalizedName(loc.currentLanguageCode),
            unit: unit,
          ),
        ],
      );
    });
  }

  Future<void> _save() async {
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final estId = acc.establishment?.id;
    if (estId == null) return;
    final lists = await loadOrderLists(estId);
    await saveOrderLists(estId, [...lists, _list]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${loc.t('order_list_name')} ✓')));
      context.go('/product-order');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/product-order')),
        title: Text(loc.t('order_list_add_products')),
        actions: [
          if (_list.items.isNotEmpty)
            TextButton(
              onPressed: _save,
              child: Text(loc.t('save')),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_list.name} · ${_list.supplierName}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: _list.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_shopping_cart, size: 64, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          loc.t('order_list_add_products'),
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _addProduct,
                          icon: const Icon(Icons.add),
                          label: Text(loc.t('order_list_add_products')),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _list.items.length,
                    itemBuilder: (_, i) {
                      final item = _list.items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(item.productName, overflow: TextOverflow.ellipsis),
                          subtitle: Text(_unitLabel(item.unit, lang)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DropdownButton<String>(
                                value: item.unit,
                                isDense: true,
                                items: _unitIds.map((id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(_unitLabel(id, lang), style: const TextStyle(fontSize: 12)),
                                )).toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    final newItems = List<OrderListItem>.from(_list.items);
                                    newItems[i] = item.copyWith(unit: v);
                                    _list = _list.copyWith(items: newItems);
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
                                onPressed: () {
                                  setState(() {
                                    final newItems = List<OrderListItem>.from(_list.items)..removeAt(i);
                                    _list = _list.copyWith(items: newItems);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add),
                      label: Text(loc.t('order_list_add_products')),
                    ),
                  ),
                  if (_list.items.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      child: Text(loc.t('save')),
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

/// Диалог выбора продукта (поиск + список).
class _ProductSelectDialog extends StatefulWidget {
  const _ProductSelectDialog({required this.products, required this.lang});

  final List<Product> products;
  final String lang;

  @override
  State<_ProductSelectDialog> createState() => _ProductSelectDialogState();
}

class _ProductSelectDialogState extends State<_ProductSelectDialog> {
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.products
        : widget.products.where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.getLocalizedName(widget.lang).toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(loc.t('ttk_choose_product')),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                labelText: loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  return ListTile(
                    title: Text(p.getLocalizedName(widget.lang), overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
