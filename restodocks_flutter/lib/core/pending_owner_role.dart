import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import '../services/account_manager_supabase.dart';
import '../utils/dev_log.dart';

class PendingOwnerRole {
  static const _kPrefixEmail = 'pending_owner_role:email:';
  static const _kPrefixEst = 'pending_owner_role:est:';

  static String _keyForEmail(String email) =>
      '$_kPrefixEmail${email.trim().toLowerCase()}';
  static String _keyForEstablishment(String establishmentId) =>
      '$_kPrefixEst${establishmentId.trim().toLowerCase()}';

  static Future<void> saveForOwner({
    required String email,
    required String establishmentId,
    required String? role,
  }) async {
    final normalized = role?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'owner') {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForEmail(email), normalized);
    if (establishmentId.trim().isNotEmpty) {
      await prefs.setString(_keyForEstablishment(establishmentId), normalized);
    }
  }

  static Future<void> clearForOwner({
    required String email,
    String? establishmentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForEmail(email));
    final est = establishmentId?.trim();
    if (est != null && est.isNotEmpty) {
      await prefs.remove(_keyForEstablishment(est));
    }
  }

  static Future<void> applyIfNeeded(AccountManagerSupabase account) async {
    final emp = account.currentEmployee;
    if (emp == null || !emp.hasRole('owner')) return;
    final email = emp.email.trim().toLowerCase();
    if (email.isEmpty) return;
    final estId = account.establishment?.id.trim();
    final prefs = await SharedPreferences.getInstance();
    final fromEmail = prefs.getString(_keyForEmail(email))?.trim().toLowerCase();
    final fromEst = (estId != null && estId.isNotEmpty)
        ? prefs.getString(_keyForEstablishment(estId))?.trim().toLowerCase()
        : null;
    final pending = (fromEmail != null && fromEmail.isNotEmpty)
        ? fromEmail
        : fromEst;
    if (pending == null || pending.isEmpty || pending == 'owner') return;
    if (emp.roles.contains(pending)) {
      await clearForOwner(email: email, establishmentId: estId);
      return;
    }
    try {
      final updated = emp.copyWith(roles: <String>[...emp.roles, pending]);
      await account.updateEmployee(updated);
      await clearForOwner(email: email, establishmentId: estId);
    } catch (e) {
      try {
        final roles = <String>[...emp.roles, pending];
        await Supabase.instance.client.rpc(
          'patch_my_employee_profile',
          params: {
            'p_patch': {
              'roles': roles,
            },
          },
        );
        // Pull fresh profile so Settings/Home reflect the newly persisted role immediately.
        await account.initialize(forceRetryFromAuth: true);
        await clearForOwner(email: email, establishmentId: estId);
      } catch (e2) {
        devLog('PendingOwnerRole.applyIfNeeded: $e / rpc fallback: $e2');
      }
    }
  }
}
