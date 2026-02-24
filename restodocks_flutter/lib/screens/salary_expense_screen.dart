import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';

/// ФЗП: список сотрудников с оплатой за смену/час, количеством смен/часов, итого и общая сумма.
class SalaryExpenseScreen extends StatefulWidget {
  const SalaryExpenseScreen({super.key});

  @override
  State<SalaryExpenseScreen> createState() => _SalaryExpenseScreenState();
}

class _SalaryExpenseScreenState extends State<SalaryExpenseScreen> {
  final Map<String, num> _shiftsOrHours = {}; // employeeId -> кол-во смен или часов
  List<Employee>? _employees;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final estab = acc.establishment;
      if (estab == null) {
        setState(() => _error = 'Заведение не найдено');
        return;
      }
      final list = await acc.getEmployeesForEstablishment(estab.id);
      setState(() {
        _employees = list.where((e) => e.isActive).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  double _totalForEmployee(Employee e) {
    final val = _shiftsOrHours[e.id] ?? 0;
    if (e.paymentType == 'hourly') {
      final rate = e.hourlyRate ?? 0;
      return rate * (val as num).toDouble();
    }
    final rate = e.ratePerShift ?? 0;
    return rate * (val as num).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final currency = context.read<AccountManagerSupabase>().establishment?.currencySymbol ?? '₽';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('salary_expenses')),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadEmployees, child: Text(loc.t('retry'))),
                      ],
                    ),
                  ),
                )
              : _employees == null || _employees!.isEmpty
                  ? Center(child: Text(loc.t('employees_empty_hint') ?? 'Нет сотрудников'))
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _employees!.length,
                            itemBuilder: (context, i) {
                              final e = _employees![i];
                              final isHourly = e.paymentType == 'hourly';
                              final rate = isHourly ? (e.hourlyRate ?? 0) : (e.ratePerShift ?? 0);
                              final val = (_shiftsOrHours[e.id] ?? 0).toDouble();
                              final total = _totalForEmployee(e);
                              final label = isHourly ? loc.t('hourly_rate') : loc.t('rate_per_shift');
                              final unitLabel = isHourly ? loc.t('salary_hours') : loc.t('salary_shifts');

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.fullName, style: theme.textTheme.titleMedium),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text('$label: $rate $currency', style: theme.textTheme.bodyMedium),
                                          ),
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: (val == 0 ? '' : val.toString()),
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: InputDecoration(
                                                labelText: unitLabel,
                                                border: const OutlineInputBorder(),
                                                isDense: true,
                                              ),
                                              onChanged: (s) {
                                                final n = num.tryParse(s.replaceAll(',', '.')) ?? 0;
                                                setState(() => _shiftsOrHours[e.id] = n);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${loc.t('ttk_total')}: ${total.toStringAsFixed(0)} $currency',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            boxShadow: [
                              BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2)),
                            ],
                          ),
                          child: SafeArea(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  loc.t('salary_total_all'),
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${_employees!.fold<double>(0, (s, e) => s + _totalForEmployee(e)).toStringAsFixed(0)} $currency',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
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
