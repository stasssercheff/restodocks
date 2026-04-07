import 'package:equatable/equatable.dart';

import 'tt_ingredient.dart';

/// Технологическая карта (ТТК)
class TechCard extends Equatable {
  /// Оверлей: язык UI → id ТТК → переведённое название (несколько языков хранятся одновременно).
  static final Map<String, Map<String, String>> _translationOverlayByLang = {};

  /// Завершён полный прогрев для пары заведение + язык (сессия + диск).
  static final Map<String, Set<String>> _warmedLanguagesByEstablishment = {};

  /// [languageCode] — целевой язык слоя (en, ru, …). Другие языки не трогаем.
  static void setTranslationOverlay(
    Map<String, String> map, {
    required String languageCode,
    bool merge = true,
  }) {
    if (map.isEmpty && merge) return;
    final bucket =
        _translationOverlayByLang.putIfAbsent(languageCode, () => {});
    if (merge) {
      bucket.addAll(map);
    } else {
      _translationOverlayByLang[languageCode] = Map<String, String>.from(map);
    }
  }

  /// Текущий слой для языка (для ensureMissing и т.п.).
  static Map<String, String> snapshotTranslationOverlay(String languageCode) =>
      Map<String, String>.from(_translationOverlayByLang[languageCode] ?? {});

  /// Сериализация для SharedPreferences.
  static Map<String, Map<String, String>> exportTranslationOverlays() {
    return _translationOverlayByLang.map(
      (k, v) => MapEntry(k, Map<String, String>.from(v)),
    );
  }

  static void importTranslationOverlays(
    Map<String, Map<String, String>> data, {
    bool merge = true,
  }) {
    for (final e in data.entries) {
      setTranslationOverlay(e.value, languageCode: e.key, merge: merge);
    }
  }

  static void restoreWarmedLanguages(
      String dataEstablishmentId, Set<String> langs) {
    _warmedLanguagesByEstablishment[dataEstablishmentId.trim()] =
        Set<String>.from(langs);
  }

  static Set<String> exportWarmedLanguages(String dataEstablishmentId) =>
      Set<String>.from(
        _warmedLanguagesByEstablishment[dataEstablishmentId.trim()] ?? {});

  static bool translationOverlaySessionMatches(
      String dataEstablishmentId, String lang) {
    return _warmedLanguagesByEstablishment[dataEstablishmentId.trim()]
            ?.contains(lang) ??
        false;
  }

  static void markTranslationOverlaySession(
      String dataEstablishmentId, String lang) {
    final id = dataEstablishmentId.trim();
    _warmedLanguagesByEstablishment.putIfAbsent(id, () => {}).add(lang);
  }

  static void clearTranslationOverlay() {
    _translationOverlayByLang.clear();
    _warmedLanguagesByEstablishment.clear();
  }

  final String id;
  final String dishName;
  final Map<String, String>? dishNameLocalized;
  final String category;
  // Цеха: [] = Скрыто (только шеф/су-шеф), ['all'] = все, ['hot_kitchen', ...] = конкретные
  final List<String> sections;

  /// Отдел заведения: kitchen | bar (колонка tech_cards.department в БД).
  final String department;
  final bool isSemiFinished; // true = ПФ (полуфабрикат), false = блюдо
  final double portionWeight; // вес порции в граммах
  final double yield; // выход готового блюда в граммах
  final Map<String, String>?
      technologyLocalized; // технология приготовления, многоязычно
  /// Описание и состав для меню зала (гостям), не кухонная ТТК.
  final String? descriptionForHall;
  final String? compositionForHall;

  /// Продажная стоимость. Устанавливается шефом (кухня) и барменеджером (бар).
  final double? sellingPrice;

  /// URL фото: блюдо — до 1, ПФ — до 10. Storage bucket tech_card_photos.
  final List<String>? photoUrls;
  final List<TTIngredient> ingredients;
  final String establishmentId;
  final String createdBy; // ID сотрудника-создателя
  final DateTime createdAt;
  final DateTime updatedAt;

