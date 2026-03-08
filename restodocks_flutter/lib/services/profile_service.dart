import 'package:intl/intl.dart';

import '../models/employee.dart';
import '../models/schedule_model.dart';
import 'schedule_storage_service.dart';

/// Сервис для расчетов в профиле пользователя
class ProfileService {
  /// Рассчитывает зарплату сотрудника за отработанный период (с начала месяца по сегодня)
  static Future<double> calculateEarnedSalary(Employee employee, String establishmentId) async {
    try {
      final schedule = await loadSchedule(establishmentId);
      final now = DateTime.now();
      final periodStart = DateTime(now.year, now.month, 1); // начало месяца
      final periodEnd = DateTime(now.year, now.month, now.day); // сегодня

      final shiftsOrHours = _shiftsOrHoursFromSchedule(employee, schedule, periodStart, periodEnd);

      if (employee.paymentType == 'hourly') {
        final rate = employee.hourlyRate ?? 0;
        return rate * shiftsOrHours;
      } else {
        final rate = employee.ratePerShift ?? 0;
        return rate * shiftsOrHours;
      }
    } catch (e) {
      return 0.0;
    }
  }

  /// Рассчитывает зарплату сотрудника за произвольный период (с учетом графика).
  static Future<double> calculateSalaryForPeriod(Employee employee, String establishmentId, DateTime periodStart, DateTime periodEnd) async {
    try {
      final schedule = await loadSchedule(establishmentId);
      final shiftsOrHours = _shiftsOrHoursFromSchedule(employee, schedule, periodStart, periodEnd);
      if (employee.paymentType == 'hourly') {
        return (employee.hourlyRate ?? 0) * shiftsOrHours;
      }
      return (employee.ratePerShift ?? 0) * shiftsOrHours;
    } catch (e) {
      return 0.0;
    }
  }

  /// Рассчитывает зарплату сотрудника за текущий календарный месяц (с учетом графика)
  static Future<double> calculateCurrentMonthSalary(Employee employee, String establishmentId) async {
    try {
      final schedule = await loadSchedule(establishmentId);
      final now = DateTime.now();
      final periodStart = DateTime(now.year, now.month, 1); // начало месяца
      final periodEnd = DateTime(now.year, now.month + 1, 0); // конец месяца

      final shiftsOrHours = _shiftsOrHoursFromSchedule(employee, schedule, periodStart, periodEnd);

      if (employee.paymentType == 'hourly') {
        final rate = employee.hourlyRate ?? 0;
        return rate * shiftsOrHours;
      } else {
        final rate = employee.ratePerShift ?? 0;
        return rate * shiftsOrHours;
      }
    } catch (e) {
      return 0.0;
    }
  }

  /// Рассчитывает количество смен/часов из графика для сотрудника в периоде
  static double _shiftsOrHoursFromSchedule(Employee employee, ScheduleModel schedule, DateTime periodStart, DateTime periodEnd) {
    final isHourly = employee.paymentType == 'hourly';
    double total = 0;

    for (final slot in schedule.slots) {
      if (slot.employeeId != employee.id) continue;

      for (var d = periodStart;
          !d.isAfter(periodEnd);
          d = d.add(const Duration(days: 1))) {
        final assign = schedule.getAssignment(slot.id, d);
        if (assign != '1') continue;

        if (isHourly) {
          final range = schedule.getTimeRange(slot.id, d);
          if (range != null) {
            final parts = range.split('|');
            if (parts.length == 2) {
              final hours = _hoursBetween(parts[0], parts[1]);
              total += hours > 0 ? hours : 8;
            } else {
              total += 8;
            }
          } else {
            total += 8;
          }
        } else {
          total += 1; // одна смена
        }
      }
    }
    return total;
  }

  /// Минуты от полуночи для "HH:mm".
  static int _minutesFromMidnight(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h.clamp(0, 23) * 60 + m.clamp(0, 59);
  }

  /// Часы между началом и концом смены ("09:00", "21:00").
  static double _hoursBetween(String startStr, String endStr) {
    final start = _minutesFromMidnight(startStr);
    final end = _minutesFromMidnight(endStr);
    if (end <= start) return 0;
    return (end - start) / 60.0;
  }

  /// Форматирует сумму с валютой
  static String formatSalary(double amount, String currencySymbol) {
    final formatter = NumberFormat('#,##0.00', 'ru_RU');
    return '${formatter.format(amount)} $currencySymbol';
  }
}