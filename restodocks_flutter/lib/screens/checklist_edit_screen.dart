import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';

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
  late final TextEditingController _nameController;
  late final TextEditingController _newItemController;
  final List<ChecklistItem> _items = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final c = await svc.getChecklistById(widget.checklistId);
      if (!mounted) return;
      setState(() {
        _checklist = c;
        _loading = false;
        if (c != null) {
          _nameController.text = c.name;
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

    // Создать tracked контроллеры
    _nameController = createTrackedController();
    _newItemController = createTrackedController();

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());

    // Настроить автосохранение
    setOnInputChanged(scheduleSave);
  }

  @override
  String get draftKey => 'checklist';

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'checklistId': widget.checklistId,
      'name': _nameController.text,
      'items': _items.map((item) => {
        'id': item.id,
        'title': item.title,
        'sortOrder': item.sortOrder,
        'cellType': item.cellType.value,
        'dropdownOptions': item.dropdownOptions,
      }).toList(),
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (data['checklistId'] != widget.checklistId) return; // Не наш черновик

    setState(() {
      _nameController.text = data['name'] ?? '';
      final itemsData = data['items'] as List<dynamic>? ?? [];
      _items.clear();
      for (final itemData in itemsData) {
        final Map<String, dynamic> itemMap = itemData as Map<String, dynamic>;
        final opts = itemMap['dropdownOptions'];
        _items.add(ChecklistItem(
          id: itemMap['id'] ?? '',
          checklistId: widget.checklistId,
          title: itemMap['title'] ?? '',
          sortOrder: itemMap['sortOrder'] ?? 0,
          cellType: ChecklistCellTypeExt.fromString(itemMap['cellType'] as String?),
          dropdownOptions: opts is List ? opts.map((e) => e.toString()).toList() : [],
        ));
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newItemController.dispose();
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
    final updated = c.copyWith(
      name: name,
      items: _items
          .map((e) => ChecklistItem(
                id: e.id,
                checklistId: c.id,
                title: e.title,
                sortOrder: e.sortOrder,
                cellType: e.cellType,
                dropdownOptions: e.dropdownOptions,
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

  Future<void> _addItem() async {
    final t = _newItemController.text.trim();
    if (t.isEmpty) return;
    final loc = context.read<LocalizationService>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AddItemDialog(
        title: t,
        loc: loc,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _items.add(ChecklistItem.template(
        title: result['title'] as String,
        sortOrder: _items.length,
        cellType: result['cellType'] as ChecklistCellType,
        dropdownOptions: result['dropdownOptions'] as List<String>,
      ));
      _newItemController.clear();
    });
    scheduleSave();
  }

  void _removeItem(int i) {
    setState(() => _items.removeAt(i));
    scheduleSave();
  }

  String _cellTypeLabel(LocalizationService loc, ChecklistCellType t) {
    switch (t) {
      case ChecklistCellType.quantity: return loc.t('checklist_cell_quantity') ?? 'Количество';
      case ChecklistCellType.checkbox: return loc.t('checklist_cell_checkbox') ?? 'Галочка';
      case ChecklistCellType.dropdown: return loc.t('checklist_cell_dropdown') ?? 'Выпадающий список';
    }
  }

  Future<void> _editItem(int i) async {
    if (i < 0 || i >= _items.length) return;
    final it = _items[i];
    final loc = context.read<LocalizationService>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AddItemDialog(
        title: it.title,
        loc: loc,
        initialCellType: it.cellType,
        initialDropdownOptions: it.dropdownOptions,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _items[i] = it.copyWith(
        title: result['title'] as String,
        cellType: result['cellType'] as ChecklistCellType,
        dropdownOptions: result['dropdownOptions'] as List<String>,
      );
    });
    scheduleSave();
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
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklists')),
          actions: [
            IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
          ],
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
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: Text(loc.t('checklists')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _checklist == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('checklists')),
        actions: [
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
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
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
            if (canEdit) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newItemController,
                      decoration: InputDecoration(
                        labelText: loc.t('add_item'),
                        hintText: context.read<LocalizationService>().t('checklist_item_hint'),
                      ),
                      onSubmitted: (_) => _addItem(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    tooltip: loc.t('add_item'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ...List.generate(_items.length, (i) {
              final it = _items[i];
              final cellLabel = _cellTypeLabel(loc, it.cellType);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(it.title),
                  subtitle: it.cellType == ChecklistCellType.dropdown && it.dropdownOptions.isNotEmpty
                      ? Text(it.dropdownOptions.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis)
                      : Text(cellLabel, style: Theme.of(context).textTheme.bodySmall),
                  trailing: canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editItem(i),
                              tooltip: loc.t('edit'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeItem(i),
                              tooltip: loc.t('delete'),
                            ),
                          ],
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

/// Диалог добавления/редактирования пункта с выбором типа ячейки.
class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.title,
    required this.loc,
    this.initialCellType = ChecklistCellType.checkbox,
    this.initialDropdownOptions = const [],
  });

  final String title;
  final LocalizationService loc;
  final ChecklistCellType initialCellType;
  final List<String> initialDropdownOptions;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  late final TextEditingController _titleCtrl;
  late ChecklistCellType _cellType;
  late List<TextEditingController> _optionCtrls;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title);
    _cellType = widget.initialCellType;
    _optionCtrls = widget.initialDropdownOptions
        .map((o) => TextEditingController(text: o))
        .toList();
    if (_optionCtrls.isEmpty && _cellType == ChecklistCellType.dropdown) {
      _optionCtrls.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _optionCtrls) c.dispose();
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtrls.length <= 1) return;
    setState(() {
      _optionCtrls[i].dispose();
      _optionCtrls.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    return AlertDialog(
      title: Text(loc.t('add_item')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: loc.t('checklist_item_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(loc.t('checklist_cell_type') ?? 'Тип ячейки', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ChecklistCellType>(
              segments: [
                ButtonSegment(
                  value: ChecklistCellType.quantity,
                  label: Text(loc.t('checklist_cell_quantity') ?? 'Кол-во'),
                  icon: const Icon(Icons.numbers, size: 18),
                ),
                ButtonSegment(
                  value: ChecklistCellType.checkbox,
                  label: Text(loc.t('checklist_cell_checkbox') ?? 'Галочка'),
                  icon: const Icon(Icons.check_box, size: 18),
                ),
                ButtonSegment(
                  value: ChecklistCellType.dropdown,
                  label: Text(loc.t('checklist_cell_dropdown') ?? 'Список'),
                  icon: const Icon(Icons.list, size: 18),
                ),
              ],
              selected: {_cellType},
              onSelectionChanged: (s) {
                setState(() {
                  _cellType = s.first;
                  if (_cellType == ChecklistCellType.dropdown && _optionCtrls.isEmpty) {
                    _optionCtrls.add(TextEditingController());
                  }
                });
              },
            ),
            if (_cellType == ChecklistCellType.dropdown) ...[
              const SizedBox(height: 16),
              Text(loc.t('checklist_dropdown_options') ?? 'Варианты выбора', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              ...List.generate(_optionCtrls.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _optionCtrls[i],
                        decoration: InputDecoration(
                          hintText: '${loc.t('option') ?? 'Вариант'} ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: _optionCtrls.length > 1 ? () => _removeOption(i) : null,
                    ),
                  ],
                ),
              )),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, size: 18),
                label: Text(loc.t('checklist_add_option') ?? 'Добавить вариант'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(loc.t('cancel'))),
        FilledButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            final opts = _cellType == ChecklistCellType.dropdown
                ? _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList()
                : <String>[];
            Navigator.of(context).pop(<String, dynamic>{
              'title': title,
              'cellType': _cellType,
              'dropdownOptions': opts,
            });
          },
          child: Text(loc.t('save')),
        ),
      ],
    );
  }
}
