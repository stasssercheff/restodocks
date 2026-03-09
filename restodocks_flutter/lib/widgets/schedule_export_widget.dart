import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../utils/translit_utils.dart';

/// Виджет графика для экспорта в PNG: один подраздел (зал/бар/кухня) за выбранный период.
class ScheduleExportWidget extends StatelessWidget {
  const ScheduleExportWidget({
    super.key,
    required this.schedule,
    required this.employees,
    required this.department,
    required this.periodStart,
    required this.periodEnd,
    required this.loc,
    required this.boundaryKey,
    required this.exportLang,
  });

  final ScheduleModel schedule;
  final List<Employee> employees;
  /// kitchen | bar | hall
  final String department;
  final DateTime periodStart;
  final DateTime periodEnd;
  final LocalizationService loc;
  final GlobalKey boundaryKey;
  /// Язык экспорта (ru/en/es): подписи и имена транслитом при en/es
  final String exportLang;

  String _t(String key) => loc.tForLanguage(exportLang, key);
  bool get _translitNames => exportLang == 'en' || exportLang == 'es';

  static const double _slotColumnWidth = 120;
  static const double _dayCellWidth = 36;
  static const double _rowHeight = 40;

  static const _kitchenSectionIds = {'hot_kitchen', 'cold_kitchen', 'grill', 'pastry', 'prep', 'cleaning', 'pizza', 'sushi', 'bakery'};

