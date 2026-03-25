import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/product_name_utils.dart';

/// Результат поиска КБЖУ и аллергенов
class NutritionResult {
  final double? calories;
  final double? protein;
  final double? fat;
  final double? carbs;
  final bool? containsGluten;
  final bool? containsLactose;

  const NutritionResult({
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.containsGluten,
    this.containsLactose,
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
  static const _timeout = Duration(seconds: 4);

  /// Макс. калории на 100 г для «обычных» продуктов (исключаем масло ~880, сухофрукты и т.п.).
  /// Авокадо ~160, масло авокадо ~880 — при совпадении по названию мог подтянуться не тот продукт.
  static const _maxSaneKcal = 320.0;
  /// Чистый сахар / патока / карамель — обычно 380–400 ккал/100 г (выше общего потолка 320).
  static const _maxSaneKcalSugar = 420.0;
  static const _minSaneKcal = 1.0;

  /// «Плохие» слова — пропускаем сухофрукты, чипсы, масло, порошки
  static const _skipWords = [
    'dried', 'сухой', 'сушен', 'chips', 'чипс', 'fried', 'жарен',
    'oil', 'масло', 'powder', 'порошок', 'crisp', 'snack', 'дегидр',
    'dehydrat', 'roasted', 'жарен', 'toasted',
  ];

  /// Сахар и чистые углеводные подсластители: у них ккал/100 г типично ~387, иначе отсекаются лимитом 320.
  static bool _isSugarOrPureCarbSweetenerName(String lower) {
    return lower.contains('сахар') ||
        lower.contains('sugar') ||
        lower.contains('sucrose') ||
        lower.contains('saccharose') ||
        lower.contains('пудра') && (lower.contains('сахар') || lower.contains('sugar')) ||
        lower.contains('icing') ||
        lower.contains('патока') ||
        lower.contains('molasses') ||
        lower.contains('treacle') ||
        lower.contains('карамель') ||
        lower.contains('caramel') ||
        (lower.contains('глюкоз') || lower.contains('glucose')) ||
        (lower.contains('фруктоз') || lower.contains('fructose')) ||
        (lower.contains('сироп') &&
            (lower.contains('глюкоз') ||
                lower.contains('glucose') ||
                lower.contains('кукуруз') ||
                lower.contains('corn')));
  }

  /// Ограничить/подставить калории от ИИ по названию: авокадо не 655, грудка не 0.
  static double? saneCaloriesForProduct(String productName, double? rawCalories) {
    final lower = productName.trim().toLowerCase();
    // Куриная грудка/филе: ИИ часто возвращает 0 — подставляем ~165 ккал/100г
    if ((lower.contains('грудка') || lower.contains('филе') || lower.contains('chicken') || lower.contains('куриц') || lower.contains('кура ')) &&
        (rawCalories == null || rawCalories < 50)) return 165.0;
    if (rawCalories == null) return null;
    // Высококалорийные: масло, орехи, сухофрукты, шоколад — не режем
    if (lower.contains('масло') || lower.contains('oil') || lower.contains('орех') || lower.contains('nut') ||
        lower.contains('сухофрукт') || lower.contains('dried') || lower.contains('шоколад') || lower.contains('chocolate') ||
        lower.contains('сливоч') || lower.contains('butter') || lower.contains('сало') || lower.contains('lard')) {
      return rawCalories;
    }
    // Авокадо (фрукт): не 655, а ~160 ккал/100г
    if ((lower.contains('авокадо') || lower.contains('avocado')) && rawCalories > 220) return 160.0;
    // Сахар ~387 ккал/100г — не режем до 320
    if (_isSugarOrPureCarbSweetenerName(lower) && rawCalories <= _maxSaneKcalSugar) {
      return rawCalories;
    }
    // Обычные продукты: макс 320 ккал/100г
    if (rawCalories > _maxSaneKcal) return _maxSaneKcal;
    return rawCalories;
  }

  /// Поиск КБЖУ по названию продукта (с проверкой адекватности).
  /// Через Edge Function fetch-nutrition-off — обход CORS и 504 в DevTools.
  static Future<NutritionResult?> fetchNutrition(String productName) async {
    if (productName.trim().isEmpty) return null;
    final clean = stripIikoPrefix(productName).trim();
    if (clean.isEmpty) return null;
    Map<String, dynamic>? raw;
    try {
      final client = Supabase.instance.client;
      final res = await client.functions
          .invoke('fetch-nutrition-off', queryParameters: {'q': clean})
          .timeout(_timeout);
      if (res.status == 200 && res.data is Map) {
        raw = Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {
      raw = null;
    }
    if (raw == null) return null;
    try {
      final json = raw;
      final products = json['products'] as List<dynamic>?;
      if (products == null || products.isEmpty) return null;

      final searchLower = clean.toLowerCase();
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

        final maxKcal =
            _isSugarOrPureCarbSweetenerName(name) ? _maxSaneKcalSugar : _maxSaneKcal;
        if (kcal != null && (kcal < _minSaneKcal || kcal > maxKcal)) continue;

        final tags = (map['allergens_tags'] as List<dynamic>?)?.cast<String>() ?? [];
        final containsGluten = tags.any((t) =>
            t.contains('gluten') || t.contains('wheat') || t.contains('cereals'));
        final containsLactose = tags.any((t) =>
            t.contains('milk') || t.contains('lactose'));

        final score = _matchScore(searchLower, name, kcal ?? 0);
        if (score > bestScore) {
          bestScore = score;
          best = NutritionResult(
            calories: kcal,
            protein: protein,
            fat: fat,
            carbs: carbs,
            containsGluten: tags.isNotEmpty ? containsGluten : null,
            containsLactose: tags.isNotEmpty ? containsLactose : null,
          );
        }
      }
      return best;
    } catch (_) {
      return null;
    }
  }

  static bool _shouldSkip(String name) {
    final lower = name.toLowerCase();
    // «Icing sugar powder» — не отбрасываем как «powder» (это сахар).
    if (_isSugarOrPureCarbSweetenerName(lower)) {
      return _skipWords
          .where((w) => w != 'powder' && w != 'порошок')
          .any((w) => lower.contains(w));
    }
    return _skipWords.any((w) => lower.contains(w));
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
