import 'supabase_service.dart';

class PosKdsShiftAccessService {
  PosKdsShiftAccessService._();
  static final PosKdsShiftAccessService instance = PosKdsShiftAccessService._();

  final SupabaseService _sb = SupabaseService();

  Future<Set<String>> fetchAllowedEmployeeIds(String establishmentId) async {
    final rows = await _sb.client
        .from('pos_kds_shift_access_permissions')
        .select('employee_id')
        .eq('establishment_id', establishmentId);
    final out = <String>{};
    for (final row in (rows as List<dynamic>)) {
      if (row is! Map) continue;
      final id = row['employee_id']?.toString();
      if (id != null && id.isNotEmpty) out.add(id);
    }
    return out;
  }

  Future<void> replaceAllowedEmployeeIds({
    required String establishmentId,
    required String managerEmployeeId,
    required Set<String> employeeIds,
  }) async {
    await _sb.client
        .from('pos_kds_shift_access_permissions')
        .delete()
        .eq('establishment_id', establishmentId);
    if (employeeIds.isEmpty) return;
    await _sb.client.from('pos_kds_shift_access_permissions').insert([
      for (final id in employeeIds)
        {
          'establishment_id': establishmentId,
          'employee_id': id,
          'created_by_employee_id': managerEmployeeId,
        }
    ]);
  }
}
