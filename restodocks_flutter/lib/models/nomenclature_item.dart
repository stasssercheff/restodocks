import 'models.dart';

/// Элемент номенклатуры: может быть продуктом или ТТК с типом ПФ
class NomenclatureItem {
  final Product? product;
  final TechCard? techCard;

  bool get isProduct => product != null;
  bool get isTechCard => techCard != null;

  String get id => product?.id ?? techCard!.id;
  String get name => product?.name ?? techCard!.dishName;
  String get category => product?.category ?? techCard!.category;
  double? get price => product?.basePrice ?? (techCard != null ? _calculateTechCardCostPerKg(techCard!) : null);

  const NomenclatureItem.product(this.product) : techCard = null;
  const NomenclatureItem.techCard(this.techCard) : product = null;

  String getLocalizedName(String lang) {
    if (isProduct) return product!.getLocalizedName(lang);
    if (isTechCard) return techCard!.dishNameLocalized?[lang] ?? techCard!.dishName;
    return name;
  }

  /// Рассчитывает стоимость за кг для ТТК с типом ПФ
  double? _calculateTechCardCostPerKg(TechCard techCard) {
    if (techCard.ingredients.isEmpty) return null;

    final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
    final totalOutput = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.outputWeight);

    if (totalOutput == 0) return null;
    return (totalCost / totalOutput) * 1000;
  }
}