import '../utils/dev_log.dart';
import 'supabase_service.dart';

enum PosShiftReportAudienceScope { all, zones }

class PosShiftReportAudienceSettings {
  const PosShiftReportAudienceSettings({
    required this.scope,
    required this.zones,
  });

  final PosShiftReportAudienceScope scope;
  final List<String> zones;

  bool get isAll => scope == PosShiftReportAudienceScope.all;

  Map<String, dynamic> toJson() {
    return {
      'scope': isAll ? 'all' : 'zones',
      'zones': zones,
    };
  }

  factory PosShiftReportAudienceSettings.fromJson(Map<String, dynamic> json) {
    final rawScope = (json['scope'] ?? 'all').toString();
    final rawZones = (json['zones'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    final scope =
        rawScope == 'zones' ? PosShiftReportAudienceScope.zones : PosShiftReportAudienceScope.all;
    return PosShiftReportAudienceSettings(
      scope: scope,
      zones: rawZones,
    );
  }

  static const PosShiftReportAudienceSettings kDefaultAll =
      PosShiftReportAudienceSettings(scope: PosShiftReportAudienceScope.all, zones: <String>[]);
}

class PosShiftReportAudienceService {
  PosShiftReportAudienceService._();
  static final PosShiftReportAudienceService instance = PosShiftReportAudienceService._();

  final SupabaseService _supabase = SupabaseService();

  static const List<String> allowedZones = <String>[
    'kitchen',
    'bar',
    'banquet',
  ];

  Future<PosShiftReportAudienceSettings> fetchForEstablishment(
      String establishmentId) async {
    try {
      final rows = await _supabase.client
          .from('pos_shift_report_audience_settings')
          .select('scope, zones')
          .eq('establishment_id', establishmentId)
          .limit(1);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return PosShiftReportAudienceSettings.kDefaultAll;
      final row = list.first;
      if (row is! Map<String, dynamic>) {
        return PosShiftReportAudienceSettings.kDefaultAll;
      }
      return PosShiftReportAudienceSettings.fromJson(Map<String, dynamic>.from(row));
    } catch (e, st) {
      devLog('PosShiftReportAudienceService: fetch $e $st');
      return PosShiftReportAudienceSettings.kDefaultAll;
    }
  }

  Future<void> upsertForOwner({
    required String establishmentId,
    required String updatedByEmployeeId,
    required PosShiftReportAudienceSettings settings,
  }) async {
    final zones = settings.isAll
        ? <String>[]
        : settings.zones.where(allowedZones.contains).toSet().toList();
    await _supabase.client.from('pos_shift_report_audience_settings').upsert({
      'establishment_id': establishmentId,
      'scope': settings.isAll ? 'all' : 'zones',
      'zones': zones,
      'updated_by_employee_id': updatedByEmployeeId,
    });
  }
}
