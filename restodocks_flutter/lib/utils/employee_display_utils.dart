import '../models/employee.dart';
import '../models/establishment.dart';
import '../services/localization_service.dart';
import 'translit_utils.dart';

/// Полное имя: [fullName] + [surname], без дублирования фамилии.
String employeeFullNameRaw(Employee e) {
  final fn = e.fullName.trim();
  final sn = e.surname?.trim();
  if (sn == null || sn.isEmpty) return fn;
  if (fn.toLowerCase().contains(sn.toLowerCase())) return fn;
  return '$fn $sn'.trim();
}

/// Имя для UI с опциональной транслитерацией латиницей.
String employeeDisplayName(Employee e, {bool translit = false}) {
  final raw = employeeFullNameRaw(e);
  if (raw.isEmpty) return '—';
  return translit ? cyrillicToLatin(raw) : raw;
}

/// Должность: кастом у владельца из заведения или локализованная роль.
String employeePositionLine(
  Employee e,
  LocalizationService loc, {
  Establishment? establishment,
}) {
  if (e.hasRole('owner')) {
    final d = establishment?.directorPosition?.trim();
    if (d != null && d.isNotEmpty) {
      if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(d)) {
        return loc.roleDisplayName(d);
      }
      return d;
    }
  }
  final code = e.positionRole ?? (e.roles.isNotEmpty ? e.roles.first : null);
  if (code == null || code.isEmpty) return '—';
  return loc.roleDisplayName(code);
}

/// «Имя Фамилия · должность» (имя и фамилия + должность везде, где нужно кратко).
String employeeNameWithPositionLine(
  Employee e,
  LocalizationService loc, {
  Establishment? establishment,
  bool translit = false,
}) {
  final name = employeeDisplayName(e, translit: translit);
  final pos = employeePositionLine(e, loc, establishment: establishment);
  if (pos == '—') return name;
  return '$name · $pos';
}
