import 'dart:convert';

import 'package:flutter/services.dart';

/// Пресеты стран из assets/data/world_tax_presets.json (версионируемый справочник).
class FiscalTaxPresetsService {
  FiscalTaxPresetsService._();
  static final FiscalTaxPresetsService instance = FiscalTaxPresetsService._();

  Map<String, dynamic>? _raw;
  String? _version;

  Future<void> ensureLoaded() async {
    if (_raw != null) return;
    final s = await rootBundle.loadString('assets/data/world_tax_presets.json');
    _raw = jsonDecode(s) as Map<String, dynamic>;
    _version = _raw!['version'] as String?;
  }

  String? get version => _version;

  /// Ключи регионов: RU, AE, ...
  Future<List<String>> regionCodes() async {
    await ensureLoaded();
    final regions = _raw!['regions'] as Map<String, dynamic>?;
    if (regions == null) return ['RU'];
    return regions.keys.toList()..sort();
  }

  Future<FiscalRegionPreset?> region(String code) async {
    await ensureLoaded();
    final regions = _raw!['regions'] as Map<String, dynamic>?;
    if (regions == null) return null;
    final r = regions[code.toUpperCase()];
    if (r is! Map<String, dynamic>) return null;
    return FiscalRegionPreset.fromJson(code.toUpperCase(), r);
  }

  Future<Map<String, String>> systemTagDescriptions() async {
    await ensureLoaded();
    final tags = _raw!['systemTags'] as Map<String, dynamic>?;
    if (tags == null) return {};
    final out = <String, String>{};
    for (final e in tags.entries) {
      final m = e.value;
      if (m is Map && m['description'] != null) {
        out[e.key] = m['description'].toString();
      }
    }
    return out;
  }
}

class FiscalRegionPreset {
  FiscalRegionPreset({
    required this.code,
    required this.defaultPriceTaxMode,
    required this.vatRates,
    this.defaultVatPercent,
    this.labelKey,
    this.salesTaxNoteKey,
    this.extraTaxes = const [],
  });

  final String code;
  final String defaultPriceTaxMode;
  final List<double> vatRates;
  final double? defaultVatPercent;
  final String? labelKey;
  final String? salesTaxNoteKey;
  final List<Map<String, dynamic>> extraTaxes;

  factory FiscalRegionPreset.fromJson(String code, Map<String, dynamic> j) {
    final vr = j['vatRates'];
    final rates = <double>[];
    if (vr is List) {
      for (final x in vr) {
        if (x is num) rates.add(x.toDouble());
      }
    }
    final dvp = j['defaultVatPercent'];
    return FiscalRegionPreset(
      code: code,
      defaultPriceTaxMode: (j['defaultPriceTaxMode'] as String?) ?? 'tax_included',
      vatRates: rates,
      defaultVatPercent: dvp is num ? dvp.toDouble() : null,
      labelKey: j['labelKey'] as String?,
      salesTaxNoteKey: j['salesTaxNoteKey'] as String?,
      extraTaxes: () {
        final ex = j['extraTaxes'];
        if (ex is! List) return <Map<String, dynamic>>[];
        return ex.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }(),
    );
  }
}
