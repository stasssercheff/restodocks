import 'package:equatable/equatable.dart';

/// Выдача из кассы зала (`pos_cash_disbursements`).
class PosCashDisbursement extends Equatable {
  const PosCashDisbursement({
    required this.id,
    required this.establishmentId,
    this.shiftId,
    required this.amount,
    required this.purpose,
    this.recipientEmployeeId,
    this.recipientName,
    this.createdByEmployeeId,
    required this.createdAt,
  });

  final String id;
  final String establishmentId;
  final String? shiftId;
  final double amount;
  final String purpose;
  final String? recipientEmployeeId;
  final String? recipientName;
  final String? createdByEmployeeId;
  final DateTime createdAt;

  factory PosCashDisbursement.fromJson(Map<String, dynamic> json) {
    return PosCashDisbursement(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      shiftId: json['shift_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      purpose: json['purpose'] as String,
      recipientEmployeeId: json['recipient_employee_id'] as String?,
      recipientName: json['recipient_name'] as String?,
      createdByEmployeeId: json['created_by_employee_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  List<Object?> get props => [id];
}
