import 'pos_dining_table.dart';

/// Заказ зала (pos_orders).
class PosOrder {
  const PosOrder({
    required this.id,
    required this.establishmentId,
    required this.diningTableId,
    required this.status,
    required this.guestCount,
    required this.createdAt,
    required this.updatedAt,
    this.tableNumber,
    this.floorName,
    this.roomName,
    this.tableStatus,
    this.paymentMethod,
    this.paidAt,
    this.discountAmount = 0,
    this.serviceChargePercent = 0,
    this.tipsAmount = 0,
  });

  final String id;
  final String establishmentId;
  final String diningTableId;
  final PosOrderStatus status;
  final int guestCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? tableNumber;
  final String? floorName;
  final String? roomName;

  /// Статус стола из embed `pos_dining_tables` (свободен / занят / счёт).
  final PosTableStatus? tableStatus;

  /// Способ оплаты при закрытии счёта (если уже закрыт).
  final PosPaymentMethod? paymentMethod;

  /// Когда зафиксирована оплата.
  final DateTime? paidAt;

  /// Скидка с суммы по меню (руб/валюта заведения).
  final double discountAmount;

  /// Сервисный сбор, % от суммы после скидки.
  final double serviceChargePercent;

  /// Чаевые (фиксируются при закрытии).
  final double tipsAmount;

  factory PosOrder.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? tableEmbed,
  }) {
    Map<String, dynamic>? t = tableEmbed;
    final embed = json['pos_dining_tables'];
    if (embed is Map<String, dynamic>) {
      t = embed;
    } else if (embed is List && embed.isNotEmpty && embed.first is Map) {
      t = Map<String, dynamic>.from(embed.first as Map);
    }

    DateTime? paidAt;
    final paidRaw = json['paid_at'];
    if (paidRaw != null) {
      paidAt = DateTime.tryParse(paidRaw.toString());
    }

    return PosOrder(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      diningTableId: json['dining_table_id'] as String,
      status: PosOrderStatus.fromApi(json['status'] as String? ?? 'draft'),
      guestCount: (json['guest_count'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      tableNumber: t != null ? (t['table_number'] as num?)?.toInt() : null,
      floorName: t?['floor_name'] as String?,
      roomName: t?['room_name'] as String?,
      tableStatus: t != null
          ? PosTableStatus.fromApi(t['status'] as String? ?? 'free')
          : null,
      paymentMethod:
          PosPaymentMethod.fromApi(json['payment_method'] as String?),
      paidAt: paidAt,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      serviceChargePercent:
          (json['service_charge_percent'] as num?)?.toDouble() ?? 0,
      tipsAmount: (json['tips_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Способ оплаты при закрытии счёта (учёт в БД, не фискальный чек).
enum PosPaymentMethod {
  cash,
  card,
  transfer,
  other,

  /// Несколько платежей — детали в pos_order_payments.
  split;

  String toApi() {
    switch (this) {
      case PosPaymentMethod.cash:
        return 'cash';
      case PosPaymentMethod.card:
        return 'card';
      case PosPaymentMethod.transfer:
        return 'transfer';
      case PosPaymentMethod.other:
        return 'other';
      case PosPaymentMethod.split:
        return 'split';
    }
  }

  static PosPaymentMethod? fromApi(String? s) {
    if (s == null || s.isEmpty) return null;
    switch (s) {
      case 'cash':
        return PosPaymentMethod.cash;
      case 'card':
        return PosPaymentMethod.card;
      case 'transfer':
        return PosPaymentMethod.transfer;
      case 'other':
        return PosPaymentMethod.other;
      case 'split':
        return PosPaymentMethod.split;
      default:
        return null;
    }
  }
}

enum PosOrderStatus {
  draft,
  sent,
  closed,
  /// Отмена без оплаты (стол освобождён).
  cancelled;

  static PosOrderStatus fromApi(String s) {
    switch (s) {
      case 'sent':
        return PosOrderStatus.sent;
      case 'closed':
        return PosOrderStatus.closed;
      case 'cancelled':
        return PosOrderStatus.cancelled;
      default:
        return PosOrderStatus.draft;
    }
  }

  String toApi() {
    switch (this) {
      case PosOrderStatus.draft:
        return 'draft';
      case PosOrderStatus.sent:
        return 'sent';
      case PosOrderStatus.closed:
        return 'closed';
      case PosOrderStatus.cancelled:
        return 'cancelled';
    }
  }
}
