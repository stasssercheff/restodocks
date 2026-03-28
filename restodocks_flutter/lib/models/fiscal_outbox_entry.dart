import 'package:equatable/equatable.dart';

/// Строка очереди `fiscal_outbox` (до обмена с ККТ).
class FiscalOutboxEntry extends Equatable {
  const FiscalOutboxEntry({
    required this.id,
    this.posOrderId,
    required this.operation,
    required this.status,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    required this.payload,
  });

  final String id;
  final String? posOrderId;
  final String operation;
  final String status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;

  factory FiscalOutboxEntry.fromJson(Map<String, dynamic> json) {
    return FiscalOutboxEntry(
      id: json['id'] as String,
      posOrderId: json['pos_order_id'] as String?,
      operation: json['operation'] as String? ?? 'sale',
      status: json['status'] as String? ?? 'pending',
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'].toString()),
      updatedAt: DateTime.parse(json['updated_at'].toString()),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : <String, dynamic>{},
    );
  }

  @override
  List<Object?> get props => [id, status, updatedAt];
}
