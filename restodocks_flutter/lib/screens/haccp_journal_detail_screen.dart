import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/employee.dart';
import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../services/haccp_pdf_export_service.dart';
import '../services/inventory_download.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран журнала ХАССП: список записей, добавить, экспорт PDF.
class HaccpJournalDetailScreen extends StatefulWidget {
  const HaccpJournalDetailScreen({super.key, required this.logTypeCode});

  final String logTypeCode;

  @override
  State<HaccpJournalDetailScreen> createState() => _HaccpJournalDetailScreenState();
}

class _HaccpJournalDetailScreenState extends State<HaccpJournalDetailScreen> {
  List<HaccpLog> _logs = [];
  List<Employee> _employees = [];
  bool _loading = true;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  HaccpLogType get _logType => HaccpLogType.fromCode(widget.logTypeCode) ?? HaccpLogType.healthHygiene;

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;

    setState(() => _loading = true);
    try {
      final svc = context.read<HaccpLogServiceSupabase>();
      final emps = await acc.getEmployeesForEstablishment(est.id);
      final logs = await svc.getLogs(
        establishmentId: est.id,
        logType: _logType,
        from: _dateFrom,
        to: _dateTo,
      );
      if (mounted) setState(() {
        _logs = logs;
        _employees = emps;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1);
    _dateTo = now;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Экспорт PDF: титульный лист + страницы за выбранный период + заключительный лист.
  Future<void> _exportPdf({
    required DateTime dateFrom,
    required DateTime dateTo,
  }) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;

    final loc = context.read<LocalizationService>();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_pdf_preparing') ?? 'Подготовка PDF...')),
      );
    }

    final emps = await acc.getEmployeesForEstablishment(est.id);
    final idToName = {
      for (final e in emps) e.id: '${e.fullName}${e.surname != null ? ' ${e.surname}' : ''}, ${e.roleDisplayName}',
    };

    final svc = context.read<HaccpLogServiceSupabase>();
    final logsForPeriod = await svc.getLogs(
      establishmentId: est.id,
      logType: _logType,
      from: dateFrom,
      to: dateTo,
    );

