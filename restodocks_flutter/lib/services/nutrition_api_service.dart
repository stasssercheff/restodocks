import 'dart:convert';

import 'package:http/http.dart' as http;

/// Результат поиска КБЖУ
class NutritionResult {
  final double? calories;
  final double? protein;
  final double? fat;
  final double? carbs;

  const NutritionResult({
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
  });

  bool get hasData =>
      (calories != null && calories! > 0) ||
      (protein != null && protein! > 0) ||
      (fat != null && fat! > 0) ||
      (carbs != null && carbs! > 0);
}

/// Сервис для загрузки КБЖУ из Open Food Facts
class NutritionApiService {
  static const _baseUrl = 'https://world.openfoodfacts.org';
  static const _timeout = Duration(seconds: 8);

  /// Макс. калории на 100 г для «обычных» продуктов (исключаем масло ~880, сухофрукты и т.п.).
  /// Авокадо ~160, масло авокадо ~880 — при совпадении по названию мог подтянуться не тот продукт.
  static const _maxSaneKcal = 320.0;
  static const _minSaneKcal = 1.0;

  /// «Плохие» слова — пропускаем сухофрукты, чипсы, масло, порошки
  static const _skipWords = [
    'dried', 'сухой', 'сушен', 'chips', 'чипс', 'fried', 'жарен',
    'oil', 'масло', 'powder', 'порошок', 'crisp', 'snack', 'дегидр',
    'dehydrat', 'roasted', 'жарен', 'toasted',
  ];

  /// Поиск КБЖУ по названию продукта (с проверкой адекватности)
  static Future<NutritionResult?> fetchNutrition(String productName) async {
    if (productName.trim().isEmpty) return null;
    final query = Uri.encodeQueryComponent(productName.trim());
    final url = Uri.parse(
      '$_baseUrl/cgi/search.pl?search_terms=$query&search_simple=1&action=process&json=1&page_size=15',
    );
    try {
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final products = json['products'] as List<dynamic>?;
      if (products == null || products.isEmpty) return null;

      final searchLower = productName.toLowerCase();
      NutritionResult? best;
      double bestScore = -1;

      for (final p in products) {
        final map = p as Map<String, dynamic>?;
        if (map == null) continue;
        final name = (map['product_name'] as String? ?? map['product_name_ru'] ?? '').toString().toLowerCase();
        if (_shouldSkip(name)) continue;

        final nutriments = map['nutriments'] as Map<String, dynamic>?;
        if (nutriments == null) continue;
        double? kcal = _parseNum(nutriments['energy-kcal_100g']);
        if (kcal == null) {
          final kj = _parseNum(nutriments['energy_100g']);
          if (kj != null) kcal = kj / 4.184;
        }
        final protein = _parseNum(nutriments['proteins_100g']);
        final fat = _parseNum(nutriments['fat_100g']);
        final carbs = _parseNum(nutriments['carbohydrates_100g']);
        if (kcal == null && protein == null && fat == null && carbs == null) continue;

        if (kcal != null && (kcal < _minSaneKcal || kcal > _maxSaneKcal)) continue;

        final score = _matchScore(searchLower, name, kcal ?? 0);
        if (score > bestScore) {
          bestScore = score;
          best = NutritionResult(
            calories: kcal,
            protein: protein,
            fat: fat,
            carbs: carbs,
          );
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  static bool _shouldSkip(String name) {
    return _skipWords.any((w) => name.contains(w));
  }

  static double _matchScore(String search, String productName, double kcal) {
    double score = 0;
    final searchWords = search.split(RegExp(r'\s+')).where((s) => s.length > 1);
    for (final w in searchWords) {
      if (productName.contains(w)) score += 2;
    }
    if (searchWords.isNotEmpty) score /= searchWords.length;
    if (productName.startsWith(search) || search.startsWith(productName)) score += 3;
    return score;
  }

  static double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