  List<DateTime> get _dates {
    final out = <DateTime>[];
    var d = periodStart;
    while (!d.isAfter(periodEnd)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }

  Set<String> get _employeeIdsForDepartment {
    switch (department) {
      case 'kitchen':
        return employees
            .where((e) =>
                e.department == 'kitchen' ||
                (e.hasRole('executive_chef') || e.hasRole('sous_chef')))
            .map((e) => e.id)
            .toSet();
      case 'bar':
        return employees
            .where((e) => e.department == 'bar' || e.hasRole('bar_manager'))
            .map((e) => e.id)
            .toSet();
      case 'hall':
        return employees
            .where((e) =>
                e.department == 'hall' ||
                e.department == 'dining_room' ||
                e.hasRole('floor_manager'))
            .map((e) => e.id)
            .toSet();
      default:
        return employees.map((e) => e.id).toSet();
    }
  }

  List<ScheduleSlot> get _displaySlots {
    final ids = _employeeIdsForDepartment;
    return schedule.slots
        .where((s) => s.employeeId != null && ids.contains(s.employeeId!))
        .toList();
  }

  Map<String, List<ScheduleSlot>> get _slotsBySection {
    final filtered = _displaySlots;
    final map = <String, List<ScheduleSlot>>{};
    for (final section in schedule.sections) {
      final list = filtered.where((s) => s.sectionId == section.id).toList();
      if (list.isNotEmpty) map[section.id] = list;
    }
    final orphanIds = filtered
        .map((s) => s.sectionId)
        .where((id) => id.isNotEmpty && !map.containsKey(id))
        .toSet();
    for (final id in orphanIds) {
      map[id] = filtered.where((s) => s.sectionId == id).toList();
    }
    return map;
  }

  List<({String sectionId, String sectionLabel, List<ScheduleSlot> slots})> _blocks() {
    final bySection = _slotsBySection;
    final blocks = <({String sectionId, String sectionLabel, List<ScheduleSlot> slots})>[];

    void addSection(String sectionId, String sectionLabel) {
      final slots = bySection[sectionId] ?? [];
      if (slots.isNotEmpty) {
        blocks.add((sectionId: sectionId, sectionLabel: sectionLabel, slots: slots));
      }
    }

    switch (department) {
      case 'kitchen':
        addSection('management', _t('role_executive_chef')); // шеф/сушеф — в рамках кухни, без отдельного «Управление»
        for (final s in schedule.sections) {
          if (_kitchenSectionIds.contains(s.id)) {
            final label = _t(s.nameKey) != s.nameKey ? _t(s.nameKey) : s.id;
            addSection(s.id, label);
          }
        }
        break;
      case 'bar':
        addSection('management', _t('role_bar_manager'));
        addSection('bar', _t('employees'));
        break;
      case 'hall':
        addSection('management', _t('role_floor_manager'));
        addSection('hall', _t('employees'));
        break;
      default:
        for (final s in schedule.sections) {
          final slots = bySection[s.id] ?? [];
          if (slots.isNotEmpty) {
            final label = _t(s.nameKey) != s.nameKey ? _t(s.nameKey) : s.id;
            blocks.add((sectionId: s.id, sectionLabel: label, slots: slots));
          }
        }
    }
    return blocks;
  }

  Employee? _employeeForSlot(ScheduleSlot slot) =>
      employees.cast<Employee?>().firstWhere(
            (e) => e?.id == slot.employeeId,
            orElse: () => null,
          );

  String _slotDisplayName(ScheduleSlot slot) {
    final emp = _employeeForSlot(slot);
    if (emp == null) return slot.name;
    final parts = emp.fullName.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : emp.fullName;
    final surnameLetter = emp.surname?.trim().isNotEmpty == true
        ? ' ${emp.surname!.trim()[0].toUpperCase()}.'
        : (parts.length > 1 ? ' ${parts.last[0].toUpperCase()}.' : '');
    var name = '$first$surnameLetter'.trim();
    if (_translitNames) name = cyrillicToLatin(name);
    return name;
  }

  String? _slotPosition(ScheduleSlot slot) {
    final emp = _employeeForSlot(slot);
    if (emp == null) return null;
    final pos = emp.positionRole;
    if (pos == null || pos.isEmpty) return null;
    final key = 'role_$pos';
    final translated = _t(key);
    return translated != key ? translated : pos;
  }

  String? _cellValue(String slotId, DateTime date) {
    final v = schedule.getAssignment(slotId, date);
    if (v == '1' || v == '0') return v;
    if (v != null && v.trim().isNotEmpty) return '1';
    return null;
  }

  String _deptTitle() {
    switch (department) {
      case 'kitchen':
        return _t('department_kitchen');
      case 'bar':
        return _t('bar');
      case 'hall':
        return _t('department_dining_room');
      default:
        return department;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = _dates;
    final localeStr = exportLang == 'ru' ? 'ru_RU' : (exportLang == 'es' ? 'es_ES' : (exportLang == 'tr' ? 'tr_TR' : 'en_US'));
    final weekdays = List.generate(7, (i) {
      final d = DateTime.utc(2024, 1, 1).add(Duration(days: i));
      return DateFormat('EEE', localeStr).format(d);
    });

    final headerBg = theme.colorScheme.primary;
    final headerFg = theme.colorScheme.onPrimary;
    final weekendHeaderBg = theme.colorScheme.secondaryContainer;
    final weekendHeaderFg = theme.colorScheme.onSecondaryContainer;
    final sectionBg = theme.colorScheme.secondaryContainer.withOpacity(0.6);
    final sectionFg = theme.colorScheme.onSecondaryContainer;
    final borderColor = theme.dividerColor;

    bool isWeekend(DateTime d) => d.weekday == 6 || d.weekday == 7;

    final blocks = _blocks();
    final rowCount = 3 + blocks.fold<int>(0, (s, b) => s + 1 + b.slots.length);
    final totalWidth = _slotColumnWidth + dates.length * _dayCellWidth;
    final totalHeight = rowCount * _rowHeight + 16;
    return RepaintBoundary(
      key: boundaryKey,
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: totalWidth,
            height: totalHeight,
            child: Table(
                columnWidths: {
                  0: const FixedColumnWidth(_slotColumnWidth),
                  for (var i = 1; i <= dates.length; i++) i: const FixedColumnWidth(_dayCellWidth),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder.all(color: borderColor, width: 1),
                children: [
                  TableRow(
                    children: [
                      TableCell(
                        child: Container(
                          width: _slotColumnWidth,
                          height: _rowHeight,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: headerBg),
                          alignment: Alignment.centerLeft,
                          child: Text(_deptTitle(), style: TextStyle(fontWeight: FontWeight.bold, color: headerFg, fontSize: 14)),
                        ),
                      ),
                      ...dates.map((d) {
                        final weekend = isWeekend(d);
                        return TableCell(
                          child: Container(
                            width: _dayCellWidth,
                            height: _rowHeight,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: weekend ? weekendHeaderBg : headerBg),
                            alignment: Alignment.center,
                            child: Text(DateFormat('dd.MM', localeStr).format(d), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: weekend ? weekendHeaderFg : headerFg)),
                          ),
                        );
                      }),
                    ],
                  ),
                  TableRow(
                    children: [
                      TableCell(
                        child: Container(
                          width: _slotColumnWidth,
                          height: _rowHeight,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: headerBg),
                          alignment: Alignment.centerLeft,
                          child: Text(_t('schedule_date'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: headerFg)),
                        ),
                      ),
                      ...dates.map((d) {
                        final weekend = isWeekend(d);
                        return TableCell(
                          child: Container(
                            width: _dayCellWidth,
                            height: _rowHeight,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: weekend ? weekendHeaderBg : headerBg),
                            alignment: Alignment.center,
                            child: Text(weekdays[d.weekday - 1], style: TextStyle(fontSize: 10, color: weekend ? weekendHeaderFg : headerFg)),
                          ),
                        );
                      }),
                    ],
                  ),
                  TableRow(
                    children: [
                      TableCell(
                        child: Container(
                          width: _slotColumnWidth,
                          height: _rowHeight,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: headerBg),
                          alignment: Alignment.centerLeft,
                          child: Text(_t('schedule_day'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: headerFg)),
                        ),
                      ),
                      ...List.generate(dates.length, (i) {
                        final d = dates[i];
                        final weekend = isWeekend(d);
                        return TableCell(
                          child: Container(
                            width: _dayCellWidth,
                            height: _rowHeight,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: weekend ? weekendHeaderBg : headerBg),
                            alignment: Alignment.center,
                            child: const SizedBox.shrink(),
                          ),
                        );
                      }),
                    ],
                  ),
                  ...blocks.expand((block) {
                    return [
                      TableRow(
                        children: [
                          TableCell(
                            child: Container(
                              width: _slotColumnWidth,
                              height: _rowHeight,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: sectionBg),
                              alignment: Alignment.centerLeft,
                              child: Text(block.sectionLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: sectionFg)),
                            ),
                          ),
                          ...List.generate(dates.length, (_) => TableCell(
                            child: Container(
                              width: _dayCellWidth,
                              height: _rowHeight,
                              decoration: BoxDecoration(color: sectionBg),
                              child: const SizedBox.shrink(),
                            ),
                          )),
                        ],
                      ),
                      ...block.slots.map((slot) {
                        return TableRow(
                          children: [
                            TableCell(
                              child: Container(
                                width: _slotColumnWidth,
                                height: _rowHeight,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3)),
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_slotDisplayName(slot), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1),
                                    if (_slotPosition(slot) != null && _slotPosition(slot)!.isNotEmpty)
                                      Text(_slotPosition(slot)!, style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis, maxLines: 1),
                                  ],
                                ),
                              ),
                            ),
                            ...dates.map((d) {
                              final val = _cellValue(slot.id, d);
                              final isShift = val == '1';
                              final isDayOff = val == '0';
                              final timeRange = isShift ? schedule.getTimeRange(slot.id, d) : null;
                              String timeDisplay = '';
                              if (timeRange != null) {
                                final parts = timeRange.split('|');
                                if (parts.length >= 2) timeDisplay = '${parts[0]}–${parts[1]}';
                              }
                              final bg = isShift ? Colors.green.shade100 : isDayOff ? Colors.amber.shade100 : theme.colorScheme.surface;
                              final displayText = isDayOff ? '0' : (isShift && timeDisplay.isNotEmpty ? timeDisplay : (val ?? '—'));
                              return TableCell(
                                child: Container(
                                  width: _dayCellWidth,
                                  height: _rowHeight,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(color: bg),
                                  alignment: Alignment.center,
                                  child: Text(displayText, style: TextStyle(fontSize: timeDisplay.isNotEmpty && isShift ? 8 : 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ];
                  }),
                ],
              ),
          ),
        ),
      ),
    );
  }

}

/// Захват виджета в PNG.
Future<Uint8List?> captureWidgetToPng(GlobalKey boundaryKey) async {
  try {
    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    final boundary = ro;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
