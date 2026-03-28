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
    );
  }
}

enum PosOrderStatus {
  draft,
  sent,
  closed;

  static PosOrderStatus fromApi(String s) {
    switch (s) {
      case 'sent':
        return PosOrderStatus.sent;
      case 'closed':
        return PosOrderStatus.closed;
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
    }
  }
}
