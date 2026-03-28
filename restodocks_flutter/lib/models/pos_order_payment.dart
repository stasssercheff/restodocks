import 'pos_order.dart';

/// Строка таблицы pos_order_payments.
class PosOrderPayment {
  const PosOrderPayment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.paymentMethod,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final double amount;
  final PosPaymentMethod paymentMethod;
  final DateTime createdAt;

  factory PosOrderPayment.fromJson(Map<String, dynamic> json) {
    final m = PosPaymentMethod.fromApi(json['payment_method'] as String?);
    if (m == null) {
      throw FormatException('pos_order_payment: bad method ${json['payment_method']}');
    }
    return PosOrderPayment(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentMethod: m,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
