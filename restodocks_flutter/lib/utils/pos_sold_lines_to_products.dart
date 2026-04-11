import '../models/models.dart';
import '../services/localization_service.dart';
import '../utils/pos_order_department.dart';
import '../utils/tech_card_section_display.dart';

/// Фильтр листов Excel: кухня / бар / все позиции.
enum PosSalesProductsFilter {
  kitchen,
  bar,
  all,
}

bool _lineMatchesFilter(PosOrderLine line, PosSalesProductsFilter filter) {
  final cat = line.techCardCategory ?? '';
  final sec = line.techCardSections;
  final isBar = posLineIsBarDish(cat, sec);
  switch (filter) {
    case PosSalesProductsFilter.kitchen:
      return !isBar;
    case PosSalesProductsFilter.bar:
      return isBar;
    case PosSalesProductsFilter.all:
      return true;
  }
}

/// Перерасчёт проданных блюд/ПФ в продукты по ТТК (как секция ПФ в бланке инвентаризации).
List<Map<String, dynamic>> aggregateSoldLinesToProducts({
  required List<PosOrderLine> lines,
  required Map<String, TechCard> tcById,
  required PosSalesProductsFilter filter,
}) {
  final result = <String, Map<String, dynamic>>{};

  void addIngredients(List<TTIngredient> ingredients, double factor) {
    for (final ing in ingredients) {
      if (ing.productId != null && ing.productName.isNotEmpty) {
        final key = ing.productId!;
        final gross = ing.grossWeight * factor;
        final net = ing.netWeight * factor;
        if (result.containsKey(key)) {
          result[key]!['grossGrams'] =
              (result[key]!['grossGrams'] as double) + gross;
          result[key]!['netGrams'] =
              (result[key]!['netGrams'] as double) + net;
        } else {
          result[key] = {
            'productId': key,
            'productName': ing.productName,
            'grossGrams': gross,
            'netGrams': net,
          };
        }
      } else if (ing.sourceTechCardId != null) {
        final nested = tcById[ing.sourceTechCardId!];
        if (nested != null) {
          final nestedYield =
              nested.yield > 0 ? nested.yield : nested.totalNetWeight;
          if (nestedYield > 0) {
            final nestedFactor = (ing.netWeight * factor) / nestedYield;
            addIngredients(nested.ingredients, nestedFactor);
          }
        }
      }
    }
  }

  for (final line in lines) {
    if (!_lineMatchesFilter(line, filter)) continue;
    final tc = tcById[line.techCardId];
    if (tc == null || tc.ingredients.isEmpty) continue;
    final yieldVal = tc.yield > 0 ? tc.yield : tc.totalNetWeight;
    if (yieldVal <= 0 || line.quantity <= 0) continue;
    final factor = (line.quantity * tc.portionWeight) / yieldVal;
    addIngredients(tc.ingredients, factor);
  }

  final list = result.values.toList();
  list.sort((a, b) => (a['productName'] as String)
      .toLowerCase()
      .compareTo((b['productName'] as String).toLowerCase()));
  return list;
}

/// Строки листа 1: агрегированные проданные позиции (по tech_card_id).
class PosSalesSheet1Row {
  PosSalesSheet1Row({
    required this.dishName,
    required this.quantity,
    required this.subdivisionLabel,
    required this.workshopLabel,
  });

  final String dishName;
  final double quantity;
  final String subdivisionLabel;
  final String workshopLabel;
}

List<PosSalesSheet1Row> buildSheet1AggregatedRows({
  required List<PosOrderLine> lines,
  required Map<String, TechCard> tcById,
  required LocalizationService loc,
}) {
  final byTc = <String, double>{};
  final meta = <String, ({String name, String subdiv, String workshop})>{};

  for (final line in lines) {
    final tc = tcById[line.techCardId];
    final name = line.dishTitleForLang(loc.currentLanguageCode);
    final cat = line.techCardCategory ?? '';
    final sec = line.techCardSections;
    final isBar = posLineIsBarDish(cat, sec);
    final subdiv = isBar
        ? loc.t('department_bar')
        : loc.t('kitchen');
    final workshop = tc != null
        ? techCardSectionGroupLabel(
            techCardSectionKeyForGroup(tc),
            loc,
          )
        : '—';

    byTc[line.techCardId] = (byTc[line.techCardId] ?? 0) + line.quantity;
    meta[line.techCardId] = (name: name, subdiv: subdiv, workshop: workshop);
  }

  final out = <PosSalesSheet1Row>[];
  for (final e in byTc.entries) {
    final m = meta[e.key];
    if (m == null) continue;
    out.add(PosSalesSheet1Row(
      dishName: m.name,
      quantity: e.value,
      subdivisionLabel: m.subdiv,
      workshopLabel: m.workshop,
    ));
  }
  out.sort((a, b) =>
      a.dishName.toLowerCase().compareTo(b.dishName.toLowerCase()));
  return out;
}
