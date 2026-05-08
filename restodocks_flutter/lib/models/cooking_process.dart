import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

import 'product.dart';

part 'cooking_process.g.dart';

/// Модель технологического процесса приготовления
@JsonSerializable()
class CookingProcess extends Equatable {
  @JsonKey(name: 'id')
  final String id;

  @JsonKey(name: 'name')
  final String name;

  @JsonKey(name: 'localized_names')
  final Map<String, String> localizedNames;

  // Коэффициенты изменения питательной ценности
  @JsonKey(name: 'calorie_multiplier')
  final double calorieMultiplier;

  @JsonKey(name: 'protein_multiplier')
  final double proteinMultiplier;

  @JsonKey(name: 'fat_multiplier')
  final double fatMultiplier;

  @JsonKey(name: 'carbs_multiplier')
  final double carbsMultiplier;

  // Потери веса при приготовлении (%)
  @JsonKey(name: 'weight_loss_percentage')
  final double weightLossPercentage;

  // Категории продуктов, к которым применим процесс
  @JsonKey(name: 'applicable_categories')
  final List<String> applicableCategories;

  const CookingProcess({
    required this.id,
    required this.name,
    required this.localizedNames,
    required this.calorieMultiplier,
    required this.proteinMultiplier,
    required this.fatMultiplier,
    required this.carbsMultiplier,
    required this.weightLossPercentage,
    required this.applicableCategories,
  });

  /// Локализованное название
  String getLocalizedName(String languageCode) {
    return localizedNames[languageCode] ?? name;
  }

  /// Применить процесс к продукту.
  /// [weightLossOverride] — ручная подстановка % ужарки (если null — используется среднее по способу).
  ProcessedProduct applyTo(Product product, double weight, {double? weightLossOverride}) {
    final multiplier = weight / 100.0;
    final lossPct = weightLossOverride ?? weightLossPercentage;
    final finalWeight = weight * (1.0 - lossPct / 100.0);

    return ProcessedProduct(
      originalProduct: product,
      cookingProcess: this,
      originalWeight: weight,
      finalWeight: finalWeight,
      totalCalories: (product.calories ?? 0) * multiplier * calorieMultiplier,
      totalProtein: (product.protein ?? 0) * multiplier * proteinMultiplier,
      totalFat: (product.fat ?? 0) * multiplier * fatMultiplier,
      totalCarbs: (product.carbs ?? 0) * multiplier * carbsMultiplier,
    );
  }

  /// Проверка, применим ли процесс к категории продукта
  bool isApplicableToCategory(String category) {
    return applicableCategories.contains(category) || applicableCategories.contains('all');
  }

