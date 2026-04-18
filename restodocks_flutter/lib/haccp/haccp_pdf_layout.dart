/// Семейство макета PDF журналов ХАССП по стране заведения (не языку UI).
/// Отдельные визуальные варианты под типичные «официальные» формы региона.
enum HaccpPdfLayoutFamily {
  /// СанПиН / ЕАЭС — плотные многострочные шапки граф.
  ruSanPin,

  /// США: FDA Food Code — короткие подписи колонок, двойная °C/°F для температур.
  usFda,

  /// ЕС 852/2004 — общий блок для ES/FR/IT/DE.
  eu852,

  /// Великобритания.
  gbFoodSafety,

  /// Турция.
  trCodex,
  ;

  static HaccpPdfLayoutFamily fromCountry(String? countryCode) {
    switch ((countryCode ?? 'RU').toUpperCase()) {
      case 'US':
        return HaccpPdfLayoutFamily.usFda;
      case 'GB':
        return HaccpPdfLayoutFamily.gbFoodSafety;
      case 'TR':
        return HaccpPdfLayoutFamily.trCodex;
      // EU / EEA + CH: типовой макет бланка под Регламент (ЕС) 852/2004.
      case 'AT':
      case 'BE':
      case 'BG':
      case 'HR':
      case 'CY':
      case 'CZ':
      case 'DK':
      case 'EE':
      case 'FI':
      case 'FR':
      case 'DE':
      case 'GR':
      case 'HU':
      case 'IE':
      case 'IT':
      case 'LV':
      case 'LT':
      case 'LU':
      case 'MT':
      case 'NL':
      case 'PL':
      case 'PT':
      case 'RO':
      case 'SK':
      case 'SI':
      case 'ES':
      case 'SE':
      case 'IS':
      case 'LI':
      case 'NO':
      case 'CH':
        return HaccpPdfLayoutFamily.eu852;
      case 'RU':
      default:
        return HaccpPdfLayoutFamily.ruSanPin;
    }
  }
}

/// Суффикс ключа `haccp_*` для PDF-шапок под региональный макет.
extension HaccpPdfLayoutFamilyHeaderSuffix on HaccpPdfLayoutFamily {
  String? get pdfHeaderSuffix => switch (this) {
        HaccpPdfLayoutFamily.ruSanPin => null,
        HaccpPdfLayoutFamily.usFda => '_layout_us',
        HaccpPdfLayoutFamily.eu852 => '_layout_eu',
        HaccpPdfLayoutFamily.gbFoodSafety => '_layout_gb',
        HaccpPdfLayoutFamily.trCodex => '_layout_tr',
      };
}
