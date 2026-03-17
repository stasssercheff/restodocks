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
  /// Для Приложения 3: выбранное помещение (null = «Все»).
  String? _selectedWarehousePremises;

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

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('haccp_period') ?? 'Период'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                if (logType == HaccpLogType.warehouseTempHumidity && _logs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          'Наименование складского помещения:',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            value: _selectedWarehousePremises ?? 'Все',
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(value: 'Все', child: Text('Все помещения')),
                              ...(() {
                                final list = _logs
                                    .map((e) => e.equipment)
                                    .whereType<String>()
                                    .where((s) => s.trim().isNotEmpty)
                                    .toSet()
                                    .toList();
                                list.sort();
                                return list.map((s) => DropdownMenuItem<String>(value: s, child: Text(s)));
                              })(),
                            ],
                            onChanged: (v) => setState(() {
                              _selectedWarehousePremises = (v == null || v == 'Все') ? null : v;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                          logs: logType == HaccpLogType.warehouseTempHumidity && _selectedWarehousePremises != null
                              ? _logs.where((l) => l.equipment == _selectedWarehousePremises).toList()
                              : _logs,
                          employees: _employees,
                          onLogTap: _openLogDetail,
                          warehousePremisesName: logType == HaccpLogType.warehouseTempHumidity ? _selectedWarehousePremises : null,
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
    final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
    final subjectId = parsed.subjectEmployeeId ?? log.createdByEmployeeId;
    final emp = idToEmp[subjectId];
    final creator = idToEmp[log.createdByEmployeeId];
    final subjectName = parsed.employeeNameSnapshot ?? (emp != null ? '${emp.fullName}${emp.surname != null ? ' ${emp.surname}' : ''}' : null);
    final subjectPos = parsed.positionOverride ?? emp?.roleDisplayName;
    context.push(
      '/haccp-journals/${widget.logTypeCode}/view',
      extra: {'log': log, 'employee': emp, 'creator': creator, 'subjectNameSnapshot': subjectName, 'subjectPositionSnapshot': subjectPos},
    );
  }
}

/// Список записей журнала в виде таблицы по макету СанПиН (Приложения 1–5 и 8).
class _JournalTableView extends StatelessWidget {
  const _JournalTableView({
    required this.logType,
    required this.establishmentName,
    required this.logs,
    required this.employees,
    required this.onLogTap,
    this.warehousePremisesName,
  });

  final HaccpLogType logType;
  final String establishmentName;
  final List<HaccpLog> logs;
  final List<Employee> employees;
  final void Function(HaccpLog log) onLogTap;
  /// Для Приложения 3: наименование помещения (в шапке). Если null при «Все» — в таблице колонка «Помещение».
  final String? warehousePremisesName;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');
  static final _timeFmt = DateFormat('HH:mm');

