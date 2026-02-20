import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Заказ продуктов: при нажатии не список продуктов, а «Создать» и список созданных списков заказов.
class OrderListsScreen extends StatefulWidget {
  const OrderListsScreen({super.key});

  @override
  State<OrderListsScreen> createState() => _OrderListsScreenState();
}

class _OrderListsScreenState extends State<OrderListsScreen> {
  List<OrderList> _lists = [];
  bool _loading = true;
  String? _establishmentId;

  Future<void> _deleteList(OrderList list) async {
    final loc = context.read<LocalizationService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete') ?? 'Удалить'),
        content: Text('${loc.t('order_list_delete_confirm') ?? 'Удалить список'} «${list.name}»?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.t('cancel') ?? 'Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete') ?? 'Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || _establishmentId == null || !mounted) return;
    final lists = await loadOrderLists(_establishmentId!);
    final filtered = lists.where((l) => l.id != list.id).toList();
    await saveOrderLists(_establishmentId!, filtered);
    if (mounted) {
      setState(() => _lists = filtered);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('order_list_deleted') ?? 'Список удалён')));
    }
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _lists = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _establishmentId = est.id;
    });
    try {
      final list = await loadOrderLists(est.id);
      if (mounted) {
        setState(() {
          _lists = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _lists = [];
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(loc.t('inbox_header_date') ?? 'Дата', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(child: Text(loc.t('inbox_header_section') ?? 'Цех', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(child: Text(loc.t('inbox_header_employee') ?? 'Сотрудник', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              Expanded(child: Text(loc.t('inbox_header_supplier') ?? 'Поставщик', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text(dateStr, style: Theme.of(context).textTheme.bodyMedium)),
              Expanded(child: Text(establishment?.name ?? '—', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(child: Text(employee?.fullName ?? '—', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(child: Text('—', style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/home')),
        title: Text(loc.t('product_order')),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lists.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_shopping_cart, size: 80, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 24),
                        Text(
                          loc.t('order_list_empty'),
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          loc.t('order_list_empty_hint'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          onPressed: () async {
                            await context.push('/product-order/new');
                            if (mounted) _load();
                          },
                          icon: const Icon(Icons.add, size: 24),
                          label: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(loc.t('order_list_create'), style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    itemCount: _lists.length,
                    itemBuilder: (_, i) {
                      final list = _lists[i];
                      final dateStr = list.savedAt != null
                          ? DateFormat('dd.MM.yyyy').format(list.savedAt!)
                          : null;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: list.isSavedWithQuantities
                                ? Colors.amber.shade100
                                : Theme.of(context).colorScheme.primaryContainer,
                            child: Icon(
                              list.isSavedWithQuantities ? Icons.check_circle : Icons.shopping_cart,
                              color: list.isSavedWithQuantities ? Colors.amber.shade800 : Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            list.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            list.supplierName + (dateStr != null ? ' · $dateStr' : ''),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                                onPressed: () => _deleteList(list),
                                tooltip: loc.t('delete') ?? 'Удалить',
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            await context.push('/product-order/${list.id}');
                            if (mounted) _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/product-order/new');
          if (mounted) _load();
        },
        icon: const Icon(Icons.add),
        label: Text(loc.t('order_list_create')),
      ),
    );
  }
}
