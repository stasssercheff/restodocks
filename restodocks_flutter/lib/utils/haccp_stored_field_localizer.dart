import '../models/product.dart';
import '../models/tech_card.dart';
import '../services/localization_service.dart';

/// Отображение сохранённых в БД строк журналов ХАССП на языке UI:
/// — ТТК / продукт из номенклатуры по совпадению снимка;
/// — типовые фразы (органолептика, допуск и т.д.) по словарю.
class HaccpStoredFieldLocalizer {
  HaccpStoredFieldLocalizer._();

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Найти продукт, если в записи сохранено то же имя, что в каталоге (RU/EN в `names`).
  static Product? matchProduct(Iterable<Product> products, String? snapshot) {
    if (snapshot == null || snapshot.trim().isEmpty) return null;
    final n = _norm(snapshot);
    for (final p in products) {
      if (_norm(p.name) == n) return p;
      final names = p.names;
      if (names == null) continue;
      for (final v in names.values) {
        if (v.trim().isNotEmpty && _norm(v) == n) return p;
      }
    }
    return null;
  }

  /// Название блюда/продукции для бракеража готовой продукции.
  static String displayBrakerageDishName({
    required String? productName,
    required TechCard? techCard,
    required Product? matchedProduct,
    required String languageCode,
    required LocalizationService loc,
  }) {
    if (techCard != null) {
      return techCard.getDisplayNameInLists(languageCode);
    }
    if (matchedProduct != null) {
      return matchedProduct.getLocalizedName(languageCode);
    }
    return localizeFreeText(productName, loc);
  }

  /// То же для входящего сырья (наименование в номенклатуре или словарь).
  static String displayIncomingProductName({
    required String? productName,
    required Product? matchedProduct,
    required String languageCode,
    required LocalizationService loc,
  }) {
    if (matchedProduct != null) {
      return matchedProduct.getLocalizedName(languageCode);
    }
    return localizeFreeText(productName, loc);
  }

  /// Разрешение к реализации: снимок мог быть на RU или EN при сохранении.
  static String localizeApprovalSnapshot(String? raw, LocalizationService loc) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final r = _norm(raw);
    const allowedRu = {'разрешено', 'допущено'};
    const deniedRu = {'запрещено', 'отклонено'};
    const allowedEn = {'permitted', 'allowed'};
    const deniedEn = {'not permitted', 'denied'};
    if (allowedRu.contains(r) || allowedEn.contains(r)) {
      return loc.t('haccp_approval_allowed');
    }
    if (deniedRu.contains(r) || deniedEn.contains(r)) {
      return loc.t('haccp_approval_denied');
    }
    return raw;
  }

  /// Органолептика, примечания, взвешивание — только известные пресеты.
  static String localizeFreeText(String? raw, LocalizationService loc) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final key = _phraseKey(_norm(raw));
    if (key != null) {
      final t = loc.t(key);
      if (t != key) return t;
    }
    return raw;
  }

  /// Ключ локализации для нормализованной фразы или null.
  static String? _phraseKey(String normalized) {
    return _ruPhraseToKey[normalized];
  }

  /// Типовые формулировки, которые часто вводят вручную на русском.
  static const Map<String, String> _ruPhraseToKey = {
    'не испорчено': 'haccp_snapshot_not_spoiled',
    'испорчено': 'haccp_snapshot_spoiled',
    'удовлетворительно': 'haccp_snapshot_satisfactory',
    'неудовлетворительно': 'haccp_snapshot_unsatisfactory',
    'соответствует': 'haccp_snapshot_compliant',
    'не соответствует': 'haccp_snapshot_non_compliant',
    'норма': 'haccp_snapshot_norm',
    'отклонение': 'haccp_snapshot_deviation',
    'допущено': 'haccp_snapshot_admitted',
    'не допущено': 'haccp_snapshot_not_admitted',
    'лосось': 'haccp_food_salmon',
    'семга': 'haccp_food_salmon_trout',
    'форель': 'haccp_food_trout',
    'курица': 'haccp_food_chicken',
    'говядина': 'haccp_food_beef',
    'свинина': 'haccp_food_pork',
  };
}
