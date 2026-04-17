import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../core/subscription_entitlements.dart';
import '../services/app_toast_service.dart';
import '../services/services.dart';
import '../utils/checklist_reminder_summary.dart';
import '../utils/employee_display_utils.dart';
import '../utils/translit_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Список чеклистов-шаблонов. Шеф может править и создавать по аналогии.
class ChecklistsScreen extends StatefulWidget {
  const ChecklistsScreen({super.key, this.embedded = false, this.department = 'kitchen'});

  final bool embedded;
  final String department;

  @override
  State<ChecklistsScreen> createState() => _ChecklistsScreenState();
}

class _ChecklistsScreenState extends State<ChecklistsScreen> {
  List<Checklist> _activeList = [];
  List<Checklist> _archivedList = [];
  List<_ArchivedChecklistEntry> _archivedEntries = [];
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
  bool _showArchive = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  /// Переводы названий чеклистов: checklistId -> переведённое название
  final Map<String, String> _translatedNames = {};

  Future<void> _loadTranslations() async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    const sourceLang = 'ru';
    if (targetLang == sourceLang) return;

    try {
      final translationSvc = context.read<TranslationService>();
      final source = {
        ..._activeList,
        ..._archivedList,
        ..._archivedEntries.map((e) => e.checklist),
      }.toList();
      for (final c in source) {
        final text = c.name.trim().isNotEmpty ? c.name : (c.additionalName?.trim().isNotEmpty == true ? c.additionalName! : '');
        if (text.isEmpty) continue;
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.checklist,
          entityId: c.id,
          fieldName: 'name',
          text: text,
          from: sourceLang,
          to: targetLang,
        );
        if (translated != null && translated != text && mounted) {
          setState(() => _translatedNames[c.id] = translated);
        }
      }
    } catch (_) {}
  }

  String _displayName(Checklist c, LocalizationService loc, bool useTranslit) {
    final base = c.name.trim().isNotEmpty
        ? c.name
        : (c.additionalName?.trim().isNotEmpty == true ? c.additionalName! : (loc.t('checklist_no_name') ?? 'Без названия'));
    var text = _translatedNames[c.id] ?? base;
    if (useTranslit) {
      text = cyrillicToLatin(text);
    }
    return text;
  }

  /// Совпадение поиска по исходному названию, переводу и (при транслите) латинице.
  List<Checklist> _filterChecklists(List<Checklist> source, bool useTranslit) {
    if (_searchQuery.isEmpty) return source;
    final q = _searchQuery;
    return source.where((c) {
      final raw = (c.name.trim().isNotEmpty ? c.name : c.additionalName ?? '').toLowerCase();
      if (raw.contains(q)) return true;
      final tr = _translatedNames[c.id]?.toLowerCase();
      if (tr != null && tr.contains(q)) return true;
      if (useTranslit) {
        final lit = cyrillicToLatin(raw).toLowerCase();
        if (lit.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  List<_ArchivedChecklistEntry> _filterArchivedEntries(bool useTranslit) {
    if (_searchQuery.isEmpty) return _archivedEntries;
    final q = _searchQuery;
    return _archivedEntries.where((entry) {
      final c = entry.checklist;
      final raw = (c.name.trim().isNotEmpty ? c.name : c.additionalName ?? '')
          .toLowerCase();
      if (raw.contains(q)) return true;
      final tr = _translatedNames[c.id]?.toLowerCase();
      if (tr != null && tr.contains(q)) return true;
      if (useTranslit) {
        final lit = cyrillicToLatin(raw).toLowerCase();
        if (lit.contains(q)) return true;
      }
      final performer = entry.performerName.toLowerCase();
      if (performer.contains(q)) return true;
      final dateText = _formatDate(entry.submittedAt.toLocal()).toLowerCase();
      if (dateText.contains(q)) return true;
      return false;
    }).toList();
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) {
      setState(() {
        _loading = false;
        _error = 'Нет заведения или сотрудника';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _translatedNames.clear();
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final acc = context.read<AccountManagerSupabase>();
      final canEdit = emp.canEditChecklistsAndTechCards;
      final isUltra =
          SubscriptionEntitlements.from(acc.establishment).hasUltraLevelFeatures;
      final list = await svc.getChecklistsForEstablishment(
        est.id,
        department: widget.department,
        currentEmployeeId: emp.id,
        applyAssignmentFilter: !canEdit,
      );
      final visibleList = isUltra
          ? list
          : list.where((c) => c.type != ChecklistType.prep).toList();
      final emps = await acc.getEmployeesForEstablishment(est.id);
      final employeeNameById = <String, String>{
        for (final e in emps) e.id: employeeDisplayName(e, translit: false),
      };
      final submissions =
          await ChecklistSubmissionService().listForEstablishment(est.id);
      final submittedChecklistIds =
          submissions.map((s) => s.checklistId).toSet();
      final latestSubmissionByChecklist = <String, ChecklistSubmission>{};
      for (final sub in submissions) {
        final prev = latestSubmissionByChecklist[sub.checklistId];
        if (prev == null || sub.createdAt.isAfter(prev.createdAt)) {
          latestSubmissionByChecklist[sub.checklistId] = sub;
        }
      }
      final archived = <Checklist>[];
      final archivedEntries = <_ArchivedChecklistEntry>[];
      final active = <Checklist>[];
      for (final c in visibleList) {
        final isRecurring = c.reminderConfig?.recurrenceEnabled == true;
        final isCompletedOnce = submittedChecklistIds.contains(c.id);
        if (!isRecurring && isCompletedOnce) {
          archived.add(c);
          final latest = latestSubmissionByChecklist[c.id];
          if (latest != null) {
            final fallbackName =
                latest.submittedByName.trim().isNotEmpty ? latest.submittedByName.trim() : '—';
            final performer = latest.submittedByEmployeeId != null
                ? (employeeNameById[latest.submittedByEmployeeId!] ?? fallbackName)
                : fallbackName;
            archivedEntries.add(
              _ArchivedChecklistEntry(
                checklist: c,
                submission: latest,
                performerName: performer.trim().isEmpty ? fallbackName : performer,
                submittedAt: latest.createdAt,
              ),
            );
          }
        } else {
          active.add(c);
        }
      }
      if (mounted) {
        setState(() {
          _activeList = active;
          _archivedList = archived;
          _archivedEntries = archivedEntries
            ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          if (_showArchive && _archivedList.isEmpty) _showArchive = false;
          _employees = emps;
          _loading = false;
        });
        _loadTranslations();
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createNew() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) return;
    await context.push('/checklists/new?department=${widget.department}');
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final canEdit = emp?.canEditChecklistsAndTechCards ?? false;
    // Шеф, су-шеф, владелец и все руководство кухни — доступ к чеклистам как у линейных сотрудников
    final canAccessChecklists = emp?.canViewDepartment('kitchen') ?? false;

    if (emp != null && !canAccessChecklists) {
      return Scaffold(
        appBar: AppBar(
          leading: widget.embedded ? null : appBarBackButton(context),
          title: GestureDetector(
            onTap: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            child: Text(loc.t('checklists')),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  loc.t('checklists_kitchen_only'),
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      context.go('/home', extra: {'back': true}),
                  icon: const Icon(Icons.home),
                  label: Text(loc.t('home')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: GestureDetector(
          onTap: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
          child: Text(loc.t('checklists')),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(loc.t('checklists') ?? 'Чеклисты'),
                    icon: const Icon(Icons.list_alt),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text(loc.t('archive') ?? 'Архив'),
                    icon: const Icon(Icons.archive_outlined),
                  ),
                ],
                selected: {_showArchive},
                onSelectionChanged: (v) {
                  setState(() => _showArchive = v.first);
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _showArchive
                    ? (loc.t('checklist_archive_search_hint') ??
                        (loc.t('checklist_search_hint') ??
                            'Поиск по названию, исполнителю и дате'))
                    : loc.t('checklist_search_hint'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final layoutPrefs = context.watch<ScreenLayoutPreferenceService>();
                final useTranslit =
                    loc.currentLanguageCode != 'ru' || layoutPrefs.showNameTranslit;
                return _body(loc, canEdit, canAccessChecklists, _scrollController, useTranslit);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: canAccessChecklists
          ? FloatingActionButton(
              onPressed: _loading ? null : _createNew,
              child: const Icon(Icons.add),
              tooltip: loc.t('create_checklist'),
            )
          : null,
    );
  }

  /// Чеклист просрочен, если deadlineAt задан и истёк.
  bool _isOverdue(Checklist c) {
    final deadline = c.deadlineAt;
    if (deadline == null) return false;
    return DateTime.now().toUtc().isAfter(deadline.toUtc());
  }

  /// Build grouped list: section → deadline → employee. Returns list of (isHeader, headerLevel, label, checklist?).
  List<({bool isHeader, int level, String label, Checklist? checklist})> _buildGroupedItems(
    LocalizationService loc,
    List<Checklist> checklists,
    bool useEmployeeTranslit,
  ) {
    final lang = loc.currentLanguageCode;
    final fmtDate = (DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final formatDateTime = (DateTime d) {
      final utc = d.toUtc();
      final hasTime = utc.hour != 0 || utc.minute != 0;
      final local = d.toLocal();
      return hasTime ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${fmtDate(local)}' : fmtDate(utc);
    };
    final noSection = loc.t('checklist_section_all') ?? 'Все цеха';
    final noDeadline = loc.t('checklist_no_deadline') ?? 'Без срока';
    final allEmployees = loc.t('checklist_all_employees') ?? 'Всем';

    final empMap = {
      for (final e in _employees) e.id: employeeDisplayName(e, translit: useEmployeeTranslit),
    };

    // Group: section -> deadline -> employee -> [Checklist]
    final grouped = <String, Map<String, Map<String, List<Checklist>>>>{};
    for (final c in checklists) {
      final secIds = c.effectiveSectionIds;
      final sectionKey = secIds.isEmpty ? '' : secIds.join('|');
      final sectionLabel = secIds.isEmpty
          ? noSection
          : secIds.map((code) => KitchenSection.fromCode(code)?.getLocalizedName(lang) ?? code).join(', ');

      final deadlineDt = c.deadlineAt;
      final deadlineKey = deadlineDt?.toIso8601String() ?? '';
      final deadlineLabel = deadlineDt != null ? formatDateTime(deadlineDt) : noDeadline;

      final empIds = c.assignedEmployeeIds ?? (c.assignedEmployeeId != null ? [c.assignedEmployeeId!] : <String>[]);
      final empKey = empIds.isNotEmpty ? empIds.first : '';
      final empLabel = empKey.isNotEmpty ? (empMap[empKey] ?? empKey) : allEmployees;

      grouped.putIfAbsent(sectionLabel, () => {});
      grouped[sectionLabel]!.putIfAbsent(deadlineLabel, () => {});
      grouped[sectionLabel]![deadlineLabel]!.putIfAbsent(empLabel, () => []);
      grouped[sectionLabel]![deadlineLabel]![empLabel]!.add(c);
    }

    // Sort sections: «Все цеха» last, rest alphabetically
    final sectionOrder = grouped.keys.toList()
      ..sort((a, b) {
        if (a == noSection) return 1;
        if (b == noSection) return -1;
        return a.compareTo(b);
      });

    final result = <({bool isHeader, int level, String label, Checklist? checklist})>[];
    for (final sec in sectionOrder) {
      result.add((isHeader: true, level: 0, label: sec, checklist: null));
      final deadlines = grouped[sec]!.keys.toList()
        ..sort((a, b) {
          if (a == noDeadline) return 1;
          if (b == noDeadline) return -1;
          return a.compareTo(b);
        });
      for (final dl in deadlines) {
        result.add((isHeader: true, level: 1, label: dl, checklist: null));
        final employees = grouped[sec]![dl]!.keys.toList()
          ..sort((a, b) {
            if (a == allEmployees) return 1;
            if (b == allEmployees) return -1;
            return a.compareTo(b);
          });
        for (final emp in employees) {
          result.add((isHeader: true, level: 2, label: emp, checklist: null));
          for (final c in grouped[sec]![dl]![emp]!) {
            result.add((isHeader: false, level: 3, label: '', checklist: c));
          }
        }
      }
    }
    return result;
  }

  Widget _body(
    LocalizationService loc,
    bool canEdit,
    bool canAccessChecklists,
    ScrollController scrollController,
    bool useTranslit,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(loc.t('refresh')),
              ),
            ],
          ),
        ),
      );
    }
    final sourceList = _showArchive ? _archivedList : _activeList;
    if (sourceList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _showArchive
                    ? (loc.t('checklist_archive_empty') ?? 'Архив пуст')
                    : loc.t('no_checklists'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _showArchive
                    ? (loc.t('checklist_archive_empty_hint') ??
                        'Завершенные неповторяющиеся чеклисты появятся здесь')
                    : loc.t('no_checklists_hint'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
              if (canAccessChecklists) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : _createNew,
                  icon: const Icon(Icons.add),
                  label: Text(loc.t('create_checklist')),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_showArchive) {
      final archived = _filterArchivedEntries(useTranslit);
      if (archived.isEmpty) {
        return Center(
          child: Text(
            loc.t('no_checklists') ?? 'Нет результатов',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey[600]),
          ),
        );
      }
      return _buildArchiveList(loc, archived, canEdit, useTranslit);
    }
    final filtered = _filterChecklists(sourceList, useTranslit);
    final grouped = _buildGroupedItems(loc, filtered, useTranslit);
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          loc.t('no_checklists') ?? 'Нет результатов',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: grouped.length,
        itemBuilder: (context, i) {
          final item = grouped[i];
          if (item.isHeader) {
            final fontSize = item.level == 0 ? 16.0 : item.level == 1 ? 14.0 : 12.0;
            final fontWeight = item.level == 0 ? FontWeight.bold : item.level == 1 ? FontWeight.w600 : FontWeight.w500;
            return Padding(
              padding: EdgeInsets.only(
                top: i > 0 ? (item.level == 0 ? 16 : item.level == 1 ? 12 : 8) : 0,
                bottom: 4,
              ),
              child: Text(
                item.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            );
          }
          final c = item.checklist!;
          final lang = loc.currentLanguageCode;
          final secIds = c.effectiveSectionIds;
          final sectionLine = secIds.isEmpty
              ? (loc.t('checklist_section_all') ?? 'Все цеха')
              : secIds.map((code) => KitchenSection.fromCode(code)?.getLocalizedName(lang) ?? code).join(', ');
          final fmtDate = (DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
          final formatDateTime = (DateTime d) {
            final utc = d.toUtc();
            final hasTime = utc.hour != 0 || utc.minute != 0;
            final local = d.toLocal();
            if (hasTime) {
              return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} ${fmtDate(local)}';
            }
            return fmtDate(utc);
          };
          final isOverdue = _isOverdue(c);
          final reminderLine = formatChecklistReminderSubtitle(c.reminderConfig, loc, lang);
          final datePartsData = <String>[
            if (reminderLine != null && reminderLine.isNotEmpty) reminderLine,
            if (c.deadlineAt != null) '${loc.t('checklist_complete_by') ?? 'Завершить до'}: ${formatDateTime(c.deadlineAt!)}',
          ];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: isOverdue
                ? RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                  )
                : null,
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isOverdue ? Icons.warning_amber_rounded : Icons.checklist,
                    color: isOverdue ? Theme.of(context).colorScheme.error : null,
                  ),
                  if (secIds.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: sectionLine,
                      child: Icon(Icons.store, size: 18, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
              title: Text(_displayName(c, loc, useTranslit)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text([
                    sectionLine,
                    '${c.items.length} ${loc.t('items_count')}',
                  ].join(' • ')),
                  if (datePartsData.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ...datePartsData.map((text) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            text,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        )),
                        if (isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              loc.t('checklist_overdue') ?? 'Просрочен',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: canEdit
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.task_alt),
                          onPressed: () async {
                            await context.push('/checklists/${c.id}/fill');
                            if (mounted) _load();
                          },
                          tooltip: loc.t('fill_checklist') ?? 'Заполнить',
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await context.push('/checklists/${c.id}');
                            } else if (v == 'fill') {
                              await context.push('/checklists/${c.id}/fill');
                            } else if (v == 'delete') {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(loc.t('checklist_delete_confirm') ?? 'Удалить чеклист?'),
                                  content: Text(_displayName(c, loc, useTranslit)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(false),
                                      child: Text(loc.t('back') ?? 'Отмена'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(ctx).pop(true),
                                      style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                                      child: Text(loc.t('delete') ?? 'Удалить'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                final toDelete = c;
                                setState(() {
                                  _activeList =
                                      _activeList.where((x) => x.id != toDelete.id).toList();
                                  _archivedList =
                                      _archivedList.where((x) => x.id != toDelete.id).toList();
                                });
                                AppToastService.show(loc.t('checklist_deleted') ?? 'Удалено');
                                try {
                                  await context.read<ChecklistServiceSupabase>().deleteChecklist(toDelete.id);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      if (_showArchive) {
                                        _archivedList = [
                                          ..._archivedList,
                                          toDelete
                                        ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                                      } else {
                                        _activeList = [
                                          ..._activeList,
                                          toDelete
                                        ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                                      }
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
                                    );
                                  }
                                }
                                return;
                              }
                            }
                            if (mounted) _load();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: Text(loc.t('edit') ?? 'Редактировать')),
                            PopupMenuItem(value: 'fill', child: Text(loc.t('fill_checklist') ?? 'Заполнить')),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(loc.t('delete') ?? 'Удалить', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () async {
                await context.push(canEdit ? '/checklists/${c.id}' : '/checklists/${c.id}/fill');
                if (mounted) await _load();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildArchiveList(
    LocalizationService loc,
    List<_ArchivedChecklistEntry> entries,
    bool canEdit,
    bool useTranslit,
  ) {
    final grouped = <String, List<_ArchivedChecklistEntry>>{};
    for (final entry in entries) {
      final key = _formatDate(entry.submittedAt.toLocal());
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: dateKeys.expand((dateKey) {
          final dayEntries = List<_ArchivedChecklistEntry>.from(grouped[dateKey]!)
            ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          return [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                dateKey,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...dayEntries.map((entry) {
              final checklist = entry.checklist;
              final sectionLine = entry.submission.section?.trim().isNotEmpty == true
                  ? entry.submission.section!.trim()
                  : (loc.t('checklist_no_section') ?? 'Без цеха');
              final subtitleParts = <String>[
                entry.performerName,
                '${_formatTime(entry.submittedAt.toLocal())} • $sectionLine',
                '${checklist.items.length} ${loc.t('items_count')}',
              ];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(_displayName(checklist, loc, useTranslit)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: subtitleParts
                        .map((line) => Text(line))
                        .toList(growable: false),
                  ),
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.visibility_outlined),
                          tooltip: loc.t('open') ?? 'Открыть',
                          onPressed: () => context.push('/checklists/${checklist.id}?view=1'),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => context.push('/checklists/${checklist.id}?view=1'),
                ),
              );
            }),
          ];
        }).toList(),
      ),
    );
  }
}

class _ArchivedChecklistEntry {
  const _ArchivedChecklistEntry({
    required this.checklist,
    required this.submission,
    required this.performerName,
    required this.submittedAt,
  });

  final Checklist checklist;
  final ChecklistSubmission submission;
  final String performerName;
  final DateTime submittedAt;
}
