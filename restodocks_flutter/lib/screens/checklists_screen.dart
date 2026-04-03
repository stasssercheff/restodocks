import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
  List<Checklist> _list = [];
  List<Employee> _employees = [];
  bool _loading = true;
  String? _error;
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
      for (final c in _list) {
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
  List<Checklist> _filterChecklists(bool useTranslit) {
    if (_searchQuery.isEmpty) return _list;
    final q = _searchQuery;
    return _list.where((c) {
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
      final list = await svc.getChecklistsForEstablishment(
        est.id,
        department: widget.department,
        currentEmployeeId: emp.id,
        applyAssignmentFilter: !canEdit,
      );
      final emps = await acc.getEmployeesForEstablishment(est.id);
      if (mounted) {
        setState(() {
          _list = list;
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
                  onPressed: () => context.go('/home'),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: loc.t('checklist_search_hint'),
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
    final noSection = loc.t('checklist_no_section') ?? 'Без цеха';
    final noDeadline = loc.t('checklist_no_deadline') ?? 'Без срока';
    final allEmployees = loc.t('checklist_all_employees') ?? 'Всем';

    final empMap = {
      for (final e in _employees) e.id: employeeDisplayName(e, translit: useEmployeeTranslit),
    };

    // Group: section -> deadline -> employee -> [Checklist]
    final grouped = <String, Map<String, Map<String, List<Checklist>>>>{};
    for (final c in checklists) {
      final sectionKey = c.assignedSection?.isNotEmpty == true ? c.assignedSection! : '';
      final sectionLabel = sectionKey.isNotEmpty
          ? (KitchenSection.fromCode(sectionKey)?.getLocalizedName(lang) ?? sectionKey)
          : noSection;

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

    // Sort sections: "Без цеха" last, rest alphabetically
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
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.checklist, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                loc.t('no_checklists'),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('no_checklists_hint'),
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
    final filtered = _filterChecklists(useTranslit);
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
          final sectionLabel = c.assignedSection != null
              ? (KitchenSection.fromCode(c.assignedSection!)?.getLocalizedName(lang) ?? c.assignedSection)
              : null;
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
                  if (sectionLabel != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: sectionLabel,
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
                    if (sectionLabel != null) sectionLabel,
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
                                setState(() => _list = _list.where((x) => x.id != toDelete.id).toList());
                                AppToastService.show(loc.t('checklist_deleted') ?? 'Удалено');
                                try {
                                  await context.read<ChecklistServiceSupabase>().deleteChecklist(toDelete.id);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => _list = [..._list, toDelete]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
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
}
