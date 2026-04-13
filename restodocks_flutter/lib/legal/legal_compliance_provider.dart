import 'package:flutter/widgets.dart' show Locale;

/// Юридический регион для подстановки норм (ЕС / ЕАЭС и др.) в шаблоны документов.
enum ComplianceRegion {
  /// Испания
  spain,

  /// Франция
  france,

  /// Италия
  italy,

  /// Германия
  germany,

  /// Общий ЕС, английский интерфейс
  europeanUnionEnglish,

  /// Россия / ЕАЭС / СНГ (не EU): ТР ТС, ФЗ и т.д.
  cisEaeu,
}

/// Нормативные подписи для шаблонов (HACCP/APPCC, пищевое право, персональные данные, eIDAS).
class LegalCompliance {
  const LegalCompliance({
    required this.systemName,
    required this.foodLaw,
    required this.dataPrivacyLaw,
    required this.electronicSignatureLaw,
  });

  /// Название системы контроля (HACCP, APPCC, PMS и т.д.).
  final String systemName;

  /// База пищевого права (регламент 852/2004 + национальный акт).
  final String foodLaw;

  /// Защита персональных данных.
  final String dataPrivacyLaw;

  /// Электронная подпись (для ЕС — eIDAS).
  final String electronicSignatureLaw;
}

/// Провайдер юридических метаданных по локали интерфейса / языку экспорта PDF.
class LegalComplianceProvider {
  LegalComplianceProvider._();

  static const LegalCompliance _spain = LegalCompliance(
    systemName:
        'APPCC (Análisis de Peligros y Puntos de Control Críticos)',
    foodLaw:
        'Reglamento (CE) n.º 852/2004 y Real Decreto 191/2011',
    dataPrivacyLaw: 'RGPD y LOPDGDD',
    electronicSignatureLaw: 'Reglamento (UE) n.º 910/2014 (eIDAS)',
  );

  static const LegalCompliance _france = LegalCompliance(
    systemName: 'HACCP / Plan de Maîtrise Sanitaire (PMS)',
    foodLaw:
        'Règlement (CE) n° 852/2004 et Arrêté du 21 décembre 2009',
    dataPrivacyLaw: 'RGPD et Loi Informatique et Libertés',
    electronicSignatureLaw: 'Règlement (UE) n° 910/2014 (eIDAS)',
  );

  static const LegalCompliance _italy = LegalCompliance(
    systemName: 'HACCP (Autocontrollo Alimentare)',
    foodLaw: 'Regolamento (CE) n. 852/2004 e D.Lgs. 193/2007',
    dataPrivacyLaw: 'RGPD e Codice della Privacy',
    electronicSignatureLaw: 'Regolamento (UE) n. 910/2014 (eIDAS)',
  );

  static const LegalCompliance _germany = LegalCompliance(
    systemName: 'HACCP (Eigenkontrollsystem)',
    foodLaw:
        'Verordnung (EG) Nr. 852/2004 und Lebensmittelhygiene-Verordnung (LMHV)',
    dataPrivacyLaw: 'DSGVO und BDSG',
    electronicSignatureLaw: 'Verordnung (EU) Nr. 910/2014 (eIDAS)',
  );

  static const LegalCompliance _euEnglish = LegalCompliance(
    systemName: 'HACCP',
    foodLaw: 'Regulation (EC) No 852/2004',
    dataPrivacyLaw: 'GDPR (General Data Protection Regulation)',
    electronicSignatureLaw: 'Regulation (EU) No 910/2014 (eIDAS)',
  );

  /// ЕАЭС / РФ / СНГ: ссылки для шаблонов на ru/kk.
  static const LegalCompliance _cisEaeuRu = LegalCompliance(
    systemName: 'HACCP / ХАССП',
    foodLaw:
        'ТР ТС 021/2011 «О безопасности пищевой продукции» (ЕАЭС)',
    dataPrivacyLaw:
        '152-ФЗ «О персональных данных» (РФ) и применимое законодательство',
    electronicSignatureLaw:
        '63-ФЗ «Об электронной подписи» (РФ) и законы об ЭЦП государств СНГ',
  );

  /// То же для tr/vi: англоязычные обозначения норм.
  static const LegalCompliance _cisEaeuEn = LegalCompliance(
    systemName: 'HACCP',
    foodLaw:
        'EAEU Technical Regulation TR CU 021/2011 “On Food Safety”',
    dataPrivacyLaw:
        'Federal Law 152-FZ “On Personal Data” (Russian Federation) and applicable law',
    electronicSignatureLaw:
        'Federal Law 63-FZ “On Electronic Signature” (Russian Federation) and analogous CIS legislation',
  );

