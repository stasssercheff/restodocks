import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/schedule_storage_service.dart';
import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

/// График: слоты (должности/имена) задаются вручную, можно выбрать сотрудника из списка или вписать имя.
/// Один график на заведение, прокрутка по неделям (неделя влезает на экран, ограничений нет).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.department = 'all', this.personalOnly = false, this.embedded = false});

  final String department;
  /// Личный график — только строка текущего сотрудника.
  final bool personalOnly;
  /// Вложен в главный экран (вкладка «График») — без кнопки «назад».
  final bool embedded;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const int _defaultWeeks = 1040; // 20 лет — график не должен заканчиваться
  static const double _slotColumnWidth = 120;
  /// Ширина ячейки дня: 7 дней влезают на экран телефона (7 × 36 ≈ 252px).
  static const double _dayCellWidth = 36;
  static const double _rowHeight = 44;

  // Определяем, является ли устройство мобильным
  bool get isMobile => MediaQuery.of(context).size.width < 600;

  final ScrollController _horizontalScrollController = ScrollController();

  ScheduleModel _model = ScheduleModel(
    startDate: DateTime(DateTime.now().year, 1, 1), // Начинаем с 1 января текущего года
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

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _scrollToCenterToday() {
    if (!_horizontalScrollController.hasClients) return;
    final dates = _visibleDates;
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

  /// Убираем дубликаты: один человек (учётная запись) = один слот. По id, затем по email.
  /// Если один email в нескольких записях — оставляем одну (приоритет: с ролью owner, иначе первая).
  static List<Employee> _dedupeEmployeesById(List<Employee> list) {
    final byId = <String, Employee>{};
    final byEmail = <String, Employee>{};
    for (final e in list) {
      if (byId.containsKey(e.id)) continue;
      final emailLower = e.email.trim().toLowerCase();
      if (byEmail.containsKey(emailLower)) {
        final existing = byEmail[emailLower]!;
        if (e.hasRole('owner') && !existing.hasRole('owner')) {
          byEmail[emailLower] = e;
          byId.remove(existing.id);
          byId[e.id] = e;
        }
        continue;
      }
      byId[e.id] = e;
      byEmail[emailLower] = e;
    }
    return byId.values.toList();
  }

  String _slotDisplayName(ScheduleSlot slot) {
    if (slot.employeeId == null) return slot.name;
    final emp = _employees.where((e) => e.id == slot.employeeId).firstOrNull;
    if (emp == null) return slot.name;
    final parts = emp.fullName.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : emp.fullName;
    final surnameLetter = emp.surname?.trim().isNotEmpty == true
        ? ' ${emp.surname!.trim()[0].toUpperCase()}.'
        : (parts.length > 1 ? ' ${parts.last[0].toUpperCase()}.' : '');
    return '$first$surnameLetter'.trim();
  }

  /// Должность для отображения в графике. Собственник — не должность; если есть должность — показываем её (напр. «Шеф»), иначе null.
  String? _slotPosition(ScheduleSlot slot, LocalizationService loc) {
    if (slot.employeeId == null) return null;
    final emp = _employees.where((e) => e.id == slot.employeeId).firstOrNull;
    if (emp == null) return null;
    final pos = emp.positionRole;
    if (pos == null || pos.isEmpty) return null;
    return _positionDisplayName(pos, loc);
  }

  /// Локализованное название должности. Использует ключ role_XXX из переводов.
  String _positionDisplayName(String code, LocalizationService loc) => loc.roleDisplayName(code);

  Employee? _employeeForSlot(ScheduleSlot slot) {
    if (slot.employeeId == null) return null;
    return _employees.where((e) => e.id == slot.employeeId).firstOrNull;
  }

  /// Секции кухни (цеха), без management/bar/hall.
  static const _kitchenSectionIds = {'hot_kitchen', 'cold_kitchen', 'grill', 'pastry', 'prep', 'cleaning', 'pizza', 'sushi', 'bakery'};

  /// Блоки отображения при department='all': Кухня (управление + цеха), Бар (управление + сотрудники), Зал (управление + сотрудники).
  List<({bool isDeptHeader, String deptLabel, String? sectionId, String sectionLabel, List<ScheduleSlot> slots})> _displayBlocks(LocalizationService loc) {
    if (widget.department != 'all') {
      return _displaySections
          .map((s) => (
                isDeptHeader: false,
                deptLabel: '',
                sectionId: s.id,
                sectionLabel: loc.translate(s.nameKey) != s.nameKey ? loc.translate(s.nameKey) : s.id,
                slots: _displaySlotsBySection[s.id] ?? [],
              ))
          .where((b) => b.slots.isNotEmpty)
          .toList();
    }
    final bySection = _displaySlotsBySection;
    final blocks = <({bool isDeptHeader, String deptLabel, String? sectionId, String sectionLabel, List<ScheduleSlot> slots})>[];

    void addDept(String deptKey, String deptLabel) {
      blocks.add((isDeptHeader: true, deptLabel: deptLabel, sectionId: null, sectionLabel: '', slots: []));
    }

    void addSection(String sectionId, String sectionLabel, List<ScheduleSlot> slots) {
      if (slots.isEmpty) return;
      blocks.add((isDeptHeader: false, deptLabel: '', sectionId: sectionId, sectionLabel: sectionLabel, slots: slots));
    }

    // Общее управление (department=='management')
    final mgmtDeptSlots = (bySection['management'] ?? []).where((s) {
      final emp = _employeeForSlot(s);
      return emp != null && emp.department == 'management';
    }).toList();
    if (mgmtDeptSlots.isNotEmpty) {
      addDept('dept_management', loc.t('dept_management'));
      addSection('management', loc.t('management'), mgmtDeptSlots);
    }

    // Кухня: управление (по department сотрудника) + цеха
    addDept('dept_kitchen', loc.t('dept_kitchen'));
    final mgmtSlots = bySection['management'] ?? [];
    final kitchenMgmt = mgmtSlots.where((s) {
      final emp = _employeeForSlot(s);
      return emp != null && emp.department == 'kitchen';
    }).toList();
    addSection('management', loc.t('management'), kitchenMgmt);
    for (final section in _model.sections) {
      if (_kitchenSectionIds.contains(section.id)) {
        final slots = bySection[section.id] ?? [];
        addSection(section.id, loc.translate(section.nameKey) != section.nameKey ? loc.translate(section.nameKey) : section.id, slots);
      }
    }

    // Бар: управление + сотрудники
    addDept('dept_bar', loc.t('dept_bar'));
    final barMgmt = mgmtSlots.where((s) {
      final emp = _employeeForSlot(s);
      return emp != null && emp.department == 'bar';
    }).toList();
    addSection('management', loc.t('management'), barMgmt);
    final barSlots = bySection['bar'] ?? [];
    addSection('bar', loc.t('employees'), barSlots);

    // Зал: управление + сотрудники
    addDept('dept_hall', loc.t('dept_hall'));
    final hallMgmt = mgmtSlots.where((s) {
      final emp = _employeeForSlot(s);
      return emp != null && (emp.department == 'hall' || emp.department == 'dining_room');
    }).toList();
    addSection('management', loc.t('management'), hallMgmt);
    final hallSlots = bySection['hall'] ?? [];
    addSection('hall', loc.t('employees'), hallSlots);
    return blocks;
  }

  /// ID сотрудников выбранного подразделения (для фильтрации графика).
  /// Для кухни: department=kitchen + шеф/су-шеф (могут иметь department=management).
  Set<String> get _employeeIdsForDepartment {
    if (widget.department == 'all') return _employees.map((e) => e.id).toSet();
    final dept = widget.department;
    return _employees.where((e) {
      if (dept == 'kitchen') {
        return e.department == 'kitchen' ||
            (e.hasRole('executive_chef') || e.hasRole('sous_chef'));
      }
      if (dept == 'bar') return e.department == 'bar' || e.hasRole('bar_manager');
      if (dept == 'hall' || dept == 'dining_room') {
        return e.department == 'hall' || e.department == 'dining_room' || e.hasRole('floor_manager');
      }
      return true;
    }).map((e) => e.id).toSet();
  }

  /// Слоты для отображения: при выборе подразделения — только сотрудники этого подразделения
  List<ScheduleSlot> get _displaySlots {
    if (widget.department == 'all') return _model.slots;
    final ids = _employeeIdsForDepartment;
    return _model.slots.where((s) => s.employeeId != null && ids.contains(s.employeeId!)).toList();
  }

  /// Секции и слоты по секциям для отображения (с учётом фильтра по подразделению)
  Map<String, List<ScheduleSlot>> get _displaySlotsBySection {
    final filtered = _displaySlots;
    final map = <String, List<ScheduleSlot>>{};
    for (final section in _model.sections) {
      final list = filtered.where((s) => s.sectionId == section.id).toList();
      if (list.isNotEmpty) map[section.id] = list;
    }
    // Слоты с sectionId, для которых нет секции (bar, hall) — добавляем секции
    final orphanSectionIds = filtered.map((s) => s.sectionId).where((id) => id.isNotEmpty && !map.containsKey(id)).toSet();
    for (final id in orphanSectionIds) {
      map[id] = filtered.where((s) => s.sectionId == id).toList();
    }
    return map;
  }

  List<ScheduleSection> get _displaySections {
    final bySection = _displaySlotsBySection;
    final ordered = ScheduleModel.sectionsInDisplayOrder(_model.sections);
    final fromModel = ordered.where((s) => bySection.containsKey(s.id)).toList();
    final orphanIds = bySection.keys.where((id) => !ordered.any((s) => s.id == id)).toList();
    if (orphanIds.isEmpty) return fromModel;
    const nameKeys = {'bar': 'dept_bar', 'hall': 'dept_hall'};
    final extra = orphanIds.map((id) => ScheduleSection(id: id, nameKey: nameKeys[id] ?? id)).toList();
    return [...fromModel, ...extra];
  }

  String _getSectionIdForEmployee(Employee employee, List<ScheduleSection> sections) {
    if (sections.isEmpty) return '';

    String sectionKey;
    // Руководители подразделений — в блок «Управление»: шеф/су-шеф (кухня), барменеджер (бар), менеджер зала (зал).
    if (employee.hasRole('executive_chef') ||
        employee.hasRole('sous_chef') ||
        employee.hasRole('bar_manager') ||
        employee.hasRole('floor_manager')) {
      sectionKey = 'management';
    } else {
      final departmentToSection = {
        'kitchen': 'hot_kitchen',
        'bar': 'bar',
        'dining_room': 'hall',
        'hall': 'hall',
        'management': 'management',
      };
      sectionKey = departmentToSection[employee.department] ?? 'hot_kitchen';
    }

    final section = sections.firstWhere(
      (s) => s.id == sectionKey,
      orElse: () => sections.first,
    );
    return section.id;
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
          if (_model.numWeeks < _defaultWeeks) {
            _model = _model.copyWith(numWeeks: _defaultWeeks);
            saveSchedule(est.id, _model);
          }
          if (_model.sections.isEmpty) {
            _model = _model.copyWith(sections: ScheduleModel.defaultSections);
          }
          // В графике только сотрудники с должностью. Собственник без должности не показывается.
          // В графике только сотрудники с должностью. Владелец без должности не показывается (positionRole==null при роли только owner).
          final scheduleableEmployees = _employees.where((e) => e.positionRole != null).toList();
          final needsManagement = scheduleableEmployees.any((e) =>
              e.hasRole('executive_chef') ||
              e.hasRole('sous_chef') ||
              e.hasRole('bar_manager') ||
              e.hasRole('floor_manager') ||
              e.department == 'management');
          if (needsManagement && !_model.sections.any((s) => s.id == 'management')) {
            _model = _model.copyWith(sections: [
              const ScheduleSection(id: 'management', nameKey: 'management'),
              ..._model.sections,
            ]);
            saveSchedule(est.id, _model);
          }
          if (_model.slots.isEmpty && _model.sections.isNotEmpty && scheduleableEmployees.isNotEmpty) {
            // Создаем слоты только для сотрудников с должностью (собственник без должности не в графике)
            final slots = scheduleableEmployees.map((e) => ScheduleSlot(
                  id: const Uuid().v4(),
                  name: e.fullName.trim().isEmpty ? 'Сотрудник' : e.fullName.trim(),
                  sectionId: _getSectionIdForEmployee(e, _model.sections),
                  employeeId: e.id,
                )).toList();
            _model = _model.copyWith(slots: slots);
            saveSchedule(est.id, _model);
          } else if (_model.sections.isNotEmpty && (_model.slots.isNotEmpty || scheduleableEmployees.isNotEmpty)) {
            // Синхронизируем слоты: удаляем сотрудников без должности, добавляем новых с должностью
            final currentEmployeeIds = scheduleableEmployees.map((e) => e.id).toSet();

            // Связываем слоты без employeeId с сотрудниками по имени (точное совпадение)
            final slotsWithEmployeeId = _model.slots.map((slot) {
              if (slot.employeeId != null) return slot;
              final slotName = slot.name.trim().toLowerCase();
              if (slotName.isEmpty) return slot;
              for (final e in scheduleableEmployees) {
                if (e.fullName.trim().toLowerCase() == slotName) {
                  return slot.copyWith(employeeId: e.id);
                }
              }
              return slot;
            }).toList();

            final existingEmployeeIds = slotsWithEmployeeId
                .where((s) => s.employeeId != null)
                .map((s) => s.employeeId!)
                .toSet();

            // Удаляем слоты для уволенных и дубликаты (один сотрудник — один слот)
            final seenEmployeeIds = <String>{};
            final toKeep = slotsWithEmployeeId.where((s) {
              if (s.employeeId == null) return true;
              if (!currentEmployeeIds.contains(s.employeeId!)) return false;
              if (seenEmployeeIds.contains(s.employeeId!)) return false;
              seenEmployeeIds.add(s.employeeId!);
              return true;
            }).toList();

            // Добавляем новых сотрудников с должностью (без слотов)
            final toAdd = scheduleableEmployees
                .where((e) => !existingEmployeeIds.contains(e.id))
                .map((e) => ScheduleSlot(
                      id: const Uuid().v4(),
                      name: e.fullName.trim().isEmpty ? 'Сотрудник' : e.fullName.trim(),
                      sectionId: _getSectionIdForEmployee(e, _model.sections),
                      employeeId: e.id,
                    ))
                .toList();

            final updatedSlots = [...toKeep, ...toAdd];

            // Обновляем секции для существующих слотов, если изменился отдел сотрудника
            final finalSlots = updatedSlots.map((slot) {
              if (slot.employeeId != null) {
                final employee = scheduleableEmployees.where((e) => e.id == slot.employeeId).firstOrNull;
                if (employee != null) {
                  final correctSectionId = _getSectionIdForEmployee(employee, _model.sections);
                  if (slot.sectionId != correctSectionId) {
                    return slot.copyWith(sectionId: correctSectionId);
                  }
                }
              }
              return slot;
            }).toList();

            if (finalSlots.length != _model.slots.length || toAdd.isNotEmpty) {
              _model = _model.copyWith(slots: finalSlots);
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
        onSave: (value, start, end, showTime) async {
          setState(() {
            _model = _model.setAssignment(slotId, date, value.isEmpty ? null : value);
            if (value == '1' && showTime && start.isNotEmpty && end.isNotEmpty) {
              _model = _model.setTimeRange(slotId, date, start, end);
            } else {
              _model = _model.setTimeRange(slotId, date, null, null);
            }
          });
          await _save();
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

  List<DateTime> get _visibleDates {
    return _model.dates; // Показываем все даты, график не должен заканчиваться
  }

  void _showCopyRangeDialog() {
    final loc = context.read<LocalizationService>();
    final establishmentId = _establishmentId;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => _CopyRangeDialog(
        dates: _visibleDates,
        slots: _model.slots,
        loc: loc,
        onCopy: (sourceStart, sourceEnd, targetStart, targetEnd, selectedSlots) async {
          var updatedModel = _model;
          final sourceDates = _getDatesInRange(sourceStart, sourceEnd);
          final targetDates = _getDatesInRange(targetStart, targetEnd);
          if (sourceDates.isEmpty || targetDates.isEmpty) return;

          for (final slotId in selectedSlots) {
            for (var i = 0; i < targetDates.length; i++) {
              final sourceDate = sourceDates[i % sourceDates.length];
              final targetDate = targetDates[i];

              final assignment = updatedModel.getAssignment(slotId, sourceDate);
              final timeRange = updatedModel.getTimeRange(slotId, sourceDate);

              updatedModel = updatedModel.setAssignment(slotId, targetDate, assignment);
              if (timeRange != null) {
                final parts = timeRange.split('|');
                if (parts.length >= 2) {
                  updatedModel = updatedModel.setTimeRange(slotId, targetDate, parts[0].trim(), parts[1].trim());
                }
              }
            }
          }
          if (establishmentId == null) {
            scaffoldMessenger.showSnackBar(SnackBar(content: Text(loc.t('no_establishment') ?? 'Заведение не выбрано')));
            return;
          }
          try {
            final ok = await saveSchedule(establishmentId, updatedModel);
            if (mounted) {
              if (ok) {
                setState(() => _model = updatedModel);
                scaffoldMessenger.showSnackBar(const SnackBar(content: Text('График вставлен в выбранный диапазон')));
              } else {
                scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Ошибка: не удалось сохранить график')));
              }
            }
          } catch (e, st) {
            debugPrint('Schedule copy save error: $e\n$st');
            if (mounted) {
              scaffoldMessenger.showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
            }
          }
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

    final dates = _visibleDates;
    final todayDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final currentEmployeeId = widget.personalOnly ? acc.currentEmployee?.id : null;

    bool slotMatchesPersonal(ScheduleSlot slot) {
      if (currentEmployeeId == null) return true;
      return slot.employeeId == currentEmployeeId;
    }

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

    Border leftCellBorder({bool top = false}) => Border(
      left: BorderSide(color: borderColor),
      right: BorderSide(color: borderColor),
      top: top ? BorderSide(color: borderColor) : BorderSide.none,
      bottom: BorderSide(color: borderColor),
    );

    Widget leftCell(Widget child, {double? height, BoxDecoration? decoration, bool withTopBorder = false}) {
      return Container(
        height: height ?? _rowHeight,
        decoration: (decoration ?? BoxDecoration()).copyWith(
          border: leftCellBorder(top: withTopBorder),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        alignment: Alignment.centerLeft,
        child: child,
      );
    }

    Widget rightCell(Widget child, {Color? bg, bool mergeRight = false}) {
      return Container(
        width: _dayCellWidth,
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            right: mergeRight ? BorderSide.none : BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        alignment: Alignment.center,
        child: child,
      );
    }

    // Строка 1: заголовок «Дата»
    leftCells.add(leftCell(
      Text(loc.t('schedule_date'), style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 12)),
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg),
      withTopBorder: true,
    ));

    // Строка 2: «День»
    leftCells.add(leftCell(
      Text(loc.t('schedule_day'), style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 11)),
      height: _rowHeight,
      decoration: BoxDecoration(color: headerBg, border: Border(right: BorderSide(color: borderColor))),
    ));

    final blocks = _displayBlocks(loc);
    final sectionBg = theme.colorScheme.secondaryContainer.withOpacity(0.6);
    final sectionFg = theme.colorScheme.onSecondaryContainer;
    final deptHeaderBg = theme.colorScheme.primary.withOpacity(0.25);
    final deptHeaderFg = theme.colorScheme.onPrimary;

    for (final block in blocks) {
      if (block.isDeptHeader) {
        leftCells.add(leftCell(
          Text(block.deptLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: deptHeaderFg), overflow: TextOverflow.ellipsis),
          height: _rowHeight,
          decoration: BoxDecoration(
            color: deptHeaderBg,
            border: Border(right: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor)),
          ),
        ));
        continue;
      }
      var sectionSlots = block.slots;
      if (widget.personalOnly && currentEmployeeId != null) {
        sectionSlots = sectionSlots.where(slotMatchesPersonal).toList();
      }
      if (sectionSlots.isEmpty) continue;

      leftCells.add(leftCell(
        Text(block.sectionLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sectionFg), overflow: TextOverflow.ellipsis),
        height: _rowHeight,
        decoration: BoxDecoration(
          color: sectionBg,
          border: Border(right: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor)),
        ),
      ));

      for (final slot in sectionSlots) {
      final position = _slotPosition(slot, loc);
      leftCells.add(leftCell(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _slotDisplayName(slot),
              style: TextStyle(fontSize: isMobile ? 11 : 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (position != null && position.isNotEmpty)
              Text(
                position,
                style: TextStyle(fontSize: isMobile ? 8 : 9, color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
          ],
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          border: Border(right: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor)),
        ),
      ));
      }
    }

    /// Строит один столбец даты для ListView.builder (виртуализация — строятся только видимые столбцы)
    Widget buildDateColumn(int index) {
      final d = dates[index];
      final columnChildren = <Widget>[];
      final isLastColumn = index == dates.length - 1;

      final weekend = isWeekend(d);
      final dayIsToday = isToday(d);
      final headerCellBg = dayIsToday ? todayHighlightBg : (weekend ? weekendHeaderBg : headerBg);
      final headerCellFg = weekend ? weekendHeaderFg : headerFg;

      columnChildren.add(rightCell(
        Text(DateFormat('dd.MM', localeStr).format(d), textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: headerCellFg)),
        bg: headerCellBg,
      ));
      columnChildren.add(rightCell(
        Text(weekdays[d.weekday - 1], textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: headerCellFg)),
        bg: headerCellBg,
      ));

      for (final block in blocks) {
        if (block.isDeptHeader) {
          columnChildren.add(rightCell(const SizedBox.shrink(), bg: deptHeaderBg, mergeRight: !isLastColumn));
          continue;
        }
        var sectionSlots = block.slots;
        if (widget.personalOnly && currentEmployeeId != null) {
          sectionSlots = sectionSlots.where(slotMatchesPersonal).toList();
        }
        if (sectionSlots.isEmpty) continue;

        // Объединённая строка раздела: без правой границы между ячейками (mergeRight), чтобы визуально сливались
        columnChildren.add(rightCell(const SizedBox.shrink(), bg: sectionBg, mergeRight: !isLastColumn));

        for (final slot in sectionSlots) {
          final val = _cellValue(slot.id, d);
          final isShift = val == '1';
          final isDayOff = val == '0';
          final timeRange = isShift ? _model.getTimeRange(slot.id, d) : null;
          String timeDisplay = '';
          if (timeRange != null) {
            final parts = timeRange.split('|');
            if (parts.length >= 2) timeDisplay = '${parts[0]}–${parts[1]}';
          }
          var bg = isShift ? Colors.green.shade100 : isDayOff ? Colors.amber.shade100 : null;
          if (isToday(d)) {
            final base = bg ?? theme.colorScheme.surface;
            bg = Color.lerp(base, todayHighlightBg, 0.6) ?? base;
          }
          final displayText = isDayOff
              ? '0'
              : (isShift && timeDisplay.isNotEmpty ? timeDisplay : (val ?? '—'));
          final content = Text(
            displayText,
            style: TextStyle(
              fontSize: timeDisplay.isNotEmpty && isShift ? 9 : 12,
              fontWeight: FontWeight.w600,
              color: val != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
          columnChildren.add(rightCell(
            canEdit
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onCellTap(slot.id, d),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: Center(child: content),
                    ),
                  )
                : Center(child: content),
            bg: bg,
          ));
        }
      }

      return RepaintBoundary(
        child: Column(mainAxisSize: MainAxisSize.min, children: columnChildren),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: Text(widget.personalOnly ? loc.t('personal_schedule') : loc.t('schedule')),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _showCopyRangeDialog,
              tooltip: 'Копировать диапазон',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canEdit)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(loc.t('schedule_view_only_hint') ?? 'Редактирование графика доступно шеф-повару и су-шефу.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SizedBox(
                height: leftCells.length * _rowHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _slotColumnWidth,
                      child: Column(mainAxisSize: MainAxisSize.min, children: leftCells),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: dates.length,
                        itemExtent: _dayCellWidth,
                        itemBuilder: (context, index) => buildDateColumn(index),
                      ),
                    ),
                  ],
                ),
              ),
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
  final Future<void> Function(String value, String start, String end, bool showTime) onSave;

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
    _showTime = false; // По умолчанию выключен при открытии диалога
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
        onPressed: () async {
          await widget.onSave(_selectedValue, _startCtrl.text.trim(), _endCtrl.text.trim(), _showTime);
          if (!context.mounted) return;
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
  final Future<void> Function(DateTime sourceStart, DateTime sourceEnd, DateTime targetStart, DateTime targetEnd, List<String> selectedSlots) onCopy;

  @override
  State<_CopyRangeDialog> createState() => _CopyRangeDialogState();
}

