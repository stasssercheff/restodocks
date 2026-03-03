import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/translation.dart';
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
  late final TextEditingController _newItemQtyController;
  final List<ChecklistItem> _items = [];
  ChecklistType _type = ChecklistType.tasks;
  bool _actionHasNumeric = false;
  bool _actionHasToggle = true;
  List<String> _actionDropdownOptions = [];
  /// Единица для нового пункта
  String _newItemUnit = 'kg';

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
        techs = await techSvc.getTechCardsForEstablishment(est.dataEstablishmentId);
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
      _ensureTechCardTranslations(techSvc, techs);
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ensureTechCardTranslations(TechCardServiceSupabase svc, List<TechCard> cards) async {
    if (!mounted) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (lang == 'ru') return;
    final missing = cards.where(
      (tc) => !(tc.dishNameLocalized?.containsKey(lang) == true &&
               (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false)),
    ).toList();
    for (final tc in missing) {
      if (!mounted) break;
      try {
        final translated = await svc.translateTechCardName(tc.id, tc.dishName, lang)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (translated != null && mounted) {
          final idx = _techCards.indexWhere((c) => c.id == tc.id);
          if (idx >= 0) {
            final updated = _techCards[idx].copyWith(
              dishNameLocalized: {...(_techCards[idx].dishNameLocalized ?? {}), lang: translated},
            );
            setState(() => _techCards[idx] = updated);
          }
        }
      } catch (_) {}
    }
  }

  @override
  void initState() {
    super.initState();

    _nameController = createTrackedController();
    _additionalNameController = createTrackedController();
    _newItemController = createTrackedController();
    _dropdownOptionsController = TextEditingController();
    _newItemQtyController = TextEditingController();

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
        'targetQuantity': item.targetQuantity,
        'targetUnit': item.targetUnit,
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
          targetQuantity: (itemMap['targetQuantity'] as num?)?.toDouble(),
          targetUnit: itemMap['targetUnit'] as String?,
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
    _newItemQtyController.dispose();
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
                targetQuantity: e.targetQuantity,
                targetUnit: e.targetUnit,
              ))
          .toList(),
    );
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final translationManager = context.read<TranslationManager>();
      final loc = context.read<LocalizationService>();
      final emp = context.read<AccountManagerSupabase>().currentEmployee;
      await svc.saveChecklist(updated);
      // Переводим название и пункты чеклиста фоново
      final sourceLang = loc.currentLanguageCode;
      final fieldsToTranslate = <String, String>{'name': name};
      if (updated.additionalName != null && updated.additionalName!.isNotEmpty) {
        fieldsToTranslate['additional_name'] = updated.additionalName!;
      }
      for (var i = 0; i < _items.length; i++) {
        final t = _items[i].title.trim();
        if (t.isNotEmpty) fieldsToTranslate['item_$i'] = t;
      }
      translationManager.handleEntitySave(
        entityType: TranslationEntityType.checklist,
        entityId: updated.id,
        textFields: fieldsToTranslate,
        sourceLanguage: sourceLang,
        userId: emp?.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('save') + ' ✓')),
        );
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

  void _addItem({String? title, String? techCardId, double? targetQuantity, String? targetUnit}) {
    final t = title ?? _newItemController.text.trim();
    if (t.isEmpty) return;
    final qty = targetQuantity ?? double.tryParse(_newItemQtyController.text.trim().replaceAll(',', '.'));
    final unit = targetUnit ?? (_newItemQtyController.text.trim().isNotEmpty ? _newItemUnit : null);
    setState(() {
      _items.add(ChecklistItem.template(
        title: t,
        sortOrder: _items.length,
        techCardId: techCardId,
        targetQuantity: qty,
        targetUnit: unit,
      ));
      _newItemController.clear();
      _newItemQtyController.clear();
    });
    scheduleSave();
  }

  void _showSelectPfDropdown() {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final pfs = _techCards.where((tc) => tc.isSemiFinished).toList();
    if (pfs.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(loc.t('select_pf') ?? 'Выбрать ПФ', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: pfs.length,
                      itemBuilder: (_, i) {
                        final tc = pfs[i];
                        return ListTile(
                          title: Text(tc.getDisplayNameInLists(lang)),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _showQuantityDialog(
                              title: tc.getDisplayNameInLists(lang),
                              techCardId: tc.id,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Диалог ввода количества после выбора ПФ или при добавлении любого пункта.
  void _showQuantityDialog({required String title, String? techCardId}) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final qtyCtrl = TextEditingController();
    String selectedUnit = 'kg';
    final units = CulinaryUnits.all.map((u) => u.id).toList();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.t('checklist_item_quantity_hint') ?? 'Укажите количество (необязательно)', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_quantity') ?? 'Количество',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: InputDecoration(
                        labelText: loc.t('unit') ?? 'Ед.',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: units.map((u) => DropdownMenuItem(value: u, child: Text(CulinaryUnits.displayName(u, lang)))).toList(),
                      onChanged: (v) {
                        if (v != null) setInner(() => selectedUnit = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _addItem(title: title, techCardId: techCardId);
              },
              child: Text(loc.t('skip') ?? 'Пропустить'),
            ),
            FilledButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
                Navigator.of(ctx).pop();
                _addItem(title: title, techCardId: techCardId, targetQuantity: qty, targetUnit: qty != null ? selectedUnit : null);
              },
              child: Text(loc.t('add_item') ?? 'Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeItem(int i) {
    setState(() => _items.removeAt(i));
    scheduleSave();
  }

  /// Редактирование количества/единицы у существующего пункта.
  void _editItemQuantity(int index) {
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final item = _items[index];
    final qtyCtrl = TextEditingController(text: item.targetQuantity?.toString() ?? '');
    final units = CulinaryUnits.all.map((u) => u.id).toList();
    String selectedUnit = item.targetUnit ?? 'kg';
    if (!units.contains(selectedUnit)) selectedUnit = 'kg';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_quantity') ?? 'Количество',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      decoration: InputDecoration(
                        labelText: loc.t('unit') ?? 'Ед.',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: units.map((u) => DropdownMenuItem(value: u, child: Text(CulinaryUnits.displayName(u, lang)))).toList(),
                      onChanged: (v) {
                        if (v != null) setInner(() => selectedUnit = v);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            if (item.targetQuantity != null)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _items[index] = item.copyWith(targetQuantity: null, targetUnit: null));
                  scheduleSave();
                },
                child: Text(loc.t('delete') ?? 'Удалить'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('back') ?? 'Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
                Navigator.of(ctx).pop();
                setState(() => _items[index] = item.copyWith(
                  targetQuantity: qty,
                  targetUnit: qty != null ? selectedUnit : null,
                ));
                scheduleSave();
              },
              child: Text(loc.t('save') ?? 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;
    final acc = context.watch<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    // Доступ к чеклистам: владелец, шеф, су-шеф, кухня. Редактирование — тем же, кто может создавать.
    final canAccessChecklists = emp?.canViewDepartment('kitchen') ?? false;
    final canEdit = canAccessChecklists;

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
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.getLocalizedName(lang))))
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
                ...KitchenSection.values.map((s) => DropdownMenuItem(value: s.code, child: Text(s.getLocalizedName(lang)))),
              ],
              onChanged: canEdit ? (v) {
                setState(() => _checklist = _checklist?.copyWith(assignedSection: v));
              } : null,
            ),
            if (canEdit) ...[
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_type == ChecklistType.prep)
                    SizedBox(
                      width: 160,
                      child: InkWell(
                        onTap: _showSelectPfDropdown,
                        borderRadius: BorderRadius.circular(4),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: loc.t('select_pf') ?? 'Выбрать ПФ',
                            suffixIcon: Icon(Icons.keyboard_arrow_down, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            border: const OutlineInputBorder(),
                          ),
                          isEmpty: true,
                          child: const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  if (_type == ChecklistType.prep) const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _newItemController,
                      decoration: InputDecoration(
                        labelText: loc.t('add_item'),
                        hintText: _type == ChecklistType.tasks
                            ? (loc.t('checklist_item_hint') ?? 'Введите наименование')
                            : (loc.t('checklist_item_prep_hint') ?? 'Введите своё или выберите ПФ'),
                      ),
                      onSubmitted: (_) {
                        if (_type == ChecklistType.prep && _newItemController.text.trim().isNotEmpty) {
                          _showQuantityDialog(title: _newItemController.text.trim());
                        } else {
                          _addItem();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      if (_type == ChecklistType.prep && _newItemController.text.trim().isNotEmpty) {
                        _showQuantityDialog(title: _newItemController.text.trim());
                      } else {
                        _addItem();
                      }
                    },
                    icon: const Icon(Icons.add),
                    tooltip: loc.t('add_item'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ...List.generate(_items.length, (i) {
              final it = _items[i];
              final lang = loc.currentLanguageCode;
              // Resolve PF display name from tech cards list if available
              final techCard = it.techCardId != null
                  ? _techCards.where((tc) => tc.id == it.techCardId).firstOrNull
                  : null;
              final displayTitle = techCard != null
                  ? techCard.getDisplayNameInLists(lang)
                  : it.title;
              // Build localized quantity label
              String? localizedQuantityLabel;
              if (it.targetQuantity != null) {
                final qty = it.targetQuantity! == it.targetQuantity!.truncateToDouble()
                    ? it.targetQuantity!.toInt().toString()
                    : it.targetQuantity!.toStringAsFixed(1);
                final unit = it.targetUnit?.isNotEmpty == true
                    ? ' ${CulinaryUnits.displayName(it.targetUnit!, lang)}'
                    : '';
                localizedQuantityLabel = '$qty$unit';
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: it.techCardId != null
                      ? Icon(Icons.link, size: 20, color: Theme.of(context).colorScheme.primary)
                      : null,
                  title: Text(displayTitle),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.techCardId != null)
                        Text(loc.t('ttk_pf') ?? 'ТТК ПФ', style: Theme.of(context).textTheme.labelSmall),
                      if (localizedQuantityLabel != null)
                        GestureDetector(
                          onTap: canEdit ? () => _editItemQuantity(i) : null,
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              localizedQuantityLabel,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        )
                      else if (canEdit && (it.techCardId != null || _type == ChecklistType.prep))
                        GestureDetector(
                          onTap: () => _editItemQuantity(i),
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              loc.t('checklist_add_quantity') ?? '+ кол-во',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
