import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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
      final logs = await svc.getLogs(
        establishmentId: est.id,
        logType: _logType,
        from: _dateFrom,
        to: _dateTo,
      );
      if (mounted) setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _dateFrom = DateTime.now();
    _dateTo = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _exportPdf({
    bool includeCover = true,
    bool includeStitching = true,
  }) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) return;

    final emps = await acc.getEmployeesForEstablishment(est.id);
    final idToName = {for (final e in emps) e.id: '${e.fullName}${e.surname != null ? ' ${e.surname}' : ''}'};

    final bytes = await HaccpPdfExportService.buildJournalPdf(
      establishmentName: est.name,
      journalTitle: _logType.displayNameRu,
      sanpinRef: _logType.sanpinRef,
      logType: _logType,
      logs: _logs,
      employeeIdToName: idToName,
      dateFrom: _dateFrom ?? DateTime.now(),
      dateTo: _dateTo ?? DateTime.now(),
      includeCover: includeCover,
      includeStitchingSheet: includeStitching,
    );

    final loc = context.read<LocalizationService>();
    final dateStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final safeCode = _logType.code.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    await saveFileBytes('haccp_${safeCode}_$dateStr.pdf', bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('haccp_pdf_saved') ?? 'PDF сохранён')),
      );
    }
  }

  Future<void> _showExportOptions() async {
    final loc = context.read<LocalizationService>();
    var includeCover = true;
    var includeStitching = true;

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('haccp_save_file') ?? 'Сохранить файл',
                style: Theme.of(ctx2).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: includeCover,
                onChanged: (v) {
                  setModal(() => includeCover = v ?? true);
                },
                title: Text(loc.t('haccp_pdf_cover') ?? 'Титульный лист'),
                subtitle: Text(
                  loc.t('haccp_pdf_cover_hint') ?? 'Название организации, даты',
                  style: Theme.of(ctx2).textTheme.bodySmall,
                ),
              ),
              CheckboxListTile(
                value: includeStitching,
                onChanged: (v) {
                  setModal(() => includeStitching = v ?? true);
                },
                title: Text(loc.t('haccp_pdf_stitching') ?? 'Лист прошивки'),
                subtitle: Text(
                  loc.t('haccp_pdf_stitching_hint') ?? '«Пронумеровано и прошнуровано»',
                  style: Theme.of(ctx2).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  Navigator.of(ctx2).pop();
                  await _exportPdf(includeCover: includeCover, includeStitching: includeStitching);
                },
                child: Text(loc.t('haccp_save_file') ?? 'Сохранить файл'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final from = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? from,
      firstDate: from,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (to == null || !mounted) return;
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
                    child: Text(
                      '${DateFormat('dd.MM.yyyy').format(_dateFrom!)} — ${DateFormat('dd.MM.yyyy').format(_dateTo!)}',
                      style: Theme.of(context).textTheme.bodySmall,
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
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _logs.length,
                          itemBuilder: (_, i) {
                            final log = _logs[i];
                            return _LogTile(log: log, onTap: () => _openAddForm());
                          },
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
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;

    final result = await context.push<Map<String, dynamic>>(
      '/haccp-journals/${widget.logTypeCode}/add',
    );
    if (result != null && mounted) await _load();
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log, required this.onTap});

  final HaccpLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(log.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(log.summaryLine(), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

}
