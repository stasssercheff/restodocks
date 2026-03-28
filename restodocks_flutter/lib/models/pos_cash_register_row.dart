import 'pos_order.dart';

/// Строка экрана кассы: заказ и сумма по позициям (ТТК × количество).
class PosCashRegisterRow {
  const PosCashRegisterRow({required this.order, required this.totalDue});

  final PosOrder order;
  final double totalDue;
}
