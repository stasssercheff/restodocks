import '../models/models.dart';
import '../utils/pos_order_department.dart';
import 'pos_order_service.dart';
import 'tech_card_service_supabase.dart';

/// Агрегация продаж по закрытым счетам POS для кухни/бара.
class KitchenBarSalesService {
  KitchenBarSalesService._();
  static final KitchenBarSalesService instance = KitchenBarSalesService._();

  final PosOrderService _pos = PosOrderService.instance;
  final TechCardServiceSupabase _tech = TechCardServiceSupabase();

  /// [routeDepartment] — `kitchen` или `bar` (как на главной сотрудника).
  Future<List<KitchenBarSalesRow>> aggregate({
    required String establishmentId,
    required String routeDepartment,
    required DateTime rangeStartUtc,
    required DateTime rangeEndUtc,
    bool Function(DateTime paidAtLocal)? paidAtLocalFilter,
    String langCode = 'ru',
  }) async {
    final bundles = await _pos.fetchClosedOrdersWithSalesLines(
      establishmentId: establishmentId,
      fromUtc: rangeStartUtc,
      toUtc: rangeEndUtc,
    );

    final cards = await _tech.getTechCardsForEstablishment(establishmentId);
    final costByTechCard = <String, double>{};
    for (final c in cards) {
      costByTechCard[c.id] = c.costPerPortion;
    }

    final dept = routeDepartment == 'bar' ? 'bar' : 'kitchen';
    final agg = <String, _Agg>{};

    for (final b in bundles) {
      final paid = b.order.paidAt;
      if (paid == null) continue;
      final paidLocal = paid.toLocal();
      if (paidAtLocalFilter != null && !paidAtLocalFilter(paidLocal)) {
        continue;
      }

      for (final line in b.lines) {
        final cat = line.techCardCategory ?? '';
        final sec = line.techCardSections;
        final isBar = posLineIsBarDish(cat, sec);
        if (dept == 'bar' && !isBar) continue;
        if (dept == 'kitchen' && isBar) continue;

        final id = line.techCardId;
        final name = line.dishTitleForLang(langCode);
        final typeLabel = cat.isEmpty ? '—' : cat;
        final subdiv =
            isBar ? 'bar' : (line.techCardDepartment?.isNotEmpty == true ? line.techCardDepartment! : 'kitchen');
        final subdivLabel = subdiv == 'bar' ? 'Бар' : 'Кухня';

        final selling = line.sellingPrice;
        final sellSum = selling != null ? selling * line.quantity : 0.0;
        final unitCost = costByTechCard[id] ?? 0.0;
        final costSum = unitCost * line.quantity;

        final prev = agg[id];
        if (prev == null) {
          agg[id] = _Agg(
            techCardId: id,
            subdivisionLabel: subdivLabel,
            dishTypeLabel: typeLabel,
            dishName: name,
            quantity: line.quantity,
            costTotal: costSum,
            sellingTotal: sellSum,
          );
        } else {
          agg[id] = _Agg(
            techCardId: id,
            subdivisionLabel: prev.subdivisionLabel,
            dishTypeLabel: prev.dishTypeLabel,
            dishName: prev.dishName,
            quantity: prev.quantity + line.quantity,
            costTotal: prev.costTotal + costSum,
            sellingTotal: prev.sellingTotal + sellSum,
          );
        }
      }
    }

    final list = agg.values
        .map(
          (a) => KitchenBarSalesRow(
            techCardId: a.techCardId,
            subdivisionLabel: a.subdivisionLabel,
            dishTypeLabel: a.dishTypeLabel,
            dishName: a.dishName,
            quantity: a.quantity,
            costTotal: a.costTotal,
            sellingTotal: a.sellingTotal,
          ),
        )
        .toList();
    list.sort((a, b) => a.dishName.compareTo(b.dishName));
    return list;
  }

  /// Сумма продаж (по позициям × цена ТТК) за день в локальной дате для подразделения.
  Future<double> factSellingTotalForLocalDay({
    required String establishmentId,
    required String routeDepartment,
    required DateTime dayLocal,
  }) async {
    final start = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
    final end = DateTime(dayLocal.year, dayLocal.month, dayLocal.day, 23, 59, 59, 999);
    final rows = await aggregate(
      establishmentId: establishmentId,
      routeDepartment: routeDepartment,
      rangeStartUtc: start.toUtc(),
      rangeEndUtc: end.toUtc(),
    );
    return rows.fold<double>(0, (s, r) => s + r.sellingTotal);
  }
}

class _Agg {
  _Agg({
    required this.techCardId,
    required this.subdivisionLabel,
    required this.dishTypeLabel,
    required this.dishName,
    required this.quantity,
    required this.costTotal,
    required this.sellingTotal,
  });

  final String techCardId;
  final String subdivisionLabel;
  final String dishTypeLabel;
  final String dishName;
  final double quantity;
  final double costTotal;
  final double sellingTotal;
}
