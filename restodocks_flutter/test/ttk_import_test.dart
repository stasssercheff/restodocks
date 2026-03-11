/// Тест парсинга ТТК: шаблон и цепочка.
/// Запуск: flutter test test/ttk_import_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restodocks/services/ai_service.dart';
import 'package:restodocks/services/ai_service_supabase.dart';

void main() {
  group('TTK template parsing', () {
    test('CSV with eol produces correct rows', () {
      final csv = 'Наименование,Продукт,Брутто,Нетто\n'
          'ПФ Крем,Сливки 33%,500,500\n';
      final decoded = CsvToListConverter(eol: '\n').convert(csv);
      expect(decoded.length, 2);
      expect(decoded[0], ['Наименование', 'Продукт', 'Брутто', 'Нетто']);
      expect((decoded[1] as List).map((e) => e.toString()).toList(),
          ['ПФ Крем', 'Сливки 33%', '500', '500']);
    });

    test('parseTtkByTemplate extracts cards from standard rows', () {
      final rows = [
        ['Наименование', 'Продукт', 'Брутто', 'Нетто'],
        ['ПФ Крем', 'Сливки 33%', '500', '500'],
        ['ПФ Крем', 'Сахар', '100', '100'],
        ['Итого', '', '600', '600'],
        ['Борщ', 'Говядина', '200', '150'],
        ['Борщ', 'Свекла', '100', '80'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list.length, 2);
      expect(list[0].dishName, contains('Крем'));
      expect(list[0].ingredients.length, 2);
      expect(list[1].dishName, contains('Борщ'));
      expect(list[1].ingredients.length, 2);
    });

    test('parseTtkByTemplate handles single-cell rows (DOCX-style)', () {
      // DOCX даёт каждый параграф как одну ячейку
      final rows = [
        ['№ Наименование продукта Ед. изм. Брутто в ед. изм. Вес брутто, кг Вес нетто, кг'],
        ['1 Т. Крылья куриные острые Баффало кг 0,150 0,150 0,150'],
        ['2 Т. Соус Терияки л 0,010 0,010 0,010'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list[0].ingredients.length, greaterThanOrEqualTo(2));
      expect(list[0].ingredients.any((i) => i.productName.contains('Крылья')), true);
    });

    test('full parseTechCardsFromExcel with standard CSV bytes', () async {
      final csv = 'Наименование,Продукт,Брутто,Нетто\n'
          'ПФ Крем,Сливки 33%,500,500\n'
          'ПФ Крем,Сахар,100,100\n'
          'Итого,,600,600\n'
          'Борщ,Говядина,200,150\n'
          'Борщ,Свекла,100,80\n';
      final bytes = Uint8List.fromList(utf8.encode(csv));

      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);

      expect(list, isNotEmpty);
      expect(list.length, 2);
      expect(list[0].dishName, contains('Крем'));
      expect(list[0].ingredients.length, 2);
      expect(list[1].dishName, contains('Борщ'));
      expect(list[1].ingredients.length, 2);
    });
  });
}
