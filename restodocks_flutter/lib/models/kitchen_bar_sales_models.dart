import 'package:flutter/material.dart';

/// Пресет периода (даты считаются в локальной зоне).
enum KitchenBarSalesPeriodKind {
  custom,
  shiftDay,
  week,
  month,
  quarter,
  halfYear,
  year,
}

/// Одна строка агрегата по блюду.
class KitchenBarSalesRow {
  KitchenBarSalesRow({
    required this.techCardId,
    required this.subdivisionLabel,
    required this.dishTypeLabel,
    required this.dishName,
    required this.quantity,
    required this.costTotal,
    required this.sellingTotal,
  });

  final String techCardId;
  final String subdivisionLabel;
  final String dishTypeLabel;
  final String dishName;
  final double quantity;
  final double costTotal;
  final double sellingTotal;
}

/// Снимок настроек экспорта (как на экране).
class KitchenBarSalesExportPrefs {
  const KitchenBarSalesExportPrefs({
    this.includeCost = true,
    this.includeSelling = true,
    this.includeSubdivision = true,
    this.includeDishType = true,
  });

  final bool includeCost;
  final bool includeSelling;
  final bool includeSubdivision;
  final bool includeDishType;

  KitchenBarSalesExportPrefs copyWith({
    bool? includeCost,
    bool? includeSelling,
    bool? includeSubdivision,
    bool? includeDishType,
  }) {
    return KitchenBarSalesExportPrefs(
      includeCost: includeCost ?? this.includeCost,
      includeSelling: includeSelling ?? this.includeSelling,
      includeSubdivision: includeSubdivision ?? this.includeSubdivision,
      includeDishType: includeDishType ?? this.includeDishType,
    );
  }
}

/// План продаж (локально на устройстве).
enum SalesPlanPeriodKind {
  shiftDay,
  week,
  month,
  quarter,
  halfYear,
  year,
}

class SalesPlanLine {
  SalesPlanLine({
    required this.techCardId,
    required this.dishName,
    required this.targetQuantity,
  });

  final String techCardId;
  final String dishName;
  final double targetQuantity;

  Map<String, dynamic> toJson() => {
        'tech_card_id': techCardId,
        'dish_name': dishName,
        'target_quantity': targetQuantity,
      };

