import '../services/localization_service.dart';

/// Из текста исключения PostgREST / RPC (`employee_limit_reached cap N`).
String? employeeLimitCapFromMessage(String message) {
  final m = RegExp(
    r'employee_limit_reached cap (\d+)',
    caseSensitive: false,
  ).firstMatch(message);
  return m?.group(1);
}

String employeeLimitUserMessage(LocalizationService loc, Object error) {
  final cap = employeeLimitCapFromMessage(error.toString());
  if (cap != null) {
    return loc.t('employee_limit_reached_cap', args: {'cap': cap});
  }
  return loc.t('employee_limit_reached');
}
