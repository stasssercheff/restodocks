import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('notifications')),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showDateFilter,
            tooltip: 'Фильтр по датам',
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '📦 Заказы'),
            Tab(text: '📋 Инвентаризации'),
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
      print('Error loading order history: $e');
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
              'История заказов',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Отправленные заказы будут отображаться здесь',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.dateFilter != null) ...[
              const SizedBox(height: 16),
              Text(
                'Фильтр: ${DateFormat('dd.MM.yyyy').format(widget.dateFilter!.start)} - ${DateFormat('dd.MM.yyyy').format(widget.dateFilter!.end)}',
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
        final employeeName = order['employees']?['full_name'] ?? 'Неизвестно';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.shopping_cart,
              color: _getStatusColor(status),
            ),
            title: Text('Заказ от ${DateFormat('dd.MM.yyyy HH:mm').format(createdAt)}'),
            subtitle: Text('Сотрудник: $employeeName\nСтатус: ${_getStatusText(status)}'),
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

  String _getStatusText(String status) {
    switch (status) {
      case 'sent': return 'Отправлен';
      case 'processing': return 'В обработке';
      case 'completed': return 'Завершен';
      case 'cancelled': return 'Отменен';
      default: return status;
    }
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Детали заказа'),
        content: SingleChildScrollView(
          child: Text(
            'Заказ ID: ${order['id']}\n'
            'Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(order['created_at']))}\n'
            'Статус: ${_getStatusText(order['status'] ?? 'sent')}\n\n'
            'Данные заказа:\n${order['order_data'] != null ? order['order_data'].toString() : 'Нет данных'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
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
      print('Error loading inventory history: $e');
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
              'История инвентаризаций',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Заполненные инвентаризационные бланки будут отображаться здесь',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            if (widget.dateFilter != null) ...[
              const SizedBox(height: 16),
              Text(
                'Фильтр: ${DateFormat('dd.MM.yyyy').format(widget.dateFilter!.start)} - ${DateFormat('dd.MM.yyyy').format(widget.dateFilter!.end)}',
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
        final employeeName = inventory['employees']?['full_name'] ?? 'Неизвестно';
        final totalItems = inventory['total_items'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.inventory,
              color: _getStatusColor(status),
            ),
            title: Text('Инвентаризация ${DateFormat('dd.MM.yyyy').format(date)}'),
            subtitle: Text('Сотрудник: $employeeName\nПозиций: $totalItems\nСтатус: ${_getStatusText(status)}'),
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

  String _getStatusText(String status) {
    switch (status) {
      case 'draft': return 'Черновик';
      case 'completed': return 'Завершена';
      case 'sent': return 'Отправлена';
      default: return status;
    }
  }

  void _showInventoryDetails(BuildContext context, Map<String, dynamic> inventory) {
    final date = DateTime.parse(inventory['date']);
    final startTime = inventory['start_time'];
    final endTime = inventory['end_time'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Детали инвентаризации'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Дата: ${DateFormat('dd.MM.yyyy').format(date)}'),
              if (startTime != null) Text('Начало: $startTime'),
              if (endTime != null) Text('Окончание: $endTime'),
              Text('Позиций: ${inventory['total_items'] ?? 0}'),
              Text('Статус: ${_getStatusText(inventory['status'] ?? 'completed')}'),
              if (inventory['notes'] != null && inventory['notes'].isNotEmpty)
                Text('Примечания: ${inventory['notes']}'),
              const SizedBox(height: 16),
              const Text('Данные:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                inventory['inventory_data'] != null
                    ? inventory['inventory_data'].toString()
                    : 'Нет данных',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}
