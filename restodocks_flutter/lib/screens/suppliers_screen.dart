import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран «Поставщики» — только карточки поставщиков со списком продуктов, без заказов.
/// Для каждого подразделения (кухня, бар, зал) свои поставщики.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.department});

  final String department;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<OrderList> _suppliers = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  bool _sortAsc = true; // true = А–Я, false = Я–А

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<OrderList> get _filteredSuppliers {
    var list = List<OrderList>.from(_suppliers);
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        if (s.supplierName.toLowerCase().contains(q)) return true;
        return s.items.any((i) => i.productName.toLowerCase().contains(q));
      }).toList();
    }
    list.sort((a, b) {
      final cmp = a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase());
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  String get _departmentLabel {
    switch (widget.department) {
      case 'kitchen':
        return 'Кухня';
      case 'bar':
        return 'Бар';
      case 'hall':
        return 'Зал';
      default:
        return widget.department;
    }
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'Нет заведения';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await loadOrderLists(est.id, department: widget.department);
      if (mounted) {
        setState(() {
          _suppliers = list.where((l) => !l.isSavedWithQuantities).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text('${loc.t('order_tab_suppliers') ?? 'Поставщики'} — $_departmentLabel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await context.push('/product-order/new?department=${widget.department}');
              if (mounted) _load();
            },
            tooltip: loc.t('order_create_supplier') ?? 'Создать поставщика',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _suppliers.isEmpty && !_loading && _error == null
          ? _buildBody(loc)
          : Column(
              children: [
                if (_suppliers.isNotEmpty) _buildSearchAndSortPanel(loc),
                Expanded(child: _buildBody(loc)),
              ],
            ),
    );
  }

  Widget _buildSearchAndSortPanel(LocalizationService loc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: loc.t('order_search_supplier_or_product') ?? 'Поиск по поставщику или продукту',
              prefixIcon: const Icon(Icons.search, size: 22),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _searchController.clear()),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                loc.t('order_sort') ?? 'Сортировка:',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(loc.t('order_sort_az') ?? 'А–Я'),
                selected: _sortAsc,
                onSelected: (_) => setState(() => _sortAsc = true),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(loc.t('order_sort_za') ?? 'Я–А'),
                selected: !_sortAsc,
                onSelected: (_) => setState(() => _sortAsc = false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LocalizationService loc) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
            ],
          ),
        ),
      );
    }
    if (_suppliers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                loc.t('order_suppliers_empty') ?? 'Нет поставщиков',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('order_suppliers_empty_hint') ??
                    'Создайте поставщика в разделе «Заказ продуктов» — «Поставщики»',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.shopping_cart),
                label: Text(loc.t('product_order') ?? 'Заказ продуктов'),
                onPressed: () => context.go('/product-order?department=${widget.department}'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredSuppliers;
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('order_no_results') ?? 'Ничего не найдено',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final s = filtered[i];
          final contacts = [s.email, s.phone, s.telegram, s.whatsapp, s.zalo]
              .where((v) => v != null && v.isNotEmpty)
              .join(' · ');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.store_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.supplierName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (contacts.isNotEmpty)
                    Text(
                      contacts,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${loc.t('order_products_count') ?? 'Продуктов'}: ${s.items.length}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      if (s.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...s.items.take(20).map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.productName,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    '${item.unit}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            )),
                        if (s.items.length > 20)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '... и ещё ${s.items.length - 20}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
