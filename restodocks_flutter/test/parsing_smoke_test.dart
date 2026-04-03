import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restodocks/services/ai_service_supabase.dart';

void main() {
  group('Parsing smoke', () {
    test('parseTtkByTemplate parses a basic table', () {
      final rows = [
        ['Наименование', 'Продукт', 'Брутто', 'Нетто'],
        ['ПФ Крем', 'Сливки 33%', '500', '500'],
        ['ПФ Крем', 'Сахар', '100', '100'],
        ['Итого', '', '600', '600'],
      ];

      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list.first.ingredients.length, greaterThanOrEqualTo(2));
    });

    test('parseTechCardsFromExcel parses CSV bytes', () async {
      final csv = 'Наименование,Продукт,Брутто,Нетто\n'
          'ПФ Крем,Сливки 33%,500,500\n'
          'ПФ Крем,Сахар,100,100\n'
          'Итого,,600,600\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final list = await AiServiceSupabase().parseTechCardsFromExcel(bytes);
      expect(list, isNotEmpty);
      expect(list.first.ingredients.length, greaterThanOrEqualTo(2));
    });
  });
}
