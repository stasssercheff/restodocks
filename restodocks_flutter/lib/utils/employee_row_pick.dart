/// Сопоставление строки `employees` с текущим JWT — как в RPC
/// `patch_my_employee_profile`: сначала `id = auth.uid()`, иначе привязка по `auth_user_id`,
/// при равенстве — самая свежая `updated_at` (у PostgREST без вторичного порядка `LIMIT 1` нестабилен).
DateTime employeeRowUpdatedAt(Map<String, dynamic> m) {
  final s = m['updated_at']?.toString();
  return DateTime.tryParse(s ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
}

Map<String, dynamic> pickEmployeeRowForAuthUid(
  List<dynamic> rows,
  String authUid,
) {
  final maps = <Map<String, dynamic>>[];
  for (final r in rows) {
    if (r is Map) maps.add(Map<String, dynamic>.from(r));
  }
  if (maps.isEmpty) {
    throw StateError('pickEmployeeRowForAuthUid: empty rows');
  }
  if (maps.length == 1) return maps.first;

  maps.sort((a, b) {
    final aPrimary = a['id']?.toString() == authUid ? 1 : 0;
    final bPrimary = b['id']?.toString() == authUid ? 1 : 0;
    if (aPrimary != bPrimary) return bPrimary.compareTo(aPrimary);
    return employeeRowUpdatedAt(b).compareTo(employeeRowUpdatedAt(a));
  });
  return maps.first;
}
