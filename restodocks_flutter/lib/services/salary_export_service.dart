import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'inventory_download.dart';

/// Экспорт ФЗП в Excel: таблица по сотрудникам + итоги по подразделениям.
class SalaryExportService {
  /// Подразделения: управление (шеф, сушеф, барменеджер, менеджер зала) внутри своих отделов, не отдельно.
  static const List<String> _departmentOrder = ['kitchen', 'bar', 'dining_room', 'hall'];

  /// Строит Excel и сохраняет файл. Возвращает имя файла.
  static Future<String> buildAndSaveExcel({
    required List<Employee> employees,
    required ScheduleModel schedule,
    required DateTime periodStart,
    required DateTime periodEnd,
    required Map<String, bool> includeInTotal,
    required double Function(Employee) shiftsOrHoursFn,
    required double Function(Employee) totalForEmployeeFn,
    required String currency,
    required String Function(String) t,
    required String lang,
  }) async {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final periodStr = '${dateFormat.format(periodStart)}–${dateFormat.format(periodEnd)}';

    final excel = Excel.createExcel();
    final sheet = excel['ФЗП'];

    // Заголовки
    final numLabel = t('salary_export_no') ?? '№';
    final deptLabel = t('salary_export_department') ?? 'Подразделение';
    final sectionLabel = t('salary_export_section') ?? 'Цех';
    final positionLabel = t('salary_export_position') ?? 'Должность';
    final nameLabel = t('salary_export_employee_name') ?? 'Имя и фамилия';
    final calcLabel = t('salary_export_calc_mode') ?? 'Порядок расчёта';
    final rateLabel = t('salary_export_rate') ?? 'Стоимость смены/часа';
    final qtyLabel = t('salary_export_qty') ?? 'Кол-во смен/часов';
    final periodLabel = t('salary_export_period') ?? 'Период расчёта';
    final totalLabel = t('salary_export_total') ?? 'Итого';

    sheet.appendRow([
      TextCellValue(numLabel),
      TextCellValue(deptLabel),
      TextCellValue(sectionLabel),
      TextCellValue(positionLabel),
      TextCellValue(nameLabel),
      TextCellValue(calcLabel),
      TextCellValue(rateLabel),
      TextCellValue(qtyLabel),
      TextCellValue(periodLabel),
      TextCellValue(totalLabel),
    ]);

    final deptNames = {
      'kitchen': t('department_kitchen'),
      'bar': t('bar'),
      'dining_room': t('department_dining_room'),
      'hall': t('dining_room'),
    };

    final calcModeHourly = t('payroll_mode_hourly') ?? 'За час';
    final calcModeShift = t('payroll_mode_shift') ?? 'За смену';

    var rowIndex = 1;
    double grandTotal = 0;

    for (final deptCode in _departmentOrder) {
      final deptEmps = employees.where((e) {
        if (e.department == deptCode) return true;
        if (deptCode == 'kitchen' &&
            e.department == 'management' &&
            (e.hasRole('executive_chef') || e.hasRole('sous_chef'))) {
          return true;
        }
        if (deptCode == 'bar' &&
            e.department == 'management' &&
            e.hasRole('bar_manager')) {
          return true;
        }
        if ((deptCode == 'hall' || deptCode == 'dining_room') &&
            (e.department == 'hall' || e.department == 'dining_room' ||
                (e.department == 'management' && e.hasRole('floor_manager')))) {
          return true;
        }
        return false;
      }).toList();

      if (deptEmps.isEmpty) continue;

      double deptTotal = 0;
      var numInDept = 1;

      for (final e in deptEmps) {
        final included = includeInTotal[e.id] ?? true;
        final total = totalForEmployeeFn(e);
        final val = shiftsOrHoursFn(e);
        final isHourly = e.paymentType == 'hourly';
        final rate = isHourly ? (e.hourlyRate ?? 0) : (e.ratePerShift ?? 0);
        final sectionName = _sectionDisplayName(e.section, t);
        final roleCode = e.positionRole ?? e.roles.firstOrNull ?? '';
        final roleKey = roleCode.isEmpty ? '' : 'role_$roleCode';
        final positionName = roleKey.isEmpty ? '' : (t(roleKey) != roleKey ? t(roleKey) : roleCode);
        final calcMode = isHourly ? calcModeHourly : calcModeShift;

        if (included) deptTotal += total;

        sheet.appendRow([
      IntCellValue(numInDept++),
      TextCellValue(deptNames[deptCode] ?? deptCode),
      TextCellValue(sectionName),
      TextCellValue(positionName),
      TextCellValue(e.fullName),
      TextCellValue(calcMode),
      DoubleCellValue(rate),
      DoubleCellValue(val),
      TextCellValue(periodStr),
      DoubleCellValue(included ? total : 0),
        ]);

        rowIndex++;
      }

      sheet.appendRow([
        TextCellValue(''),
        TextCellValue('${t('salary_export_dept_total') ?? 'Итого'} ${deptNames[deptCode] ?? deptCode}'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(''),
        DoubleCellValue(deptTotal),
      ]);
      rowIndex++;
      grandTotal += deptTotal;
    }

    sheet.appendRow([
      TextCellValue(''),
      TextCellValue(t('salary_export_grand_total') ?? 'Итого по всем сотрудникам'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(grandTotal),
    ]);

    excel.setDefaultSheet('ФЗП');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel');

    final fileName = 'FZP_${dateFormat.format(periodStart)}_${dateFormat.format(periodEnd)}.xlsx';
    await saveFileBytes(fileName, bytes);
    return fileName;
  }

  static String _sectionDisplayName(String? sectionCode, String Function(String) t) {
    if (sectionCode == null || sectionCode.isEmpty) return '';
    final key = 'section_$sectionCode';
    final translated = t(key);
    if (translated != key) return translated;
    return sectionCode;
  }
}
