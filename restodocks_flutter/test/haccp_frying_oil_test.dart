// Проверка цепочки «Учёт фритюрных жиров»: типы, модель, парсинг из БД.

import 'package:flutter_test/flutter_test.dart';
import 'package:restodocks/models/haccp_log.dart';
import 'package:restodocks/models/haccp_log_type.dart';

void main() {
  group('HaccpLogType frying oil', () {
    test('supportedInApp contains fryingOil and has 6 items', () {
      expect(HaccpLogType.supportedInApp.length, 6);
      expect(HaccpLogType.supportedInApp.contains(HaccpLogType.fryingOil), true);
    });

    test('fromCode frying_oil returns fryingOil', () {
      expect(HaccpLogType.fromCode('frying_oil'), HaccpLogType.fryingOil);
    });

    test('fryingOil has quality table', () {
      expect(HaccpLogType.fryingOil.targetTable, HaccpLogTable.quality);
    });
  });

  group('HaccpLog fromQualityJson frying oil fields', () {
    test('parses frying oil columns from JSON', () {
      final json = {
        'id': 'test-id',
        'establishment_id': 'est-id',
        'created_by_employee_id': 'emp-id',
        'log_type': 'frying_oil',
        'created_at': '2026-03-16T12:00:00Z',
        'oil_name': 'Подсолнечное',
        'organoleptic_start': 'Норма',
        'frying_equipment_type': 'Фритюрница',
        'frying_product_type': 'Картофель фри',
        'frying_end_time': '14:00',
        'organoleptic_end': 'Норма',
        'carry_over_kg': 2.5,
        'utilized_kg': 0.5,
        'commission_signatures': 'Иванов И.И.',
      };
      final log = HaccpLog.fromQualityJson(json);
      expect(log.logType, HaccpLogType.fryingOil);
      expect(log.oilName, 'Подсолнечное');
      expect(log.organolepticStart, 'Норма');
      expect(log.fryingEquipmentType, 'Фритюрница');
      expect(log.fryingProductType, 'Картофель фри');
      expect(log.fryingEndTime, '14:00');
      expect(log.organolepticEnd, 'Норма');
      expect(log.carryOverKg, 2.5);
      expect(log.utilizedKg, 0.5);
      expect(log.commissionSignatures, 'Иванов И.И.');
    });
  });
}
