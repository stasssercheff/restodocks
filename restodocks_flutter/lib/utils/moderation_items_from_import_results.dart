import '../models/models.dart';
import '../services/product_store_supabase.dart';

/// Преобразует результаты интеллектуального импорта Excel в буфер [ModerationItem] для [ImportReviewScreen].
///
/// [ambiguousResolutions] — ответы диалога неоднозначностей: имя строки из файла → `replace` | `create`.
/// Строки ambiguous без решения в карте пропускаются.
List<ModerationItem> moderationItemsFromProductImportResults({
  required List<ProductImportResult> results,
  required String establishmentId,
  required ProductStoreSupabase store,
  Map<String, String>? ambiguousResolutions,
}) {
  final out = <ModerationItem>[];
  for (final r in results) {
    if (r.error != null) continue;
    final item = _mapOne(r, establishmentId, store, ambiguousResolutions);
    if (item != null) out.add(item);
  }
  return out;
}

ModerationItem? _mapOne(
  ProductImportResult r,
  String establishmentId,
  ProductStoreSupabase store,
  Map<String, String>? ambiguousResolutions,
) {
  final mr = r.matchResult;
  final id = mr.existingProductId;
  final existingName = mr.existingProductName;

  (double?, bool) estPrice(String? productId) {
    if (productId == null) return (null, false);
    final ep = store.getEstablishmentPrice(productId, establishmentId);
    return (ep?.$1, ep != null);
  }

  switch (mr.type) {
    case MatchType.exact:
      if (id == null) return null;
      final p = estPrice(id);
      return ModerationItem(
        name: r.fileName,
        price: r.filePrice,
        existingProductId: id,
        existingProductName: existingName,
        existingPrice: p.$1,
        existingPriceFromEstablishment: p.$2,
        category: ModerationCategory.priceUpdate,
      );
    case MatchType.priceUpdate:
      if (id == null) return null;
      final p = estPrice(id);
      return ModerationItem(
        name: r.fileName,
        price: r.filePrice,
        existingProductId: id,
        existingProductName: existingName,
        existingPrice: p.$1,
        existingPriceFromEstablishment: p.$2,
        category: ModerationCategory.priceUpdate,
      );
    case MatchType.fuzzy:
      if (id == null) return null;
      final pr = estPrice(id);
      return ModerationItem(
        name: r.fileName,
        price: r.filePrice,
        existingProductId: id,
        existingProductName: existingName,
        existingPrice: pr.$1,
        existingPriceFromEstablishment: pr.$2,
        category: ModerationCategory.priceUpdate,
        linkAliasFromImportName: true,
      );
    case MatchType.ambiguous:
      final res = ambiguousResolutions?[r.fileName];
      if (res == null) return null;
      if (res == 'replace' && id != null) {
        final pr = estPrice(id);
        return ModerationItem(
          name: r.fileName,
          price: r.filePrice,
          existingProductId: id,
          existingProductName: existingName,
          existingPrice: pr.$1,
          existingPriceFromEstablishment: pr.$2,
          category: ModerationCategory.priceUpdate,
          linkAliasFromImportName: true,
        );
      }
      if (res == 'create') {
        return ModerationItem(
          name: r.fileName,
          price: r.filePrice,
          category: ModerationCategory.newProduct,
        );
      }
      return null;
    case MatchType.create:
      return ModerationItem(
        name: r.fileName,
        price: r.filePrice,
        category: ModerationCategory.newProduct,
      );
    case MatchType.error:
      return null;
  }
}
