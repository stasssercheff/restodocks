/// Строка establishment_fiscal_settings.
class EstablishmentFiscalSettings {
  const EstablishmentFiscalSettings({
    required this.establishmentId,
    required this.taxRegion,
    required this.priceTaxMode,
    this.vatOverridePercent,
    this.fiscalSectionId,
    required this.updatedAt,
  });

  final String establishmentId;
  final String taxRegion;

  /// tax_included | tax_excluded
  final String priceTaxMode;
  final double? vatOverridePercent;
  final String? fiscalSectionId;
  final DateTime updatedAt;

  factory EstablishmentFiscalSettings.fromJson(Map<String, dynamic> json) {
    final v = json['vat_override_percent'];
    return EstablishmentFiscalSettings(
      establishmentId: json['establishment_id'] as String,
      taxRegion: (json['tax_region'] as String?)?.toUpperCase() ?? 'RU',
      priceTaxMode:
          (json['price_tax_mode'] as String?) ?? 'tax_included',
      vatOverridePercent: v is num ? v.toDouble() : null,
      fiscalSectionId: json['fiscal_section_id'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toUpsertRow() {
    return {
      'establishment_id': establishmentId,
      'tax_region': taxRegion,
      'price_tax_mode': priceTaxMode,
      'vat_override_percent': vatOverridePercent,
      'fiscal_section_id':
          fiscalSectionId != null && fiscalSectionId!.trim().isEmpty
              ? null
              : fiscalSectionId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
