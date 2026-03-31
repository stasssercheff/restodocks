import '../services/localization_service.dart';

/// Заголовок AppBar для бланка из payload (стандарт / выборочная; iiko — отдельный экран).
String inventoryBlankTitleForPayload(
    Map<String, dynamic>? payload, LocalizationService loc) {
  if (payload?['type']?.toString() == 'selective_inventory') {
    return loc.t('inventory_selective_blank_title') ?? 'Выборочная инвентаризация';
  }
  return loc.t('inventory_blank_title');
}

/// Краткая подпись вида бланка для списков (кабинет шефа и т.п.).
String inventoryDocKindSubtitle(
    Map<String, dynamic>? payload, LocalizationService loc) {
  final t = payload?['type']?.toString() ?? '';
  if (t == 'selective_inventory') {
    return loc.t('inventory_selective_type_name') ?? 'Выборочная инвентаризация';
  }
  if (t == 'iiko_inventory') {
    return loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko';
  }
  return loc.t('doc_type_inventory') ?? 'Инвентаризация';
}
