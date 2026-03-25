import '../models/models.dart';
import 'product_store_supabase.dart';

/// Подставляет `final_*` КБЖУ в ингредиентах ТТК из номенклатуры и вложенных ПФ.
///
/// В БД хранятся снимки `final_calories` и т.д. на момент сохранения. Если позже в продукты
/// подтянули КБЖУ, строки ТТК остаются с нулями — блок КБЖУ в редакторе не показывается.
/// Этот слой при открытии списка/редактора пересчитывает нули из актуальных продуктов
/// (как [TechCardCostHydrator] для цен).
class TechCardNutritionHydrator {
  static const _eps = 1e-9;

  static bool _needsNutrition(TTIngredient ing) {
    return ing.finalCalories.abs() < _eps &&
        ing.finalProtein.abs() < _eps &&
        ing.finalFat.abs() < _eps &&
        ing.finalCarbs.abs() < _eps;
  }

  static bool _productHasAnyMacro(Product p) {
    return (p.calories ?? 0) > 0 ||
        (p.protein ?? 0) > 0 ||
        (p.fat ?? 0) > 0 ||
        (p.carbs ?? 0) > 0;
  }

  /// Те же формулы, что при редактировании веса; стоимость строки не трогаем.
  static TTIngredient _hydrateLeaf(TTIngredient ing, ProductStoreSupabase store) {
    if (!_needsNutrition(ing)) return ing;
    if (ing.productName.trim().isEmpty) return ing;
    final product = store.findProductForIngredient(ing.productId, ing.productName);
    if (product == null || !_productHasAnyMacro(product)) return ing;
    final proc = ing.cookingProcessId != null && ing.cookingProcessId!.trim().isNotEmpty
        ? CookingProcess.findById(ing.cookingProcessId!)
        : null;
    final updated = ing.updateGrossWeight(ing.grossWeight, product, proc);
    return updated.copyWith(
      cost: ing.cost,
      pricePerKg: ing.pricePerKg,
      costCurrency: ing.costCurrency,
    );
  }

  static TTIngredient _hydrateNested(TTIngredient ing, TechCard nestedResolved) {
    if (!_needsNutrition(ing)) return ing;
    final totalNet = nestedResolved.totalNetWeight;
    if (totalNet <= 0) return ing;
    final factor = ing.grossWeight / totalNet;
    return ing.copyWith(
      finalCalories: nestedResolved.totalCalories * factor,
      finalProtein: nestedResolved.totalProtein * factor,
      finalFat: nestedResolved.totalFat * factor,
      finalCarbs: nestedResolved.totalCarbs * factor,
    );
  }

  static List<TechCard> hydrate(
    List<TechCard> techCards,
    ProductStoreSupabase store,
  ) {
    if (techCards.isEmpty) return techCards;
    final byId = {for (final tc in techCards) tc.id: tc};
    final memo = <String, TechCard>{};
    final resolving = <String>{};

    TechCard resolve(TechCard tc) {
      final cached = memo[tc.id];
      if (cached != null) return cached;
      if (!resolving.add(tc.id)) return tc;
      try {
        final resolved = tc.ingredients.map((ing) {
          final sid = ing.sourceTechCardId;
          if (sid == null || sid.isEmpty) {
            return _hydrateLeaf(ing, store);
          }
          if (sid == tc.id) {
            return ing.copyWith(sourceTechCardId: null, sourceTechCardName: null);
          }
          final nested = byId[sid];
          if (nested == null) return ing;
          final rn = resolve(nested);
          return _hydrateNested(ing, rn);
        }).toList();

        final out = tc.copyWith(ingredients: resolved);
        memo[tc.id] = out;
        return out;
      } finally {
        resolving.remove(tc.id);
      }
    }

    return techCards.map(resolve).toList();
  }
}