  const TechCard({
    required this.id,
    required this.dishName,
    this.dishNameLocalized,
    required this.category,
    this.sections = const [],
    this.department = 'kitchen',
    this.isSemiFinished = true,
    required this.portionWeight,
    required this.yield,
    this.technologyLocalized,
    this.descriptionForHall,
    this.compositionForHall,
    this.sellingPrice,
    this.photoUrls,
    required this.ingredients,
    required this.establishmentId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Фабричный конструктор для создания из JSON
  factory TechCard.fromJson(Map<String, dynamic> json) {
    return TechCard(
      id: json['id'] as String,
      dishName: json['dish_name'] as String,
      dishNameLocalized:
          (json['dish_name_localized'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as String),
      ),
      category: json['category'] as String,
      sections: (json['sections'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      department: (json['department'] as String?)?.trim().isNotEmpty == true
          ? (json['department'] as String).trim()
          : 'kitchen',
      isSemiFinished: json['is_semi_finished'] as bool? ?? true,
      portionWeight: (json['portion_weight'] as num).toDouble(),
      yield: (json['yield'] as num).toDouble(),
      technologyLocalized:
          (json['technology_localized'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value as String),
      ),
      descriptionForHall: json['description_for_hall'] as String?,
      compositionForHall: json['composition_for_hall'] as String?,
      sellingPrice: (json['selling_price'] as num?)?.toDouble(),
      photoUrls: (json['photo_urls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList(),
      ingredients: const [], // Загружается отдельно через сервис
      establishmentId: json['establishment_id'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Конвертация в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dish_name': dishName,
      'dish_name_localized': dishNameLocalized,
      'category': category,
      'sections': sections,
      'department': department,
      'is_semi_finished': isSemiFinished,
      'portion_weight': portionWeight,
      'yield': yield,
      'technology_localized': technologyLocalized,
      'description_for_hall': descriptionForHall,
      'composition_for_hall': compositionForHall,
      'selling_price': sellingPrice,
      'photo_urls': photoUrls ?? [],
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Копия с новым значением выхода (обход зарезервированного слова yield в async).
  static TechCard withYieldValue(TechCard t, double y) => t.copyWith(yield: y);

  /// Выход (в grams) отдельным геттером, чтобы в async-коде не использовать `.yield`
  /// (у `yield` есть синтаксические ограничения в async/async*/sync* контекстах).
  double get yieldValue => yield;

  /// Создание копии с изменениями
  TechCard copyWith({
    String? id,
    String? dishName,
    Map<String, String>? dishNameLocalized,
    String? category,
    List<String>? sections,
    String? department,
    bool? isSemiFinished,
    double? portionWeight,
    double? yield,
    Map<String, String>? technologyLocalized,
    String? descriptionForHall,
    String? compositionForHall,
    double? sellingPrice,
    List<String>? photoUrls,
    List<TTIngredient>? ingredients,
    String? establishmentId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TechCard(
      id: id ?? this.id,
      dishName: dishName ?? this.dishName,
      dishNameLocalized: dishNameLocalized ?? this.dishNameLocalized,
      category: category ?? this.category,
      sections: sections ?? this.sections,
      department: department ?? this.department,
      isSemiFinished: isSemiFinished ?? this.isSemiFinished,
      portionWeight: portionWeight ?? this.portionWeight,
      yield: yield ?? this.yield,
      technologyLocalized: technologyLocalized ?? this.technologyLocalized,
      descriptionForHall: descriptionForHall ?? this.descriptionForHall,
      compositionForHall: compositionForHall ?? this.compositionForHall,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      photoUrls: photoUrls ?? this.photoUrls,
      ingredients: ingredients ?? this.ingredients,
      establishmentId: establishmentId ?? this.establishmentId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Локализованная технология приготовления
  String getLocalizedTechnology(String languageCode) {
    final t = technologyLocalized;
    if (t == null || t.isEmpty) return '';
    final v = t[languageCode];
    if (v != null && v.trim().isNotEmpty) return v;
    return t['ru'] ?? t['en'] ?? '';
  }

  /// Порядок fallback для подписей (синхронно с [LocalizationService.productLanguageCodes]).
  static const List<String> kDishNameFallbackLanguageOrder = [
    'ru',
    'en',
    'es',
    'de',
    'fr',
    'it',
    'tr',
    'vi',
  ];

  /// Локализованное название блюда.
  /// [translationTableOverride] — строка из таблицы `translations` (целевой язык), если JSON на карточке пуст.
  String getLocalizedDishName(
    String languageCode, {
    String? translationTableOverride,
  }) {
    final localized = dishNameLocalized;
    if (localized != null && localized.containsKey(languageCode)) {
      final exact = localized[languageCode]?.trim();
      if (exact != null && exact.isNotEmpty) return exact;
    }
    final table = (translationTableOverride ??
            _translationOverlayByLang[languageCode]?[id])
        ?.trim();
    if (table != null && table.isNotEmpty) return table;
    // Fallback to any existing translation before raw base name.
    if (localized != null && localized.isNotEmpty) {
      for (final code in kDishNameFallbackLanguageOrder) {
        final value = localized[code]?.trim();
        if (value != null && value.isNotEmpty) return value;
      }
      for (final value in localized.values) {
        final v = value.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return dishName;
  }

  /// Название для списков (инвентаризация, выбор ПФ и т.д.): для ПФ — «ПФ/Prep Название», для блюда — просто название.
  /// Если название уже начинается с префикса ПФ (ПФ , п/ф , Prep и т.д.) — не дублируем.
  String getDisplayNameInLists(
    String languageCode, {
    String? sfPrefix,
    String? translationTableOverride,
  }) {
    final name = getLocalizedDishName(
      languageCode,
      translationTableOverride: translationTableOverride,
    );
    if (!isSemiFinished) return name;
    const pfPrefixes = ['пф ', 'п/ф ', 'п.ф. ', 'pf ', 'prep ', 'sf ', 'hf '];
    final nameLower = name.trim().toLowerCase();
    for (final p in pfPrefixes) {
      if (nameLower.startsWith(p))
        return name; // уже есть префикс — не дублируем
    }
    final prefix = sfPrefix ?? _defaultSfPrefix(languageCode);
    return '$prefix $name';
  }

  static String _defaultSfPrefix(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'Prep';
      case 'es':
        return 'SF';
      case 'it':
        return 'PF';
      case 'fr':
        return 'SF';
      case 'de':
        return 'HF';
      default:
        return 'ПФ';
    }
  }

  /// Имя вложенного ПФ в составе блюда: оверлей `translations` + префикс как в [getDisplayNameInLists].
  static String pfLinkedIngredientDisplayName(TTIngredient ing, String languageCode) {
    final sid = ing.sourceTechCardId?.trim();
    if (sid == null || sid.isEmpty) return ing.productName.trim();
    final fromOverlay =
        _translationOverlayByLang[languageCode]?[sid]?.trim();
    final base = (fromOverlay != null && fromOverlay.isNotEmpty)
        ? fromOverlay
        : (ing.sourceTechCardName ?? ing.productName).trim();
    if (base.isEmpty) return '';
    const pfPrefixes = ['пф ', 'п/ф ', 'п.ф. ', 'pf ', 'prep ', 'sf ', 'hf '];
    final nameLower = base.toLowerCase();
    for (final p in pfPrefixes) {
      if (nameLower.startsWith(p)) return base;
    }
    final prefix = _defaultSfPrefix(languageCode);
    return '$prefix $base';
  }

  /// Общий вес брутто всех ингредиентов
  double get totalGrossWeight {
    return ingredients.fold(
        0, (sum, ingredient) => sum + ingredient.grossWeight);
  }

  /// Общий вес нетто всех ингредиентов
  double get totalNetWeight {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.netWeight);
  }

  /// Общие калории
  double get totalCalories {
    return ingredients.fold(
        0, (sum, ingredient) => sum + ingredient.finalCalories);
  }

  /// Общий белок
  double get totalProtein {
    return ingredients.fold(
        0, (sum, ingredient) => sum + ingredient.finalProtein);
  }

  /// Общие жиры
  double get totalFat {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.finalFat);
  }

  /// Общие углеводы
  double get totalCarbs {
    return ingredients.fold(
        0, (sum, ingredient) => sum + ingredient.finalCarbs);
  }

  /// Общая стоимость
  double get totalCost {
    return ingredients.fold(0, (sum, ingredient) => sum + ingredient.cost);
  }

  /// КБЖУ на порцию
  double get caloriesPerPortion =>
      portionWeight > 0 ? totalCalories / portionWeight * 100 : 0;
  double get proteinPerPortion =>
      portionWeight > 0 ? totalProtein / portionWeight * 100 : 0;
  double get fatPerPortion =>
      portionWeight > 0 ? totalFat / portionWeight * 100 : 0;
  double get carbsPerPortion =>
      portionWeight > 0 ? totalCarbs / portionWeight * 100 : 0;

  /// Стоимость порции
  double get costPerPortion =>
      portionWeight > 0 ? totalCost / portionWeight * 100 : 0;

  /// Процент выхода (отношение выхода к общему весу брутто)
  double get yieldPercentage {
    return totalGrossWeight > 0 ? (yield / totalGrossWeight) * 100 : 0;
  }

  /// Добавить ингредиент
  TechCard addIngredient(TTIngredient ingredient) {
    return copyWith(
      ingredients: [...ingredients, ingredient],
      updatedAt: DateTime.now(),
    );
  }

  /// Удалить ингредиент
  TechCard removeIngredient(String ingredientId) {
    return copyWith(
      ingredients: ingredients.where((ing) => ing.id != ingredientId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// Обновить ингредиент
  TechCard updateIngredient(TTIngredient updatedIngredient) {
    final newIngredients = ingredients.map((ing) {
      return ing.id == updatedIngredient.id ? updatedIngredient : ing;
    }).toList();

    return copyWith(
      ingredients: newIngredients,
      updatedAt: DateTime.now(),
    );
  }

  /// Проверить корректность ТТК
  bool get isValid {
    return dishName.isNotEmpty &&
        ingredients.isNotEmpty &&
        portionWeight > 0 &&
        yield > 0;
  }

  /// Краткая информация о ТТК
  String get summary {
    final ingredientCount = ingredients.length;
    final calories = totalCalories.round();
    final cost = totalCost.toStringAsFixed(2);

    return '$dishName: $ingredientCount ингр., $calories ккал, $cost';
  }

  @override
  List<Object?> get props => [
        id,
        dishName,
        dishNameLocalized,
        category,
        sections,
        department,
        isSemiFinished,
        portionWeight,
        yield,
        technologyLocalized,
        descriptionForHall,
        compositionForHall,
        sellingPrice,
        photoUrls,
        ingredients,
        establishmentId,
        createdBy,
        createdAt,
        updatedAt,
      ];

  /// Создание новой ТТК
  /// Является ли ТТК скрытой (пустой список цехов = скрыто, только шеф/су-шеф)
  bool get isHidden => sections.isEmpty;

  /// Доступна ли ТТК для всех цехов
  bool get isForAllSections => sections.contains('all');

  /// Доступна ли ТТК для конкретного цеха
  bool isVisibleForSection(String? employeeSection) {
    if (sections.isEmpty) return false; // скрыто
    if (sections.contains('all')) return true; // все цеха
    if (employeeSection == null) return false;
    return sections.contains(employeeSection);
  }

  factory TechCard.create({
    required String dishName,
    Map<String, String>? dishNameLocalized,
    required String category,
    List<String> sections = const [],
    String department = 'kitchen',
    bool isSemiFinished = true,
    required String establishmentId,
    required String createdBy,
  }) {
    final now = DateTime.now();
    return TechCard(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dishName: dishName,
      dishNameLocalized: dishNameLocalized,
      category: category,
      sections: sections,
      department: department,
      isSemiFinished: isSemiFinished,
      portionWeight: 100, // вес порции по умолчанию
      yield: 0,
      technologyLocalized: null,
      descriptionForHall: null,
      compositionForHall: null,
      sellingPrice: null,
      photoUrls: null,
      ingredients: [],
      establishmentId: establishmentId,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Убирает ссылку на вложенную ТТК, если она указывает на саму эту карту
/// (ломает себестоимость и даёт циклы при разворачивании ПФ).
TechCard stripInvalidNestedPfSelfLinks(TechCard tc) {
  final sid = tc.id;
  var changed = false;
  final next = <TTIngredient>[];
  for (final ing in tc.ingredients) {
    final s = ing.sourceTechCardId;
    if (s != null && s.isNotEmpty && s == sid) {
      changed = true;
      next.add(ing.copyWith(sourceTechCardId: null, sourceTechCardName: null));
    } else {
      next.add(ing);
    }
  }
  if (!changed) return tc;
  return tc.copyWith(ingredients: next, updatedAt: DateTime.now());
}
