import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';

/// Экран «Заказ продуктов» — сохранённые заказы. Поставщики — через иконку в AppBar и при создании заказа.
/// [department] = kitchen|bar|hall для фильтрации по подразделению.
class OrderListsScreen extends StatefulWidget {
  const OrderListsScreen({super.key, this.embedded = false, this.department = 'kitchen'});

  final bool embedded;
  final String department;

  @override
  State<OrderListsScreen> createState() => _OrderListsScreenState();
}

class _OrderListsScreenState extends State<OrderListsScreen> {
  List<OrderList> _allLists = [];
  bool _loading = true;
  String? _establishmentId;
  final TextEditingController _orderSearchController = TextEditingController();
  String _orderSearchQuery = '';

  /// Поставщики — шаблоны (нет savedAt)
  List<OrderList> get _suppliers =>
      _allLists.where((l) => !l.isSavedWithQuantities).toList();

  /// Сохранённые списки заказа (есть savedAt)
  List<OrderList> get _savedOrders =>
      _allLists.where((l) => l.isSavedWithQuantities).toList()
        ..sort((a, b) => (b.savedAt ?? DateTime(0)).compareTo(a.savedAt ?? DateTime(0)));

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _allLists = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _establishmentId = est.id;
    });
    try {
      final list = await loadOrderLists(est.id, department: widget.department);
      if (mounted) {
        setState(() {
          _allLists = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _allLists = [];
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _orderSearchController.dispose();
    super.dispose();
  }

  List<OrderList> get _filteredOrders {
    if (_orderSearchQuery.isEmpty) return _savedOrders;
    final q = _orderSearchQuery.trim().toLowerCase();
    return _savedOrders.where((o) => o.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _deleteList(OrderList list) async {
    final estId = _establishmentId;
    if (estId == null) return;
    final updated = _allLists.where((l) => l.id != list.id).toList();
    await saveOrderLists(estId, updated, department: widget.department);
    if (mounted) setState(() => _allLists = updated);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: ScrollToTopAppBarTitle(
          child: Text(loc.t('product_order')),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _OrderListsTab(
                        orders: _filteredOrders,
                        searchController: _orderSearchController,
                        onSearchChanged: (v) => setState(() => _orderSearchQuery = v.trim().toLowerCase()),
                        onTap: (order) async {
                          await context.push('/product-order/${order.id}?department=${widget.department}');
                          if (mounted) _load();
                        },
                        onDelete: _deleteList,
                        onCreate: () async {
                          if (_suppliers.isEmpty) {
                            await context.push('/product-order/new?department=${widget.department}');
                          } else {
                            await context.push('/product-order/create-order?department=${widget.department}');
                          }
                          if (mounted) _load();
                        },
                        loc: loc,
                      ),
    );
  }

}

// ────────────────────────────────────────────────────────────────
// Вкладка заказов (поставщики — через иконку в AppBar и при создании заказа)
// ────────────────────────────────────────────────────────────────

// ────────────────────────────────────────────────────────────────
// Helper for grouped order list items
// ────────────────────────────────────────────────────────────────

class _OrderListItem {
  const _OrderListItem({required this.isHeader, this.headerLabel, this.order});
  final bool isHeader;
  final String? headerLabel;
  final OrderList? order;
}

// ────────────────────────────────────────────────────────────────
// Вкладка «Списки заказа»
// ────────────────────────────────────────────────────────────────

class _OrderListsTab extends StatelessWidget {
  const _OrderListsTab({
    required this.orders,
    required this.onTap,
    required this.onDelete,
    required this.onCreate,
    required this.loc,
    required this.searchController,
    required this.onSearchChanged,
  });

  final List<OrderList> orders;
  final void Function(OrderList) onTap;
  final void Function(OrderList) onDelete;
  final VoidCallback onCreate;
  final LocalizationService loc;
  final TextEditingController searchController;
  final void Function(String) onSearchChanged;

  @override
  Widget build(BuildContext context) {
    // Group orders by supplierName, build flat list (header, item, item, header, item...)
    final supplierGroups = <String, List<OrderList>>{};
    for (final o in orders) {
      final key = o.supplierName.trim().isEmpty ? '—' : o.supplierName;
      supplierGroups.putIfAbsent(key, () => []).add(o);
    }
    final supplierNames = supplierGroups.keys.toList()..sort((a, b) => a.compareTo(b));
    final flatItems = <_OrderListItem>[];
    for (final supplier in supplierNames) {
      flatItems.add(_OrderListItem(isHeader: true, headerLabel: supplier, order: null));
      for (final order in supplierGroups[supplier]!) {
        flatItems.add(_OrderListItem(isHeader: false, headerLabel: null, order: order));
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: loc.t('order_search_hint'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.list_alt_outlined,
                            size: 72,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 20),
                        Text(
                          loc.t('order_list_empty') ?? 'Нет списков заказа',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loc.t('order_list_empty_hint') ??
                              'Выберите поставщика, заполните количества и сохраните или отправьте заказ',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: flatItems.length,
                  itemBuilder: (_, i) {
                    final item = flatItems[i];
                    if (item.isHeader) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 6),
                        child: Text(
                          item.headerLabel!,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      );
                    }
                    final order = item.order!;
                    final dateStr = order.savedAt != null
                        ? DateFormat('dd.MM.yyyy HH:mm')
                            .format(order.savedAt!)
                        : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.shade100,
                          child: Icon(Icons.check_circle,
                              color: Colors.amber.shade800),
                        ),
                        title: Text(order.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.supplierName,
                                overflow: TextOverflow.ellipsis),
                            if (dateStr != null)
                              Text(dateStr,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chevron_right),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: Theme.of(context).colorScheme.error,
                              tooltip: loc.t('delete') ?? 'Удалить',
                              onPressed: () => _confirmDelete(context, order),
                            ),
                          ],
                        ),
                        onTap: () => onTap(order),
                      ),
                    );
                  },
                ),
        ),
        _BottomCreateButton(
          label: loc.t('order_list_create') ?? 'Создать заказ',
          onPressed: onCreate,
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, OrderList order) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete') ?? 'Удалить'),
        content: Text(
            '${loc.t('order_delete_order_confirm') ?? 'Удалить список заказа'} «${order.name}»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.t('cancel') ?? 'Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete') ?? 'Удалить'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) onDelete(order);
    });
  }
}

// ────────────────────────────────────────────────────────────────
// Кнопка «Создать» внизу экрана
// ────────────────────────────────────────────────────────────────

class _BottomCreateButton extends StatelessWidget {
  const _BottomCreateButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add),
          label: Text(label),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ),
    );
  }
}
