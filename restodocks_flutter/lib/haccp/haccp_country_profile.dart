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

  /// Рекомендуемая форма бланка — строки в [localizable.json] `haccp_recommended_sample_*`.
  static String recommendedSampleLabelTr(
    String? countryCode,
    String Function(String key, {Map<String, String>? args}) tr,
  ) {
    final cc = (countryCode ?? 'RU').toUpperCase();
    final key = 'haccp_recommended_sample_$cc';
    final out = tr(key);
    if (out != key) return out;
    return tr('haccp_recommended_sample_fallback');
  }

  /// Юридическая строка под заголовком журнала — `haccp_journal_legal_*`, плейсхолдер `{code}`.
  static String journalLegalLineTr(
    String? countryCode,
    HaccpLogType logType,
    String Function(String key, {Map<String, String>? args}) tr,
  ) {
    final cc = (countryCode ?? 'RU').toUpperCase();
    final key = 'haccp_journal_legal_$cc';
    final out = tr(key, args: {'code': logType.code});
    if (out != key) return out;
    return tr('haccp_journal_legal_fallback', args: {'code': logType.code});
  }

  /// Нижний колонтитул PDF — `haccp_journal_footer_*`.
  static String journalFooterLineTr(
    String? countryCode,
    String Function(String key, {Map<String, String>? args}) tr,
  ) {
    final cc = (countryCode ?? 'RU').toUpperCase();
    final key = 'haccp_journal_footer_$cc';
    final out = tr(key);
    if (out != key) return out;
    return tr('haccp_journal_footer_fallback');
  }

  static String templateCountryLabel(
    String countryCode,
    String languageCode,
  ) {
    final label = countryCodeAndNameLabel(countryCode, languageCode);
    final lc = languageCode.toLowerCase();
    switch (lc) {
      case 'ru':
        return 'Шаблон страны: $label';
      case 'es':
        return 'Pais de plantilla: $label';
      case 'fr':
        return 'Pays du modele: $label';
      case 'it':
        return 'Paese del modello: $label';
      case 'de':
        return 'Vorlagenland: $label';
      case 'tr':
        return 'Sablon ulkesi: $label';
      default:
        return 'Template country: $label';
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

  static String templateCountryUpdatedLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Страна шаблона HACCP обновлена';
      case 'es':
        return 'Pais de plantilla HACCP actualizado';
      case 'fr':
        return 'Pays du modele HACCP mis a jour';
      case 'it':
        return 'Paese modello HACCP aggiornato';
      case 'de':
        return 'HACCP-Vorlagenland aktualisiert';
      case 'tr':
        return 'HACCP sablon ulkesi guncellendi';
      default:
        return 'HACCP template country updated';
    }
  }

  static String templateCountryAutoLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Страна шаблона HACCP переключена на автоопределение';
      case 'es':
        return 'Pais de plantilla HACCP cambiado a deteccion automatica';
      case 'fr':
        return 'Pays du modele HACCP bascule en detection automatique';
      case 'it':
        return 'Paese modello HACCP passato al rilevamento automatico';
      case 'de':
        return 'HACCP-Vorlagenland auf automatische Erkennung umgestellt';
      case 'tr':
        return 'HACCP sablon ulkesi otomatik algilamaya gecirildi';
      default:
        return 'HACCP template country switched to auto-detected';
    }
  }

  static String incompatibleJournalsDisabledLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Отключено несовместимых журналов';
      case 'es':
        return 'Diarios incompatibles desactivados';
      case 'fr':
        return 'Journaux incompatibles desactives';
      case 'it':
        return 'Registri incompatibili disattivati';
      case 'de':
        return 'Inkompatible Journale deaktiviert';
      case 'tr':
        return 'Uyumsuz gunlukler devre disi birakildi';
      default:
        return 'Incompatible journals disabled';
    }
  }

  static String profileTitleLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Профиль страны HACCP';
      case 'es':
        return 'Perfil de pais HACCP';
      case 'fr':
        return 'Profil pays HACCP';
      case 'it':
        return 'Profilo paese HACCP';
      case 'de':
        return 'HACCP-Landesprofil';
      case 'tr':
        return 'HACCP ulke profili';
      default:
        return 'HACCP country profile';
    }
  }

  static String profileAutoLockHintLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Зафиксируйте вручную для стабильного шаблона';
      case 'es':
        return 'Fijelo manualmente para bloquear la plantilla';
      case 'fr':
        return 'Definissez manuellement pour verrouiller le modele';
      case 'it':
        return 'Impostare manualmente per bloccare il modello';
      case 'de':
        return 'Manuell festlegen, um die Vorlage zu sperren';
      case 'tr':
        return 'Sablonu sabitlemek icin manuel secin';
      default:
        return 'Set manually to lock template';
    }
  }

  static String templateCountryFieldLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Страна шаблона для HACCP форм/PDF';
      case 'es':
        return 'Pais de plantilla para formularios/PDF HACCP';
      case 'fr':
        return 'Pays du modele pour formulaires/PDF HACCP';
      case 'it':
        return 'Paese modello per moduli/PDF HACCP';
      case 'de':
        return 'Vorlagenland fur HACCP-Formulare/PDF';
      case 'tr':
        return 'HACCP form/PDF sablon ulkesi';
      default:
        return 'Template country for HACCP forms/PDF';
    }
  }

  static String useAutoTemplateLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Использовать автоопределенный шаблон';
      case 'es':
        return 'Usar plantilla autodetectada';
      case 'fr':
        return 'Utiliser le modele detecte automatiquement';
      case 'it':
        return 'Usa modello rilevato automaticamente';
      case 'de':
        return 'Automatisch erkannte Vorlage verwenden';
      case 'tr':
        return 'Otomatik algilanan sablonu kullan';
      default:
        return 'Use auto-detected template';
    }
  }

  static String templateUsageHintLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Выбранный профиль страны применяется к шаблону HACCP формы и сохраненному PDF.';
      case 'es':
        return 'El perfil de pais seleccionado se aplica a la plantilla del formulario HACCP y al PDF guardado.';
      case 'fr':
        return 'Le profil pays selectionne est applique au modele de formulaire HACCP et au PDF enregistre.';
      case 'it':
        return 'Il profilo paese selezionato viene applicato al modello modulo HACCP e al PDF salvato.';
      case 'de':
        return 'Das ausgewahlte Landesprofil wird auf die HACCP-Formularvorlage und das gespeicherte PDF angewendet.';
      case 'tr':
        return 'Secilen ulke profili HACCP form sablonuna ve kaydedilen PDF duzenine uygulanir.';
      default:
        return 'Selected country profile is used for HACCP form template and saved PDF layout.';
    }
  }

  static String availableCountriesLabel(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Доступные страны HACCP (нормативные профили)';
      case 'es':
        return 'Paises HACCP disponibles (perfiles regulatorios)';
      case 'fr':
        return 'Pays HACCP disponibles (profils reglementaires)';
      case 'it':
        return 'Paesi HACCP disponibili (profili normativi)';
      case 'de':
        return 'Verfugbare HACCP-Lander (regulatorische Profile)';
      case 'tr':
        return 'Kullanilabilir HACCP ulkeleri (duzenleyici profiller)';
      default:
        return 'Available HACCP countries (regulatory profiles)';
    }
  }

  static String notSupportedBodyLabel(
    String languageCode,
    String countryCode,
  ) {
    final cc = countryCode.toUpperCase();
    switch (languageCode.toLowerCase()) {
      case 'ru':
        return 'Доступны только журналы, поддерживаемые для профиля страны $cc.';
      case 'es':
        return 'Solo estan disponibles los diarios compatibles con el perfil de pais $cc.';
      case 'fr':
        return 'Seuls les journaux pris en charge pour le profil pays $cc sont disponibles.';
      case 'it':
        return 'Sono disponibili solo i registri supportati per il profilo paese $cc.';
      case 'de':
        return 'Nur Journale, die fur das Landesprofil $cc unterstutzt werden, sind verfugbar.';
      case 'tr':
        return '$cc ulke profili icin desteklenen gunlukler kullanilabilir.';
      default:
        return 'Only journals supported for country profile $cc are available.';
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

  static String datePatternForCountry(String? countryCode) {
    switch ((countryCode ?? '').toUpperCase()) {
      case 'US':
        return 'MM/dd/yyyy';
      case 'GB':
      case 'ES':
      case 'FR':
      case 'IT':
        return 'dd/MM/yyyy';
      case 'DE':
      case 'TR':
      case 'RU':
      default:
        return 'dd.MM.yyyy';
    }
  }

  static String fallbackLogTypeName(
    HaccpLogType logType,
    String languageCode,
  ) {
    if (languageCode.toLowerCase() == 'ru') return logType.displayNameRu;
    switch (logType.code) {
      case 'health_hygiene':
        return 'Hygiene journal (staff)';
      case 'fridge_temperature':
        return 'Refrigeration temperature log';
      case 'warehouse_temp_humidity':
        return 'Warehouse temperature and humidity log';
      case 'finished_product_brakerage':
        return 'Finished product quality log';
      case 'incoming_raw_brakerage':
        return 'Incoming raw product quality log';
      case 'frying_oil':
        return 'Frying oil usage log';
      case 'med_book_registry':
        return 'Medical book registry';
      case 'med_examinations':
        return 'Medical examinations log';
      case 'disinfectant_accounting':
        return 'Disinfectant accounting log';
      case 'equipment_washing':
        return 'Equipment washing and disinfection log';
      case 'general_cleaning_schedule':
        return 'General cleaning schedule log';
      case 'sieve_filter_magnet':
        return 'Sieve/filter/magnet checks log';
      default:
        return logType.code.replaceAll('_', ' ');
    }
  }

  static String resolveLogTypeTitle({
    required HaccpLogType logType,
    required String languageCode,
    required String? localizedValue,
  }) {
    final v = localizedValue?.trim();
    if (v == null || v.isEmpty || v == logType.displayNameKey) {
      return fallbackLogTypeName(logType, languageCode);
    }
    return v;
  }

  static String? _countryByAddress(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    final normalized = address.trim().toLowerCase();
    final compact = normalized
        .replaceAll(',', ' ')
        .replaceAll('.', ' ')
        .replaceAll(';', ' ')
        .replaceAll(':', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const tokenMap = <String, String>{
      'россия': 'RU',
      'russia': 'RU',
      'сша': 'US',
      'usa': 'US',
      'united states': 'US',
      'us': 'US',
      'испания': 'ES',
      'spain': 'ES',
      'españa': 'ES',
      'france': 'FR',
      'франция': 'FR',
      'united kingdom': 'GB',
      'great britain': 'GB',
      'britain': 'GB',
      'uk': 'GB',
      'великобритания': 'GB',
      'turkey': 'TR',
      'turkiye': 'TR',
      'tuerkiye': 'TR',
      'türkiye': 'TR',
      'турция': 'TR',
      'italy': 'IT',
      'italia': 'IT',
      'италия': 'IT',
      'germany': 'DE',
      'deutschland': 'DE',
      'германия': 'DE',
    };
    for (final entry in tokenMap.entries) {
      if (compact.contains(entry.key)) return entry.value;
    }
    return null;
  }
}
