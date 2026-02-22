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
  /// Ширина ячейки дня: 7 дней влезают на экран телефона (7 × 36 ≈ 252px).
  static const double _dayCellWidth = 36;
  static const double _rowHeight = 44;

  // Определяем, является ли устройство мобильным
  bool get isMobile => MediaQuery.of(context).size.width < 600;

  final ScrollController _horizontalScrollController = ScrollController();

  ScheduleModel _model = ScheduleModel(
    startDate: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    numWeeks: _defaultWeeks,
  );
  bool _loading = true;
  String? _establishmentId;
  List<Employee> _employees = [];
  bool _showTimeInCells = false; // Показывать время в ячейках графика

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _scrollToCenterToday() {
    if (!_horizontalScrollController.hasClients) return;
    final dates = _model.dates;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    int? todayIndex;
    for (var i = 0; i < dates.length; i++) {
      final d = dates[i];
      if (d.year == todayDate.year && d.month == todayDate.month && d.day == todayDate.day) {
        todayIndex = i;
        break;
      }
    }
    if (todayIndex == null) return;
    final viewportWidth = _horizontalScrollController.position.viewportDimension;
    final scrollOffset = (todayIndex * _dayCellWidth) - (viewportWidth / 2) + (_dayCellWidth / 2);
    final maxScroll = _horizontalScrollController.position.maxScrollExtent;
    _horizontalScrollController.jumpTo(scrollOffset.clamp(0.0, maxScroll));
  }

  /// Убираем дубликаты сотрудников по id (один человек — один слот в графике).
  static List<Employee> _dedupeEmployeesById(List<Employee> list) {
    final seen = <String>{};
    return list.where((e) => seen.add(e.id)).toList();
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
          final raw = employees ?? [];
          _employees = _dedupeEmployeesById(raw);
          _model = model;
          if (_model.sections.isEmpty) {
            _model = _model.copyWith(sections: ScheduleModel.defaultSections);
          }
          final firstSectionId = _model.sections.isNotEmpty ? _model.sections.first.id : '';
          if (_model.slots.isEmpty && _model.sections.isNotEmpty) {
            final slots = _employees.isNotEmpty
                ? _employees.map((e) => ScheduleSlot(
                      id: const Uuid().v4(),
                      name: e.fullName.trim().isEmpty ? 'Повар' : e.fullName.trim(),
                      sectionId: firstSectionId,
                    )).toList()
                : [
                    ScheduleSlot(
                      id: const Uuid().v4(),
                      name: 'Повар',
                      sectionId: firstSectionId,
                    ),
                  ];
            _model = _model.copyWith(slots: slots);
            saveSchedule(est.id, _model);
          } else if (_model.sections.isNotEmpty && _employees.isNotEmpty) {
            final existingNames = _model.slots.map((s) => s.name.trim().toLowerCase()).toSet();
            final toAdd = _employees
                .where((e) {
                  final name = e.fullName.trim().isEmpty ? 'Повар' : e.fullName.trim();
                  return !existingNames.contains(name.toLowerCase());
                })
                .map((e) => ScheduleSlot(
                      id: const Uuid().v4(),
                      name: e.fullName.trim().isEmpty ? 'Повар' : e.fullName.trim(),
                      sectionId: firstSectionId,
                    ))
                .toList();
            if (toAdd.isNotEmpty) {
              _model = _model.copyWith(slots: [..._model.slots, ...toAdd]);
              saveSchedule(est.id, _model);
            }
          }
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToCenterToday();
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

  /// Значение ячейки для отображения: "1" (смена), "0" (выходной) или null (не указано). Устаревшее (имя) считаем сменой.
  String? _cellValue(String slotId, DateTime date) {
    final v = _model.getAssignment(slotId, date);
    if (v == '1' || v == '0') return v;
    if (v != null && v.trim().isNotEmpty) return '1'; // раньше хранили имя — считаем сменой
    return null;
  }

  /// По тапу открываем диалог: смена/выходной + время начала и конца (для почасового учёта).
  void _onCellTap(String slotId, DateTime date) {
    final loc = context.read<LocalizationService>();
    final current = _cellValue(slotId, date);
    final timeStr = _model.getTimeRange(slotId, date);
    String startStr = '09:00';
    String endStr = '21:00';
    if (timeStr != null) {
      final parts = timeStr.split('|');
      if (parts.length >= 2) {
        startStr = parts[0].trim();
        endStr = parts[1].trim();
      }
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => _ScheduleCellDialog(
        date: date,
        initialValue: current ?? '1',
        initialStart: startStr,
        initialEnd: endStr,
        loc: loc,
        onSave: (value, start, end, showTime) {
          setState(() {
            _model = _model.setAssignment(slotId, date, value.isEmpty ? null : value);
            if (value == '1' && showTime && start.isNotEmpty && end.isNotEmpty) {
              _model = _model.setTimeRange(slotId, date, start, end);
            } else {
              _model = _model.setTimeRange(slotId, date, null, null);
            }
            _save();
          });
        },
      ),
    );
  }

  void _submitAssignment(BuildContext ctx, String slotId, DateTime date, String value) {
    Navigator.of(ctx).pop();
    setState(() {
      _model = _model.setAssignment(slotId, date, value.isEmpty ? null : value);
      _save();
    });
  }

  void _showCopyRangeDialog() {
    final loc = context.read<LocalizationService>();
    showDialog<void>(
      context: context,
      builder: (ctx) => _CopyRangeDialog(
        dates: _model.dates,
        slots: _model.slots,
        loc: loc,
        onCopy: (sourceStart, sourceEnd, targetStart, targetEnd, selectedSlots) {
          setState(() {
            // Копируем данные из исходного диапазона в целевой
            for (final slotId in selectedSlots) {
              final sourceDates = _getDatesInRange(sourceStart, sourceEnd);
              final targetDates = _getDatesInRange(targetStart, targetEnd);

              if (sourceDates.length == targetDates.length) {
                for (var i = 0; i < sourceDates.length; i++) {
                  final sourceDate = sourceDates[i];
                  final targetDate = targetDates[i];

                  final assignment = _model.getAssignment(slotId, sourceDate);
                  final timeRange = _model.getTimeRange(slotId, sourceDate);

                  _model = _model.setAssignment(slotId, targetDate, assignment);
                  if (timeRange != null) {
                    final parts = timeRange.split('|');
                    if (parts.length >= 2) {
                      _model = _model.setTimeRange(slotId, targetDate, parts[0].trim(), parts[1].trim());
                    }
                  }
                }
              }
            }
            _save();
          });
        },
      ),
    );
  }

  List<DateTime> _getDatesInRange(DateTime start, DateTime end) {
    final dates = <DateTime>[];
    var current = start;
    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final acc = context.watch<AccountManagerSupabase>();
    final canEdit = acc.currentEmployee?.canEditSchedule ?? false;
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
    final todayDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final headerBg = theme.colorScheme.primary;
    final headerFg = theme.colorScheme.onPrimary;
    final weekendHeaderBg = theme.colorScheme.secondaryContainer;
    final weekendHeaderFg = theme.colorScheme.onSecondaryContainer;
    final todayHighlightBg = theme.colorScheme.primary.withOpacity(0.15);
    final borderColor = theme.dividerColor;

    bool isWeekend(DateTime d) => d.weekday == 6 || d.weekday == 7;
    bool isToday(DateTime d) => d.year == todayDate.year && d.month == todayDate.month && d.day == todayDate.day;

    // Строки таблицы: левая колонка (имена) и правая часть (даты) — чтобы при горизонтальной прокрутке левая колонка оставалась на месте
    final leftCells = <Widget>[];
    final rightRows = <Widget>[];

    Widget leftCell(Widget child, {double? height, BoxDecoration? decoration}) {
      return Container(
        height: height ?? _rowHeight,
        decoration: decoration != null ? BoxDecoration(border: Border(right: BorderSide(color: borderColor))) : null,
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        alignment: Alignment.centerLeft,
        child: child,
      );
    }

    Widget rightCell(Widget child, {Color? bg}) {
      return Container(
        width: _dayCellWidth,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: Border(right: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor)),
        ),
        child: child,
      );
    }

    // Строка 1: заголовок «Дата» + даты
    leftCells.add(leftCell(
      Text(loc.t('schedule_date'), style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 12)),
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg, border: Border(right: BorderSide(color: borderColor))),
    ));
    rightRows.add(Container(
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg),
      child: Row(
        children: dates.map((d) {
          final weekend = isWeekend(d);
          final dayIsToday = isToday(d);
          final bg = dayIsToday ? todayHighlightBg : (weekend ? weekendHeaderBg : headerBg);
          final fg = weekend ? weekendHeaderFg : headerFg;
          return rightCell(
            Text(DateFormat('dd.MM', localeStr).format(d), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
            bg: bg,
          );
        }).toList(),
      ),
    ));

    // Строка 2: «День» + Пн, Вт, ...
    leftCells.add(leftCell(
      Text(loc.t('schedule_day'), style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 11)),
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg, border: Border(right: BorderSide(color: borderColor))),
    ));
    rightRows.add(Container(
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg),
      child: Row(
        children: dates.map((d) {
          final weekend = isWeekend(d);
          final dayIsToday = isToday(d);
          final bg = dayIsToday ? todayHighlightBg : (weekend ? weekendHeaderBg : headerBg);
          final fg = weekend ? weekendHeaderFg : headerFg;
          return rightCell(
            Text(weekdays[d.weekday - 1], textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: fg)),
            bg: bg,
          );
        }).toList(),
      ),
    ));

    for (final section in _model.sections) {
      final sectionSlots = _model.slotsBySection[section.id] ?? [];
      if (sectionSlots.isEmpty) continue;
      final sectionName = loc.translate(section.nameKey);
      final sectionLabel = sectionName == section.nameKey ? section.id : sectionName;
      final sectionBg = theme.colorScheme.secondaryContainer.withOpacity(0.6);
      final sectionFg = theme.colorScheme.onSecondaryContainer;

      // Разделитель цеха: одна единая ячейка (слева — название, справа — одна полоса на все даты, без кучи пустых ячеек)
      leftCells.add(leftCell(
        Text(sectionLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sectionFg), overflow: TextOverflow.ellipsis),
        height: _rowHeight,
        decoration: BoxDecoration(color: sectionBg, border: Border(right: BorderSide(color: borderColor))),
      ));
      rightRows.add(Container(
        width: dates.length * _dayCellWidth,
        height: _rowHeight,
        decoration: BoxDecoration(
          color: sectionBg,
          border: Border(right: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor)),
        ),
      ));

      for (final slot in sectionSlots) {
        leftCells.add(leftCell(
          GestureDetector(
            onTap: canEdit ? () => _editSlot(slot) : null,
            child: Row(
              children: [
                Expanded(child: Text(slot.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                if (canEdit) Icon(Icons.edit, size: 14, color: theme.colorScheme.primary),
              ],
            ),
          ),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3), border: Border(right: BorderSide(color: borderColor))),
        ));
        rightRows.add(Container(
          height: _rowHeight,
          child: Row(
            children: dates.map((date) {
              final val = _cellValue(slot.id, date);
              final isShift = val == '1';
              final isDayOff = val == '0';
              final timeRange = isShift ? _model.getTimeRange(slot.id, date) : null;
              String timeDisplay = '';
              if (timeRange != null) {
                final parts = timeRange.split('|');
                if (parts.length >= 2) timeDisplay = '${parts[0]}–${parts[1]}';
              }
              var bg = isShift ? Colors.green.shade100 : isDayOff ? Colors.amber.shade100 : null;
              if (isToday(date)) {
                final base = bg ?? theme.colorScheme.surface;
                bg = Color.lerp(base, todayHighlightBg, 0.6) ?? base;
              }
              final content = _showTimeInCells && timeDisplay.isNotEmpty ? Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: timeDisplay.split('–').map((time) => Text(
                  time.trim(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )).toList(),
              ) : Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(val ?? '—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: val != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                  if (timeDisplay.isNotEmpty && !_showTimeInCells) Text(timeDisplay, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withOpacity(0.8)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              );
              return rightCell(
                canEdit
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onCellTap(slot.id, date),
                        child: Container(
                          constraints: BoxConstraints(
                            minWidth: isMobile ? 44 : 36,
                            minHeight: isMobile ? 44 : 36,
                          ),
                          child: content,
                        ),
                      )
                    : content,
                bg: bg,
              );
            }).toList(),
          ),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('schedule')),
        actions: [
          if (canEdit) ...[
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _showCopyRangeDialog,
              tooltip: 'Копировать диапазон',
            ),
            IconButton(
              icon: Icon(_showTimeInCells ? Icons.access_time : Icons.access_time_outlined),
              onPressed: () => setState(() => _showTimeInCells = !_showTimeInCells),
              tooltip: _showTimeInCells ? 'Скрыть время' : 'Показать время',
            ),
          ],
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: canEdit
                ? Text(loc.t('schedule_tap_hint'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                : Text(loc.t('schedule_view_only_hint') ?? 'Редактирование графика доступно шеф-повару и су-шефу.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _slotColumnWidth,
                    child: Column(mainAxisSize: MainAxisSize.min, children: leftCells),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: rightRows,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canEdit)
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

class _ScheduleCellDialog extends StatefulWidget {
  const _ScheduleCellDialog({
    required this.date,
    required this.initialValue,
    required this.initialStart,
    required this.initialEnd,
    required this.loc,
    required this.onSave,
  });

  final DateTime date;
  final String initialValue;
  final String initialStart;
  final String initialEnd;
  final LocalizationService loc;
  final void Function(String value, String start, String end, bool showTime) onSave;

  @override
  State<_ScheduleCellDialog> createState() => _ScheduleCellDialogState();
}

class _ScheduleCellDialogState extends State<_ScheduleCellDialog> {
  late String _selectedValue;
  late TextEditingController _startCtrl;
  late TextEditingController _endCtrl;
  late bool _showTime;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.initialValue.isEmpty ? '1' : widget.initialValue;
    _startCtrl = TextEditingController(text: widget.initialStart);
    _endCtrl = TextEditingController(text: widget.initialEnd);
    _showTime = widget.initialStart.isNotEmpty && widget.initialEnd.isNotEmpty;
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.t('schedule_edit_shift'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                ..._buildDialogContent(loc),
                const SizedBox(height: 16),
                ..._buildDialogActions(loc),
              ],
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(loc.t('schedule_edit_shift')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildDialogContent(loc),
        ),
      ),
      actions: _buildDialogActions(loc).map((w) => w).toList(),
    );
  }

  List<Widget> _buildDialogContent(LocalizationService loc) {
    return [
      Text(
        DateFormat('EEEE, d MMM', Localizations.localeOf(context).toString().replaceAll('_', '-')).format(widget.date),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Text(loc.t('schedule_shift_or_day_off'), style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: '1', label: Text(loc.t('schedule_shift')), icon: const Icon(Icons.watch_later, size: 18)),
          ButtonSegment(value: '0', label: Text(loc.t('schedule_day_off')), icon: const Icon(Icons.event_busy, size: 18)),
        ],
        selected: {_selectedValue},
        onSelectionChanged: (s) => setState(() => _selectedValue = s.first),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(loc.t('schedule_time_range'), style: Theme.of(context).textTheme.labelMedium),
          ),
          Switch(
            value: _showTime,
            onChanged: (value) => setState(() => _showTime = value),
          ),
        ],
      ),
      const SizedBox(height: 4),
      if (_showTime) ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startCtrl,
                decoration: InputDecoration(labelText: loc.t('schedule_time_start'), border: const OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.datetime,
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
            Expanded(
              child: TextField(
                controller: _endCtrl,
                decoration: InputDecoration(labelText: loc.t('schedule_time_end'), border: const OutlineInputBorder(), isDense: true),
                keyboardType: TextInputType.datetime,
              ),
            ),
          ],
        )
      ] else Text(
        loc.t('schedule_show_time'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _buildDialogActions(LocalizationService loc) {
    return [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
      FilledButton(
        onPressed: () {
          widget.onSave(_selectedValue, _startCtrl.text.trim(), _endCtrl.text.trim(), _showTime);
          Navigator.of(context).pop();
        },
        child: Text(loc.t('save')),
      ),
    ];
  }
}

class _CopyRangeDialog extends StatefulWidget {
  const _CopyRangeDialog({
    required this.dates,
    required this.slots,
    required this.loc,
    required this.onCopy,
  });

  final List<DateTime> dates;
  final List<ScheduleSlot> slots;
  final LocalizationService loc;
  final void Function(DateTime sourceStart, DateTime sourceEnd, DateTime targetStart, DateTime targetEnd, List<String> selectedSlots) onCopy;

  @override
  State<_CopyRangeDialog> createState() => _CopyRangeDialogState();
}

class _CopyRangeDialogState extends State<_CopyRangeDialog> {
  DateTime? _sourceStart;
  DateTime? _sourceEnd;
  DateTime? _targetStart;
  DateTime? _targetEnd;
  final Set<String> _selectedSlots = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Копировать диапазон графика'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Выберите диапазон для копирования:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DatePickerButton(
                    label: 'От',
                    selectedDate: _sourceStart,
                    dates: widget.dates,
                    onChanged: (date) => setState(() => _sourceStart = date),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DatePickerButton(
                    label: 'До',
                    selectedDate: _sourceEnd,
                    dates: widget.dates,
                    onChanged: (date) => setState(() => _sourceEnd = date),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Выберите диапазон для вставки:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DatePickerButton(
                    label: 'От',
                    selectedDate: _targetStart,
                    dates: widget.dates,
                    onChanged: (date) => setState(() => _targetStart = date),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DatePickerButton(
                    label: 'До',
                    selectedDate: _targetEnd,
                    dates: widget.dates,
                    onChanged: (date) => setState(() => _targetEnd = date),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Выберите сотрудников:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: widget.slots.map((slot) => FilterChip(
                label: Text(slot.name),
                selected: _selectedSlots.contains(slot.id),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSlots.add(slot.id);
                    } else {
                      _selectedSlots.remove(slot.id);
                    }
                  });
                },
              )).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _canCopy ? _copy : null,
          child: const Text('Копировать'),
        ),
      ],
    );
  }

  bool get _canCopy =>
      _sourceStart != null &&
      _sourceEnd != null &&
      _targetStart != null &&
      _targetEnd != null &&
      _selectedSlots.isNotEmpty &&
      _sourceStart!.isBefore(_sourceEnd!) &&
      _targetStart!.isBefore(_targetEnd!);

  void _copy() {
    if (!_canCopy) return;
    widget.onCopy(_sourceStart!, _sourceEnd!, _targetStart!, _targetEnd!, _selectedSlots.toList());
    Navigator.of(context).pop();
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.label,
    required this.selectedDate,
    required this.dates,
    required this.onChanged,
  });

  final String label;
  final DateTime? selectedDate;
  final List<DateTime> dates;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final result = await showDialog<DateTime>(
          context: context,
          builder: (ctx) => _DatePickerDialog(dates: dates, initialDate: selectedDate),
        );
        if (result != null) {
          onChanged(result);
        }
      },
      child: Text(selectedDate != null
          ? DateFormat('d MMM', Localizations.localeOf(context).toString().replaceAll('_', '-')).format(selectedDate!)
          : label),
    );
  }
}

class _DatePickerDialog extends StatelessWidget {
  const _DatePickerDialog({required this.dates, this.initialDate});

  final List<DateTime> dates;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выберите дату'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView.builder(
          itemCount: dates.length,
          itemBuilder: (context, index) {
            final date = dates[index];
            final isSelected = initialDate != null && date.isAtSameMomentAs(initialDate!);
            return ListTile(
              title: Text(DateFormat('EEEE, d MMMM', Localizations.localeOf(context).toString().replaceAll('_', '-')).format(date)),
              selected: isSelected,
              onTap: () => Navigator.of(context).pop(date),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
