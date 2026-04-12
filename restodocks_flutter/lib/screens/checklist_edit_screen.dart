import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/translation.dart';
import '../services/app_toast_service.dart';
import '../services/screen_layout_preference_service.dart';
import '../services/services.dart';
import '../utils/translit_utils.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/time_picker_field.dart';

/// Редактирование чеклиста-шаблона. Сохранить, создать по аналогии, удалить.
class ChecklistEditScreen extends StatefulWidget {
  const ChecklistEditScreen(
      {super.key,
      required this.checklistId,
      this.viewOnly = false,
      this.initialDepartment = 'kitchen'});

  final String checklistId;

  /// Режим только просмотра (например по ссылке из входящих «чеклист не выполнен»).
  final bool viewOnly;

  /// Для checklistId='new' — подразделение при создании.
  final String initialDepartment;

  @override
  State<ChecklistEditScreen> createState() => _ChecklistEditScreenState();
}

class _ChecklistEditScreenState extends State<ChecklistEditScreen>
    with
        AutoSaveMixin<ChecklistEditScreen>,
        InputChangeListenerMixin<ChecklistEditScreen> {
  Checklist? _checklist;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<TechCard> _techCards = [];
  late final TextEditingController _nameController;
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
  List<Employee> _employees = [];

  /// null или пусто = всем
  List<String> _selectedEmployeeIds = [];
  bool _deadlineEnabled = false;
  DateTime? _deadline;

  /// Тумблер «указать время» для срока выполнения (по умолчанию выключен — только дата).
  bool _deadlineWithTime = false;
  ChecklistReminderConfig _reminderConfig = const ChecklistReminderConfig();

  bool get _isNew => widget.checklistId == 'new';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      final emp = acc.currentEmployee;
      final svc = context.read<ChecklistServiceSupabase>();
      final techSvc = context.read<TechCardServiceSupabase>();
      Checklist? c;
      if (!_isNew) {
        c = await svc.getChecklistById(widget.checklistId);
      } else if (est != null && emp != null) {
        final now = DateTime.now();
        c = Checklist(
          id: 'new',
          establishmentId: est.id,
          createdBy: emp.id,
          name: '',
          items: [],
          createdAt: now,
          updatedAt: now,
          assignedDepartment: widget.initialDepartment,
        );
      }
      List<TechCard> techs = [];
      List<Employee> emps = [];
      if (est != null) {
        techs =
            await techSvc.getTechCardsForEstablishment(est.dataEstablishmentId);
        emps = await acc.getEmployeesForEstablishment(est.id);
      }
      if (!mounted) return;
      // Персонал и ТТК — только по подразделению чеклиста
      final dept = c?.assignedDepartment ?? widget.initialDepartment;
      final filteredEmps = emps.where((e) {
        if (dept == 'hall')
          return e.department == 'hall' || e.department == 'dining_room';
        return e.department == dept;
      }).toList();
      const barCats = {
        'beverages',
        'alcoholic_cocktails',
        'non_alcoholic_drinks',
        'hot_drinks',
        'drinks_pure',
        'snacks'
      };
      final filteredTechs = dept == 'bar'
          ? techs
              .where((t) =>
                  barCats.contains(t.category) ||
                  t.sections.contains('bar') ||
                  t.sections.contains('all'))
              .toList()
          : dept == 'hall' || dept == 'dining_room'
              ? techs
              : techs
                  .where((t) =>
                      !barCats.contains(t.category) ||
                      t.sections.contains('all'))
                  .toList();
      if (widget.viewOnly && c != null && mounted) {
        final estId = context.read<AccountManagerSupabase>().establishment?.id;
        context.read<InboxViewedService>().addViewed(estId, widget.checklistId);
      }
      setState(() {
        _checklist = c;
        _techCards = filteredTechs.isNotEmpty ? filteredTechs : techs;
        _employees = filteredEmps.isNotEmpty ? filteredEmps : emps;
        _loading = false;
        if (c != null) {
          _nameController.text = c.name;
          _type = c.type ?? ChecklistType.tasks;
          _actionHasNumeric = c.actionConfig.hasNumeric;
          _actionHasToggle = c.actionConfig.hasToggle;
          _actionDropdownOptions =
              List.from(c.actionConfig.dropdownOptions ?? []);
          _dropdownOptionsController.text = _actionDropdownOptions.join(', ');
          if (_items.length <= c.items.length) {
            _items
              ..clear()
              ..addAll(c.items);
          }
          final ids = c.assignedEmployeeIds;
          if (ids != null && ids.isNotEmpty) {
            _selectedEmployeeIds = List.from(ids);
          } else if (c.assignedEmployeeId != null &&
              c.assignedEmployeeId!.isNotEmpty) {
            _selectedEmployeeIds = [c.assignedEmployeeId!];
          } else {
            _selectedEmployeeIds = [];
          }
          _deadlineEnabled = c.deadlineAt != null;
          _deadline = c.deadlineAt;
          final dt = c.deadlineAt;
          _deadlineWithTime = dt != null && (dt.hour != 0 || dt.minute != 0);
          _reminderConfig = c.reminderConfig ?? const ChecklistReminderConfig();
        }
      });
      _ensureTechCardTranslations(techSvc, techs);
      if (mounted) await restoreDraftNow();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _ensureTechCardTranslations(
      TechCardServiceSupabase svc, List<TechCard> cards) async {
    if (!mounted) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (lang == 'ru') return;
    final missing = cards
        .where(
          (tc) => !(tc.dishNameLocalized?.containsKey(lang) == true &&
              (tc.dishNameLocalized![lang]?.trim().isNotEmpty ?? false)),
        )
        .toList();
    for (final tc in missing) {
      if (!mounted) break;
      try {
        final translated = await svc
            .translateTechCardName(tc.id, tc.dishName, lang)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (translated != null && mounted) {
          final idx = _techCards.indexWhere((c) => c.id == tc.id);
          if (idx >= 0) {
            final updated = _techCards[idx].copyWith(
              dishNameLocalized: {
                ...(_techCards[idx].dishNameLocalized ?? {}),
                lang: translated
              },
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
  bool get restoreDraftAfterLoad => true;

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'checklistId': widget.checklistId,
      'name': _nameController.text,
      'type': _type.code,
      'actionHasNumeric': _actionHasNumeric,
      'actionHasToggle': _actionHasToggle,
      'actionDropdownOptions': _actionDropdownOptions,
      'selectedEmployeeIds': _selectedEmployeeIds,
      'deadlineEnabled': _deadlineEnabled,
      'deadline': _deadline?.toIso8601String(),
      'deadlineWithTime': _deadlineWithTime,
      'reminderConfig': _reminderConfig.toJson(),
      'items': _items
          .map((item) => {
                'id': item.id,
                'title': item.title,
                'sortOrder': item.sortOrder,
                'techCardId': item.techCardId,
                'targetQuantity': item.targetQuantity,
                'targetUnit': item.targetUnit,
                'imageUrl': item.imageUrl,
              })
          .toList(),
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (data['checklistId'] != widget.checklistId) return;

    setState(() {
      _nameController.text = data['name'] ?? '';
      _type = ChecklistType.fromCode(data['type'] as String?) ??
          ChecklistType.tasks;
      _actionHasNumeric = data['actionHasNumeric'] == true;
      _actionHasToggle = data['actionHasToggle'] != false;
      _actionDropdownOptions = List<String>.from(
          data['actionDropdownOptions'] as List<dynamic>? ?? []);
      _selectedEmployeeIds = List<String>.from(
          data['selectedEmployeeIds'] as List<dynamic>? ?? []);
      _deadlineEnabled = data['deadlineEnabled'] == true;
      _deadline = data['deadline'] != null
          ? DateTime.tryParse(data['deadline'] as String)
          : null;
      _deadlineWithTime = data['deadlineWithTime'] == true;
      final rc = data['reminderConfig'];
      _reminderConfig = rc is Map
          ? ChecklistReminderConfig.fromJson(Map<String, dynamic>.from(rc))
          : const ChecklistReminderConfig();
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
          imageUrl: itemMap['imageUrl'] as String?,
        ));
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newItemController.dispose();
    _dropdownOptionsController.dispose();
    _newItemQtyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = _checklist;
    if (c == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context
                      .read<LocalizationService>()
                      .t('checklist_not_found') ??
                  'Чеклист не найден')),
        );
      }
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context
                .read<LocalizationService>()
                .t('checklist_name_required'))),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
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
    final empIds = _selectedEmployeeIds.isEmpty ? null : _selectedEmployeeIds;
    // Дата без времени — сохраняем как UTC-полночь, чтобы при парсинге hour/minute были 0
    final deadlineVal = _deadlineEnabled && _deadline != null
        ? (_deadlineWithTime
            ? _deadline
            : DateTime.utc(_deadline!.year, _deadline!.month, _deadline!.day))
        : null;
    if (_reminderConfig.recurrenceEnabled && _reminderConfig.weekdays.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context
                  .read<LocalizationService>()
                  .t('checklist_weekdays_required'))),
        );
      }
      setState(() => _saving = false);
      return;
    }
    final reminderToSave = _normalizeReminderForSave();
    final itemsForSave = _items
        .map((e) => ChecklistItem.template(
              title: e.title,
              sortOrder: e.sortOrder,
              techCardId: e.techCardId,
              targetQuantity: e.targetQuantity,
              targetUnit: e.targetUnit,
              imageUrl: e.imageUrl,
            ))
        .toList();
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final translationManager = context.read<TranslationManager>();
      final loc = context.read<LocalizationService>();
      final emp = context.read<AccountManagerSupabase>().currentEmployee;
      final String savedId;
      final String dept;
      if (_isNew) {
        final created = await svc.createChecklist(
          establishmentId: c.establishmentId,
          createdBy: c.createdBy,
          name: name,
          items: itemsForSave,
          assignedSection: c.assignedSection,
          assignedSectionIds: c.effectiveSectionIds,
          assignedEmployeeId: empIds?.length == 1 ? empIds!.first : null,
          assignedEmployeeIds: empIds,
          deadlineAt: deadlineVal,
          scheduledForAt: null,
          reminderConfig: reminderToSave,
          type: _type,
          actionConfig: actionConfig,
          assignedDepartment: c.assignedDepartment,
        );
        savedId = created.id;
        dept = created.assignedDepartment;
      } else {
        final updated = c.copyWith(
          name: name,
          additionalName: null,
          type: _type,
          actionConfig: actionConfig,
          assignedSection: c.assignedSection,
          assignedSectionIds: c.assignedSectionIds,
          assignedEmployeeIds: empIds,
          assignedEmployeeId: empIds?.length == 1 ? empIds!.first : null,
          deadlineAt: deadlineVal,
          scheduledForAt: null,
          reminderConfig: reminderToSave,
          items: _items
              .map((e) => ChecklistItem(
                    id: e.id,
                    checklistId: c.id,
                    title: e.title,
                    sortOrder: e.sortOrder,
                    techCardId: e.techCardId,
                    targetQuantity: e.targetQuantity,
                    targetUnit: e.targetUnit,
                    imageUrl: e.imageUrl,
                  ))
              .toList(),
        );
        await svc.saveChecklist(updated);
        savedId = updated.id;
        dept = updated.assignedDepartment;
      }
      // Переводим название и пункты чеклиста фоново (поля name, item_<id> — те же, что при отображении)
      final sourceLang = loc.currentLanguageCode;
      final persisted = await svc.getChecklistById(savedId);
      final fieldsToTranslate = <String, String>{'name': name};
      if (persisted != null) {
        for (final it in persisted.items) {
          final t = it.title.trim();
          if (t.isNotEmpty) fieldsToTranslate['item_${it.id}'] = t;
        }
      } else {
        for (var i = 0; i < _items.length; i++) {
          final t = _items[i].title.trim();
          if (t.isNotEmpty) fieldsToTranslate['item_$i'] = t;
        }
      }
      translationManager.handleEntitySave(
        entityType: TranslationEntityType.checklist,
        entityId: savedId,
        textFields: fieldsToTranslate,
        sourceLanguage: sourceLang,
        userId: emp?.id,
      );
      if (mounted) {
        // Для нового чеклиста показываем явное подтверждение создания.
        final toastText =
            _isNew ? loc.t('checklist_created') : loc.t('saved');
        AppToastService.show(toastText, duration: const Duration(seconds: 4));
        clearDraft();
        context.go('/checklists?department=$dept&refresh=1');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context
                  .read<LocalizationService>()
                  .t('error_with_message')
                  .replaceAll('%s', e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _duplicate() async {
    final c = _checklist;
    if (c == null || _isNew) return;
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null) return;
    try {
      final svc = context.read<ChecklistServiceSupabase>();
      final created = await svc.duplicateChecklist(c, emp.id);
      if (mounted) {
        AppToastService.show(context
            .read<LocalizationService>()
            .t('checklist_created_duplicate'));
        context.pushReplacement('/checklists/${created.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context
                  .read<LocalizationService>()
                  .t('error_with_message')
                  .replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  Future<void> _delete() async {
    if (_isNew) return;
    final loc = context.read<LocalizationService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('delete')),
        content: Text(
            context.read<LocalizationService>().t('checklist_delete_confirm')),
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
          SnackBar(
              content: Text(context
                  .read<LocalizationService>()
                  .t('error_with_message')
                  .replaceAll('%s', e.toString()))),
        );
      }
    }
  }

  void _addItem(
      {String? title,
      String? techCardId,
      double? targetQuantity,
      String? targetUnit}) {
    final t = title ?? _newItemController.text.trim();
    if (t.isEmpty) return;
    final qty = targetQuantity ??
        double.tryParse(_newItemQtyController.text.trim().replaceAll(',', '.'));
    final unit = targetUnit ??
        (_newItemQtyController.text.trim().isNotEmpty ? _newItemUnit : null);
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
                    child: Text(loc.t('select_pf'),
                        style: Theme.of(context).textTheme.titleMedium),
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
              Text(
                  loc.t('checklist_item_quantity_hint'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_quantity'),
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
                        labelText: loc.t('unit'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: units
                          .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(CulinaryUnits.displayName(u, lang))))
                          .toList(),
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
              child: Text(loc.t('skip')),
            ),
            FilledButton(
              onPressed: () {
                final qty =
                    double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
                Navigator.of(ctx).pop();
                _addItem(
                    title: title,
                    techCardId: techCardId,
                    targetQuantity: qty,
                    targetUnit: qty != null ? selectedUnit : null);
              },
              child: Text(loc.t('add_item')),
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
    final qtyCtrl =
        TextEditingController(text: item.targetQuantity?.toString() ?? '');
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: loc.t('checklist_quantity'),
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
                        labelText: loc.t('unit'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: units
                          .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text(CulinaryUnits.displayName(u, lang))))
                          .toList(),
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
                  setState(() => _items[index] =
                      item.copyWith(targetQuantity: null, targetUnit: null));
                  scheduleSave();
                },
                child: Text(loc.t('delete')),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('back')),
            ),
            FilledButton(
              onPressed: () {
                final qty =
                    double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.'));
                Navigator.of(ctx).pop();
                setState(() => _items[index] = item.copyWith(
                      targetQuantity: qty,
                      targetUnit: qty != null ? selectedUnit : null,
                    ));
                scheduleSave();
              },
              child: Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _openItemPhotoPreview(String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            u,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Padding(
              padding: EdgeInsets.all(24),
              child: Icon(Icons.broken_image_outlined, size: 64),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickItemPhoto(int index) async {
    final loc = context.read<LocalizationService>();
    final est = context.read<AccountManagerSupabase>().establishment;
    if (est == null || !mounted) return;
    final item = _items[index];
    final svc = context.read<ChecklistServiceSupabase>();
    final imageService = ImageService();

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(loc.t('photo_from_camera')),
              onTap: () => Navigator.of(ctx).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(loc.t('photo_from_gallery')),
              onTap: () => Navigator.of(ctx).pop('gallery'),
            ),
            if (item.imageUrl != null && item.imageUrl!.trim().isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text(loc.t('delete')),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'remove') {
      setState(() => _items[index] = item.copyWith(imageUrl: null));
      scheduleSave();
      return;
    }
    final source =
        action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final xFile = source == ImageSource.camera
        ? await imageService.takePhotoWithCamera()
        : await imageService.pickImageFromGallery();
    if (xFile == null || !mounted) return;
    final bytes = await imageService.xFileToBytes(xFile);
    if (bytes == null || bytes.isEmpty || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final url = await svc.uploadChecklistItemPhoto(
      establishmentId: est.dataEstablishmentId,
      bytes: bytes,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('photo_upload_error'))),
      );
      return;
    }
    setState(() => _items[index] = item.copyWith(imageUrl: url.trim()));
    scheduleSave();
  }

  Widget _buildSectionSelector(
      LocalizationService loc, String lang, bool canEdit) {
    final ids = _checklist?.effectiveSectionIds ?? const <String>[];
    final label = ids.isEmpty
        ? (loc.t('checklist_section_all'))
        : '${ids.length} ${loc.t('checklist_section')}';
    return InkWell(
      onTap: canEdit ? () => _showSectionPicker(loc, lang, canEdit) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: loc.t('section'),
          hintText: loc.t('checklist_section_select'),
          border: const OutlineInputBorder(),
          suffixIcon: canEdit
              ? Icon(Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
        child: Text(label),
      ),
    );
  }

  Future<void> _showSectionPicker(
      LocalizationService loc, String lang, bool canEdit) async {
    final selected = List<String>.from(_checklist?.effectiveSectionIds ?? []);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          return AlertDialog(
            title: Text(loc.t('section')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Radio<bool>(
                      value: true,
                      groupValue: selected.isEmpty,
                      onChanged: (_) => setInner(() => selected.clear()),
                    ),
                    title: Text(loc.t('checklist_section_all')),
                    onTap: () => setInner(() => selected.clear()),
                  ),
                  ...KitchenSection.values.map((s) {
                    final isSelected = selected.contains(s.code);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: canEdit
                          ? (v) {
                              setInner(() {
                                if (v == true) {
                                  selected.add(s.code);
                                } else {
                                  selected.remove(s.code);
                                }
                              });
                            }
                          : null,
                      title: Text(s.getLocalizedName(lang)),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(loc.t('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(loc.t('save'))),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        final sorted = List<String>.from(selected)..sort();
        _checklist = _checklist?.copyWith(
          assignedSectionIds: sorted,
          assignedSection: sorted.isEmpty ? null : sorted.first,
        );
        scheduleSave();
      });
    }
  }

  Widget _buildEmployeeSelector(
      LocalizationService loc, String lang, bool canEdit) {
    final label = _selectedEmployeeIds.isEmpty
        ? loc.t('checklist_employee_all')
        : '${_selectedEmployeeIds.length} ${loc.t('checklist_employee')}';
    return InkWell(
      onTap: canEdit ? () => _showEmployeePicker(loc, lang, canEdit) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: loc.t('checklist_employee'),
          hintText: loc.t('checklist_employee_select'),
          border: const OutlineInputBorder(),
          suffixIcon: canEdit
              ? Icon(Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
        child: Text(label),
      ),
    );
  }

  Future<void> _showEmployeePicker(
      LocalizationService loc, String lang, bool canEdit) async {
    final selected = List<String>.from(_selectedEmployeeIds);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          return AlertDialog(
            title: Text(loc.t('checklist_employee')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: Radio<bool>(
                      value: true,
                      groupValue: selected.isEmpty,
                      onChanged: (_) => setInner(() => selected.clear()),
                    ),
                    title: Text(loc.t('checklist_employee_all')),
                    onTap: () => setInner(() => selected.clear()),
                  ),
                  ..._employees.map((e) {
                    final isSelected = selected.contains(e.id);
                    final rolesDisplay =
                        e.roles.map((r) => loc.roleDisplayName(r)).join(', ');
                    final displayName = ctx
                            .read<ScreenLayoutPreferenceService>()
                            .showNameTranslit
                        ? cyrillicToLatin(e.fullName)
                        : e.fullName;
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: canEdit
                          ? (v) {
                              setInner(() {
                                if (v == true)
                                  selected.add(e.id);
                                else
                                  selected.remove(e.id);
                              });
                            }
                          : null,
                      title: Text(displayName,
                          style: Theme.of(ctx).textTheme.bodyMedium),
                      subtitle: Text(
                        rolesDisplay.isNotEmpty
                            ? rolesDisplay
                            : (loc.t('employee')),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(loc.t('cancel'))),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(loc.t('save'))),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _selectedEmployeeIds = selected;
        scheduleSave();
      });
    }
  }

  ChecklistReminderConfig? _normalizeReminderForSave() {
    var r = _reminderConfig;
    if (!r.hasAny) return null;

    // Если повторение выключено — чистим поля повторения.
    if (!r.recurrenceEnabled) {
      r = r.copyWith(
        recurrenceKind: ChecklistRecurrenceKind.none,
        dailyTimes: const [],
        weekdays: const [],
        everyNWeeks: 1,
        recurrenceEndDate: null,
      );
    } else {
      var times = List<String>.from(r.dailyTimes)
          .map((t) => t.trim())
          .where((t) => RegExp(r'^\d{2}:\d{2}$').hasMatch(t))
          .toSet()
          .toList()
        ..sort();
      if (r.recurrenceKind == ChecklistRecurrenceKind.multiDaily &&
          times.isEmpty) {
        times = ['09:00'];
      }
      var kind = ChecklistRecurrenceKind.none;
      if (r.weekdays.isNotEmpty) {
        kind = ChecklistRecurrenceKind.weekdays;
      } else if (times.isNotEmpty) {
        kind = ChecklistRecurrenceKind.multiDaily;
      }
      r = r.copyWith(
        recurrenceKind: kind,
        dailyTimes: times,
        useSpecificTime: times.isNotEmpty ? false : r.useSpecificTime,
      );
    }
    // Если уведомления выключены — не держим специфичное время.
    if (!r.enabled) {
      r = r.copyWith(useSpecificTime: false);
    }
    return r;
  }

  String _weekdayLetter(int iso, String lang) =>
      DateFormat.E(lang == 'ru' ? 'ru' : 'en').format(DateTime(2024, 1, iso));

  Future<void> _addMultiDailyTime() async {
    final t = await _pickTimeLikeIos(
      initialHour: _reminderConfig.hour,
      initialMinute: _reminderConfig.minute,
    );
    if (t == null || !mounted) return;
    final s =
        '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';
    setState(() {
      final list = List<String>.from(_reminderConfig.dailyTimes);
      if (!list.contains(s)) list.add(s);
      list.sort();
      _reminderConfig = _reminderConfig.copyWith(dailyTimes: list);
      scheduleSave();
    });
  }

  Future<(int, int)?> _pickTimeLikeIos({
    required int initialHour,
    required int initialMinute,
  }) async {
    DateTime selected = DateTime(
        2024, 1, 1, initialHour.clamp(0, 23), initialMinute.clamp(0, 59));
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 240,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: selected,
                  onDateTimeChanged: (d) => selected = d,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child:
                          Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(selected),
                      child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return null;
    return (result.hour, result.minute);
  }

  Widget _buildDeadlineRow(LocalizationService loc, String lang, bool canEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: _deadlineEnabled,
              onChanged: canEdit
                  ? (v) => setState(() {
                        _deadlineEnabled = v;
                        if (v && _deadline == null) _deadline = DateTime.now();
                        scheduleSave();
                      })
                  : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(loc.t('checklist_complete_by')),
            ),
          ],
        ),
        if (_deadlineEnabled && canEdit) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final loc = context.read<LocalizationService>();
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _deadline ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: Locale(loc.currentLanguageCode == 'en'
                          ? 'en_GB'
                          : loc.currentLanguageCode),
                    );
                    if (date != null && mounted) {
                      setState(() {
                        final d = _deadline ?? DateTime.now();
                        _deadline = DateTime(
                            date.year, date.month, date.day, d.hour, d.minute);
                        scheduleSave();
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), isDense: true),
                    child: Text(_deadline != null
                        ? '${_deadline!.day.toString().padLeft(2, '0')}.${_deadline!.month.toString().padLeft(2, '0')}.${_deadline!.year}'
                        : '—'),
                  ),
                ),
              ),
              if (_deadlineWithTime) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TimePickerField(
                    label: loc.t('time'),
                    value: _deadline != null
                        ? '${_deadline!.hour.toString().padLeft(2, '0')}:${_deadline!.minute.toString().padLeft(2, '0')}'
                        : '00:00',
                    onChanged: (s) {
                      final parts = s.split(':');
                      if (parts.length >= 2 && mounted) {
                        final h = int.tryParse(parts[0]) ?? 0;
                        final m = int.tryParse(parts[1]) ?? 0;
                        setState(() {
                          final d = _deadline ?? DateTime.now();
                          _deadline = DateTime(d.year, d.month, d.day,
                              h.clamp(0, 23), m.clamp(0, 59));
                          scheduleSave();
                        });
                      }
                    },
                    enabled: canEdit,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: _deadlineWithTime,
                onChanged: canEdit
                    ? (v) => setState(() {
                          _deadlineWithTime = v;
                          if (!v && _deadline != null) {
                            _deadline = DateTime(_deadline!.year,
                                _deadline!.month, _deadline!.day);
                          }
                          scheduleSave();
                        })
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 16),
              Expanded(
                  child:
                      Text(loc.t('checklist_include_time'))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRecurrenceRow(
      LocalizationService loc, String lang, bool canEdit) {
    final hasMultiDaily = _reminderConfig.dailyTimes.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: _reminderConfig.recurrenceEnabled,
              onChanged: canEdit
                  ? (v) => setState(() {
                        // Повторение отдельно от уведомления: выключение не сбрасывает настройки уведомления.
                        var next =
                            _reminderConfig.copyWith(recurrenceEnabled: v);
                        if (v &&
                            next.recurrenceKind ==
                                ChecklistRecurrenceKind.none) {
                          next = next.copyWith(
                              recurrenceKind: ChecklistRecurrenceKind.weekdays);
                        }
                        if (v &&
                            next.recurrenceKind ==
                                ChecklistRecurrenceKind.multiDaily &&
                            next.dailyTimes.isEmpty) {
                          next = next.copyWith(dailyTimes: ['09:00']);
                        }
                        if (!v) {
                          next = next.copyWith(
                            recurrenceKind: ChecklistRecurrenceKind.none,
                            dailyTimes: const [],
                            weekdays: const [],
                            everyNWeeks: 1,
                            recurrenceEndDate: null,
                          );
                        }
                        _reminderConfig = next;
                        scheduleSave();
                      })
                  : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(loc.t('checklist_recurrence'))),
          ],
        ),
        if (_reminderConfig.recurrenceEnabled && canEdit) ...[
          const SizedBox(height: 8),
          Text(loc.t('checklist_weekdays_pick'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: List.generate(7, (i) {
              final day = i + 1;
              final sel = _reminderConfig.weekdays.contains(day);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 6 ? 4 : 0),
                  child: FilterChip(
                    showCheckmark: false,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: EdgeInsets.zero,
                    label: SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          _weekdayLetter(day, lang),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    selected: sel,
                    onSelected: canEdit
                        ? (v) {
                            setState(() {
                              final w =
                                  List<int>.from(_reminderConfig.weekdays);
                              if (v) {
                                if (!w.contains(day)) w.add(day);
                              } else {
                                w.remove(day);
                              }
                              w.sort();
                              _reminderConfig =
                                  _reminderConfig.copyWith(weekdays: w);
                              scheduleSave();
                            });
                          }
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(loc.t('checklist_every_n_weeks')),
              SizedBox(
                width: 92,
                child: DropdownButtonFormField<int>(
                  value: _reminderConfig.everyNWeeks.clamp(1, 8),
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: List.generate(
                    8,
                    (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                  ),
                  onChanged: canEdit
                      ? (n) {
                          if (n == null) return;
                          setState(() {
                            _reminderConfig =
                                _reminderConfig.copyWith(everyNWeeks: n);
                            scheduleSave();
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: hasMultiDaily,
                onChanged: canEdit
                    ? (v) => setState(() {
                          _reminderConfig = _reminderConfig.copyWith(
                            dailyTimes: v
                                ? (_reminderConfig.dailyTimes.isEmpty
                                    ? ['09:00']
                                    : List<String>.from(
                                        _reminderConfig.dailyTimes))
                                : const [],
                          );
                          scheduleSave();
                        })
                    : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(loc.t('checklist_recurrence_multi_daily'))),
            ],
          ),
          if (hasMultiDaily) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._reminderConfig.dailyTimes.map((t) {
                  return InputChip(
                    label: Text(t),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: canEdit
                        ? () {
                            setState(() {
                              final list =
                                  List<String>.from(_reminderConfig.dailyTimes)
                                    ..remove(t);
                              _reminderConfig =
                                  _reminderConfig.copyWith(dailyTimes: list);
                              scheduleSave();
                            });
                          }
                        : null,
                  );
                }),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: Text(loc.t('checklist_add_time')),
                  onPressed: canEdit ? _addMultiDailyTime : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: canEdit
                      ? () async {
                          final l = context.read<LocalizationService>();
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _reminderConfig.recurrenceEndDate ??
                                DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: Locale(l.currentLanguageCode == 'en'
                                ? 'en_GB'
                                : l.currentLanguageCode),
                          );
                          if (!mounted) return;
                          setState(() {
                            _reminderConfig = _reminderConfig.copyWith(
                              recurrenceEndDate: date != null
                                  ? DateTime(date.year, date.month, date.day)
                                  : _reminderConfig.recurrenceEndDate,
                            );
                            scheduleSave();
                          });
                        }
                      : null,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: loc.t('checklist_recurrence_end_date'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      _reminderConfig.recurrenceEndDate != null
                          ? '${_reminderConfig.recurrenceEndDate!.day.toString().padLeft(2, '0')}.${_reminderConfig.recurrenceEndDate!.month.toString().padLeft(2, '0')}.${_reminderConfig.recurrenceEndDate!.year}'
                          : (loc.t('not_specified')),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: loc.t('clear'),
                onPressed: canEdit && _reminderConfig.recurrenceEndDate != null
                    ? () => setState(() {
                          _reminderConfig =
                              _reminderConfig.copyWith(recurrenceEndDate: null);
                          scheduleSave();
                        })
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNotificationRow(
      LocalizationService loc, String lang, bool canEdit) {
    final showSingleTime = _reminderConfig.dailyTimes.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Switch(
              value: _reminderConfig.enabled,
              onChanged: canEdit
                  ? (v) => setState(() {
                        // Уведомление отдельно от повторения: выключение не сбрасывает расписание.
                        _reminderConfig = _reminderConfig.copyWith(enabled: v);
                        scheduleSave();
                      })
                  : null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(loc.t('checklist_reminder'))),
          ],
        ),
        if (_reminderConfig.enabled && canEdit) ...[
          const SizedBox(height: 8),
          if (showSingleTime) ...[
            Row(
              children: [
                Switch(
                  value: _reminderConfig.useSpecificTime,
                  onChanged: canEdit
                      ? (on) => setState(() {
                            _reminderConfig =
                                _reminderConfig.copyWith(useSpecificTime: on);
                            scheduleSave();
                          })
                      : null,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(loc.t('checklist_reminder_use_time'))),
              ],
            ),
            if (_reminderConfig.useSpecificTime) ...[
              const SizedBox(height: 8),
              TimePickerField(
                label: loc.t('time'),
                value:
                    '${_reminderConfig.hour.toString().padLeft(2, '0')}:${_reminderConfig.minute.toString().padLeft(2, '0')}',
                onChanged: (s) {
                  final parts = s.split(':');
                  if (parts.length >= 2 && mounted) {
                    final h = int.tryParse(parts[0]) ?? 0;
                    final m = int.tryParse(parts[1]) ?? 0;
                    setState(() {
                      _reminderConfig = _reminderConfig.copyWith(
                        hour: h.clamp(0, 23),
                        minute: m.clamp(0, 59),
                      );
                      scheduleSave();
                    });
                  }
                },
                enabled: canEdit,
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                loc.t('checklist_reminder_shift_hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ] else ...[
            Text(
              loc.t('checklist_recurrence_multi_daily'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              loc.t('checklist_reminder_multi_daily_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ],
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
    final canEdit = !widget.viewOnly && canAccessChecklists;

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
                Text(loc.t('checklists_kitchen_only'),
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                    onPressed: () => context.go('/home'),
                    icon: const Icon(Icons.home),
                    label: Text(loc.t('home'))),
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
                Text(_error ?? loc.t('checklist_not_found'),
                    textAlign: TextAlign.center),
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
        actions: const [],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          return Stack(
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
                    if (canEdit)
                      DropdownButtonFormField<ChecklistType>(
                        value: _type,
                        decoration: InputDecoration(
                          labelText: loc.t('checklist_type'),
                        ),
                        items: ChecklistType.values
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.getLocalizedName(lang))))
                            .toList(),
                        onChanged: (v) => setState(() {
                          if (v != null) _type = v;
                          scheduleSave();
                        }),
                      ),
                    if (canEdit) const SizedBox(height: 16),
                    // Цех и сотрудники — на узком экране столбиком, на широком — в одну строку.
                    if (narrow) ...[
                      _buildSectionSelector(loc, lang, canEdit),
                      const SizedBox(height: 12),
                      _buildEmployeeSelector(loc, lang, canEdit),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _buildSectionSelector(loc, lang, canEdit),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEmployeeSelector(loc, lang, canEdit),
                          ),
                        ],
                      ),
                    ],
                    if (canEdit) const SizedBox(height: 12),
                    if (canEdit)
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: loc.t('checklist_item_format_label'),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              dense: true,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              title: Text(
                                  loc.t('checklist_action_numeric')),
                              value: _actionHasNumeric,
                              onChanged: (v) {
                                setState(() {
                                  _actionHasNumeric = v;
                                  scheduleSave();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              dense: true,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              title: Text(loc.t('checklist_action_toggle') ??
                                  'Сделано/не сделано'),
                              value: _actionHasToggle,
                              onChanged: (v) {
                                setState(() {
                                  _actionHasToggle = v;
                                  scheduleSave();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (canEdit) const SizedBox(height: 10),
                    if (canEdit)
                      TextField(
                        controller: _dropdownOptionsController,
                        decoration: InputDecoration(
                          labelText: loc.t('checklist_dropdown_options'),
                          hintText: loc.t('checklist_dropdown_hint_example'),
                        ),
                        onChanged: (_) => scheduleSave(),
                      ),
                    const SizedBox(height: 16),
                    _buildDeadlineRow(loc, lang, canEdit),
                    const SizedBox(height: 12),
                    _buildRecurrenceRow(loc, lang, canEdit),
                    const SizedBox(height: 12),
                    _buildNotificationRow(loc, lang, canEdit),
                    const SizedBox(height: 16),
                    if (canEdit) ...[
                      const SizedBox(height: 24),
                      if (narrow) ...[
                        if (_type == ChecklistType.prep) ...[
                          InkWell(
                            onTap: _showSelectPfDropdown,
                            borderRadius: BorderRadius.circular(4),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: loc.t('select_pf'),
                                suffixIcon: Icon(Icons.keyboard_arrow_down,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                                border: const OutlineInputBorder(),
                              ),
                              isEmpty: true,
                              child: const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newItemController,
                                decoration: InputDecoration(
                                  labelText: loc.t('add_item'),
                                  hintText: _type == ChecklistType.tasks
                                      ? (loc.t('checklist_item_hint'))
                                      : (loc.t('checklist_item_prep_hint')),
                                ),
                                onSubmitted: (_) {
                                  if (_type == ChecklistType.prep &&
                                      _newItemController.text
                                          .trim()
                                          .isNotEmpty) {
                                    _showQuantityDialog(
                                        title: _newItemController.text.trim());
                                  } else {
                                    _addItem();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: () {
                                if (_type == ChecklistType.prep &&
                                    _newItemController.text.trim().isNotEmpty) {
                                  _showQuantityDialog(
                                      title: _newItemController.text.trim());
                                } else {
                                  _addItem();
                                }
                              },
                              icon: const Icon(Icons.add),
                              tooltip: loc.t('add_item'),
                            ),
                          ],
                        ),
                      ] else ...[
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
                                      labelText:
                                          loc.t('select_pf'),
                                      suffixIcon: Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                      border: const OutlineInputBorder(),
                                    ),
                                    isEmpty: true,
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            if (_type == ChecklistType.prep)
                              const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _newItemController,
                                decoration: InputDecoration(
                                  labelText: loc.t('add_item'),
                                  hintText: _type == ChecklistType.tasks
                                      ? (loc.t('checklist_item_hint'))
                                      : (loc.t('checklist_item_prep_hint')),
                                ),
                                onSubmitted: (_) {
                                  if (_type == ChecklistType.prep &&
                                      _newItemController.text
                                          .trim()
                                          .isNotEmpty) {
                                    _showQuantityDialog(
                                        title: _newItemController.text.trim());
                                  } else {
                                    _addItem();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: () {
                                if (_type == ChecklistType.prep &&
                                    _newItemController.text.trim().isNotEmpty) {
                                  _showQuantityDialog(
                                      title: _newItemController.text.trim());
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
                    ],
                    const SizedBox(height: 16),
                    ...List.generate(_items.length, (i) {
                      final it = _items[i];
                      final lang = loc.currentLanguageCode;
                      // Resolve PF display name from tech cards list if available
                      final techCard = it.techCardId != null
                          ? _techCards
                              .where((tc) => tc.id == it.techCardId)
                              .firstOrNull
                          : null;
                      final displayTitle = techCard != null
                          ? techCard.getDisplayNameInLists(lang)
                          : it.title;
                      // Build localized quantity label
                      String? localizedQuantityLabel;
                      if (it.targetQuantity != null) {
                        final qty = it.targetQuantity! ==
                                it.targetQuantity!.truncateToDouble()
                            ? it.targetQuantity!.toInt().toString()
                            : it.targetQuantity!.toStringAsFixed(1);
                        final unit = it.targetUnit?.isNotEmpty == true
                            ? ' ${CulinaryUnits.displayName(it.targetUnit!, lang)}'
                            : '';
                        localizedQuantityLabel = '$qty$unit';
                      }
                      final photoUrl = it.imageUrl?.trim();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: photoUrl != null && photoUrl.isNotEmpty
                              ? InkWell(
                                  onTap: () => _openItemPhotoPreview(photoUrl),
                                  borderRadius: BorderRadius.circular(8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      photoUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => SizedBox(
                                        width: 56,
                                        height: 56,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : (it.techCardId != null
                                  ? Icon(Icons.link,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)
                                  : null),
                          title: Text(displayTitle),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (it.techCardId != null)
                                Text(loc.t('ttk_pf'),
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              if (localizedQuantityLabel != null)
                                GestureDetector(
                                  onTap: canEdit
                                      ? () => _editItemQuantity(i)
                                      : null,
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      localizedQuantityLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSecondaryContainer,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                )
                              else if (canEdit &&
                                  (it.techCardId != null ||
                                      _type == ChecklistType.prep))
                                GestureDetector(
                                  onTap: () => _editItemQuantity(i),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      loc.t('checklist_add_quantity'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: canEdit
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        photoUrl != null &&
                                                photoUrl.isNotEmpty
                                            ? Icons.edit_outlined
                                            : Icons.add_a_photo_outlined,
                                      ),
                                      tooltip: loc.t('checklist_item_photo'),
                                      onPressed: () => _pickItemPhoto(i),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                      onPressed: () => _removeItem(i),
                                      tooltip: loc.t('delete'),
                                    ),
                                  ],
                                )
                              : (photoUrl != null && photoUrl.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.photo_outlined),
                                      tooltip: loc.t('checklist_item_photo'),
                                      onPressed: () =>
                                          _openItemPhotoPreview(photoUrl),
                                    )
                                  : null),
                        ),
                      );
                    }),
                    if (canEdit) ...[
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(loc.t('save')),
                      ),
                    ],
                  ],
                ),
              ),
              DataSafetyIndicator(isVisible: true),
            ],
          );
        },
      ),
    );
  }
}
