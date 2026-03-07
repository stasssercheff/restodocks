import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/number_format_utils.dart';
import '../../widgets/app_bar_home_button.dart';
import '../salary_expense_screen.dart';

/// Экран «Расходы» для собственника: вкладки «ФЗП» и «Заказы продуктов».
/// Заказы продуктов — список за месяц с тоталом внизу.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('expenses') ?? 'Расходы'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: loc.t('salary_tab_fzp') ?? 'ФЗП'),
            Tab(text: loc.t('expenses_tab_product_orders') ?? 'Заказы продуктов'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const SalaryExpenseScreen(embedInScaffold: false),
          const _ProductOrdersTab(),
        ],
      ),
    );
  }
}

class _ProductOrdersTab extends StatefulWidget {
  const _ProductOrdersTab();

  @override
  State<_ProductOrdersTab> createState() => _ProductOrdersTabState();
}

class _ProductOrdersTabState extends State<_ProductOrdersTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        setState(() {
          _loading = false;
          _error = 'Заведение не выбрано';
        });
        return;
      }
      final docs = await OrderDocumentService().listForEstablishment(establishmentId);
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final monthEnd = DateTime(now.year, now.month + 1, 0);
      final forMonth = docs.where((d) {
        final createdAt = DateTime.tryParse(d['created_at']?.toString() ?? '');
        if (createdAt == null) return false;
        return !createdAt.isBefore(monthStart) && !createdAt.isAfter(monthEnd);
      }).toList();

      if (mounted) {
        setState(() {
          _orders = forMonth;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final currency = account.establishment?.defaultCurrency ?? 'VND';
    final currencySymbol = account.establishment?.currencySymbol ?? Establishment.currencySymbolFor(currency);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
            ],
          ),
        ),
      );
    }

    double totalSum = 0;
    for (final order in _orders) {
      final payload = order['payload'] as Map<String, dynamic>? ?? {};
      final grand = (payload['grandTotal'] as num?)?.toDouble();
      if (grand != null) totalSum += grand;
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('product_order_received_empty') ?? 'Отправленные заказы будут отображаться здесь',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${loc.t('salary_period') ?? 'Период'}: ${DateFormat('MMMM yyyy').format(DateTime.now())}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '${DateFormat('MMMM yyyy').format(DateTime.now())}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final order = _orders[i];
                final payload = order['payload'] as Map<String, dynamic>? ?? {};
                final header = payload['header'] as Map<String, dynamic>? ?? {};
                final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();
                final dateStr = DateFormat('dd.MM.yyyy').format(createdAt);
                final employeeName = header['employeeName'] ?? '—';
                final supplier = header['supplierName'] ?? '—';
                final grandTotal = (payload['grandTotal'] as num?)?.toDouble();
                final sumStr = grandTotal != null
                    ? NumberFormatUtils.formatSum(grandTotal, currency)
                    : '—';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('$dateStr · ${header['supplierName'] ?? '—'}'),
                    subtitle: Text('${loc.t('inbox_header_employee') ?? 'Сотрудник'}: $employeeName'),
                    trailing: Text(
                      sumStr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => context.push('/inbox/order/${order['id']}'),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2)),
              ],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.t('salary_total_all') ?? 'Итого по всем',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${NumberFormatUtils.formatSum(totalSum, currency)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
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
