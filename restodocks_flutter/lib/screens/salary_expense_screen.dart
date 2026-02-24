import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/schedule_storage_service.dart';
import '../services/services.dart';

/// ФЗП: список сотрудников с оплатой за смену/час. Часы/смены подтягиваются из графика.
/// Собственник без должности не отображается. Toggle — включать ли в итог.
class SalaryExpenseScreen extends StatefulWidget {
  const SalaryExpenseScreen({super.key});

  @override
  State<SalaryExpenseScreen> createState() => _SalaryExpenseScreenState();
}

class _SalaryExpenseScreenState extends State<SalaryExpenseScreen> {
  List<Employee>? _employees;
  ScheduleModel? _schedule;
  String? _error;
  bool _loading = true;

  /// Период: начало и конец (включительно).
  late DateTime _periodStart;
  late DateTime _periodEnd;

  /// Включить ли сотрудника в итоговую сумму (по умолчанию — да).
  final Map<String, bool> _includeInTotal = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodStart = DateTime(now.year, now.month, 1);
    _periodEnd = DateTime(now.year, now.month + 1, 0); // последний день месяца
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final estab = acc.establishment;
      if (estab == null) {
        setState(() => _error = 'Заведение не найдено');
        _loading = false;
        return;
      }
      final list = await acc.getEmployeesForEstablishment(estab.id);
      final schedule = await loadSchedule(estab.id);

      // Только сотрудники с должностью (positionRole != null). Собственник без должности не показываем.
      final withPosition = list.where((e) => e.isActive && e.positionRole != null).toList();

      setState(() {
        _employees = withPosition;
        _schedule = schedule;
        _loading = false;
        for (final e in withPosition) {
          _includeInTotal.putIfAbsent(e.id, () => true);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Смены или часы по сотруднику за период из графика.
  double _shiftsOrHoursFromSchedule(Employee e) {
    final schedule = _schedule;
    if (schedule == null) return 0;

    final isHourly = e.paymentType == 'hourly';
    double total = 0;

    for (final slot in schedule.slots) {
      if (slot.employeeId != e.id) continue;

      for (var d = _periodStart;
          !d.isAfter(_periodEnd);
          d = d.add(const Duration(days: 1))) {
        final assign = schedule.getAssignment(slot.id, d);
        if (assign != '1') continue;

        if (isHourly) {
          final range = schedule.getTimeRange(slot.id, d);
          if (range != null) {
            final parts = range.split('|');
            if (parts.length == 2) {
              final hours = _hoursBetween(parts[0], parts[1]);
              total += hours > 0 ? hours : 8;
            } else {
              total += 8;
            }
          } else {
            total += 8;
          }
        } else {
          total += 1; // одна смена
        }
      }
    }
    return total;
  }

  /// Минуты от полуночи для "HH:mm".
  int _minutesFromMidnight(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h.clamp(0, 23) * 60 + m.clamp(0, 59);
  }

  /// Часы между началом и концом смены ("09:00", "21:00").
  double _hoursBetween(String startStr, String endStr) {
    final start = _minutesFromMidnight(startStr);
    final end = _minutesFromMidnight(endStr);
    if (end <= start) return 0;
    return (end - start) / 60.0;
  }

  double _totalForEmployee(Employee e) {
    final val = _shiftsOrHoursFromSchedule(e);
    if (e.paymentType == 'hourly') {
      final rate = e.hourlyRate ?? 0;
      return rate * val;
    }
    final rate = e.ratePerShift ?? 0;
    return rate * val;
  }

  double _totalIncluded() {
    if (_employees == null) return 0;
    return _employees!
        .where((e) => _includeInTotal[e.id] ?? true)
        .fold<double>(0, (s, e) => s + _totalForEmployee(e));
  }

  void _showPeriodPicker(BuildContext context, LocalizationService loc) {
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _periodStart, end: _periodEnd),
      helpText: loc.t('salary_period'),
    ).then((range) {
      if (range != null && mounted) {
        setState(() {
          _periodStart = DateTime(range.start.year, range.start.month, range.start.day);
          _periodEnd = DateTime(range.end.year, range.end.month, range.end.day);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final accountManager = context.read<AccountManagerSupabase>();
    final currency = accountManager.currentEmployee?.currencySymbol ?? accountManager.establishment?.currencySymbol ?? '₽';
    final dateFormat = DateFormat('dd.MM.yyyy');

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
                        FilledButton(onPressed: _load, child: Text(loc.t('retry'))),
                      ],
                    ),
                  ),
                )
              : _employees == null || _employees!.isEmpty
                  ? Center(child: Text(loc.t('employees_empty_hint')))
                  : Column(
                      children: [
                        // Период вверху
                        InkWell(
                          onTap: () => _showPeriodPicker(context, loc),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month, color: theme.colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(loc.t('salary_period'), style: theme.textTheme.titleSmall),
                                      Text(
                                        '${dateFormat.format(_periodStart)} — ${dateFormat.format(_periodEnd)}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _employees!.length,
                            itemBuilder: (context, i) {
                              final e = _employees![i];
                              final isHourly = e.paymentType == 'hourly';
                              final rate = isHourly ? (e.hourlyRate ?? 0) : (e.ratePerShift ?? 0);
                              final val = _shiftsOrHoursFromSchedule(e);
                              final total = _totalForEmployee(e);
                              final label = isHourly ? loc.t('hourly_rate') : loc.t('rate_per_shift');
                              final unitLabel = isHourly ? loc.t('salary_hours') : loc.t('salary_shifts');
                              final included = _includeInTotal[e.id] ?? true;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Toggle слева
                                      Padding(
                                        padding: const EdgeInsets.only(right: 12, top: 4),
                                        child: Switch(
                                          value: included,
                                          onChanged: (v) => setState(() => _includeInTotal[e.id] = v),
                                        ),
                                      ),
                                      Expanded(
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
                                                  child: Text(
                                                    '${val.toStringAsFixed(isHourly ? 1 : 0)} $unitLabel',
                                                    style: theme.textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
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
                                  '${_totalIncluded().toStringAsFixed(0)} $currency',
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
