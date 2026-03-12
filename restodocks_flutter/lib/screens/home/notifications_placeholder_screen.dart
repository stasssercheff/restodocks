import 'package:flutter/material.dart';
import '../../utils/dev_log.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

/// Экран уведомлений с историей заказов и инвентаризаций
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange? _dateFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('notifications')),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showDateFilter,
            tooltip: loc.t('filter_by_dates'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '📦 ${loc.t('tab_orders')}'),
            Tab(text: '📋 ${loc.t('tab_inventories')}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrderHistoryTab(dateFilter: _dateFilter),
          _InventoryHistoryTab(dateFilter: _dateFilter),
        ],
      ),
    );
  }

  void _showDateFilter() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, now.day);

    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateFilter ?? DateTimeRange(start: lastMonth, end: now),
    ).then((range) {
      if (range != null) {
        setState(() => _dateFilter = range);
      }
    });
  }
}

/// Вкладка истории заказов
class _OrderHistoryTab extends StatefulWidget {
  final DateTimeRange? dateFilter;

  const _OrderHistoryTab({this.dateFilter});

  @override
  State<_OrderHistoryTab> createState() => _OrderHistoryTabState();
}

class _OrderHistoryTabState extends State<_OrderHistoryTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrderHistory();
  }

  @override
  void didUpdateWidget(_OrderHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateFilter != widget.dateFilter) {
      _loadOrderHistory();
    }
  }

  Future<void> _loadOrderHistory() async {
    setState(() => _loading = true);

    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        setState(() => _loading = false);
        return;
      }

      final orderService = context.read<OrderHistoryService>();
      final orders = await orderService.getOrderHistory(
        establishmentId,
        startDate: widget.dateFilter?.start,
        endDate: widget.dateFilter?.end,
      );

      setState(() {
        _orders = orders;
        _loading = false;
      });
    } catch (e) {
      devLog('Error loading order history: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              loc.t('order_history'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('order_history_empty'),
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.dateFilter != null) ...[
              const SizedBox(height: 16),
              Text(
                loc.t('filter_date_range').replaceFirst('%s', DateFormat('dd.MM.yyyy').format(widget.dateFilter!.start)).replaceFirst('%s', DateFormat('dd.MM.yyyy').format(widget.dateFilter!.end)),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final order = _orders[index];
        final createdAt = DateTime.parse(order['created_at']);
        final status = order['status'] ?? 'sent';
        final employeeName = order['employees']?['full_name'] ?? loc.t('unknown');

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.shopping_cart,
              color: _getStatusColor(status),
            ),
            title: Text(loc.t('order_from').replaceFirst('%s', DateFormat('dd.MM.yyyy HH:mm').format(createdAt))),
            subtitle: Text('${loc.t('employee_label')}: $employeeName\n${loc.t('status_label')}: ${_getStatusText(loc, status)}'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => _showOrderDetails(context, order),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'sent': return Colors.blue;
      case 'processing': return Colors.orange;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusText(LocalizationService loc, String status) {
    switch (status) {
      case 'sent': return loc.t('status_sent');
      case 'processing': return loc.t('status_processing');
      case 'completed': return loc.t('status_completed');
      case 'cancelled': return loc.t('status_cancelled');
      default: return status;
    }
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    final loc = context.read<LocalizationService>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_details')),
        content: SingleChildScrollView(
          child: Text(
            '${loc.t('order_id_label')}: ${order['id']}\n'
            '${loc.t('date_label')}: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(order['created_at']))}\n'
            '${loc.t('status_label')}: ${_getStatusText(loc, order['status'] ?? 'sent')}\n\n'
            '${loc.t('order_data_label')}:\n${order['order_data'] != null ? order['order_data'].toString() : loc.t('no_data')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('close')),
          ),
        ],
      ),
    );
  }
}

/// Вкладка истории инвентаризаций
class _InventoryHistoryTab extends StatefulWidget {
  final DateTimeRange? dateFilter;

  const _InventoryHistoryTab({this.dateFilter});

  @override
  State<_InventoryHistoryTab> createState() => _InventoryHistoryTabState();
}

class _InventoryHistoryTabState extends State<_InventoryHistoryTab> {
  List<Map<String, dynamic>> _inventories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInventoryHistory();
  }

  @override
  void didUpdateWidget(_InventoryHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateFilter != widget.dateFilter) {
      _loadInventoryHistory();
    }
  }

  Future<void> _loadInventoryHistory() async {
    setState(() => _loading = true);

    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        setState(() => _loading = false);
        return;
      }

      final inventoryService = context.read<InventoryHistoryService>();
      final inventories = await inventoryService.getInventoryHistory(
        establishmentId,
        startDate: widget.dateFilter?.start,
        endDate: widget.dateFilter?.end,
      );

      setState(() {
        _inventories = inventories;
        _loading = false;
      });
    } catch (e) {
      devLog('Error loading inventory history: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_inventories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              loc.t('inventory_history'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('inventory_history_empty'),
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.dateFilter != null) ...[
              const SizedBox(height: 16),
              Text(
                loc.t('filter_date_range').replaceFirst('%s', DateFormat('dd.MM.yyyy').format(widget.dateFilter!.start)).replaceFirst('%s', DateFormat('dd.MM.yyyy').format(widget.dateFilter!.end)),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _inventories.length,
      itemBuilder: (context, index) {
        final inventory = _inventories[index];
        final date = DateTime.parse(inventory['date']);
        final status = inventory['status'] ?? 'completed';
        final employeeName = inventory['employees']?['full_name'] ?? loc.t('unknown');
        final totalItems = inventory['total_items'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.inventory,
              color: _getStatusColor(status),
            ),
            title: Text(loc.t('inventory_title').replaceFirst('%s', DateFormat('dd.MM.yyyy').format(date))),
            subtitle: Text('${loc.t('employee_label')}: $employeeName\n${loc.t('items_count')}: $totalItems\n${loc.t('status_label')}: ${_getInventoryStatusText(loc, status)}'),
            trailing: Icon(Icons.chevron_right),
            onTap: () => _showInventoryDetails(context, inventory),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft': return Colors.grey;
      case 'completed': return Colors.green;
      case 'sent': return Colors.blue;
      default: return Colors.grey;
    }
  }

  String _getInventoryStatusText(LocalizationService loc, String status) {
    switch (status) {
      case 'draft': return loc.t('status_draft');
      case 'completed': return loc.t('status_inventory_completed');
      case 'sent': return loc.t('status_inventory_sent');
      default: return status;
    }
  }

  void _showInventoryDetails(BuildContext context, Map<String, dynamic> inventory) {
    final loc = context.read<LocalizationService>();
    final date = DateTime.parse(inventory['date']);
    final startTime = inventory['start_time'];
    final endTime = inventory['end_time'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('inventory_details')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${loc.t('date_label')}: ${DateFormat('dd.MM.yyyy').format(date)}'),
              if (startTime != null) Text('${loc.t('start_label')}: $startTime'),
              if (endTime != null) Text('${loc.t('end_label')}: $endTime'),
              Text('${loc.t('items_count')}: ${inventory['total_items'] ?? 0}'),
              Text('${loc.t('status_label')}: ${_getInventoryStatusText(loc, inventory['status'] ?? 'completed')}'),
              if (inventory['notes'] != null && inventory['notes'].isNotEmpty)
                Text('${loc.t('notes_label')}: ${inventory['notes']}'),
              const SizedBox(height: 16),
              Text(loc.t('data_label'), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                inventory['inventory_data'] != null
                    ? inventory['inventory_data'].toString()
                    : loc.t('no_data'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('close')),
          ),
        ],
      ),
    );
  }
}
