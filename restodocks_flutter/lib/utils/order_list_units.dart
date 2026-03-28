import '../models/culinary_units.dart';
import '../models/product.dart';

/// Перевод количества из строки списка заказа в граммы (склад POS в г).
double orderListQuantityToGrams(
  double quantity,
  String unit,
  Product? product,
) {
  final u = unit.toLowerCase().trim();
  if (u == 'pkg' &&
      product?.packageWeightGrams != null &&
      product!.packageWeightGrams! > 0) {
    return quantity * product.packageWeightGrams!;
  }
  return CulinaryUnits.toGrams(
    quantity,
    unit,
    gramsPerPiece: product?.gramsPerPiece ?? product?.packageWeightGrams,
  );
}