  /// Соответствие кода языка интерфейса региону норм (не путать с гражданством заведения).
  static ComplianceRegion regionForLocale(Locale locale) =>
      regionForLanguageCode(locale.languageCode);

  static ComplianceRegion regionForLanguageCode(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
        return ComplianceRegion.spain;
      case 'fr':
        return ComplianceRegion.france;
      case 'it':
        return ComplianceRegion.italy;
      case 'de':
        return ComplianceRegion.germany;
      case 'en':
        return ComplianceRegion.europeanUnionEnglish;
      case 'ru':
      case 'kk':
        return ComplianceRegion.cisEaeu;
      default:
        return ComplianceRegion.cisEaeu;
    }
  }

  static LegalCompliance complianceForRegion(ComplianceRegion region) {
    switch (region) {
      case ComplianceRegion.spain:
        return _spain;
      case ComplianceRegion.france:
        return _france;
      case ComplianceRegion.italy:
        return _italy;
      case ComplianceRegion.germany:
        return _germany;
      case ComplianceRegion.europeanUnionEnglish:
        return _euEnglish;
      case ComplianceRegion.cisEaeu:
        return _cisEaeuRu;
    }
  }

  /// Предпочитать вместо [complianceForRegion], если важен код языка (tr/vi vs ru/kk).
  static LegalCompliance complianceForLocale(Locale locale) =>
      complianceForLanguageCode(locale.languageCode);

  /// Учитывает язык: для tr/vi подставляются англоязычные обозначения норм ЕАЭС/РФ.
  static LegalCompliance complianceForLanguageCode(String languageCode) {
    final code = languageCode.toLowerCase();
    switch (code) {
      case 'es':
        return _spain;
      case 'fr':
        return _france;
      case 'it':
        return _italy;
      case 'de':
        return _germany;
      case 'en':
        return _euEnglish;
      case 'tr':
      case 'vi':
        return _cisEaeuEn;
      case 'ru':
      case 'kk':
      default:
        return _cisEaeuRu;
    }
  }

  /// Подстановка `{{SYSTEM_NAME}}`, `{{FOOD_LAW}}`, `{{DATA_PRIVACY_LAW}}`, `{{E_SIGNATURE_LAW}}`.
  static String applyCompliancePlaceholders(
    String template,
    LegalCompliance compliance,
  ) {
    return template
        .replaceAll('{{SYSTEM_NAME}}', compliance.systemName)
        .replaceAll('{{FOOD_LAW}}', compliance.foodLaw)
        .replaceAll('{{DATA_PRIVACY_LAW}}', compliance.dataPrivacyLaw)
        .replaceAll(
            '{{E_SIGNATURE_LAW}}', compliance.electronicSignatureLaw);
  }

  /// Языки экспорта PDF журналов, для которых показывается короткий футер eIDAS + защита данных.
  static const Set<String> journalPdfEuComplianceFooterLanguages = {
    'es',
    'fr',
    'it',
    'de',
    'en',
  };

  /// Две строки для подвала PDF (eIDAS + GDPR/национальная приватность). `null` — не показывать.
  static String? journalPdfComplianceFooter(String languageCode) {
    final lc = languageCode.toLowerCase();
    if (!journalPdfEuComplianceFooterLanguages.contains(lc)) return null;
    final c = complianceForLanguageCode(lc);
    switch (lc) {
      case 'es':
        return 'Identificación y registro con usuario: marco de referencia ${c.electronicSignatureLaw}. '
            'Datos personales: ${c.dataPrivacyLaw}.';
      case 'fr':
        return 'Identification et enregistrement par compte utilisateur : référence ${c.electronicSignatureLaw}. '
            'Données personnelles : ${c.dataPrivacyLaw}.';
      case 'it':
        return 'Identificazione e registrazione tramite account utente: riferimento ${c.electronicSignatureLaw}. '
            'Dati personali: ${c.dataPrivacyLaw}.';
      case 'de':
        return 'Anmeldung und Protokollierung über das Benutzerkonto: Referenzrahmen ${c.electronicSignatureLaw}. '
            'Personenbezogene Daten: ${c.dataPrivacyLaw}.';
      case 'en':
        return 'User sign-in and record keeping: electronic identification framework ${c.electronicSignatureLaw}. '
            'Personal data: ${c.dataPrivacyLaw}.';
      default:
        return null;
    }
  }
}
