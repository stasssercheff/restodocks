import '../models/establishment_fiscal_settings.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

class EstablishmentFiscalSettingsService {
  EstablishmentFiscalSettingsService._();
  static final EstablishmentFiscalSettingsService instance =
      EstablishmentFiscalSettingsService._();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'establishment_fiscal_settings';

  Future<EstablishmentFiscalSettings?> fetch(String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from(_table)
          .select()
          .eq('establishment_id', establishmentId)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return null;
      return EstablishmentFiscalSettings.fromJson(
        Map<String, dynamic>.from(list.first as Map),
      );
    } catch (e, st) {
      devLog('EstablishmentFiscalSettingsService: fetch $e $st');
      rethrow;
    }
  }

  Future<EstablishmentFiscalSettings> upsert(
    EstablishmentFiscalSettings settings,
  ) async {
    final row = await _supabase.client
        .from(_table)
        .upsert(settings.toUpsertRow(), onConflict: 'establishment_id')
        .select()
        .single();
    return EstablishmentFiscalSettings.fromJson(
      Map<String, dynamic>.from(row),
    );
  }
}
