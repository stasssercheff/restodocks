import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Список сотрудников подразделения текущего пользователя (менеджмент). Карточка: данные, тип оплаты, ставка/час.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Employee> _list = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final current = acc.currentEmployee;
    final est = acc.establishment;
    if (current == null || est == null) {
      setState(() { _loading = false; _error = 'Нет заведения'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final all = await acc.getEmployeesForEstablishment(est.id);
      final dept = current.department;
      final filtered = dept.isEmpty ? all : all.where((e) => e.department == dept).toList();
      if (mounted) setState(() { _list = filtered; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _roleDisplay(Employee e, LocalizationService loc) {
    if (e.roles.isEmpty) return '—';
    final roleKeys = <String, String>{
      'owner': 'Владелец', 'executive_chef': 'Шеф-повар', 'sous_chef': 'Су-шеф', 'cook': 'Повар',
      'bartender': 'Бармен', 'waiter': 'Официант', 'bar_manager': 'Менеджер бара',
      'general_manager': 'Управляющий', 'brigadier': 'Бригадир',
    };
    return e.roles.map((r) => roleKeys[r] ?? r).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('employees')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _buildBody(loc, theme),
    );
  }

  Widget _buildBody(LocalizationService loc, ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('refresh'))),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('employees_empty_hint'),
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _list.length,
      itemBuilder: (_, i) => _EmployeeCard(employee: _list[i], loc: loc, onUpdated: _load),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.employee, required this.loc, required this.onUpdated});

  final Employee employee;
  final LocalizationService loc;
  final VoidCallback onUpdated;

  String _roleDisplay(Employee e) {
    const roleKeys = {
      'owner': 'Владелец', 'executive_chef': 'Шеф-повар', 'sous_chef': 'Су-шеф', 'cook': 'Повар',
      'bartender': 'Бармен', 'waiter': 'Официант', 'bar_manager': 'Менеджер бара',
      'general_manager': 'Управляющий', 'brigadier': 'Бригадир',
    };
    return e.roles.isEmpty ? '—' : e.roles.map((r) => roleKeys[r] ?? r).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPerShift = employee.paymentType == 'per_shift';
    final rate = isPerShift ? employee.ratePerShift : employee.hourlyRate;
    final rateLabel = isPerShift ? loc.t('payment_per_shift') : loc.t('payment_hourly');
    final rateStr = rate != null && rate > 0
        ? '${rate.toStringAsFixed(0)} ${loc.t('currency_rub_short')}'
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    (employee.fullName.isNotEmpty ? employee.fullName[0] : '?').toUpperCase(),
                    style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.fullName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (employee.email.isNotEmpty)
                        Text(employee.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text(_roleDisplay(employee), style: theme.textTheme.bodySmall),
                      if (employee.section != null && employee.section!.isNotEmpty)
                        Text(employee.section!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.payments_outlined, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('$rateLabel: $rateStr', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
