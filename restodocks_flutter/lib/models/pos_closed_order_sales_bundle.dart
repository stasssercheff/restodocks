import 'pos_order.dart';
import 'pos_order_line.dart';

/// Закрытый счёт с позициями для отчёта по продажам (кухня/бар).
class PosClosedOrderSalesBundle {
  const PosClosedOrderSalesBundle({
    required this.order,
    required this.lines,
  });

  final PosOrder order;
  final List<PosOrderLine> lines;
}
