/// Кулинарные единицы измерения (мировые стандарты)
class CulinaryUnits {
  CulinaryUnits._();

  /// Код единицы -> множитель для перевода в граммы (для веса)
  /// Для объёма: мл ~ 1г (вода), для жидкостей условно 1:1
  static const Map<String, double> _toGrams = {
    'g': 1,
    'г': 1,
    'gram': 1,
    'gramme': 1,
    'грамм': 1,
    'кг': 1000,
    'kg': 1000,
    'kilogram': 1000,
    'мг': 0.001,
    'mg': 0.001,
    'lb': 453.592,
    'фунт': 453.592,
    'pound': 453.592,
    'oz': 28.3495,
    'унция': 28.3495,
    'ounce': 28.3495,
    'шт': 0, // специально: нужен gramsPerPiece
    'pcs': 0,
    'piece': 0,
    'штука': 0,
    'ml': 1,
    'мл': 1,
    'milliliter': 1,
    'миллилитр': 1,
    'l': 1000,
    'л': 1000,
    'liter': 1000,
    'литр': 1000,
    'gal': 3785.41,
    'галлон': 3785.41,
    'gallon': 3785.41,
    'fl_oz': 29.5735,
    'cup': 240,
    'стакан': 240,
    'tbsp': 15,
    'ст.л': 15,
    'tablespoon': 15,
    'tsp': 5,
    'ч.л': 5,
    'teaspoon': 5,
    'pinch': 0.5,
    'щепотка': 0.5,
    'dash': 1,
    'банка': 400, // условно
    'can': 400,
    'коробка': 1000, // условно
    'box': 1000,
    'упаковка': 500,
    'pack': 500,
    'package': 500,
    'пучок': 30,
    'bunch': 30,
    'зубчик': 5,
    'clove': 5,
    'долька': 10,
    'slice': 10,
    'ломтик': 20,
    'piece_slice': 20,
  };

  /// Все единицы для выбора (id, отображаемое название)
  static const List<({String id, String ru, String en})> all = [
    (id: 'g', ru: 'г', en: 'g'),
    (id: 'kg', ru: 'кг', en: 'kg'),
    (id: 'mg', ru: 'мг', en: 'mg'),
    (id: 'pcs', ru: 'штуки', en: 'pcs'),
    (id: 'шт', ru: 'штуки', en: 'pcs'),
    (id: 'lb', ru: 'фунт', en: 'lb'),
    (id: 'oz', ru: 'унция', en: 'oz'),
    (id: 'ml', ru: 'мл', en: 'ml'),
    (id: 'l', ru: 'л', en: 'L'),
    (id: 'gal', ru: 'галлон', en: 'gal'),
    (id: 'fl_oz', ru: 'ж.унция', en: 'fl oz'),
    (id: 'cup', ru: 'стакан', en: 'cup'),
    (id: 'tbsp', ru: 'ст.л', en: 'tbsp'),
    (id: 'tsp', ru: 'ч.л', en: 'tsp'),
    (id: 'pinch', ru: 'щепотка', en: 'pinch'),
    (id: 'clove', ru: 'зубчик', en: 'clove'),
    (id: 'bunch', ru: 'пучок', en: 'bunch'),
    (id: 'slice', ru: 'долька', en: 'slice'),
    (id: 'pack', ru: 'упак.', en: 'pack'),
    (id: 'can', ru: 'банка', en: 'can'),
    (id: 'box', ru: 'коробка', en: 'box'),
  ];

  /// Конвертировать значение в граммы
  static double toGrams(double value, String unitId, {double? gramsPerPiece}) {
    final u = unitId.toLowerCase().trim();
    if (u == 'pcs' || u == 'шт' || u == 'piece' || u == 'штука') {
      return value * (gramsPerPiece ?? 50);
    }
    final factor = _toGrams[u] ?? _toGrams[u.replaceAll(' ', '')] ?? 1;
    return value * factor;
  }

  /// Конвертировать граммы обратно в единицу (для отображения)
  static double fromGrams(double grams, String unitId, {double? gramsPerPiece}) {
    final u = unitId.toLowerCase().trim();
    if (u == 'pcs' || u == 'шт') {
      final gpp = gramsPerPiece ?? 50;
      return gpp > 0 ? grams / gpp : grams;
    }
    final factor = _toGrams[u] ?? 1;
    return factor > 0 ? grams / factor : grams;
  }

  /// Получить отображаемое название единицы
  static String displayName(String unitId, String lang) {
    for (final e in all) {
      if (e.id == unitId) return lang == 'ru' ? e.ru : e.en;
    }
    return unitId;
  }

  /// Единица является счётной (шт, зубчик и т.д.) — нужен ввод "грамм на единицу"
  static bool isCountable(String unitId) {
    const countable = ['pcs', 'шт', 'clove', 'slice', 'bunch'];
    return countable.any((c) => unitId.toLowerCase() == c);
  }
}
