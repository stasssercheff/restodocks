import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/schedule_storage_service.dart';
import '../../services/services.dart';

/// График: слоты (должности/имена) задаются вручную, можно выбрать сотрудника из списка или вписать имя.
/// Один график на заведение, прокрутка по неделям (неделя влезает на экран, ограничений нет).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const int _defaultWeeks = 12;
  static const double _slotColumnWidth = 120;
  static const double _dayCellWidth = 44;
  static const double _rowHeight = 44;

  ScheduleModel _model = ScheduleModel(
    startDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    numWeeks: _defaultWeeks,
  );
  bool _loading = true;
  String? _establishmentId;
  List<Employee> _employees = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      if (mounted) setState(() { _loading = false; });
      return;
    }
    setState(() { _loading = true; _establishmentId = est.id; });
    try {
      final employees = await acc.getEmployeesForEstablishment(est.id);
      final model = await loadSchedule(est.id);
      if (mounted) {
        setState(() {
          _employees = employees ?? [];
          _model = model;
          if (_model.sections.isEmpty) {
            _model = _model.copyWith(sections: ScheduleModel.defaultSections);
          }
          if (_model.slots.isEmpty && _model.sections.isNotEmpty) {
            _model = _model.copyWith(
              slots: [
                ScheduleSlot(
                  id: const Uuid().v4(),
                  name: 'Повар',
                  sectionId: _model.sections.first.id,
                ),
              ],
            );
            saveSchedule(est.id, _model);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _save() async {
    if (_establishmentId == null) return;
    await saveSchedule(_establishmentId!, _model);
  }

  void _addSlot() {
    if (_model.sections.isEmpty) return;
    final loc = context.read<LocalizationService>();
    String selectedSectionId = _model.sections.first.id;
    final nameCtrl = TextEditingController(text: 'Повар');
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.t('schedule_add_slot')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.t('schedule_section'), style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: selectedSectionId,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: _model.sections.map((s) {
                  final label = loc.translate(s.nameKey);
                  return DropdownMenuItem(value: s.id, child: Text(label == s.nameKey ? s.id : label));
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedSectionId = v ?? selectedSectionId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: loc.t('schedule_slot_name'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop();
                setState(() {
                  _model = _model.copyWith(
                    slots: [..._model.slots, ScheduleSlot(id: const Uuid().v4(), name: name, sectionId: selectedSectionId)],
                  );
                  _save();
                });
              },
              child: Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  void _editSlot(ScheduleSlot slot) {
    final idx = _model.slots.indexWhere((s) => s.id == slot.id);
    if (idx < 0) return;
    final loc = context.read<LocalizationService>();
    final ctrl = TextEditingController(text: slot.name);
    String? selectedSectionId = slot.sectionId;
    if (selectedSectionId == null || selectedSectionId.isEmpty) selectedSectionId = _model.sections.isNotEmpty ? _model.sections.first.id : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(loc.t('schedule_slot_name')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: selectedSectionId,
                decoration: InputDecoration(labelText: loc.t('schedule_section'), border: const OutlineInputBorder(), isDense: true),
                items: _model.sections.map((s) {
                  final label = loc.translate(s.nameKey);
                  return DropdownMenuItem(value: s.id, child: Text(label == s.nameKey ? s.id : label));
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedSectionId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: loc.t('schedule_slot_name'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            if (_model.slots.length > 1)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(false);
                  setState(() {
                    final newSlots = List<ScheduleSlot>.from(_model.slots)..removeAt(idx);
                    _model = _model.copyWith(slots: newSlots);
                    _save();
                  });
                },
                child: Text(loc.t('delete'), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop(true);
                setState(() {
                  final newSlots = List<ScheduleSlot>.from(_model.slots);
                  newSlots[idx] = newSlots[idx].copyWith(name: name, sectionId: selectedSectionId ?? slot.sectionId);
                  _model = _model.copyWith(slots: newSlots);
                  _save();
                });
              },
              child: Text(loc.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  /// Ключи должностей для выпадающего списка (когда нет/дополнение к сотрудникам).
  static const List<String> _roleKeys = [
    'role_executive_chef', 'role_sous_chef', 'role_cook', 'role_pastry_chef', 'role_confectioner',
    'role_bartender', 'role_waiter', 'role_dishwasher', 'role_grill_cook', 'role_prep_cook',
    'role_baker', 'role_brigadier', 'role_senior_cook', 'role_host',
  ];

  void _onCellTap(String slotId, DateTime date) {
    final loc = context.read<LocalizationService>();
    final current = _model.getAssignment(slotId, date) ?? '';
    final ctrl = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(loc.t('schedule_who_works')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  DateFormat('EEEE, d MMM', Localizations.localeOf(context).toString().replaceAll('_', '-')).format(date),
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: loc.t('schedule_assign_name'),
                    hintText: loc.t('schedule_assign_name_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submitAssignment(ctx, slotId, date, ctrl.text),
                ),
                if (_employees.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(loc.t('schedule_pick_employee'), style: Theme.of(ctx).textTheme.labelMedium),
                  ..._employees.take(10).map((e) => ListTile(
                    dense: true,
                    title: Text(e.fullName),
                    onTap: () => _submitAssignment(ctx, slotId, date, e.fullName),
                  )),
                ],
                const SizedBox(height: 8),
                Text(loc.t('schedule_pick_role'), style: Theme.of(ctx).textTheme.labelMedium),
                ..._roleKeys.map((key) {
                  final label = loc.translate(key);
                  return ListTile(
                    dense: true,
                    title: Text(label == key ? key : label),
                    onTap: () => _submitAssignment(ctx, slotId, date, label == key ? key : label),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => _submitAssignment(ctx, slotId, date, ctrl.text),
              child: Text(loc.t('save')),
            ),
          ],
        );
      },
    );
  }

  void _submitAssignment(BuildContext ctx, String slotId, DateTime date, String value) {
    Navigator.of(ctx).pop();
    setState(() {
      _model = _model.setAssignment(slotId, date, value.isEmpty ? null : value);
      _save();
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final locale = loc.currentLocale;
    final localeStr = '${locale.languageCode}_${locale.countryCode ?? ''}';
    final weekdays = List.generate(7, (i) {
      final d = DateTime.utc(2024, 1, 1).add(Duration(days: i));
      return DateFormat('EEE', localeStr).format(d);
    });

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.t('schedule'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final dates = _model.dates;
    final totalWidth = _slotColumnWidth + dates.length * _dayCellWidth;
    final headerBg = theme.colorScheme.primary;
    final headerFg = theme.colorScheme.onPrimary;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('schedule')),
        actions: [
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              loc.t('schedule_by_role'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  child: Table(
                    border: TableBorder.all(color: theme.dividerColor),
                    columnWidths: {
                      for (var i = 0; i < 1 + dates.length; i++)
                        i: i == 0 ? FixedColumnWidth(_slotColumnWidth) : const FixedColumnWidth(_dayCellWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: headerBg),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Text(
                              loc.t('schedule_role_or_name'),
                              style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 13),
                            ),
                          ),
                          ...dates.map((d) {
                            final isWeekStart = d.weekday == 1;
                            return Container(
                              width: _dayCellWidth,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                              decoration: BoxDecoration(
                                color: isWeekStart ? headerFg.withOpacity(0.15) : null,
                              ),
                              child: Text(
                                '${DateFormat('d', localeStr).format(d)}\n${weekdays[d.weekday - 1]}',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: headerFg),
                                maxLines: 2,
                              ),
                            );
                          }),
                        ],
                      ),
                      ..._model.sections.expand((section) {
                        final sectionSlots = _model.slotsBySection[section.id] ?? [];
                        final sectionName = loc.translate(section.nameKey);
                        final sectionLabel = sectionName == section.nameKey ? section.id : sectionName;
                        final sectionBg = theme.colorScheme.secondaryContainer;
                        final sectionFg = theme.colorScheme.onSecondaryContainer;
                        return [
                          TableRow(
                            decoration: BoxDecoration(color: sectionBg),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                child: Text(
                                  sectionLabel,
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: sectionFg),
                                ),
                              ),
                              ...dates.map((_) => Container(color: sectionBg)),
                            ],
                          ),
                          ...sectionSlots.map((slot) => TableRow(
                            children: [
                              GestureDetector(
                                onTap: () => _editSlot(slot),
                                child: Container(
                                  height: _rowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  alignment: Alignment.centerLeft,
                                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          slot.name,
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
                                    ],
                                  ),
                                ),
                              ),
                              ...dates.map((date) {
                                final who = _model.getAssignment(slot.id, date);
                                return GestureDetector(
                                  onTap: () => _onCellTap(slot.id, date),
                                  child: Container(
                                    height: _rowHeight,
                                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                    alignment: Alignment.center,
                                    child: Text(
                                      who != null && who.isNotEmpty ? who : '—',
                                      style: TextStyle(fontSize: 11, color: who != null && who.isNotEmpty ? null : theme.colorScheme.onSurfaceVariant),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          )),
                        ];
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: _addSlot,
              icon: const Icon(Icons.add, size: 20),
              label: Text(loc.t('schedule_add_slot')),
            ),
          ),
        ],
      ),
    );
  }
}
