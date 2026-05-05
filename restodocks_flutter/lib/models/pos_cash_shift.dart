import 'package:equatable/equatable.dart';

/// Смена виртуальной кассы зала (`pos_cash_shifts`).
class PosCashShift extends Equatable {
  const PosCashShift({
    required this.id,
    required this.establishmentId,
    required this.startedAt,
    this.endedAt,
    required this.openingBalance,
    this.closingBalance,
    this.openedByEmployeeId,
    this.closedByEmployeeId,
    this.notes,
    this.closeReportScope,
    this.closeReportZones = const <String>[],
  });

  final String id;
  final String establishmentId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double openingBalance;
  final double? closingBalance;
  final String? openedByEmployeeId;
  final String? closedByEmployeeId;
  final String? notes;
  final String? closeReportScope;
  final List<String> closeReportZones;

  bool get isOpen => endedAt == null;

  factory PosCashShift.fromJson(Map<String, dynamic> json) {
    return PosCashShift(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      openingBalance: (json['opening_balance'] as num).toDouble(),
      closingBalance: json['closing_balance'] != null
          ? (json['closing_balance'] as num).toDouble()
          : null,
      openedByEmployeeId: json['opened_by_employee_id'] as String?,
      closedByEmployeeId: json['closed_by_employee_id'] as String?,
      notes: json['notes'] as String?,
      closeReportScope: json['close_report_scope'] as String?,
      closeReportZones: (json['close_report_zones'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id];
}