  factory SalesPlanLine.fromJson(Map<String, dynamic> j) {
    return SalesPlanLine(
      techCardId: j['tech_card_id'] as String? ?? '',
      dishName: j['dish_name'] as String? ?? '',
      targetQuantity: (j['target_quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SalesPlan {
  SalesPlan({
    required this.id,
    required this.establishmentId,
    required this.department,
    required this.periodKind,
    required this.periodStart,
    required this.periodEnd,
    required this.targetCashAmount,
    required this.lines,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String establishmentId;
  final String department;
  final SalesPlanPeriodKind periodKind;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double targetCashAmount;
  final List<SalesPlanLine> lines;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'establishment_id': establishmentId,
        'department': department,
        'period_kind': periodKind.name,
        'period_start': periodStart.toUtc().toIso8601String(),
        'period_end': periodEnd.toUtc().toIso8601String(),
        'target_cash_amount': targetCashAmount,
        'lines': lines.map((e) => e.toJson()).toList(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': (updatedAt ?? createdAt).toUtc().toIso8601String(),
      };

  factory SalesPlan.fromJson(Map<String, dynamic> j) {
    return SalesPlan(
      id: j['id'] as String? ?? '',
      establishmentId: j['establishment_id'] as String? ?? '',
      department: j['department'] as String? ?? 'kitchen',
      periodKind: SalesPlanPeriodKind.values.firstWhere(
        (e) => e.name == j['period_kind'],
        orElse: () => SalesPlanPeriodKind.month,
      ),
      periodStart: DateTime.parse(j['period_start'] as String),
      periodEnd: DateTime.parse(j['period_end'] as String),
      targetCashAmount: (j['target_cash_amount'] as num?)?.toDouble() ?? 0,
      lines: (j['lines'] as List<dynamic>?)
              ?.map((e) => SalesPlanLine.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: j['updated_at'] != null
          ? DateTime.tryParse(j['updated_at'].toString())
          : null,
    );
  }
}

/// Режим отображения календаря плана.
enum SalesPlanCalendarDisplayMode {
  percent,
  amountFraction,
}

/// Границы периода в локальном времени.
(DateTime startLocal, DateTime endLocal) kitchenBarSalesResolvePeriod({
  required KitchenBarSalesPeriodKind kind,
  required DateTime nowLocal,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);
  DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  switch (kind) {
    case KitchenBarSalesPeriodKind.custom:
      final a = customStart ?? nowLocal;
      final b = customEnd ?? nowLocal;
      final s = startOfDay(a.isBefore(b) ? a : b);
      final e = endOfDay(a.isBefore(b) ? b : a);
      return (s, e);
    case KitchenBarSalesPeriodKind.shiftDay:
      final d = startOfDay(nowLocal);
      return (d, endOfDay(nowLocal));
    case KitchenBarSalesPeriodKind.week:
      final d0 = startOfDay(nowLocal);
      final wd = d0.weekday;
      final monday = d0.subtract(Duration(days: wd - 1));
      final sunday = monday.add(const Duration(days: 6));
      return (monday, endOfDay(sunday));
    case KitchenBarSalesPeriodKind.month:
      final s = DateTime(nowLocal.year, nowLocal.month, 1);
      final e = DateTime(nowLocal.year, nowLocal.month + 1, 0);
      return (s, endOfDay(e));
    case KitchenBarSalesPeriodKind.quarter:
      final q = ((nowLocal.month - 1) ~/ 3);
      final m0 = q * 3 + 1;
      final s = DateTime(nowLocal.year, m0, 1);
      final e = DateTime(nowLocal.year, m0 + 3, 0);
      return (s, endOfDay(e));
    case KitchenBarSalesPeriodKind.halfYear:
      final firstHalf = nowLocal.month <= 6;
      final s = firstHalf
          ? DateTime(nowLocal.year, 1, 1)
          : DateTime(nowLocal.year, 7, 1);
      final e = firstHalf
          ? endOfDay(DateTime(nowLocal.year, 6, 30))
          : endOfDay(DateTime(nowLocal.year, 12, 31));
      return (s, e);
    case KitchenBarSalesPeriodKind.year:
      return (
        DateTime(nowLocal.year, 1, 1),
        endOfDay(DateTime(nowLocal.year, 12, 31))
      );
  }
}

(DateTime startLocal, DateTime endLocal) salesPlanResolvePeriodBounds({
  required SalesPlanPeriodKind kind,
  required DateTime anchorLocal,
}) {
  return kitchenBarSalesResolvePeriod(
    kind: switch (kind) {
      SalesPlanPeriodKind.shiftDay => KitchenBarSalesPeriodKind.shiftDay,
      SalesPlanPeriodKind.week => KitchenBarSalesPeriodKind.week,
      SalesPlanPeriodKind.month => KitchenBarSalesPeriodKind.month,
      SalesPlanPeriodKind.quarter => KitchenBarSalesPeriodKind.quarter,
      SalesPlanPeriodKind.halfYear => KitchenBarSalesPeriodKind.halfYear,
      SalesPlanPeriodKind.year => KitchenBarSalesPeriodKind.year,
    },
    nowLocal: anchorLocal,
  );
}

bool kitchenBarTimeOfDayInRange(
  DateTime localInstant, {
  required TimeOfDay start,
  required TimeOfDay end,
}) {
  final minutes = localInstant.hour * 60 + localInstant.minute;
  final a = start.hour * 60 + start.minute;
  final b = end.hour * 60 + end.minute;
  if (a <= b) {
    return minutes >= a && minutes <= b;
  }
  return minutes >= a || minutes <= b;
}
