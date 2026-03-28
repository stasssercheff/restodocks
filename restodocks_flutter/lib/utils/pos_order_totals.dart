import 'dart:math' as math;

import '../models/pos_order.dart';

/// Итоги по счёту зала: меню → скидка → сервис → чаевые → к оплате.
class PosOrderTotals {
  const PosOrderTotals({
    required this.menuSubtotal,
    required this.discountAmount,
    required this.afterDiscount,
    required this.serviceChargePercent,
    required this.serviceAmount,
    required this.beforeTips,
    required this.tipsAmount,
    required this.grandTotal,
  });

  final double menuSubtotal;
  final double discountAmount;
  final double afterDiscount;
  final double serviceChargePercent;
  final double serviceAmount;
  final double beforeTips;
  final double tipsAmount;
  final double grandTotal;
}

const double posOrderTotalsEpsilon = 0.009;

/// Расчёт итогов по полям заказа и сумме меню.
PosOrderTotals computePosOrderTotals({
  required double menuSubtotal,
  required PosOrder orderFields,
}) {
  return computePosOrderTotalsRaw(
    menuSubtotal: menuSubtotal,
    discountAmount: orderFields.discountAmount,
    serviceChargePercent: orderFields.serviceChargePercent,
    tipsAmount: orderFields.tipsAmount,
  );
}

PosOrderTotals computePosOrderTotalsRaw({
  required double menuSubtotal,
  required double discountAmount,
  required double serviceChargePercent,
  required double tipsAmount,
}) {
  final disc = math.max(0.0, discountAmount);
  final after = math.max(0.0, menuSubtotal - disc);
  final svcPct = serviceChargePercent.clamp(0.0, 100.0);
  final svc = after * (svcPct / 100.0);
  final beforeTips = after + svc;
  final tips = math.max(0.0, tipsAmount);
  final grand = beforeTips + tips;
  return PosOrderTotals(
    menuSubtotal: menuSubtotal,
    discountAmount: disc,
    afterDiscount: after,
    serviceChargePercent: svcPct,
    serviceAmount: svc,
    beforeTips: beforeTips,
    tipsAmount: tips,
    grandTotal: grand,
  );
}

bool posPaymentsMatchTotal(Iterable<double> amounts, double grandTotal) {
  var s = 0.0;
  for (final a in amounts) {
    s += a;
  }
  return (s - grandTotal).abs() <= posOrderTotalsEpsilon;
}