class _CopyRangeDialogState extends State<_CopyRangeDialog> {
  static DateTime get _today =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  late DateTime? _sourceStart;
  late DateTime? _sourceEnd;
  late DateTime? _targetStart;
  late DateTime? _targetEnd;
  final Set<String> _selectedSlots = {};

  @override
  void initState() {
    super.initState();
    _sourceStart = _today;
    _sourceEnd = _today;
    _targetStart = _today;
    _targetEnd = _today;
  }

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
                    initialDate: _today,
                    onChanged: (date) => setState(() => _sourceStart = date),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DatePickerButton(
                    label: 'До',
                    selectedDate: _sourceEnd,
                    dates: widget.dates,
                    initialDate: _today,
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
                    initialDate: _today,
                    onChanged: (date) => setState(() => _targetStart = date),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DatePickerButton(
                    label: 'До',
                    selectedDate: _targetEnd,
                    dates: widget.dates,
                    initialDate: _today,
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
          onPressed: _canCopy ? () async { await _copy(); } : null,
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
      !_sourceStart!.isAfter(_sourceEnd!) &&
      !_targetStart!.isAfter(_targetEnd!);

  Future<void> _copy() async {
    if (!_canCopy) return;
    await widget.onCopy(_sourceStart!, _sourceEnd!, _targetStart!, _targetEnd!, _selectedSlots.toList());
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.label,
    required this.selectedDate,
    required this.dates,
    required this.initialDate,
    required this.onChanged,
  });

  final String label;
  final DateTime? selectedDate;
  final List<DateTime> dates;
  final DateTime initialDate;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final result = await showDialog<DateTime>(
          context: context,
          builder: (ctx) => _DatePickerDialog(
            dates: dates,
            initialDate: selectedDate ?? initialDate,
          ),
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

class _DatePickerDialog extends StatefulWidget {
  const _DatePickerDialog({required this.dates, this.initialDate});

  final List<DateTime> dates;
  final DateTime? initialDate;

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 56;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final initial = widget.initialDate;
      if (initial != null) {
        final idx = widget.dates.indexWhere((d) =>
            d.year == initial.year && d.month == initial.month && d.day == initial.day);
        if (idx >= 0) {
          final offset = (idx * _itemHeight) - 100;
          final maxExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(offset.clamp(0.0, maxExtent));
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dates = widget.dates;
    final initialDate = widget.initialDate;
    return AlertDialog(
      title: const Text('Выберите дату'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView.builder(
          controller: _scrollController,
          itemExtent: _itemHeight,
          itemCount: dates.length,
          itemBuilder: (context, index) {
            final date = dates[index];
            final isSelected = initialDate != null &&
                date.year == initialDate.year &&
                date.month == initialDate.month &&
                date.day == initialDate.day;
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
