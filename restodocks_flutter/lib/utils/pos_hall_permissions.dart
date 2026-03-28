import '../models/employee.dart';
import '../models/pos_order_line.dart';
import 'pos_order_department.dart';

/// Кухня/бар по категориям строки (как в списках подразделений).
bool posLineIsBarForOrderLine(PosOrderLine line) {
  return posLineIsBarDish(line.techCardCategory ?? '', line.techCardSections);
}

/// Кто может отметить позицию «отдано» (кухня/бар/зал по типу блюда).
bool posCanMarkOrderLineServed(Employee? e, PosOrderLine line) {
  if (e == null) return false;
  final lineIsBar = posLineIsBarForOrderLine(line);
  if (e.hasRole('owner') || e.hasRole('general_manager')) return true;
  if (e.hasRole('executive_chef') || e.hasRole('sous_chef')) return !lineIsBar;
  if (e.hasRole('bar_manager')) return lineIsBar;
  if (e.department == 'bar') return lineIsBar;
  if (e.department == 'kitchen' || e.department == 'production') {
    return !lineIsBar;
  }
  if (e.department == 'hall' || e.department == 'dining_room') return true;
  if (e.department == 'management') return true;
  return false;
}

/// Кто может редактировать столы зала (CRUD pos_dining_tables).
bool posCanManageHallTables(Employee? e) {
  if (e == null) return false;
  if (e.hasRole('owner')) return true;
  if (e.hasRole('general_manager')) return true;
  final hall = e.department == 'hall' || e.department == 'dining_room';
  return e.hasRole('floor_manager') && hall;
}

/// Отчёт смены / свод по оплатам (владелец, управление, менеджер зала).
bool posCanViewPosShiftReport(Employee? e) {
  if (e == null) return false;
  if (e.hasRole('owner') || e.hasRole('general_manager')) return true;
  if (e.department == 'management') return true;
  final hall = e.department == 'hall' || e.department == 'dining_room';
  return e.hasRole('floor_manager') && hall;
}

/// Закрыть счёт зала и освободить стол (владелец/управление/любой сотрудник зала).
bool posCanCloseHallOrder(Employee? e) {
  if (e == null) return false;
  if (posCanManageHallTables(e)) return true;
  final hall = e.department == 'hall' || e.department == 'dining_room';
  return hall;
}

/// Таймер и шрифты на экранах списков заказов: те же роли, что пункт «Отображение заказов» в настройках.
bool posCanConfigureOrdersDisplay(Employee? e) {
  if (e == null) return false;
  if (e.hasRole('owner')) return true;
  if (e.department == 'management') return true;
  return e.hasRole('executive_chef') ||
      e.hasRole('sous_chef') ||
      e.hasRole('bar_manager') ||
      e.hasRole('floor_manager') ||
      e.hasRole('general_manager');
}
