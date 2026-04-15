/// Режим нормативной подачи журналов автоконтроля: не только перевод интерфейса,
/// но и привязка к локальному праву (названия регистров, ссылки в шапке/PDF).
///
/// Тексты для каждого языка лежат в `assets/translations/localizable.json`
/// (например `haccp_sanpin_line_*`, `haccp_log_*_title`). Здесь — перечень языков,
/// для которых эти ключи заполнены под юрисдикцию, отличную от РФ/СНГ.
abstract final class HaccpJournalRegulatoryLocale {
  /// Коды языка UI с профилем норм ЕС в `localizable.json` (не СНГ/СанПиН).
  static const Set<String> localizedRegulatoryProfileCodes = {
    'es',
    'fr',
    'it',
    'de',
    'en',
  };

  static bool usesLocalizedRegulatoryProfile(String languageCode) =>
      localizedRegulatoryProfileCodes.contains(languageCode);
}