  Widget _header(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          border: Border(right: BorderSide(color: Colors.grey.shade400), bottom: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      );

  Widget _cell(String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color != null ? color.withValues(alpha: 0.15) : null,
          border: Border(right: BorderSide(color: Colors.grey.shade400), bottom: BorderSide(color: Colors.grey.shade400)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black)),
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
          child: logType == HaccpLogType.warehouseTempHumidity
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Приложение № 3 к СанПиН 2.3/2.4.3590-20',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                    ),
                    if (warehousePremisesName != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Наименование складского помещения: $warehousePremisesName',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                )
              : Text(
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
        return _buildWarehouseTable(idToEmp, idToName);
      case HaccpLogType.finishedProductBrakerage:
        return _buildBrakerageFinishedTable(idToName);
      case HaccpLogType.incomingRawBrakerage:
        return _buildBrakerageIncomingTable(idToEmp, idToName);
      case HaccpLogType.fryingOil:
        return _buildFryingOilTable(idToName);
      case HaccpLogType.medBookRegistry:
        return _buildMedBookTable(idToName);
      case HaccpLogType.medExaminations:
        return _buildMedExaminationsTable(idToName);
      case HaccpLogType.disinfectantAccounting:
        return _buildDisinfectantAccountingTable(idToName);
      case HaccpLogType.equipmentWashing:
        return _buildEquipmentWashingTable(idToName);
      case HaccpLogType.generalCleaningSchedule:
        return _buildGeneralCleaningTable(idToName);
      case HaccpLogType.sieveFilterMagnet:
        return _buildSieveFilterMagnetTable(idToName);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMedExaminationsTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(children: [_header('№'), _header('Ф. И. О.'), _header('Должность'), _header('Дата осмотра'), _header('Заключение'), _header('Решение'), _header('Подпись')]),
      ...logs.asMap().entries.map((e) {
        final log = e.value;
        return TableRow(children: [
          _wrapTap(_cell('${e.key + 1}'), log),
          _wrapTap(_cell(log.medExamEmployeeName ?? '—'), log),
          _wrapTap(_cell(log.medExamPosition ?? '—'), log),
          _wrapTap(_cell(log.medExamDate != null ? _dateFmt.format(log.medExamDate!) : '—'), log),
          _wrapTap(_cell(log.medExamConclusion ?? '—'), log),
          _wrapTap(_cell(log.medExamEmployerDecision ?? '—'), log),
          _wrapTap(_cell(idToName[log.createdByEmployeeId] ?? '—'), log),
        ]);
      }),
    ];
    return Table(columnWidths: const {0: FlexColumnWidth(0.3), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.7), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(0.7), 6: FlexColumnWidth(0.7)}, border: TableBorder.all(color: Colors.grey), children: rows);
  }

  Widget _buildDisinfectantAccountingTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(children: [_header('Дата'), _header('Объект/Дезсредство'), _header('Кол-во/Площадь'), _header('Поступление'), _header('Ответственный')]),
      ...logs.map((log) => TableRow(children: [
        _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
        _wrapTap(_cell(log.disinfObjectName ?? log.disinfAgentName ?? '—'), log),
        _wrapTap(_cell(log.disinfObjectCount != null ? log.disinfObjectCount.toString() : (log.disinfQuantity != null ? log.disinfQuantity.toString() : '—')), log),
        _wrapTap(_cell(log.disinfReceiptDate != null ? _dateFmt.format(log.disinfReceiptDate!) : '—'), log),
        _wrapTap(_cell(log.disinfResponsibleName ?? idToName[log.createdByEmployeeId] ?? '—'), log),
      ])),
    ];
    return Table(columnWidths: const {0: FlexColumnWidth(0.6), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(0.5), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(0.8)}, border: TableBorder.all(color: Colors.grey), children: rows);
  }

  Widget _buildEquipmentWashingTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(children: [_header('Дата'), _header('Время'), _header('Оборудование'), _header('Моющее'), _header('Дез. раствор'), _header('Контролёр')]),
      ...logs.map((log) => TableRow(children: [
        _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
        _wrapTap(_cell(log.washTime ?? '—'), log),
        _wrapTap(_cell(log.washEquipmentName ?? '—'), log),
        _wrapTap(_cell(log.washSolutionName ?? '—'), log),
        _wrapTap(_cell(log.washDisinfectantName ?? '—'), log),
        _wrapTap(_cell(log.washControllerSignature ?? idToName[log.createdByEmployeeId] ?? '—'), log),
      ])),
    ];
    return Table(columnWidths: const {0: FlexColumnWidth(0.6), 1: FlexColumnWidth(0.4), 2: FlexColumnWidth(1), 3: FlexColumnWidth(0.8), 4: FlexColumnWidth(0.8), 5: FlexColumnWidth(0.7)}, border: TableBorder.all(color: Colors.grey), children: rows);
  }

  Widget _buildGeneralCleaningTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(children: [_header('№'), _header('Помещение'), _header('Дата'), _header('Ответственный')]),
      ...logs.asMap().entries.map((e) {
        final log = e.value;
        return TableRow(children: [
          _wrapTap(_cell('${e.key + 1}'), log),
          _wrapTap(_cell(log.genCleanPremises ?? '—'), log),
          _wrapTap(_cell(log.genCleanDate != null ? _dateFmt.format(log.genCleanDate!) : '—'), log),
          _wrapTap(_cell(log.genCleanResponsible ?? idToName[log.createdByEmployeeId] ?? '—'), log),
        ]);
      }),
    ];
    return Table(columnWidths: const {0: FlexColumnWidth(0.3), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(0.6), 3: FlexColumnWidth(0.8)}, border: TableBorder.all(color: Colors.grey), children: rows);
  }

  Widget _buildSieveFilterMagnetTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(children: [_header('№ сита/магнита'), _header('Наименование / Расположение'), _header('Состояние'), _header('Дата очистки'), _header('ФИО'), _header('Комментарии')]),
      ...logs.map((log) => TableRow(children: [
        _wrapTap(_cell(log.sieveNo ?? '—'), log),
        _wrapTap(_cell(log.sieveNameLocation ?? '—'), log),
        _wrapTap(_cell(log.sieveCondition ?? '—'), log),
        _wrapTap(_cell(log.sieveCleaningDate != null ? _dateFmt.format(log.sieveCleaningDate!) : '—'), log),
        _wrapTap(_cell(log.sieveSignature ?? idToName[log.createdByEmployeeId] ?? '—'), log),
        _wrapTap(_cell(log.sieveComments ?? '—'), log),
      ])),
    ];
    return Table(columnWidths: const {0: FlexColumnWidth(0.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(0.6), 3: FlexColumnWidth(0.6), 4: FlexColumnWidth(0.7), 5: FlexColumnWidth(0.6)}, border: TableBorder.all(color: Colors.grey), children: rows);
  }

  Widget _buildMedBookTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('№ п/п'),
          _header('Фамилия, имя, отчество'),
          _header('Должность'),
          _header('Номер медицинской книжки'),
          _header('Срок действия медицинской книжки'),
          _header('Расписка и дата получения медицинской книжки'),
          _header('Расписка и дата возврата медицинской книжки'),
        ],
      ),
      ...logs.asMap().entries.map((e) {
        final log = e.value;
        final sign = idToName[log.createdByEmployeeId] ?? '—';
        final issued = log.medBookIssuedAt != null ? _dateFmt.format(log.medBookIssuedAt!) : '—';
        final returned = log.medBookReturnedAt != null ? _dateFmt.format(log.medBookReturnedAt!) : '—';
        return TableRow(
          children: [
            _wrapTap(_cell('${e.key + 1}'), log),
            _wrapTap(_cell(log.medBookEmployeeName ?? '—'), log),
            _wrapTap(_cell(log.medBookPosition ?? '—'), log),
            _wrapTap(_cell(log.medBookNumber ?? '—'), log),
            _wrapTap(_cell(log.medBookValidUntil != null ? _dateFmt.format(log.medBookValidUntil!) : '—'), log),
            _wrapTap(_cell('$issued\n$sign'), log),
            _wrapTap(_cell('$returned\n$sign'), log),
          ],
        );
      }),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(0.4),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.9),
        5: FlexColumnWidth(1),
        6: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildFryingOilTable(Map<String, String> idToName) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('Дата'), _header('Время начала'), _header('Вид жира'), _header('Оценка на начало'),
          _header('Оборудование'), _header('Вид продукции'), _header('Время окончания жарки'),
          _header('Оценка по окончании'), _header('Переходящий остаток, кг'), _header('Утилизировано, кг'), _header('Контролёр'),
        ],
      ),
      ...logs.map((log) => TableRow(
            children: [
              _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
              _wrapTap(_cell(_timeFmt.format(log.createdAt)), log),
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
        0: FlexColumnWidth(0.7), 1: FlexColumnWidth(0.5), 2: FlexColumnWidth(0.8), 3: FlexColumnWidth(0.8),
        4: FlexColumnWidth(0.8), 5: FlexColumnWidth(0.7), 6: FlexColumnWidth(0.6), 7: FlexColumnWidth(0.8),
        8: FlexColumnWidth(0.5), 9: FlexColumnWidth(0.5), 10: FlexColumnWidth(0.8),
      },
      border: TableBorder.all(color: Colors.grey),
      children: rows,
    );
  }

  Widget _buildHealthHygieneTable(Map<String, Employee> idToEmp) {
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('№ п/п'),
          _header('Дата'),
          _header('Ф. И. О. работника (последнее при наличии)'),
          _header('Должность'),
          _header('Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
          _header('Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
          _header('Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)'),
          _header('Подпись медицинского работника (ответственного лица)'),
        ],
      ),
      ...logs.asMap().entries.map((e) {
        final i = e.key + 1;
        final log = e.value;
        final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
        final subjectId = parsed.subjectEmployeeId ?? log.createdByEmployeeId;
        final emp = idToEmp[subjectId];
        final name = parsed.employeeNameSnapshot ?? (emp != null ? '${emp.fullName}${emp.surname != null ? ' ${emp.surname}' : ''}' : null) ?? '—';
        final pos = parsed.positionOverride ?? emp?.roleDisplayName ?? '—';
        final creator = idToEmp[log.createdByEmployeeId];
        final creatorName = creator != null ? '${creator.fullName}${creator.surname != null ? ' ${creator.surname}' : ''}' : '—';
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
            _wrapTap(_cell(creatorName), log),
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

  /// Приложение № 3: 5 обязательных колонок. При просмотре «Все» — 6-я колонка «Помещение». Подсветка красным при t>25°C или влажность>75%.
  Widget _buildWarehouseTable(Map<String, Employee> idToEmp, Map<String, String> idToName) {
    final showPremisesColumn = warehousePremisesName == null;
    final rows = <TableRow>[
      TableRow(
        children: [
          _header('№ п/п'),
          if (showPremisesColumn) _header('Наименование складского помещения'),
          _header('Дата'),
          _header('Температура, °C'),
          _header('Относительная влажность, %'),
          _header('Подпись ответственного лица'),
        ],
      ),
      ...logs.asMap().entries.map((e) {
        final log = e.value;
        final tempVal = log.value1;
        final humVal = log.value2;
        final tempOut = tempVal != null ? '${tempVal.toStringAsFixed(0)}' : '—';
        final humOut = humVal != null ? '${humVal.toStringAsFixed(0)}%' : '—';
        final tempAlert = tempVal != null && tempVal > 25;
        final humAlert = humVal != null && humVal > 75;
        Widget tempCell = _cell(tempOut);
        if (tempAlert) tempCell = _cell(tempOut, color: Colors.red);
        Widget humCell = _cell(humOut);
        if (humAlert) humCell = _cell(humOut, color: Colors.red);
        final sign = idToName[log.createdByEmployeeId] ?? '—';
        return TableRow(
          children: [
            _wrapTap(_cell('${e.key + 1}'), log),
            if (showPremisesColumn) _wrapTap(_cell(log.equipment ?? '—'), log),
            _wrapTap(_cell(_dateFmt.format(log.createdAt)), log),
            _wrapTap(tempCell, log),
            _wrapTap(humCell, log),
            _wrapTap(_cell(sign), log),
          ],
        );
      }),
    ];
    return Table(
      columnWidths: showPremisesColumn
          ? const {
              0: FlexColumnWidth(0.4),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(0.7),
              4: FlexColumnWidth(0.8),
              5: FlexColumnWidth(1.2),
            }
          : const {
              0: FlexColumnWidth(0.4),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(0.8),
              3: FlexColumnWidth(0.7),
              4: FlexColumnWidth(1.2),
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