  /// JSON сериализация
  factory CookingProcess.fromJson(Map<String, dynamic> json) => _$CookingProcessFromJson(json);
  Map<String, dynamic> toJson() => _$CookingProcessToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    localizedNames,
    calorieMultiplier,
    proteinMultiplier,
    fatMultiplier,
    carbsMultiplier,
    weightLossPercentage,
    applicableCategories,
  ];

  /// Предопределенные процессы приготовления
  /// Дефолтные weightLossPercentage должны совпадать с SQL `public._default_cooking_loss_rows()` (миграция seed глобальных % ужарки).
  static List<CookingProcess> get defaultProcesses => [
    // Смешивание (соусы, заправки и т.п.) — UI: ключ `cooking_process_mixing` в localizable.json
    CookingProcess(
      id: 'mixing',
      name: 'Mixing',
      localizedNames: {},
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),

    // Варка
    CookingProcess(
      id: 'boiling',
      name: 'Boiling',
      localizedNames: {
        'ru': 'Варка',
        'en': 'Boiling',
        'es': 'Hervir',
        'de': 'Kochen',
        'fr': 'Bouillir',
      },
      calorieMultiplier: 0.95,
      proteinMultiplier: 0.95,
      fatMultiplier: 0.90,
      carbsMultiplier: 0.98,
      weightLossPercentage: 25.0,
      applicableCategories: ['vegetables', 'meat', 'fish', 'grains', 'pasta', 'misc'],
    ),

    // Жарка на масле
    CookingProcess(
      id: 'frying',
      name: 'Frying',
      localizedNames: {
        'ru': 'Жарка',
        'en': 'Frying',
        'es': 'Freír',
        'de': 'Braten',
        'fr': 'Frire',
      },
      calorieMultiplier: 1.10,
      proteinMultiplier: 0.95,
      fatMultiplier: 1.20,
      carbsMultiplier: 0.98,
      weightLossPercentage: 15.0,
      applicableCategories: ['meat', 'fish', 'vegetables', 'misc'],
    ),

    // Запекание
    CookingProcess(
      id: 'baking',
      name: 'Baking',
      localizedNames: {
        'ru': 'Запекание',
        'en': 'Baking',
        'es': 'Hornear',
        'de': 'Backen',
        'fr': 'Cuire au four',
      },
      calorieMultiplier: 1.05,
      proteinMultiplier: 0.98,
      fatMultiplier: 1.05,
      carbsMultiplier: 0.97,
      weightLossPercentage: 20.0,
      applicableCategories: ['meat', 'fish', 'vegetables', 'dough'],
    ),

    // Тушение
    CookingProcess(
      id: 'stewing',
      name: 'Stewing',
      localizedNames: {
        'ru': 'Тушение',
        'en': 'Stewing',
        'es': 'Estofar',
        'de': 'Schmoren',
        'fr': 'Étouffée',
      },
      calorieMultiplier: 0.98,
      proteinMultiplier: 0.97,
      fatMultiplier: 0.95,
      carbsMultiplier: 0.99,
      weightLossPercentage: 30.0,
      applicableCategories: ['meat', 'vegetables'],
    ),

    // Су-вид
    CookingProcess(
      id: 'sous_vide',
      name: 'Sous-vide',
      localizedNames: {
        'ru': 'Су-вид',
        'en': 'Sous-vide',
        'es': 'Sous-vide',
        'de': 'Sous-vide',
        'fr': 'Sous-vide',
      },
      calorieMultiplier: 0.99,
      proteinMultiplier: 0.99,
      fatMultiplier: 0.98,
      carbsMultiplier: 1.00,
      weightLossPercentage: 5.0,
      applicableCategories: ['meat', 'fish'],
    ),

    // Ферментация
    CookingProcess(
      id: 'fermentation',
      name: 'Fermentation',
      localizedNames: {
        'ru': 'Ферментация',
        'en': 'Fermentation',
        'es': 'Fermentación',
        'de': 'Fermentation',
        'fr': 'Fermentation',
      },
      calorieMultiplier: 0.95,
      proteinMultiplier: 0.98,
      fatMultiplier: 0.95,
      carbsMultiplier: 0.90,
      weightLossPercentage: 10.0,
      applicableCategories: ['vegetables', 'dairy'],
    ),

    // Гриль
    CookingProcess(
      id: 'grilling',
      name: 'Grilling',
      localizedNames: {
        'ru': 'Гриль',
        'en': 'Grilling',
        'es': 'Asar a la parrilla',
        'de': 'Grillen',
        'fr': 'Griller',
      },
      calorieMultiplier: 1.08,
      proteinMultiplier: 0.96,
      fatMultiplier: 0.85,
      carbsMultiplier: 0.98,
      weightLossPercentage: 25.0,
      applicableCategories: ['meat', 'fish', 'vegetables'],
    ),

    // Обжарка горелкой
    CookingProcess(
      id: 'torch_browning',
      name: 'Torch Browning',
      localizedNames: {
        'ru': 'Обжарка горелкой',
        'en': 'Torch Browning',
        'es': 'Dorar con soplete',
        'de': 'Flamme bräunen',
        'fr': 'Brunir au chalumeau',
      },
      calorieMultiplier: 1.02,
      proteinMultiplier: 0.99,
      fatMultiplier: 0.98,
      carbsMultiplier: 0.99,
      weightLossPercentage: 2.0,
      applicableCategories: ['meat', 'fish', 'desserts'],
    ),

    // Пассеровка (быстрое обжаривание)
    CookingProcess(
      id: 'sauteing',
      name: 'Sautéing',
      localizedNames: {
        'ru': 'Пассеровка',
        'en': 'Sautéing',
        'es': 'Saltear',
        'de': 'Anschwitzen',
        'fr': 'Sauter',
      },
      calorieMultiplier: 1.05,
      proteinMultiplier: 0.97,
      fatMultiplier: 1.10,
      carbsMultiplier: 0.96,
      weightLossPercentage: 15.0,
      applicableCategories: ['vegetables', 'onions'],
    ),

    // Бланширование
    CookingProcess(
      id: 'blanching',
      name: 'Blanching',
      localizedNames: {
        'ru': 'Бланширование',
        'en': 'Blanching',
        'es': 'Blanquear',
        'de': 'Blanchieren',
        'fr': 'Blanchir',
      },
      calorieMultiplier: 0.98,
      proteinMultiplier: 0.99,
      fatMultiplier: 0.95,
      carbsMultiplier: 0.97,
      weightLossPercentage: 10.0,
      applicableCategories: ['vegetables'],
    ),

    // Пароварка
    CookingProcess(
      id: 'steaming',
      name: 'Steaming',
      localizedNames: {
        'ru': 'Пароварка',
        'en': 'Steaming',
        'es': 'Cocción al vapor',
        'de': 'Dämpfen',
        'fr': 'Cuisson vapeur',
      },
      calorieMultiplier: 0.97,
      proteinMultiplier: 0.98,
      fatMultiplier: 0.90,
      carbsMultiplier: 0.99,
      weightLossPercentage: 8.0,
      applicableCategories: ['vegetables', 'fish', 'meat', 'misc'],
    ),

    // Консервирование
    CookingProcess(
      id: 'canning',
      name: 'Canning',
      localizedNames: {
        'ru': 'Консервирование',
        'en': 'Canning',
        'es': 'Enlatado',
        'de': 'Konservierung',
        'fr': 'Conservation',
      },
      calorieMultiplier: 0.95,
      proteinMultiplier: 0.96,
      fatMultiplier: 0.94,
      carbsMultiplier: 0.98,
      weightLossPercentage: 5.0,
      applicableCategories: ['vegetables', 'fish', 'meat'],
    ),

    // Разделка (обвалка, нарезка — без потерь веса или минимальные)
    CookingProcess(
      id: 'cutting',
      name: 'Cutting',
      localizedNames: {
        'ru': 'Разделка',
        'en': 'Cutting',
        'es': 'Corte',
        'de': 'Zerteilen',
        'fr': 'Découpe',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
    // Бар: взбивание в шейкере
    CookingProcess(
      id: 'shaking',
      name: 'Shaking',
      localizedNames: {
        'ru': 'Шейк',
        'en': 'Shaking',
        'es': 'Coctelera',
        'kk': 'Шейкермен шайқау',
        'it': 'Shakerare',
        'tr': 'Shaker ile çalkalama',
        'vi': 'Lắc shaker',
        'de': 'Shaken',
        'fr': 'Shaker',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
    // Бар: перемешивание барной ложкой
    CookingProcess(
      id: 'stirring',
      name: 'Stirring',
      localizedNames: {
        'ru': 'Стир',
        'en': 'Stirring',
        'es': 'Mezclado en vaso',
        'kk': 'Араластыру (стир)',
        'it': 'Stirring',
        'tr': 'Karıştırma (stir)',
        'vi': 'Khuấy (stir)',
        'de': 'Rühren (Stir)',
        'fr': 'Mélange au verre (stir)',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
    // Бар: сборка напитка в бокале
    CookingProcess(
      id: 'building',
      name: 'Building',
      localizedNames: {
        'ru': 'Билд',
        'en': 'Building',
        'es': 'Montado en vaso',
        'kk': 'Тікелей жинау (build)',
        'it': 'Build nel bicchiere',
        'tr': 'Bardakta hazırlama (build)',
        'vi': 'Build trực tiếp trong ly',
        'de': 'Build im Glas',
        'fr': 'Montage au verre (build)',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
    // Бар: блендирование
    CookingProcess(
      id: 'blending',
      name: 'Blending',
      localizedNames: {
        'ru': 'Бленд',
        'en': 'Blending',
        'es': 'Licuado',
        'kk': 'Блендерлеу',
        'it': 'Frullatura',
        'tr': 'Blender ile hazırlama',
        'vi': 'Xay (blending)',
        'de': 'Blenden',
        'fr': 'Mixage (blender)',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
    // Бар: экстракция эспрессо
    CookingProcess(
      id: 'espresso_extraction',
      name: 'Espresso extraction',
      localizedNames: {
        'ru': 'Экстракция эспрессо',
        'en': 'Espresso extraction',
        'es': 'Extracción de espresso',
        'kk': 'Эспрессо экстракциясы',
        'it': 'Estrazione espresso',
        'tr': 'Espresso ekstraksiyonu',
        'vi': 'Chiết xuất espresso',
        'de': 'Espresso-Extraktion',
        'fr': 'Extraction espresso',
      },
      calorieMultiplier: 1.0,
      proteinMultiplier: 1.0,
      fatMultiplier: 1.0,
      carbsMultiplier: 1.0,
      weightLossPercentage: 0.0,
      applicableCategories: ['all'],
    ),
  ];

  static const Set<String> _barProcessIds = {
    'mixing',
    'shaking',
    'stirring',
    'building',
    'blending',
    'espresso_extraction',
    'steaming',
    'cutting',
    'boiling',
  };

  static List<CookingProcess> forDepartment(String department) {
    final dep = department.trim().toLowerCase();
    if (dep == 'bar') {
      return defaultProcesses
          .where((p) => _barProcessIds.contains(p.id))
          .toList();
    }
    return defaultProcesses;
  }

  /// Найти процесс по ID
  static CookingProcess? findById(String id) {
    return defaultProcesses.where((process) => process.id == id).firstOrNull;
  }

  /// Сопоставить значение из ИИ/импорта: id (`baking`), локализованное имя или EN-имя.
  static CookingProcess? resolveFromAiToken(String? token, [String languageCode = 'ru']) {
    final raw = token?.trim() ?? '';
    if (raw.isEmpty) return null;
    final byId = findById(raw);
    if (byId != null) return byId;
    final lower = raw.toLowerCase();
    for (final p in defaultProcesses) {
      if (p.id.toLowerCase() == lower) return p;
      if (p.name.trim().toLowerCase() == lower) return p;
      final loc = p.getLocalizedName(languageCode).trim().toLowerCase();
      if (loc == lower) return p;
      for (final v in p.localizedNames.values) {
        if (v.trim().toLowerCase() == lower) return p;
      }
    }
    return null;
  }

  /// Получить процессы для категории продукта
  static List<CookingProcess> forCategory(String category) {
    return defaultProcesses.where((process) => process.isApplicableToCategory(category)).toList();
  }
}

/// Результат применения технологического процесса к продукту
class ProcessedProduct {
  final Product originalProduct;
  final CookingProcess cookingProcess;
  final double originalWeight;
  final double finalWeight;
  final double totalCalories;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;

  const ProcessedProduct({
    required this.originalProduct,
    required this.cookingProcess,
    required this.originalWeight,
    required this.finalWeight,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalFat,
    required this.totalCarbs,
  });

  /// Процент потери веса
  double get weightLossPercentage {
    if (originalWeight <= 0) return 0;
    return ((originalWeight - finalWeight) / originalWeight) * 100.0;
  }

  /// КБЖУ на 100г готового продукта
  double get caloriesPer100g => (totalCalories / finalWeight) * 100;
  double get proteinPer100g => (totalProtein / finalWeight) * 100;
  double get fatPer100g => (totalFat / finalWeight) * 100;
  double get carbsPer100g => (totalCarbs / finalWeight) * 100;
}