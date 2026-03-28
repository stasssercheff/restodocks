import '../models/employee.dart';

/// Кто может редактировать столы зала (CRUD pos_dining_tables).
bool posCanManageHallTables(Employee? e) {
  if (e == null) return false;
  if (e.hasRole('owner')) return true;
  if (e.hasRole('general_manager')) return true;
  final hall = e.department == 'hall' || e.department == 'dining_room';
  return e.hasRole('floor_manager') && hall;
}
