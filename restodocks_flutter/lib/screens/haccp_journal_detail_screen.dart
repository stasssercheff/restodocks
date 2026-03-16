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

  HaccpLogType? get _logType {
    final t = HaccpLogType.fromCode(widget.logTypeCode);
    return t != null && HaccpLogType.supportedInApp.contains(t) ? t : null;
  }

  Future<void> _load() async {
    if (_logType == null) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;

    setState(() => _loading = true);
    try {
      final svc = context.read<HaccpLogServiceSupabase>();
      final emps = await acc.getEmployeesForEstablishment(est.id);
      final logs = await svc.getLogs(
        establishmentId: est.id,
        logType: _logType!,
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
    final logType = _logType;
    if (logType == null) return;
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
      logType: logType,
      from: dateFrom,
      to: dateTo,
    );

    final bytes = await HaccpPdfExportService.buildJournalPdf(
      establishmentName: est.name,
      journalTitle: logType.displayNameRu,
      sanpinRef: logType.sanpinRef,
      logType: logType,
      logs: logsForPeriod,
      employeeIdToName: idToName,
      dateFrom: dateFrom,
      dateTo: dateTo,
      includeCover: true,
      includeStitchingSheet: true,
    );

    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final safeCode = logType.code.replaceAll(RegExp(r'[^a-z0-9]'), '_');
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
    final logType = _logType;

    if (logType == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: const Text('Журнал'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  'Этот журнал больше не поддерживается.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Используются только журналы по СанПиН 2.3/2.4.3590-20 (Приложения 1–5).',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('К списку журналов'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(logType.displayNameRu),
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
                      : _JournalTableView(
                          logType: logType,
                          establishmentName: est?.name ?? '—',
                          logs: _logs,
                          employees: _employees,
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

/// Список записей журнала в виде таблицы по макету СанПиН (Приложения 1–5).
class _JournalTableView extends StatelessWidget {
  const _JournalTableView({
    required this.logType,
    required this.establishmentName,
    required this.logs,
    required this.employees,
    required this.onLogTap,
  });

  final HaccpLogType logType;
  final String establishmentName;
  final List<HaccpLog> logs;
  final List<Employee> employees;
  final void Function(HaccpLog log) onLogTap;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');

  Widget _header(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          border: Border(right: BorderSide(color: Colors.grey.shade400), bottom: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      );

  Widget _cell(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey.shade400), bottom: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );

  Widget _wrapTap(Widget child, HaccpLog log) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onLogTap(log),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final idToEmp = {for (final e in employees) e.id: e};
    final idToName = {
      for (final e in employees) e.id: '${e.fullName}${e.surname != null ? ' ${e.surname}' : ''}, ${e.roleDisplayName}',
    };
    if (!HaccpLogType.supportedInApp.contains(logType)) {
      return const Center(child: Text('Неизвестный тип журнала'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            'Рекомендуемый образец',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
              child: SizedBox(
                width: 1200,
                child: _buildTable(context, idToEmp, idToName),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context, Map<String, Employee> idToEmp, Map<String, String> idToName) {
    switch (logType) {
      case HaccpLogType.healthHygiene:
        return _buildHealthHygieneTable(idToEmp);
      case HaccpLogType.fridgeTemperature:
        return _buildFridgeTable(idToEmp);
      case HaccpLogType.warehouseTempHumidity:
        return _buildWarehouseTable(idToEmp);
      case HaccpLogType.finishedProductBrakerage:
        return _buildBrakerageFinishedTable(idToName);
      case HaccpLogType.incomingRawBrakerage:
        return _buildBrakerageIncomingTable(idToEmp, idToName);
      case HaccpLogType.fryingOil:
        return _buildFryingOilTable(idToName);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFryingOilTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('Дата (час) начала'), _header('Вид жира'), _header('Оценка на начало'),
          _header('Оборудование'), _header('Вид продукции'), _header('Время окончания жарки'),
          _header('Оценка по окончании'), _header('Переходящий остаток, кг'), _header('Утилизировано, кг'), _header('Контролёр'),
        ],
      ),
      ...logs.map((log) => TableRow(
            children: [
              _wrapTap(_cell(_dateTimeFmt.format(log.createdAt)), log),
              _wrapTap(_cell(log.oilName ?? '—'), log),
              _wrapTap(_cell(log.organolepticStart ?? '—'), log),
              _wrapTap(_cell(log.fryingEquipmentType ?? '—'), log),
              _wrapTap(_cell(log.fryingProductType ?? '—'), log),
              _wrapTap(_cell(log.fryingEndTime ?? '—'), log),
              _wrapTap(_cell(log.organolepticEnd ?? '—'), log),
              _wrapTap(_cell(log.carryOverKg != null ? log.carryOverKg!.toStringAsFixed(2) : '—'), log),
              _wrapTap(_cell(log.utilizedKg != null ? log.utilizedKg!.toStringAsFixed(2) : '—'), log),
              _wrapTap(_cell(log.commissionSignatures ?? idToName[log.createdByEmployeeId] ?? '—'), log),
            ],
          )),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1), 1: FlexColumnWidth(0.8), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.7), 5: FlexColumnWidth(0.6), 6: FlexColumnWidth(0.8), 7: FlexColumnWidth(0.5),
        8: FlexColumnWidth(0.5), 9: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildHealthHygieneTable(Map<String, Employee> idToEmp) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('№'), _header('Дата'), _header('Ф.И.О.'), _header('Должность'),
          _header('Подпись (инф.забол.)'), _header('Подпись (ОРВИ/кожа)'), _header('Результат'), _header('Подпись'),
        ],
      ),
      ...logs.asMap().entries.map((e) {
        final i = e.key + 1;
        final log = e.value;
        final emp = idToEmp[log.createdByEmployeeId];
        final name = emp != null ? '${emp.fullName}${emp.surname != null ? ' ${emp.surname}' : ''}' : '—';
        final pos = emp?.roleDisplayName ?? '—';
        final r = log.statusOk == true ? 'допущен' : (log.statusOk == false ? 'отстранен' : '—');
        return TableRow(
          children: [
            _wrapTap(_cell('$i'), log),
            _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
            _wrapTap(_cell(name), log),
            _wrapTap(_cell(pos), log),
            _wrapTap(_cell(log.statusOk != null ? (log.statusOk! ? 'Да' : 'Нет') : '—'), log),
            _wrapTap(_cell(log.status2Ok != null ? (log.status2Ok! ? 'Да' : 'Нет') : '—'), log),
            _wrapTap(_cell(r), log),
            _wrapTap(_cell(name), log),
          ],
        );
      }),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(1.2), 5: FlexColumnWidth(1.2), 6: FlexColumnWidth(0.8), 7: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildFridgeTable(Map<String, Employee> idToEmp) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('Помещение'), _header('Оборудование'), _header('Дата'), _header('Температура °C'),
        ],
      ),
      ...logs.map((log) => TableRow(
            children: [
              _wrapTap(_cell(establishmentName), log),
              _wrapTap(_cell(log.equipment ?? '—'), log),
              _wrapTap(_cell(_dateTimeFmt.format(log.createdAt)), log),
              _wrapTap(_cell(log.value1 != null ? log.value1!.toStringAsFixed(1) : '—'), log),
            ],
          )),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2), 3: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildWarehouseTable(Map<String, Employee> idToEmp) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('№'), _header('Помещение'), _header('Дата'), _header('Температура °C'), _header('Влажность %'),
        ],
      ),
      ...logs.asMap().entries.map((e) {
        final log = e.value;
        final temp = log.value1 != null ? '+${log.value1!.toStringAsFixed(0)}' : '—';
        final hum = log.value2 != null ? '${log.value2!.toStringAsFixed(0)}%' : '—';
        return TableRow(
          children: [
            _wrapTap(_cell('${e.key + 1}'), log),
            _wrapTap(_cell(establishmentName), log),
            _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
            _wrapTap(_cell(temp), log),
            _wrapTap(_cell(hum), log),
          ],
        );
      }),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1), 3: FlexColumnWidth(0.7), 4: FlexColumnWidth(0.7),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildBrakerageFinishedTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('Дата/час'), _header('Время бракеража'), _header('Блюдо'), _header('Органолептика'),
          _header('Разрешение'), _header('Подписи'), _header('Взвешивание'), _header('Прим.'),
        ],
      ),
      ...logs.map((log) => TableRow(
            children: [
              _wrapTap(_cell(_dateTimeFmt.format(log.createdAt)), log),
              _wrapTap(_cell(log.timeBrakerage ?? '—'), log),
              _wrapTap(_cell(log.productName ?? '—'), log),
              _wrapTap(_cell(log.result ?? '—'), log),
              _wrapTap(_cell(log.approvalToSell ?? '—'), log),
              _wrapTap(_cell(log.commissionSignatures ?? '—'), log),
              _wrapTap(_cell(log.weighingResult ?? '—'), log),
              _wrapTap(_cell(log.note ?? '—'), log),
            ],
          )),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1), 1: FlexColumnWidth(0.6), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
        4: FlexColumnWidth(0.7), 5: FlexColumnWidth(0.7), 6: FlexColumnWidth(0.7), 7: FlexColumnWidth(0.6),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildBrakerageIncomingTable(Map<String, Employee> idToEmp, Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('Поступление'), _header('Наименование'), _header('Фасовка'), _header('Поставщик'),
          _header('Кол-во'), _header('№ док.'), _header('Оценка'), _header('Хранение/срок'), _header('Реализация'), _header('Подпись'), _header('Прим.'),
        ],
      ),
      ...logs.map((log) {
        final dateSold = log.dateSold != null ? _dateFmt.format(log.dateSold!) : '—';
        final empName = idToName[log.createdByEmployeeId] ?? '—';
        return TableRow(
          children: [
            _wrapTap(_cell(_dateTimeFmt.format(log.createdAt)), log),
            _wrapTap(_cell(log.productName ?? '—'), log),
            _wrapTap(_cell(log.packaging ?? '—'), log),
            _wrapTap(_cell(log.manufacturerSupplier ?? '—'), log),
            _wrapTap(_cell(log.quantityKg != null ? log.quantityKg!.toStringAsFixed(2) : '—'), log),
            _wrapTap(_cell(log.documentNumber ?? '—'), log),
            _wrapTap(_cell(log.result ?? '—'), log),
            _wrapTap(_cell(log.storageConditions ?? '—'), log),
            _wrapTap(_cell(dateSold), log),
            _wrapTap(_cell(empName), log),
            _wrapTap(_cell(log.note ?? '—'), log),
          ],
        );
      }),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.9), 1: FlexColumnWidth(0.9), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(0.4), 5: FlexColumnWidth(0.5), 6: FlexColumnWidth(0.8), 7: FlexColumnWidth(0.7),
        8: FlexColumnWidth(0.7), 9: FlexColumnWidth(0.6), 10: FlexColumnWidth(0.5),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }
}
