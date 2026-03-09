import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/schedule_storage_service.dart';
import '../services/salary_export_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/schedule_export_widget.dart';

enum _AdjustmentType { bonus, fine, advance }

class _EmployeeAdjustment {
  final _AdjustmentType type;
  final double amount;

  const _EmployeeAdjustment({required this.type, required this.amount});

  /// Премия добавляется, штраф и аванс — вычитаются.
  double get signedAmount => type == _AdjustmentType.bonus ? amount : -amount;

  String label(String currency) {
    final sign = type == _AdjustmentType.bonus ? '+' : '-';
    return '$sign${amount.toStringAsFixed(0)} $currency';
  }

  String get typeName {
    switch (type) {
      case _AdjustmentType.bonus:
        return 'Премия';
      case _AdjustmentType.fine:
        return 'Штраф';
      case _AdjustmentType.advance:
        return 'Аванс';
    }
  }
}

/// ФЗП: список сотрудников с оплатой за смену/час. Часы/смены подтягиваются из графика.
/// Собственник без должности не отображается. Toggle — включать ли в итог.
/// [embedInScaffold] = false: только контент (для вкладки в экране «Расходы»).
/// [departmentFilter] = kitchen|bar|hall — показывать только сотрудников подразделения (для руководителей).
class SalaryExpenseScreen extends StatefulWidget {
  const SalaryExpenseScreen({super.key, this.embedInScaffold = true, this.departmentFilter});

  final bool embedInScaffold;
  /// Фильтр по подразделению для руководителя: kitchen (кухня+руководство), bar (бар), hall (зал).
  final String? departmentFilter;

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

  /// Удержания и поощрения по каждому сотруднику.
  final Map<String, List<_EmployeeAdjustment>> _adjustments = {};

  /// Раскрыта ли панель удержаний/поощрений по каждому сотруднику.
  final Map<String, bool> _adjustmentsExpanded = {};

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
      var withPosition = list.where((e) => e.isActive && e.positionRole != null).toList();

      // Фильтр по подразделению для руководителя: только сотрудники подразделения + руководство
      final deptFilter = widget.departmentFilter;
      if (deptFilter != null && deptFilter.isNotEmpty) {
        withPosition = withPosition.where((e) {
          if (deptFilter == 'kitchen') {
            return e.department == 'kitchen' ||
                (e.department == 'management' && (e.hasRole('executive_chef') || e.hasRole('sous_chef')));
          }
          if (deptFilter == 'bar') return e.department == 'bar';
          if (deptFilter == 'hall') return e.department == 'dining_room' || e.department == 'hall';
          return true;
        }).toList();
      }

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

  double _baseForEmployee(Employee e) {
    final val = _shiftsOrHoursFromSchedule(e);
    if (e.paymentType == 'hourly') {
      final rate = e.hourlyRate ?? 0;
      return rate * val;
    }
    final rate = e.ratePerShift ?? 0;
    return rate * val;
  }

  double _adjustmentsTotal(String employeeId) {
    return (_adjustments[employeeId] ?? [])
        .fold<double>(0, (s, a) => s + a.signedAmount);
  }

  double _totalForEmployee(Employee e) {
    return _baseForEmployee(e) + _adjustmentsTotal(e.id);
  }

  double _totalIncluded() {
    if (_employees == null) return 0;
    return _employees!
        .where((e) => _includeInTotal[e.id] ?? true)
        .fold<double>(0, (s, e) => s + _totalForEmployee(e));
  }

