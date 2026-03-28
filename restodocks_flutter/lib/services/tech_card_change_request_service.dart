import '../models/models.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';
import 'tech_card_service_supabase.dart';

/// Заявки на изменение ТТК (не-владелец → очередь, владелец применяет).
class TechCardChangeRequestService {
  TechCardChangeRequestService._();
  static final TechCardChangeRequestService instance =
      TechCardChangeRequestService._();

  final SupabaseService _supabase = SupabaseService();

  Map<String, dynamic> _proposalPayload(TechCard card) {
    return {
      'card': card.toJson(),
      'ingredients': card.ingredients.map((e) => e.toJson()).toList(),
    };
  }

  TechCard _techCardFromProposal(Map<String, dynamic> proposed) {
    final raw = proposed['card'];
    if (raw is! Map<String, dynamic>) {
      throw FormatException('ttk_change_bad_card');
    }
    final ings = proposed['ingredients'];
    final list = <TTIngredient>[];
    if (ings is List) {
      for (final e in ings) {
        if (e is Map<String, dynamic>) {
          list.add(TTIngredient.fromJson(e));
        }
      }
    }
    return TechCard.fromJson(Map<String, dynamic>.from(raw))
        .copyWith(ingredients: list);
  }

  Future<void> submitProposal({
    required TechCard techCard,
    required String authorEmployeeId,
  }) async {
    await _supabase.client.from('tech_card_change_requests').insert({
      'establishment_id': techCard.establishmentId,
      'tech_card_id': techCard.id,
      'proposed_payload': _proposalPayload(techCard),
      'author_employee_id': authorEmployeeId,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> listPending(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('tech_card_change_requests')
          .select(
            'id, tech_card_id, proposed_payload, author_employee_id, created_at, status',
          )
          .eq('establishment_id', establishmentId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      final out = <Map<String, dynamic>>[];
      for (final row in rows as List<dynamic>) {
        if (row is Map<String, dynamic>) {
          out.add(Map<String, dynamic>.from(row));
        }
      }
      return out;
    } catch (e, st) {
      devLog('TechCardChangeRequestService: listPending $e $st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    try {
      final row = await _supabase.client
          .from('tech_card_change_requests')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (e, st) {
      devLog('TechCardChangeRequestService: getById $e $st');
      return null;
    }
  }

  Future<void> approve({
    required String requestId,
    required String resolverEmployeeId,
    String? note,
  }) async {
    final row = await getById(requestId);
    if (row == null) throw StateError('ttk_change_not_found');
    if ((row['status'] as String?) != 'pending') {
      throw StateError('ttk_change_not_pending');
    }
    final proposed = row['proposed_payload'];
    if (proposed is! Map<String, dynamic>) {
      throw FormatException('ttk_change_bad_payload');
    }
    final card = _techCardFromProposal(Map<String, dynamic>.from(proposed));
    final svc = TechCardServiceSupabase();
    await svc.saveTechCard(
      card,
      changedByEmployeeId: resolverEmployeeId,
      changedByName: null,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.client.from('tech_card_change_requests').update({
      'status': 'approved',
      'resolved_at': now,
      'resolved_by_employee_id': resolverEmployeeId,
      if (note != null && note.isNotEmpty) 'resolution_note': note,
    }).eq('id', requestId);
  }

  Future<void> reject({
    required String requestId,
    required String resolverEmployeeId,
    String? note,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.client.from('tech_card_change_requests').update({
      'status': 'rejected',
      'resolved_at': now,
      'resolved_by_employee_id': resolverEmployeeId,
      if (note != null && note.isNotEmpty) 'resolution_note': note,
    }).eq('id', requestId);
  }
}