    final bytes = await HaccpPdfExportService.buildJournalPdf(
      establishmentName: est.name,
      journalTitle: _logType.displayNameRu,
      sanpinRef: _logType.sanpinRef,
      logType: _logType,
      logs: logsForPeriod,
      employeeIdToName: idToName,
      dateFrom: dateFrom,
      dateTo: dateTo,
      includeCover: true,
      includeStitchingSheet: true,
    );

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final safeCode = _logType.code.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    await saveFileBytes('haccp_${safeCode}_$dateStr.pdf', bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_pdf_saved') ?? 'PDF сохранён')),
      );
    }
  }

  /// Три варианта периода экспорта: 1) весь месяц, 2) с 1 числа по сегодня, 3) с даты по дату.
  Future<void> _showExportOptions() async {
    final loc = context.read<LocalizationService>();
    final now = DateTime.now();

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('haccp_save_file') ?? 'Сохранить журнал в PDF',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('haccp_pdf_period_hint') ?? 'Титульный лист, страницы за период, заключительный лист.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(loc.t('haccp_pdf_period_full_month') ?? 'Весь месяц'),
                subtitle: Text(loc.t('haccp_pdf_period_full_month_hint') ?? 'Выбор месяца — с 1 по последнее число'),
                onTap: () => Navigator.pop(ctx, 'full_month'),
              ),
              ListTile(
                leading: const Icon(Icons.today),
                title: Text(loc.t('haccp_pdf_period_month_to_today') ?? 'С 1 числа по сегодня'),
                subtitle: Text('${DateFormat('dd.MM').format(DateTime(now.year, now.month, 1))} — ${DateFormat('dd.MM.yyyy').format(now)}'),
                onTap: () => Navigator.pop(ctx, 'month_to_today'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(loc.t('haccp_pdf_period_custom') ?? 'С выбранной даты по выбранную дату'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    DateTime dateFrom;
    DateTime dateTo;

    if (choice == 'month_to_today') {
      dateFrom = DateTime(now.year, now.month, 1);
      dateTo = now;
      await _exportPdf(dateFrom: dateFrom, dateTo: dateTo);
      return;
    }

    if (choice == 'full_month') {
      final picked = await _pickMonth(context);
      if (picked == null || !mounted) return;
      dateFrom = DateTime(picked.year, picked.month, 1);
      dateTo = DateTime(picked.year, picked.month + 1, 0); // last day of month
      await _exportPdf(dateFrom: dateFrom, dateTo: dateTo);
      return;
    }

    if (choice == 'custom') {
      final range = await _pickDateRange(context);
      if (range == null || !mounted) return;
      dateFrom = range.$1;
      dateTo = range.$2;
      await _exportPdf(dateFrom: dateFrom, dateTo: dateTo);
    }
  }

  Future<DateTime?> _pickMonth(BuildContext context) async {
    final now = DateTime.now();
    var year = now.year;
    var month = now.month;
    return showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.read<LocalizationService>().t('haccp_pdf_period_full_month') ?? 'Весь месяц',
                    style: Theme.of(ctx2).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          if (month == 1) {
                            year--;
                            month = 12;
                          } else {
                            month--;
                          }
                        }),
                      ),
                      SizedBox(
                        width: 180,
                        child: Text(
                          '${_monthName(month)} $year',
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx2).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() {
                          if (month == 12) {
                            year++;
                            month = 1;
                          } else {
                            month++;
                          }
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, DateTime(year, month, 1)),
                    child: Text(context.read<LocalizationService>().t('ok') ?? 'OK'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
  ];
  String _monthName(int month) => _monthNames[month - 1];

  Future<(DateTime, DateTime)?> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    var from = DateTime(now.year, now.month, 1);
    var to = now;
    final result = await showModalBottomSheet<(DateTime, DateTime)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.read<LocalizationService>().t('haccp_pdf_period_custom') ?? 'Период',
                    style: Theme.of(ctx2).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(DateFormat('dd.MM.yyyy').format(from)),
                    subtitle: const Text('Дата начала'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: from,
                        firstDate: DateTime(2020),
                        lastDate: now,
                      );
                      if (d != null) setState(() { from = d; if (from.isAfter(to)) to = from; });
                    },
                  ),
                  ListTile(
                    title: Text(DateFormat('dd.MM.yyyy').format(to)),
                    subtitle: const Text('Дата окончания'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: to,
                        firstDate: from,
                        lastDate: now,
                      );
                      if (d != null) setState(() => to = d);
                    },
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, (from, to)),
                    child: Text(context.read<LocalizationService>().t('ok') ?? 'OK'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return result;
  }

  String _formatDateRange(DateTime from, DateTime to, LocalizationService loc) {
    final today = DateTime.now();
    final fromDay = DateTime(from.year, from.month, from.day);
    final toDay = DateTime(to.year, to.month, to.day);
    final todayStart = DateTime(today.year, today.month, today.day);
    if (fromDay == toDay && fromDay == todayStart) {
      return loc.t('haccp_period_today') ?? 'Сегодня';
    }
    return '${DateFormat('dd.MM.yyyy').format(from)} — ${DateFormat('dd.MM.yyyy').format(to)}';
  }

  Future<void> _showDateRangePicker() async {
    final loc = context.read<LocalizationService>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('haccp_period') ?? 'Период',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.today),
                title: Text(loc.t('haccp_period_today') ?? 'Сегодня'),
                onTap: () => Navigator.pop(ctx, 'today'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(loc.t('haccp_period_month_to_today') ?? 'С 1 числа по сегодня'),
                subtitle: Text('${DateFormat('dd.MM').format(DateTime(now.year, now.month, 1))} — ${DateFormat('dd.MM.yyyy').format(now)}'),
                onTap: () => Navigator.pop(ctx, 'month'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_month),
                title: Text(loc.t('haccp_pdf_period_full_month') ?? 'Весь месяц'),
                onTap: () => Navigator.pop(ctx, 'full_month'),
              ),
              ListTile(
                leading: const Icon(Icons.date_range),
                title: Text(loc.t('haccp_pdf_period_custom') ?? 'С даты по дату'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'full_month') {
      final picked = await _pickMonth(context);
      if (picked == null || !mounted) return;
      setState(() {
        _dateFrom = DateTime(picked.year, picked.month, 1);
        _dateTo = DateTime(picked.year, picked.month + 1, 0);
      });
      _load();
      return;
    }
    if (choice == 'custom') {
      final range = await _pickDateRange(context);
      if (range == null || !mounted) return;
      setState(() {
        _dateFrom = range.$1;
        _dateTo = range.$2;
      });
      _load();
      return;
    }

    final from = choice == 'today' ? today : DateTime(now.year, now.month, 1);
    final to = now;
    setState(() {
      _dateFrom = from;
      _dateTo = to;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final est = acc.establishment;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(_logType.displayNameRu),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _showDateRangePicker,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _showExportOptions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_dateFrom != null && _dateTo != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Text(
                          _formatDateRange(_dateFrom!, _dateTo!, loc),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _showDateRangePicker,
                          child: Text(loc.t('haccp_change_period') ?? 'Изменить период'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.assignment_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                              const SizedBox(height: 16),
                              Text(
                                loc.t('haccp_no_entries') ?? 'Записей пока нет',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                loc.t('haccp_empty_journal_subtitle') ?? 'Добавьте первую запись в журнал',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () => _openAddForm(),
                                icon: const Icon(Icons.add),
                                label: Text(loc.t('haccp_add_entry') ?? 'Добавить запись'),
                              ),
                            ],
                          ),
                        )
                      : _JournalPagesView(
                          logs: _logs,
                          employees: _employees,
                          showEmployeeInfo: acc.currentEmployee?.canViewDepartment('management') ?? false,
                          onLogTap: _openLogDetail,
                        ),
                ),
              ],
            ),
      floatingActionButton: est != null
          ? FloatingActionButton.extended(
              onPressed: () => _openAddForm(),
              icon: const Icon(Icons.add),
              label: Text(loc.t('haccp_add_entry') ?? 'Добавить'),
            )
          : null,
    );
  }

  Future<void> _openAddForm() async {
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (est == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_establishment_not_selected') ?? 'Заведение не выбрано')),
      );
      return;
    }
    if (emp == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_employee_required') ?? 'Выберите сотрудника или войдите под учётной записью с доступом к заведению')),
      );
      return;
    }

    final result = await context.push<Map<String, dynamic>>(
      '/haccp-journals/${widget.logTypeCode}/add',
    );
    if (result != null && mounted) await _load();
  }

  void _openLogDetail(HaccpLog log) {
    final idToEmp = {for (final e in _employees) e.id: e};
    final emp = idToEmp[log.createdByEmployeeId];
    context.push(
      '/haccp-journals/${widget.logTypeCode}/view',
      extra: {'log': log, 'employee': emp},
    );
  }
}

