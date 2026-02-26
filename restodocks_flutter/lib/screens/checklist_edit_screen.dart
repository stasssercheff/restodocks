import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';
import '../widgets/app_bar_home_button.dart';

/// Редактирование чеклиста-шаблона. Сохранить, создать по аналогии, удалить.
class ChecklistEditScreen extends StatefulWidget {
  const ChecklistEditScreen({super.key, required this.checklistId});

  final String checklistId;

  @override
  State<ChecklistEditScreen> createState() => _ChecklistEditScreenState();
}

class _ChecklistEditScreenState extends State<ChecklistEditScreen>
    with AutoSaveMixin<ChecklistEditScreen>, InputChangeListenerMixin<ChecklistEditScreen> {
  Checklist? _checklist;
  bool _loading = true;
  String? _error;
  List<TechCard> _techCards = [];
  late final TextEditingController _nameController;
  late final TextEditingController _additionalNameController;
  late final TextEditingController _newItemController;
  late final TextEditingController _dropdownOptionsController;
  final List<ChecklistItem> _items = [];
  ChecklistType _type = ChecklistType.tasks;
  bool _actionHasNumeric = false;
  bool _actionHasToggle = true;
  List<String> _actionDropdownOptions = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      final svc = context.read<ChecklistServiceSupabase>();
      final techSvc = context.read<TechCardServiceSupabase>();
      final c = await svc.getChecklistById(widget.checklistId);
      List<TechCard> techs = [];
      if (est != null) {
        techs = await techSvc.getTechCardsForEstablishment(est.id);
      }
      if (!mounted) return;
      setState(() {
        _checklist = c;
        _techCards = techs;
        _loading = false;
        if (c != null) {
          _nameController.text = c.name;
          _additionalNameController.text = c.additionalName ?? '';
          _type = c.type ?? ChecklistType.tasks;
          _actionHasNumeric = c.actionConfig.hasNumeric;
          _actionHasToggle = c.actionConfig.hasToggle;
          _actionDropdownOptions = List.from(c.actionConfig.dropdownOptions ?? []);
          _dropdownOptionsController.text = _actionDropdownOptions.join(', ');
          _items
            ..clear()
            ..addAll(c.items);
        }
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

    _nameController = createTrackedController();
    _additionalNameController = createTrackedController();
    _newItemController = createTrackedController();
    _dropdownOptionsController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());

    // Настроить автосохранение
    setOnInputChanged(scheduleSave);
  }

  @override
  String get draftKey => 'checklist_edit_${widget.checklistId}';

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'checklistId': widget.checklistId,
      'name': _nameController.text,
      'additionalName': _additionalNameController.text,
      'type': _type.code,
      'actionHasNumeric': _actionHasNumeric,
      'actionHasToggle': _actionHasToggle,
      'actionDropdownOptions': _actionDropdownOptions,
      'items': _items.map((item) => {
        'id': item.id,
        'title': item.title,
        'sortOrder': item.sortOrder,
        'techCardId': item.techCardId,
      }).toList(),
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (data['checklistId'] != widget.checklistId) return;

    setState(() {
      _nameController.text = data['name'] ?? '';
      _additionalNameController.text = data['additionalName'] ?? '';
      _type = ChecklistType.fromCode(data['type'] as String?) ?? ChecklistType.tasks;
      _actionHasNumeric = data['actionHasNumeric'] == true;
      _actionHasToggle = data['actionHasToggle'] != false;
      _actionDropdownOptions = List<String>.from(data['actionDropdownOptions'] as List<dynamic>? ?? []);
      final itemsData = data['items'] as List<dynamic>? ?? [];
      _items.clear();
      for (final itemData in itemsData) {
        final Map<String, dynamic> itemMap = itemData as Map<String, dynamic>;
        _items.add(ChecklistItem(
          id: itemMap['id'] ?? '',
          checklistId: widget.checklistId,
          title: itemMap['title'] ?? '',
          sortOrder: (itemMap['sortOrder'] as num?)?.toInt() ?? 0,
          techCardId: itemMap['techCardId'] as String?,
        ));
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _additionalNameController.dispose();
    _newItemController.dispose();
    _dropdownOptionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _checklist;
    if (c == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocalizationService>().t('checklist_name_required'))),
      );
      return;
    }
    final opts = _dropdownOptionsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final actionConfig = ChecklistActionConfig(
      hasNumeric: _actionHasNumeric,
      dropdownOptions: opts.isEmpty ? null : opts,
      hasToggle: _actionHasToggle,
    );
    final updated = c.copyWith(
      name: name,
      additionalName: _additionalNameController.text.trim().isEmpty ? null : _additionalNameController.text.trim(),
      type: _type,
      actionConfig: actionConfig,
      assignedSection: c.assignedSection,
      items: _items
          .map((e) => ChecklistItem(
                id: e.id,
                checklistId: c.id,
                title: e.title,
                sortOrder: e.sortOrder,
                techCardId: e.techCardId,
              ))
          .toList(),
    );
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      await svc.saveChecklist(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('save') + ' ✓')),
        );
        // Очистка черновика после успешного сохранения
        clearDraft();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  Future<void> _duplicate() async {
    final c = _checklist;
    if (c == null) return;
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null) return;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final created = await svc.duplicateChecklist(c, emp.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('checklist_created_duplicate'))),
        );
        context.pushReplacement('/checklists/${created.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  Future<void> _delete() async {
    final loc = context.read<LocalizationService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete')),
        content: Text(context.read<LocalizationService>().t('checklist_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.t('back')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      await svc.deleteChecklist(widget.checklistId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.read<LocalizationService>().t('error_with_message').replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  void _addItem({String? title, String? techCardId}) {
    final t = title ?? _newItemController.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _items.add(ChecklistItem.template(
        title: t,
        sortOrder: _items.length,
        techCardId: techCardId,
      ));
      _newItemController.clear();
    });
    scheduleSave();
  }

  void _showAddItemDialog() {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    if (_type == ChecklistType.prep && _techCards.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          String? selectedTechId;
          final customController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(loc.t('add_item') ?? 'Добавить пункт'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      loc.t('checklist_item_prep_hint') ?? 'ТТК ПФ из списка или своё наименование',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedTechId,
                      decoration: InputDecoration(
                        labelText: loc.t('ttk_pf') ?? 'ТТК ПФ',
                      ),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text(loc.t('custom') ?? 'Своё (ввести текст)')),
                        ..._techCards
                            .where((tc) => tc.isSemiFinished)
                            .map((tc) => DropdownMenuItem(
                                  value: tc.id,
                                  child: Text(tc.getDisplayNameInLists(lang)),
                                )),
                      ],
                      onChanged: (v) => setDialogState(() => selectedTechId = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: customController,
                      decoration: InputDecoration(
                        labelText: selectedTechId == null ? (loc.t('custom') ?? 'Своё') : (loc.t('or_override') ?? 'Или переопределить'),
                        hintText: loc.t('checklist_item_hint'),
                      ),
                      enabled: selectedTechId == null || customController.text.isNotEmpty,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(loc.t('cancel')),
                  ),
                    FilledButton(
                    onPressed: () {
                      if (selectedTechId != null) {
                        final tc = _techCards.firstWhere((t) => t.id == selectedTechId);
                        _addItem(title: tc.getDisplayNameInLists(lang), techCardId: selectedTechId);
                        Navigator.of(ctx).pop();
                      } else if (customController.text.trim().isNotEmpty) {
                        _addItem(title: customController.text.trim());
                        Navigator.of(ctx).pop();
                      }
                    },
                    child: Text(loc.t('add')),
                  ),
                ],
              );
            },
          );
        },
      );
    } else {
      _addItem();
    }
  }

  void _removeItem(int i) {
    setState(() => _items.removeAt(i));
    scheduleSave(); // Автосохранение при удалении элемента
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final canEdit = emp?.canEditChecklistsAndTechCards ?? false;
    // Шеф, су-шеф, владелец и руководство кухни — доступ как у линейных сотрудников
    final canAccessChecklists = emp?.canViewDepartment('kitchen') ?? false;

    if (emp != null && !canAccessChecklists) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('checklists')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(loc.t('checklists_kitchen_only'), style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: () => context.go('/home'), icon: const Icon(Icons.home), label: Text(loc.t('home'))),
              ],
            ),
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('checklists')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _checklist == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('checklists')),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error ?? 'Чеклист не найден', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: Text(loc.t('back')),
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
        title: Text(loc.t('checklists')),
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: () => context.push('/checklists/${widget.checklistId}/fill'),
              icon: const Icon(Icons.task_alt, size: 18),
              label: Text(loc.t('fill_checklist') ?? 'Заполнить'),
            ),
          if (canEdit)
            TextButton(
              onPressed: _duplicate,
              child: Text(loc.t('create_by_analogy')),
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
              tooltip: loc.t('delete'),
            ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            TextField(
              controller: _nameController,
              readOnly: !canEdit,
              decoration: InputDecoration(
                labelText: loc.t('checklist_name'),
                hintText: loc.t('checklist_name_hint'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _additionalNameController,
              readOnly: !canEdit,
              decoration: InputDecoration(
                labelText: loc.t('checklist_additional_name') ?? 'Дополнительное название',
                hintText: loc.t('checklist_additional_name_hint') ?? 'Подзаголовок чеклиста',
              ),
            ),
            const SizedBox(height: 12),
            if (canEdit)
              DropdownButtonFormField<ChecklistType>(
                value: _type,
                decoration: InputDecoration(
                  labelText: loc.t('checklist_type') ?? 'Тип чеклиста',
                ),
                items: ChecklistType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.displayName)))
                    .toList(),
                onChanged: (v) => setState(() {
                  if (v != null) _type = v;
                  scheduleSave();
                }),
              ),
            if (canEdit) const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (canEdit)
                  FilterChip(
                    label: Text(loc.t('checklist_action_numeric') ?? 'Цифра'),
                    selected: _actionHasNumeric,
                    onSelected: (v) {
                      setState(() {
                        _actionHasNumeric = v;
                        scheduleSave();
                      });
                    },
                  ),
                if (canEdit)
                  FilterChip(
                    label: Text(loc.t('checklist_action_toggle') ?? 'Сделано/не сделано'),
                    selected: _actionHasToggle,
                    onSelected: (v) {
                      setState(() {
                        _actionHasToggle = v;
                        scheduleSave();
                      });
                    },
                  ),
              ],
            ),
            if (canEdit) const SizedBox(height: 8),
            if (canEdit)
              TextField(
                controller: _dropdownOptionsController,
                decoration: InputDecoration(
                  labelText: loc.t('checklist_dropdown_options') ?? 'Варианты выбора (через запятую)',
                  hintText: 'Вариант 1, Вариант 2, Вариант 3',
                ),
                onChanged: (_) => scheduleSave(),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _checklist?.assignedSection?.isNotEmpty == true ? _checklist!.assignedSection : null,
              decoration: InputDecoration(
                labelText: loc.t('checklist_section') ?? 'Цех/отдел',
              ),
              items: [
                DropdownMenuItem(value: null, child: Text(loc.t('not_specified') ?? 'Не указан')),
                ...KitchenSection.values.map((s) => DropdownMenuItem(value: s.code, child: Text(s.displayName))),
              ],
              onChanged: canEdit ? (v) {
                setState(() => _checklist = _checklist?.copyWith(assignedSection: v));
              } : null,
            ),
            if (canEdit) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newItemController,
                      decoration: InputDecoration(
                        labelText: loc.t('add_item'),
                        hintText: _type == ChecklistType.tasks
                            ? (loc.t('checklist_item_hint') ?? 'Введите наименование')
                            : (loc.t('checklist_item_prep_hint') ?? 'ТТК ПФ или своё'),
                      ),
                      onSubmitted: (_) => _type == ChecklistType.prep ? _showAddItemDialog() : _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _type == ChecklistType.prep ? _showAddItemDialog() : _addItem(),
                    icon: const Icon(Icons.add),
                    tooltip: loc.t('add_item'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ...List.generate(_items.length, (i) {
              final it = _items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: it.techCardId != null
                      ? Icon(Icons.link, size: 20, color: Theme.of(context).colorScheme.primary)
                      : null,
                  title: Text(it.title),
                  subtitle: it.techCardId != null ? Text(loc.t('ttk_pf') ?? 'ТТК ПФ', style: Theme.of(context).textTheme.labelSmall) : null,
                  trailing: canEdit
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _removeItem(i),
                          tooltip: loc.t('delete'),
                        )
                      : null,
                ),
              );
            }),
            if (canEdit) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _save,
                child: Text(loc.t('save')),
              ),
            ],
          ],
        ),
      ),
      DataSafetyIndicator(isVisible: true),
    ],
  ),
);
  }
}
