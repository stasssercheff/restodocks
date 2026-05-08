import 'dart:math';

import 'supabase_service.dart';

/// Управление токенами внешнего KDS (только авторизованные клиенты, RLS).
class PosKitchenDisplayTokenService {
  PosKitchenDisplayTokenService._();
  static final PosKitchenDisplayTokenService instance =
      PosKitchenDisplayTokenService._();

  final SupabaseService _sb = SupabaseService();

  static String generateToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<List<Map<String, dynamic>>> listActive({
    required String establishmentId,
  }) async {
    final rows = await _sb.client
        .from('pos_kitchen_display_tokens')
        .select(
          'id, token, department, require_active_shift, label, created_at',
        )
        .eq('establishment_id', establishmentId)
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    final list = rows as List<dynamic>;
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> create({
    required String establishmentId,
    required String department,
    bool requireActiveShift = true,
    String? label,
  }) async {
    final token = generateToken();
    final row = await _sb.client
        .from('pos_kitchen_display_tokens')
        .insert({
          'establishment_id': establishmentId,
          'token': token,
          'department': department.trim().toLowerCase(),
          'require_active_shift': requireActiveShift,
          if (label != null && label.isNotEmpty) 'label': label,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> revoke(String id) async {
    await _sb.client.from('pos_kitchen_display_tokens').update({
      'revoked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