/// Журнальные страницы: группировка по 1 дню.
class _JournalPagesView extends StatelessWidget {
  const _JournalPagesView({
    required this.logs,
    required this.employees,
    required this.showEmployeeInfo,
    required this.onLogTap,
  });

  final List<HaccpLog> logs;
  final List<Employee> employees;
  final bool showEmployeeInfo;
  final void Function(HaccpLog log) onLogTap;

  @override
  Widget build(BuildContext context) {
    final idToEmp = {for (final e in employees) e.id: e};
    final byDate = <DateTime, List<HaccpLog>>{};
    for (final log in logs) {
      final d = DateTime(log.createdAt.year, log.createdAt.month, log.createdAt.day);
      byDate.putIfAbsent(d, () => []).add(log);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: dates.length,
      itemBuilder: (_, i) {
        final date = dates[i];
        final dayLogs = byDate[date]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: i > 0 ? 12 : 0, bottom: 4),
              child: Text(
                DateFormat('dd.MM.yyyy').format(date),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...dayLogs.map((log) => _LogTile(
                  log: log,
                  employee: showEmployeeInfo ? idToEmp[log.createdByEmployeeId] : null,
                  onTap: () => onLogTap(log),
                )),
          ],
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, this.employee, required this.onTap});

  final HaccpLog log;
  final Employee? employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm').format(log.createdAt);
    final summary = log.summaryLine();
    final empName = employee != null
        ? '${employee!.fullName}${employee!.surname != null ? ' ${employee!.surname}' : ''}'
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  timeStr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      summary.isNotEmpty ? summary : '—',
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (empName != null && empName.isNotEmpty)
                      Text(
                        empName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