  void _showAddAdjustmentDialog(BuildContext context, Employee e, String currency) {
    final loc = context.read<LocalizationService>();
    _AdjustmentType selectedType = _AdjustmentType.bonus;
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.t('salary_add_adjustment_dialog_title') ?? 'Добавить удержание / поощрение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<_AdjustmentType>(
                value: selectedType,
                decoration: InputDecoration(
                  labelText: loc.t('salary_adjustment_reason') ?? 'Причина',
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                items: const [
                  DropdownMenuItem(value: _AdjustmentType.bonus, child: Text('Премия')),
                  DropdownMenuItem(value: _AdjustmentType.fine, child: Text('Штраф')),
                  DropdownMenuItem(value: _AdjustmentType.advance, child: Text('Аванс')),
                ],
                onChanged: (v) => setDialogState(() => selectedType = v ?? selectedType),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${loc.t('salary_adjustment_amount') ?? 'Сумма'} ($currency)',
                  border: const OutlineInputBorder(),
                  filled: true,
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) return;
                setState(() {
                  _adjustments.putIfAbsent(e.id, () => []).add(
                    _EmployeeAdjustment(type: selectedType, amount: amount),
                  );
                  _adjustmentsExpanded[e.id] = true;
                });
                Navigator.pop(ctx);
              },
              child: Text(loc.t('salary_add_adjustment') ?? 'Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPayroll(BuildContext context) async {
    if (_employees == null || _employees!.isEmpty || _schedule == null) return;
    final loc = context.read<LocalizationService>();
    final accountManager = context.read<AccountManagerSupabase>();
    final currency = accountManager.establishment?.currencySymbol ??
        accountManager.currentEmployee?.currencySymbol ??
        Establishment.currencySymbolFor(accountManager.establishment?.defaultCurrency ?? 'VND');

    final selectedLang = await showDialog<String>(
      context: context,
      builder: (ctx) => _ExportLanguageDialog(loc: loc),
    );
    if (selectedLang == null || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Выгрузка...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final t = (String key) => loc.tForLanguage(selectedLang, key);
      final dateFormat = DateFormat('dd.MM.yyyy');

      final fileName = await SalaryExportService.buildAndSaveExcel(
        employees: _employees!,
        schedule: _schedule!,
        periodStart: _periodStart,
        periodEnd: _periodEnd,
        includeInTotal: _includeInTotal,
        shiftsOrHoursFn: _shiftsOrHoursFromSchedule,
        totalForEmployeeFn: _totalForEmployee,
        currency: currency,
        t: t,
        lang: selectedLang,
      );

      final pngFiles = <String>[];
      for (final dept in ['kitchen', 'bar', 'hall']) {
        final boundaryKey = GlobalKey();
        final pngBytes = await _captureSchedulePng(
          context: context,
          schedule: _schedule!,
          employees: _employees!,
          department: dept,
          boundaryKey: boundaryKey,
          periodStart: _periodStart,
          periodEnd: _periodEnd,
          exportLang: selectedLang,
        );
        if (pngBytes != null && pngBytes.isNotEmpty) {
          final deptName = dept == 'kitchen'
              ? 'kitchen'
              : dept == 'bar'
                  ? 'bar'
                  : 'hall';
          final pngName =
              'schedule_${deptName}_${dateFormat.format(_periodStart)}_${dateFormat.format(_periodEnd)}.png';
          await saveFileBytes(pngName, pngBytes);
          pngFiles.add(pngName);
        }
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            loc.t('salary_export_saved') ?? 'Выгружено: $fileName${pngFiles.isNotEmpty ? ' + ${pngFiles.length} график(ов)' : ''}',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Salary export error: $e\n$st');
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(loc.t('salary_export_error') ?? 'Ошибка выгрузки: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<Uint8List?> _captureSchedulePng({
    required BuildContext context,
    required ScheduleModel schedule,
    required List<Employee> employees,
    required String department,
    required GlobalKey boundaryKey,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String exportLang,
  }) async {
    final loc = context.read<LocalizationService>();
    return Navigator.of(context).push<Uint8List?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _ScheduleCapturePage(
          schedule: schedule,
          employees: employees,
          department: department,
          boundaryKey: boundaryKey,
          loc: loc,
          periodStart: periodStart,
          periodEnd: periodEnd,
          exportLang: exportLang,
        ),
      ),
    );
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
    final currency = accountManager.establishment?.currencySymbol ?? accountManager.currentEmployee?.currencySymbol ?? Establishment.currencySymbolFor(accountManager.establishment?.defaultCurrency ?? 'VND');
    final dateFormat = DateFormat('dd.MM.yyyy');

    final body = _loading
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
                              final base = _baseForEmployee(e);
                              final adjTotal = _adjustmentsTotal(e.id);
                              final total = base + adjTotal;
                              final label = isHourly ? loc.t('hourly_rate') : loc.t('rate_per_shift');
                              final unitLabel = isHourly ? loc.t('salary_hours') : loc.t('salary_shifts');
                              final included = _includeInTotal[e.id] ?? true;
                              final adjustments = _adjustments[e.id] ?? [];
                              final expanded = _adjustmentsExpanded[e.id] ?? false;

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
                                            Builder(
                                              builder: (_) {
                                                final roleCode = e.positionRole ?? e.roles.firstOrNull ?? '';
                                                if (roleCode.isEmpty) return const SizedBox.shrink();
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    loc.roleDisplayName(roleCode),
                                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                                  ),
                                                );
                                              },
                                            ),
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
                                            // Базовая сумма
                                            Text(
                                              '${loc.t('ttk_total')}: ${base.toStringAsFixed(0)} $currency',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            // Панель удержаний и поощрений
                                            InkWell(
                                              borderRadius: BorderRadius.circular(8),
                                              onTap: () => setState(() => _adjustmentsExpanded[e.id] = !expanded),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.tune,
                                                      size: 16,
                                                      color: theme.colorScheme.primary,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      loc.t('salary_deductions_bonuses') ?? 'Удержания и поощрения',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: theme.colorScheme.primary,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (adjustments.isNotEmpty) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: theme.colorScheme.primaryContainer,
                                                          borderRadius: BorderRadius.circular(10),
                                                        ),
                                                        child: Text(
                                                          '${adjustments.length}',
                                                          style: theme.textTheme.labelSmall?.copyWith(
                                                            color: theme.colorScheme.onPrimaryContainer,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                    const Spacer(),
                                                    Icon(
                                                      expanded ? Icons.expand_less : Icons.expand_more,
                                                      size: 18,
                                                      color: theme.colorScheme.primary,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (expanded) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: theme.colorScheme.outlineVariant,
                                                  ),
                                                ),
                                                child: Column(
                                                  children: [
                                                    if (adjustments.isEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.all(12),
                                                        child: Text(
                                                          loc.t('salary_no_adjustments') ?? 'Нет записей',
                                                          style: theme.textTheme.bodySmall?.copyWith(
                                                            color: theme.colorScheme.onSurfaceVariant,
                                                          ),
                                                        ),
                                                      ),
                                                    ...adjustments.asMap().entries.map((entry) {
                                                      final idx = entry.key;
                                                      final adj = entry.value;
                                                      final isPositive = adj.type == _AdjustmentType.bonus;
                                                      return ListTile(
                                                        dense: true,
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                                        leading: CircleAvatar(
                                                          radius: 14,
                                                          backgroundColor: isPositive
                                                              ? Colors.green.withOpacity(0.15)
                                                              : Colors.red.withOpacity(0.15),
                                                          child: Icon(
                                                            isPositive ? Icons.add : Icons.remove,
                                                            size: 14,
                                                            color: isPositive ? Colors.green : Colors.red,
                                                          ),
                                                        ),
                                                        title: Text(adj.typeName, style: theme.textTheme.bodySmall),
                                                        trailing: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              adj.label(currency),
                                                              style: theme.textTheme.bodySmall?.copyWith(
                                                                color: isPositive ? Colors.green : Colors.red,
                                                                fontWeight: FontWeight.w600,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            InkWell(
                                                              onTap: () => setState(() {
                                                                _adjustments[e.id]!.removeAt(idx);
                                                                if (_adjustments[e.id]!.isEmpty) {
                                                                  _adjustments.remove(e.id);
                                                                }
                                                              }),
                                                              child: Icon(
                                                                Icons.close,
                                                                size: 16,
                                                                color: theme.colorScheme.onSurfaceVariant,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                    Padding(
                                                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                                      child: OutlinedButton.icon(
                                                        onPressed: () => _showAddAdjustmentDialog(context, e, currency),
                                                        icon: const Icon(Icons.add, size: 16),
                                                        label: Text(loc.t('salary_add_adjustment') ?? 'Добавить'),
                                                        style: OutlinedButton.styleFrom(
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                          minimumSize: const Size(0, 32),
                                                          textStyle: theme.textTheme.bodySmall,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (adjustments.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Корректировка: ${adjTotal >= 0 ? '+' : ''}${adjTotal.toStringAsFixed(0)} $currency',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: adjTotal >= 0 ? Colors.green : Colors.red,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                            const SizedBox(height: 8),
                                            // Итоговая сумма
                                            Text(
                                              '${loc.t('salary_payable') ?? 'К выплате'}: ${total.toStringAsFixed(0)} $currency',
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
                    );
    if (widget.embedInScaffold) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('salary_expenses')),
          actions: [
            if (!_loading && _error == null && _employees != null && _employees!.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _exportPayroll(context),
                tooltip: loc.t('salary_export_btn') ?? 'Выгрузить',
              ),
          ],
        ),
        body: body,
      );
    }
    return body;
  }
}

class _ExportLanguageDialog extends StatelessWidget {
  const _ExportLanguageDialog({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    String selectedLang = loc.currentLanguageCode;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(loc.t('salary_export_dialog_title') ?? 'Выгрузить ФЗП'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t('salary_export_lang') ?? 'Язык сохранения:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['ru', 'en', 'es'].map((code) {
                return ChoiceChip(
                  label: Text(loc.getLanguageName(code)),
                  selected: selectedLang == code,
                  onSelected: (_) => setState(() => selectedLang = code),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(selectedLang),
            child: Text(loc.t('salary_export_btn') ?? 'Выгрузить'),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCapturePage extends StatefulWidget {
  const _ScheduleCapturePage({
    required this.schedule,
    required this.employees,
    required this.department,
    required this.boundaryKey,
    required this.loc,
    required this.periodStart,
    required this.periodEnd,
    required this.exportLang,
  });

  final ScheduleModel schedule;
  final List<Employee> employees;
  final String department;
  final GlobalKey boundaryKey;
  final LocalizationService loc;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String exportLang;

  @override
  State<_ScheduleCapturePage> createState() => _ScheduleCapturePageState();
}

class _ScheduleCapturePageState extends State<_ScheduleCapturePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _captureAndPop());
  }

  Future<void> _captureAndPop() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final bytes = await captureWidgetToPng(widget.boundaryKey);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SizedBox(
        width: 1200,
        height: 800,
        child: ScheduleExportWidget(
          schedule: widget.schedule,
          employees: widget.employees,
          department: widget.department,
          periodStart: widget.periodStart,
          periodEnd: widget.periodEnd,
          loc: widget.loc,
          boundaryKey: widget.boundaryKey,
          exportLang: widget.exportLang,
        ),
      ),
    );
  }
}
