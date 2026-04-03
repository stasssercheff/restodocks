import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restodocks/services/order_list_export_service.dart';

void main() {
  String t(String key) => key;

  group('Export smoke', () {
    test('buildOrderExcelBytesFromPayload returns non-empty bytes', () async {
      final payload = <String, dynamic>{
        'header': {
          'establishmentName': 'Resto',
          'supplierName': 'Supplier A',
          'employeeName': 'Ivan',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'orderForDate': DateTime.now().toUtc().toIso8601String(),
        },
        'items': [
          {
            'productId': 'p1',
            'productName': 'Tomato',
            'unit': 'kg',
            'quantity': 2,
            'pricePerUnit': 100,
            'lineTotal': 200,
          },
        ],
        'grandTotal': 200,
        'comment': 'ok',
      };

      final bytes = await OrderListExportService.buildOrderExcelBytesFromPayload(
        payload: payload,
        t: t,
        currency: 'RUB',
      );
      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, true);
    });

    test('buildProductOrdersExpenseExcelBytes returns non-empty bytes', () async {
      final orders = <Map<String, dynamic>>[
        {
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'header': {
              'supplierName': 'Supplier A',
              'employeeName': 'Ivan',
            },
            'grandTotal': 300,
          },
        },
      ];

      final bytes = await OrderListExportService.buildProductOrdersExpenseExcelBytes(
        orders: orders,
        dateStart: DateTime.now().subtract(const Duration(days: 1)),
        dateEnd: DateTime.now().add(const Duration(days: 1)),
        selectedSupplierNames: const {},
        t: t,
        currency: 'RUB',
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.isNotEmpty, true);
    });
  });
}
