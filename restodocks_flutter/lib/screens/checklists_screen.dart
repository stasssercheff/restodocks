import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
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
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

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
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final list = await svc.getChecklistsForEstablishment(est.id, department: widget.department);
      if (mounted) setState(() {
        _list = list;
        _loading = false;
      });
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
    super.dispose();
  }

  Future<void> _createNew() async {
    final loc = context.read<LocalizationService>();
    ChecklistType type = ChecklistType.tasks;
    String name = '';
    String additionalName = '';
    final nameCtrl = TextEditingController();
    final addNameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(loc.t('create_checklist')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<ChecklistType>(
                      value: type,
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_type') ?? 'Тип',
                      ),
                      items: ChecklistType.values
                          .map((t) => DropdownMenuItem(value: t, child: Text(t.getLocalizedName(loc.currentLanguageCode))))
                          .toList(),
                      onChanged: (v) => setDialogState(() => type = v ?? type),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_name'),
                        hintText: loc.t('checklist_name_hint'),
                      ),
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (type == ChecklistType.prep) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: addNameCtrl,
                        decoration: InputDecoration(
                          labelText: loc.t('checklist_additional_name') ?? 'Дополнительное название',
                          hintText: loc.t('checklist_additional_name_hint'),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(loc.t('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(nameCtrl.text.trim().isNotEmpty),
                  child: Text(loc.t('save')),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    final finalName = nameCtrl.text.trim();
    final finalAdditional = addNameCtrl.text.trim();
    if (finalName.isEmpty) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment!;
    final emp = acc.currentEmployee!;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final created = await svc.createChecklist(
        establishmentId: est.id,
        createdBy: emp.id,
        name: finalName,
        additionalName: finalAdditional.isEmpty ? null : finalAdditional,
        type: type,
        assignedDepartment: widget.department,
      );
      if (mounted) {
        await _load();
        context.push('/checklists/${created.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
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
      body: _body(loc, canEdit, canAccessChecklists, _scrollController),
      floatingActionButton: canAccessChecklists
          ? FloatingActionButton(
              onPressed: _loading ? null : _createNew,
              child: const Icon(Icons.add),
              tooltip: loc.t('create_checklist'),
            )
          : null,
    );
  }

  Widget _body(LocalizationService loc, bool canEdit, bool canAccessChecklists, ScrollController scrollController) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: _list.length,
        itemBuilder: (context, i) {
          final c = _list[i];
          final lang = loc.currentLanguageCode;
          final sectionLabel = c.assignedSection != null
              ? (KitchenSection.fromCode(c.assignedSection!)?.getLocalizedName(lang) ?? c.assignedSection)
              : null;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.checklist),
                  if (sectionLabel != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: sectionLabel,
                      child: Icon(Icons.store, size: 18, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ],
              ),
              title: Text(c.name),
              subtitle: Text([
                if (sectionLabel != null) sectionLabel,
                '${c.items.length} ${loc.t('items_count')}',
              ].join(' • ')),
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
                                  content: Text('${c.name}'),
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
                                try {
                                  await context.read<ChecklistServiceSupabase>().deleteChecklist(c.id);
                                  if (mounted) _load();
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))),
                                    );
                                  }
                                }
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
                if (mounted) _load();
              },
            ),
          );
        },
      ),
    );
  }
}
