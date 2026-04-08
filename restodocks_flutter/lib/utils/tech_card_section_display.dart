import '../models/models.dart';
import '../services/localization_service.dart';

/// Порядок групп цехов — как в списке ТТК.
const kTechCardSectionOrder = [
  'all',
  'hot_kitchen',
  'cold_kitchen',
  'preparation',
  'prep',
  'confectionery',
  'pastry',
  'grill',
  'pizza',
  'sushi',
  'bakery',
  'banquet_catering',
  'bar',
  'hidden',
];

String techCardSectionKeyForGroup(TechCard tc) {
  if (tc.sections.isEmpty) return 'hidden';
  if (tc.sections.contains('all')) return 'all';
  return tc.sections.first;
}

String techCardSectionCodeToLabel(String code, LocalizationService loc) {
  const keys = {
    'hot_kitchen': 'section_hot_kitchen',
    'cold_kitchen': 'section_cold_kitchen',
    'preparation': 'section_prep',
    'prep': 'section_prep',
    'confectionery': 'section_pastry',
    'pastry': 'section_pastry',
    'grill': 'section_grill',
    'pizza': 'section_pizza',
    'sushi': 'section_sushi',
    'bakery': 'section_bakery',
    'banquet_catering': 'section_banquet_catering',
    'bar': 'department_bar',
  };
  final key = keys[code];
  return key != null ? loc.t(key) : code;
}

String techCardSectionGroupLabel(String sectionKey, LocalizationService loc) {
  if (sectionKey == 'all') return loc.t('ttk_sections_all');
  if (sectionKey == 'hidden') return loc.t('ttk_sections_hidden');
  return techCardSectionCodeToLabel(sectionKey, loc);
}

/// Группировка карточек по цеху (один ключ на карточку).
List<({String section, List<TechCard> cards})> groupTechCardsBySection(
    List<TechCard> cards) {
  final grouped = <String, List<TechCard>>{};
  for (final tc in cards) {
    final key = techCardSectionKeyForGroup(tc);
    grouped.putIfAbsent(key, () => []).add(tc);
  }
  final result = <({String section, List<TechCard> cards})>[];
  final seen = <String>{};
  for (final s in kTechCardSectionOrder) {
    final list = grouped.remove(s);
    if (list != null && list.isNotEmpty) {
      result.add((section: s, cards: list));
      seen.add(s);
    }
  }
  for (final e in grouped.entries) {
    result.add((section: e.key, cards: e.value));
  }
  return result;
}
