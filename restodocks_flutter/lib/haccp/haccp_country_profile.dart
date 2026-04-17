import '../models/haccp_log_type.dart';
import '../models/models.dart';

/// Нормативный профиль HACCP по стране (не язык интерфейса).
class HaccpCountryProfile {
  final String countryCode;
  final String displayName;
  final String legalFramework;
  final List<HaccpLogType> supportedLogTypes;

  const HaccpCountryProfile({
    required this.countryCode,
    required this.displayName,
    required this.legalFramework,
    required this.supportedLogTypes,
  });
}

abstract final class HaccpCountryProfiles {
  static final List<HaccpCountryProfile> available = [
    HaccpCountryProfile(
      countryCode: 'RU',
      displayName: 'Russia',
      legalFramework: 'SanPiN / EAEU',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'US',
      displayName: 'United States',
      legalFramework: 'FDA Food Code / HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'ES',
      displayName: 'Spain',
      legalFramework: 'EU 852/2004 + APPCC',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'FR',
      displayName: 'France',
      legalFramework: 'EU 852/2004 + HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'GB',
      displayName: 'United Kingdom',
      legalFramework: 'UK Food Hygiene + HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'TR',
      displayName: 'Turkey',
      legalFramework: 'Turkish Food Codex + HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'IT',
      displayName: 'Italy',
      legalFramework: 'EU 852/2004 + HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
    HaccpCountryProfile(
      countryCode: 'DE',
      displayName: 'Germany',
      legalFramework: 'EU 852/2004 + HACCP',
      supportedLogTypes: HaccpLogType.supportedInApp,
    ),
  ];

  static HaccpCountryProfile fallback() => byCountryCode('RU');

  static HaccpCountryProfile byCountryCode(String? code) {
    final normalized = code?.trim().toUpperCase();
    return available.firstWhere(
      (p) => p.countryCode == normalized,
      orElse: fallback,
    );
  }

  static HaccpCountryProfile resolveForEstablishment(Establishment est) {
    final byAddress = _countryByAddress(est.address);
    if (byAddress != null) return byCountryCode(byAddress);

    // Fallback для старых данных, где страна не записывалась явно.
    if (est.defaultCurrency == 'USD') return byCountryCode('US');
    if (est.defaultCurrency == 'TRY') return byCountryCode('TR');
    if (est.defaultCurrency == 'GBP') return byCountryCode('GB');
    if (est.defaultCurrency == 'EUR') return byCountryCode('DE');
    return fallback();
  }

  static String effectiveCountryCodeForEstablishment(
    Establishment est, {
    String? overrideCountryCode,
  }) {
    final normalizedOverride = overrideCountryCode?.trim().toUpperCase();
    if (normalizedOverride != null &&
        normalizedOverride.isNotEmpty &&
        available.any((p) => p.countryCode == normalizedOverride)) {
      return normalizedOverride;
    }
    return resolveForEstablishment(est).countryCode;
  }

  static String recommendedSampleLabel(String? countryCode) {
    switch ((countryCode ?? '').toUpperCase()) {
      case 'US':
        return 'Recommended FDA-style record form';
      case 'ES':
        return 'Modelo recomendado APPCC';
      case 'FR':
        return 'Modele recommande HACCP';
      case 'GB':
        return 'Recommended HACCP record template';
      case 'TR':
        return 'Tavsiye edilen HACCP kayit formu';
      case 'IT':
        return 'Modello consigliato HACCP';
      case 'DE':
        return 'Empfohlenes HACCP-Protokollformular';
      case 'RU':
      default:
        return 'Рекомендуемый образец';
    }
  }

  static String journalLegalLine(
    String? countryCode,
    HaccpLogType logType,
  ) {
    switch ((countryCode ?? '').toUpperCase()) {
      case 'US':
        return 'FDA Food Code / HACCP record: ${logType.code}';
      case 'ES':
        return 'APPCC (Reglamento (CE) 852/2004): ${logType.code}';
      case 'FR':
        return 'HACCP (Reglement (CE) 852/2004): ${logType.code}';
      case 'GB':
        return 'UK Food Hygiene / HACCP record: ${logType.code}';
      case 'TR':
        return 'Turkish Food Codex / HACCP kaydi: ${logType.code}';
      case 'IT':
        return 'HACCP (Regolamento (CE) 852/2004): ${logType.code}';
      case 'DE':
        return 'HACCP (VO (EG) Nr. 852/2004): ${logType.code}';
      case 'RU':
      default:
        return 'СанПиН / ХАССП: ${logType.code}';
    }
  }

  static String journalFooterLine(
    String? countryCode,
    HaccpLogType logType,
  ) {
    switch ((countryCode ?? '').toUpperCase()) {
      case 'US':
        return 'FDA HACCP compliance record';
      case 'ES':
        return 'Registro APPCC conforme normativa espanola/UE';
      case 'FR':
        return 'Registre HACCP conforme aux exigences UE';
      case 'GB':
        return 'HACCP record compliant with UK hygiene guidance';
      case 'TR':
        return 'HACCP kaydi, Turkiye gida hijyen kurallarina uygun';
      case 'IT':
        return 'Registro HACCP conforme ai requisiti UE';
      case 'DE':
        return 'HACCP-Nachweis gemaess EU-Hygienevorgaben';
      case 'RU':
      default:
        return 'Журнал ХАССП (внутренний производственный контроль)';
    }
  }

  static String templateCountryLabel(
    String countryCode,
    String languageCode,
  ) {
    final profile = byCountryCode(countryCode);
    final localizedCountry = countryNameForLanguage(
      profile.countryCode,
      languageCode,
    );
    final lc = languageCode.toLowerCase();
    switch (lc) {
      case 'ru':
        return 'Шаблон страны: ${profile.countryCode} - $localizedCountry';
      case 'es':
        return 'Pais de plantilla: ${profile.countryCode} - $localizedCountry';
      case 'fr':
        return 'Pays du modele: ${profile.countryCode} - $localizedCountry';
      case 'it':
        return 'Paese del modello: ${profile.countryCode} - $localizedCountry';
      case 'de':
        return 'Vorlagenland: ${profile.countryCode} - $localizedCountry';
      case 'tr':
        return 'Sablon ulkesi: ${profile.countryCode} - $localizedCountry';
      default:
        return 'Template country: ${profile.countryCode} - $localizedCountry';
    }
  }

  static String countryNameForLanguage(
      String countryCode, String languageCode) {
    final cc = countryCode.toUpperCase();
    final lc = languageCode.toLowerCase();
    switch (lc) {
      case 'ru':
        return switch (cc) {
          'RU' => 'Россия',
          'US' => 'США',
          'ES' => 'Испания',
          'FR' => 'Франция',
          'GB' => 'Великобритания',
          'TR' => 'Турция',
          'IT' => 'Италия',
          'DE' => 'Германия',
          _ => byCountryCode(cc).displayName,
        };
      case 'es':
        return switch (cc) {
          'RU' => 'Rusia',
          'US' => 'Estados Unidos',
          'ES' => 'Espana',
          'FR' => 'Francia',
          'GB' => 'Reino Unido',
          'TR' => 'Turquia',
          'IT' => 'Italia',
          'DE' => 'Alemania',
          _ => byCountryCode(cc).displayName,
        };
      case 'fr':
        return switch (cc) {
          'RU' => 'Russie',
          'US' => 'Etats-Unis',
          'ES' => 'Espagne',
          'FR' => 'France',
          'GB' => 'Royaume-Uni',
          'TR' => 'Turquie',
          'IT' => 'Italie',
          'DE' => 'Allemagne',
          _ => byCountryCode(cc).displayName,
        };
      case 'it':
        return switch (cc) {
          'RU' => 'Russia',
          'US' => 'Stati Uniti',
          'ES' => 'Spagna',
          'FR' => 'Francia',
          'GB' => 'Regno Unito',
          'TR' => 'Turchia',
          'IT' => 'Italia',
          'DE' => 'Germania',
          _ => byCountryCode(cc).displayName,
        };
      case 'de':
        return switch (cc) {
          'RU' => 'Russland',
          'US' => 'Vereinigte Staaten',
          'ES' => 'Spanien',
          'FR' => 'Frankreich',
          'GB' => 'Vereinigtes Konigreich',
          'TR' => 'Turkei',
          'IT' => 'Italien',
          'DE' => 'Deutschland',
          _ => byCountryCode(cc).displayName,
        };
      case 'tr':
        return switch (cc) {
          'RU' => 'Rusya',
          'US' => 'Amerika Birlesik Devletleri',
          'ES' => 'Ispanya',
          'FR' => 'Fransa',
          'GB' => 'Birlesik Krallik',
          'TR' => 'Turkiye',
          'IT' => 'Italya',
          'DE' => 'Almanya',
          _ => byCountryCode(cc).displayName,
        };
      default:
        return byCountryCode(cc).displayName;
    }
  }

  static String countryCodeAndNameLabel(
    String countryCode,
    String languageCode,
  ) {
    final cc = countryCode.toUpperCase();
    return '$cc - ${countryNameForLanguage(cc, languageCode)}';
  }

  static String profileSourceLabel({
    required bool manual,
    required String languageCode,
  }) {
    final lc = languageCode.toLowerCase();
    if (manual) {
      switch (lc) {
        case 'ru':
          return 'Источник профиля: выбран вручную';
        case 'es':
          return 'Origen del perfil: seleccion manual';
        case 'fr':
          return 'Source du profil: selection manuelle';
        case 'it':
          return 'Origine profilo: selezione manuale';
        case 'de':
          return 'Profilquelle: manuelle Auswahl';
        case 'tr':
          return 'Profil kaynagi: manuel secim';
        default:
          return 'Profile source: manual selection';
      }
    }

    switch (lc) {
      case 'ru':
        return 'Источник профиля: автоопределение';
      case 'es':
        return 'Origen del perfil: deteccion automatica';
      case 'fr':
        return 'Source du profil: detection automatique';
      case 'it':
        return 'Origine profilo: rilevamento automatico';
      case 'de':
        return 'Profilquelle: automatische Erkennung';
      case 'tr':
        return 'Profil kaynagi: otomatik algilama';
      default:
        return 'Profile source: auto-detected';
    }
  }

  static String legalFrameworkLabel(
    String countryCode,
    String languageCode,
  ) {
    final cc = countryCode.toUpperCase();
    final lc = languageCode.toLowerCase();
    switch (cc) {
      case 'RU':
        return lc == 'ru' ? 'СанПиН / ЕАЭС' : 'SanPiN / EAEU';
      case 'US':
        return lc == 'ru' ? 'FDA Food Code / HACCP' : 'FDA Food Code / HACCP';
      case 'ES':
        return lc == 'es'
            ? 'Reglamento (CE) 852/2004 + APPCC'
            : 'EU 852/2004 + APPCC';
      case 'FR':
        return lc == 'fr'
            ? 'Reglement (CE) 852/2004 + HACCP'
            : 'EU 852/2004 + HACCP';
      case 'GB':
        return lc == 'ru'
            ? 'Гигиена пищевого производства UK + HACCP'
            : 'UK Food Hygiene + HACCP';
      case 'TR':
        return lc == 'tr'
            ? 'Turk Gida Kodeksi + HACCP'
            : 'Turkish Food Codex + HACCP';
      case 'IT':
        return lc == 'it'
            ? 'Regolamento (CE) 852/2004 + HACCP'
            : 'EU 852/2004 + HACCP';
      case 'DE':
        return lc == 'de' ? 'VO (EG) 852/2004 + HACCP' : 'EU 852/2004 + HACCP';
      default:
        return byCountryCode(cc).legalFramework;
    }
  }

  static String? _countryByAddress(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final normalized = address.trim().toLowerCase();
    const map = <String, String>{
      'россия': 'RU',
      'russia': 'RU',
      'сша': 'US',
      'usa': 'US',
      'united states': 'US',
      'испания': 'ES',
      'spain': 'ES',
      'france': 'FR',
      'франция': 'FR',
      'united kingdom': 'GB',
      'great britain': 'GB',
      'великобритания': 'GB',
      'turkey': 'TR',
      'tuerkiye': 'TR',
      'türkiye': 'TR',
      'турция': 'TR',
      'italy': 'IT',
      'италия': 'IT',
      'germany': 'DE',
      'deutschland': 'DE',
      'германия': 'DE',
    };
    return map[normalized];
  }
}
