import 'dart:async';

import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Черновики форм в `account_form_drafts` (продолжение с другого устройства).
class CloudDraftService {
  CloudDraftService._();
  static final CloudDraftService instance = CloudDraftService._();

  final SupabaseService _supabase = SupabaseService();
  bool _draftTableUnavailable = false;
  Timer? _throttle;
  String? _pendingKey;
  Map<String, dynamic>? _pendingPayload;

  /// Отложенная запись (не дёргать Supabase на каждый символ).
  void scheduleUpsert(String draftKey, Map<String, dynamic> payload) {
    if (!_supabase.isAuthenticated) return;
    if (_draftTableUnavailable) return;
    _pendingKey = draftKey;
    _pendingPayload = Map<String, dynamic>.from(payload);
    _throttle?.cancel();
    _throttle = Timer(const Duration(seconds: 2), () {
      final k = _pendingKey;
      final p = _pendingPayload;
      if (k == null || p == null) return;
      unawaited(upsertPayload(k, p));
    });
  }

  Future<void> flushPending() async {
    _throttle?.cancel();
    _throttle = null;
    final k = _pendingKey;
    final p = _pendingPayload;
    _pendingKey = null;
    _pendingPayload = null;
    if (k != null && p != null) await upsertPayload(k, p);
  }

  Future<Map<String, dynamic>?> fetchPayload(String draftKey) async {
    if (!_supabase.isAuthenticated) return null;
    if (_draftTableUnavailable) return null;
    final uid = _supabase.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _supabase.client
          .from('account_form_drafts')
          .select('payload, updated_at')
          .eq('user_id', uid)
          .eq('draft_key', draftKey)
          .maybeSingle();
      if (row == null) return null;
      final p = row['payload'];
      if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
      if (p is Map) return Map<String, dynamic>.from(p);
      return null;
    } catch (e) {
      if (_isDraftTableUnavailableError(e)) _draftTableUnavailable = true;
      devLog('CloudDraft fetchPayload: $e');
      return null;
    }
  }

  Future<DateTime?> fetchUpdatedAt(String draftKey) async {
    if (!_supabase.isAuthenticated) return null;
    if (_draftTableUnavailable) return null;
    final uid = _supabase.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _supabase.client
          .from('account_form_drafts')
          .select('updated_at')
          .eq('user_id', uid)
          .eq('draft_key', draftKey)
          .maybeSingle();
      if (row == null) return null;
      final s = row['updated_at']?.toString();
      return s != null ? DateTime.tryParse(s) : null;
    } catch (e) {
      if (_isDraftTableUnavailableError(e)) _draftTableUnavailable = true;
      devLog('CloudDraft fetchUpdatedAt: $e');
      return null;
    }
  }

  Future<void> upsertPayload(
      String draftKey, Map<String, dynamic> payload) async {
    if (!_supabase.isAuthenticated) return;
    if (_draftTableUnavailable) return;
    final uid = _supabase.currentUser?.id;
    if (uid == null) return;
    final copy = Map<String, dynamic>.from(payload);
    copy['draftSavedAt'] = DateTime.now().toUtc().toIso8601String();
    try {
      await _supabase.client.from('account_form_drafts').upsert(
        {
          'user_id': uid,
          'draft_key': draftKey,
          'payload': copy,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,draft_key',
      );
    } catch (e) {
      if (_isDraftTableUnavailableError(e)) _draftTableUnavailable = true;
      devLog('CloudDraft upsert: $e');
    }
  }

  Future<void> deleteDraft(String draftKey) async {
    if (!_supabase.isAuthenticated) return;
    if (_draftTableUnavailable) return;
    final uid = _supabase.currentUser?.id;
    if (uid == null) return;
    try {
      await _supabase.client
          .from('account_form_drafts')
          .delete()
          .eq('user_id', uid)
          .eq('draft_key', draftKey);
    } catch (e) {
      if (_isDraftTableUnavailableError(e)) _draftTableUnavailable = true;
      devLog('CloudDraft delete: $e');
    }
  }

  bool _isDraftTableUnavailableError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('account_form_drafts') &&
        (msg.contains('404') ||
            msg.contains('does not exist') ||
            msg.contains('pgrst'));
  }
}
