import '../models/models.dart';
import 'product_store_supabase.dart';

/// Общая гидратация стоимости ТТК из номенклатуры (стоимость за кг выходного веса).
/// Используется в списке ТТК и редакторе — один расчёт, один источник истины.
class TechCardCostHydrator {
  static double _ingredientOutput(TTIngredient ing) {
    if (ing.outputWeight > 0) return ing.outputWeight;
    if (ing.netWeight > 0) return ing.netWeight;
    return ing.grossWeight;
  }

  /// Сумма выходных весов строк состава (г), как оценка выхода рецепта, если в ТТК не задан [TechCard.yield].
  static double sumIngredientOutputGrams(TechCard tc) {
    return tc.ingredients
        .where((i) => i.productName.trim().isNotEmpty)
        .fold<double>(0, (s, i) => s + _ingredientOutput(i));
  }

  static double _quantityForCost(TTIngredient ing) {
    final qty =
        ing.grossWeight > 0 ? ing.grossWeight : (ing.netWeight > 0 ? ing.netWeight : ing.outputWeight);
    if (qty <= 0) return 0;
    final u = ing.unit.toLowerCase().trim();
    if (u == 'шт' || u == 'pcs') {
      final gpp = ing.gramsPerPiece ?? 50.0;
      return gpp > 0 ? qty / gpp : qty / 1000;
    }
    return qty / 1000;
  }

  static TTIngredient _enrichLeaf(
    TTIngredient ing,
    ProductStoreSupabase store,
    String establishmentId,
  ) {
    if (ing.sourceTechCardId != null && ing.sourceTechCardId!.isNotEmpty) {
      return ing;
    }
    if (ing.productName.trim().isEmpty) return ing;
    if (ing.effectiveCost > 0) return ing;
    if (ing.pricePerKg != null && ing.pricePerKg! > 0) {
      final qty = _quantityForCost(ing);
      if (qty > 0) {
        final c = ing.pricePerKg! * qty;
        if (c > 0) return ing.copyWith(cost: c);
      }
    }
    final product = store.findProductForIngredient(ing.productId, ing.productName);
    if (product == null) return ing;
    final priceInfo = store.getEstablishmentPrice(product.id, establishmentId);
    double pricePerKg = priceInfo?.$1 ?? 0.0;
    if (pricePerKg <= 0 && product.basePrice != null && product.basePrice! > 0) {
      pricePerKg = product.basePrice!;
    }
    if (pricePerKg <= 0) return ing;
    final qty = _quantityForCost(ing);
    if (qty <= 0) return ing;
    final cost = pricePerKg * qty;
    return ing.copyWith(productId: product.id, pricePerKg: pricePerKg, cost: cost);
  }

  /// Гидратирует список ТТК: заполняет cost/pricePerKg из номенклатуры.
  /// Результат — карточки с теми же cost, что показываются в «Итого» редактора.
  static List<TechCard> hydrate(
    List<TechCard> techCards,
    ProductStoreSupabase store,
    String establishmentId,
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
            return _enrichLeaf(ing, store, establishmentId);
          }
          if (sid == tc.id) {
            return ing.copyWith(sourceTechCardId: null, sourceTechCardName: null);
          }
          final nested = byId[sid];
          if (nested == null) return ing;

          final rn = resolve(nested);
          final nestedIngs = rn.ingredients.where((i) => i.productName.trim().isNotEmpty).toList();
          final nestedOutput = nestedIngs.fold<double>(0, (s, i) => s + _ingredientOutput(i));
          final nestedCost = nestedIngs.fold<double>(0, (s, i) {
            var c = i.effectiveCost;
            if (c <= 0 && i.pricePerKg != null && i.pricePerKg! > 0) {
              final q = _quantityForCost(i);
              if (q > 0) c = i.pricePerKg! * q;
            }
            return s + (c > 0 ? c : 0);
          });

          if (nestedOutput <= 0 || nestedCost <= 0) return ing;
          final pricePerKg = nestedCost * 1000 / nestedOutput;
          final io = _ingredientOutput(ing);
          final cost = ing.cost > 0 ? ing.cost : pricePerKg * io / 1000;

          return ing.copyWith(
            pricePerKg: (ing.pricePerKg == null || ing.pricePerKg! <= 0) ? pricePerKg : ing.pricePerKg,
            cost: cost,
          );
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

  /// Итого стоимость за кг выходного веса (как в «Итого» редактора).
  static double costPerKgOutput(TechCard tc) {
    if (tc.ingredients.isEmpty) return 0;
    final totalOutput = tc.ingredients
        .where((i) => i.productName.trim().isNotEmpty)
        .fold<double>(0, (s, i) => s + _ingredientOutput(i));
    if (totalOutput <= 0) return 0;
    final totalCost = tc.ingredients
        .where((i) => i.productName.trim().isNotEmpty)
        .fold<double>(0, (s, i) {
      final c = i.effectiveCost;
      if (c > 0) return s + c;
      if (i.pricePerKg != null && i.pricePerKg! > 0) {
        final q = _quantityForCost(i);
        if (q > 0) return s + i.pricePerKg! * q;
      }
      return s;
    });
    return (totalCost / totalOutput) * 1000;
  }
}
