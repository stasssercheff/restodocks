/// Стол зала (pos_dining_tables).
class PosDiningTable {
  const PosDiningTable({
    required this.id,
    required this.establishmentId,
    this.floorName,
    this.roomName,
    required this.tableNumber,
    required this.sortOrder,
    required this.status,
  });

  final String id;
  final String establishmentId;
  final String? floorName;
  final String? roomName;
  final int tableNumber;
  final int sortOrder;
  final PosTableStatus status;

  factory PosDiningTable.fromJson(Map<String, dynamic> json) {
    return PosDiningTable(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      floorName: json['floor_name'] as String?,
      roomName: json['room_name'] as String?,
      tableNumber: (json['table_number'] as num).toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      status: PosTableStatus.fromApi(json['status'] as String? ?? 'free'),
    );
  }
}

enum PosTableStatus {
  free,
  occupied,
  billRequested;

  static PosTableStatus fromApi(String s) {
    switch (s) {
      case 'occupied':
        return PosTableStatus.occupied;
      case 'bill_requested':
        return PosTableStatus.billRequested;
      default:
        return PosTableStatus.free;
    }
  }

  String toApi() {
    switch (this) {
      case PosTableStatus.free:
        return 'free';
      case PosTableStatus.occupied:
        return 'occupied';
      case PosTableStatus.billRequested:
        return 'bill_requested';
    }
  }
}
