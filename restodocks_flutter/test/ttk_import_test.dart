/// Тест парсинга ТТК: шаблон и цепочка.
/// Запуск: flutter test test/ttk_import_test.dart
///
/// Фикстуры DOCX (как iiko-бланк — исходники в проекте):
///   test/fixtures/Техкарта_Салат_Цезарь.docx
///   test/fixtures/Технологическая карта.docx
///   test/fixtures/tehnologicheskie_kartiy_blyud.docx
import 'dart:convert';
import 'dart:io';
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

    test('parseTtkByTemplate Набор сырья / 3-row header (школьное питание)', () {
      // Заголовок: Набор сырья, Расход; возрасты; Брутто/Нетто
      final rows = [
        ['Набор сырья', 'Расход продуктов на 1 порцию'],
        ['', 'от 7 до 11 лет', 'от 11 лет и старше'],
        ['', 'Брутто, г.', 'Нетто, г.', 'Брутто, г.', 'Нетто, г.'],
        ['Крупа овсяная «Геркулес»', '40,0', '40,0', '55,0', '55,0'],
        ['Молоко', '88,0', '88,0', '123,0', '123,0'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list[0].ingredients.length, greaterThanOrEqualTo(2));
      expect(list[0].ingredients.any((i) => i.productName.contains('Геркулес')), true);
      expect(list[0].ingredients.any((i) => i.productName.contains('Молоко')), true);
    });

    test('parseTtkByTemplate iiko-style № Наименование Ед.изм Брутто/Нетто кг', () {
      // Технологическая карта iiko: № | Наименование продукта | Ед.изм | Брутто | Вес брутто кг | Вес нетто кг
      final rows = [
        ['№', 'Наименование продукта', 'Ед. изм.', 'Брутто в ед. изм.', 'Вес брутто, кг', 'Вес нетто или п/ф, кг'],
        ['1', 'Т. Крылья куриные острые Баффало', 'кг', '0,150', '0,150', '0,150'],
        ['2', 'Т. Соус Терияки', 'л', '0,010', '0,010', '0,010'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list[0].ingredients.length, greaterThanOrEqualTo(2));
      expect(list[0].ingredients.any((i) => i.productName.contains('Крылья')), true);
      final wings = list[0].ingredients.firstWhere((i) => i.productName.contains('Крылья'));
      expect(wings.grossGrams, 150); // 0,150 kg → 150 g
    });

    test('parseTtkByTemplate супы format minimal (1 block)', () {
      final rows = [
        ['Тыквенный суп', ''],
        ['№', 'Наименование продукта', 'Вес гр/шт'],
        ['1', 'Сливки 22%', '30'],
        ['Выход', '', '400'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list.length, 1);
      expect(list[0].dishName, contains('Тыквенный'));
      expect(list[0].ingredients.length, 1);
    });

    test('parseTtkByTemplate супы.xlsx / Полное пособие Кухня (блоки: название→№|Наименование|Вес→Выход)', () {
      final rows = [
        ['Тыквенный крем-суп с горгонзолой', '', '', '', 'Доставка:', '', ''],
        ['№', 'Наименование продукта', 'Вес гр/шт', 'Вид нарезки', '', ''],
        ['1', 'Сливки 22% или кокосовое молоко', '30', '', '', ''],
        ['3', 'Тыквенный суп пф', '420', '', 'Технология', ''],
        ['4', 'Горгонзола п/ф', '25', 'мелкие кусочки', '', ''],
        ['Выход', '', '400', '', '', ''],
        ['Рыбная похлебка по-лигурийски', '', '', '', 'Доставка:', ''],
        ['№', 'Наименование продукта', '', 'Вид нарезки', '', ''],
        ['1', 'Набор морепродуктов', '1 шт', '', '', ''],
        ['4', 'База на лигурию п/ф', '290', '', '', ''],
        ['5', 'Бульон куриный п/ф', '160', '', '', ''],
        ['Выход', '', '420/70', '', '', ''],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      // debug: print(list.map((c) => '${c.dishName} (${c.ingredients.length})').join('; '));
      expect(list.length, 2);
      expect(list[0].dishName, contains('Тыквенный'));
      expect(list[0].ingredients.length, greaterThanOrEqualTo(3));
      expect(list[1].dishName, contains('Рыбная'));
      expect(list[1].ingredients.length, greaterThanOrEqualTo(2));
    });

    test('parseTtkByTemplate iiko/1С с пустой колонкой № empty Наименование (печенная свекла.xls)', () {
      final rows = [
        ['ПЕЧЕНАЯ СВЕКЛА С СЫРОМ СТРАЧАТЕЛЛА И ШПИНАТОМ', '', '', '', '', '', '', '', '', ''],
        ['Технологическая карта № 121138271', '', '', '', '', '', '', '', '', ''],
        ['', '', '', '', '', '', '', '', '', ''],
        ['№', '', 'Наименование продукта', '', '', '', 'Ед. изм.', 'Брутто в ед. изм.', '', 'Вес брутто, кг'],
        ['1', '', 'Свекла печеная п/ф.', '', '', '', 'кг', '0.23', '', '0.23'],
        ['2', '', 'Соус органик п/ф.', '', '', '', 'кг', '0.03', '', '0.03'],
        ['3', '', 'Орех Кедровый', '', '', '', 'кг', '0.01', '', '0.01'],
        ['ИТОГО', '', '', '', '', '', '', '', '', ''],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list.length, 1, reason: 'Got: ${list.map((c) => "${c.dishName}(${c.ingredients.length})").join("; ")}');
      expect(list[0].dishName, contains('ПЕЧЕНАЯ'));
      expect(list[0].ingredients.length, greaterThanOrEqualTo(3));
    });

    test('parseTtkByTemplate ГОСТ 2-row header (docx Цезарь)', () {
      // Заголовок в 2 строках: row0 Наименование/Расход, row1 Брутто/Нетто
      final rows = [
        ['Наименование сырья и продуктов', 'Расход сырья на 1 порцию'],
        ['', 'Брутто', 'Нетто'],
        ['Куриное филе', '70', '50'],
        ['Хлеб', '40', '20'],
        ['Сыр твёрдый', '20', '20'],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty);
      expect(list[0].ingredients.length, 3);
      expect(list[0].ingredients.any((i) => i.productName.contains('Куриное')), true);
      expect(list[0].ingredients.any((i) => i.productName.contains('Хлеб')), true);
      expect(list[0].ingredients.firstWhere((i) => i.productName.contains('Куриное')).grossGrams, 70);
    });

    test('format detection routes DOCX/OLE/CSV correctly', () async {
      final csv = 'Наименование,Продукт,Брутто\nБорщ,Свекла,100\n';
      final csvBytes = Uint8List.fromList(utf8.encode(csv));
      final list = await AiServiceSupabase().parseTechCardsFromExcel(csvBytes);
      expect(list, isNotEmpty);
      expect(list.first.ingredients.any((i) => i.productName.contains('Свекла')), true);
    });

    test('safeParseDouble handles 0.5 кг, 1/2 шт', () {
      expect(AiServiceSupabase.safeParseDouble('0.5 кг'), 0.5);
      expect(AiServiceSupabase.safeParseDouble('1/2'), 0.5);
      expect(AiServiceSupabase.safeParseDouble('100 г'), 100);
      expect(AiServiceSupabase.safeParseDouble(null), 0);
    });

    test('parseTtkByTemplate with errors collects failed cards', () {
      final rows = [
        ['Наименование', 'Продукт', 'Брутто', 'Нетто'],
        ['Борщ', 'Свекла', '100', '80'],
        ['Борщ', 'Говядина', '200', '150'],
        ['Итого', '', '', ''],
        ['Салат', 'Помидоры', '50', '50'],
      ];
      final errors = <TtkParseError>[];
      final list = AiServiceSupabase.parseTtkByTemplate(rows, errors: errors);
      expect(list.length, 2);
      expect(errors, isEmpty);
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

  group('TTK DOCX fixtures (как iiko-бланк — документы из test/fixtures/)', () {
    Future<Uint8List?> _loadFixture(String name) async {
      final f = File('test/fixtures/$name');
      if (!await f.exists()) return null;
      return f.readAsBytes();
    }

    test('parseTechCardsFromExcel Техкарта_Салат_Цезарь.docx', () async {
      final bytes = await _loadFixture('Техкарта_Салат_Цезарь.docx');
      if (bytes == null) {
        return; // фикстура отсутствует — пропускаем
      }
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);
      // debug: print('Cards: ${list.map((c) => "${c.dishName} (${c.ingredients.length})").join("; ")}');
      expect(list, isNotEmpty, reason: 'Должна распознаться хотя бы 1 карточка');
      final cezarCard = list.where((c) {
        final n = (c.dishName ?? '').toLowerCase();
        return n.contains('цезар') || n.contains('салат');
      }).toList();
      expect(cezarCard, isNotEmpty, reason: 'Название должно содержать Салат/Цезарь, получено: ${list.map((c) => c.dishName).join(", ")}');
      if (cezarCard.first.ingredients.isNotEmpty) {
        expect(cezarCard.first.ingredients.length, greaterThanOrEqualTo(2), reason: 'Ожидаем ингредиенты (Куриное филе, Хлеб и т.д.)');
      }
    });

    test('parseTechCardsFromExcel Технологическая карта.docx', () async {
      final bytes = await _loadFixture('Технологическая карта.docx');
      if (bytes == null) return;
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);
      expect(list, isNotEmpty, reason: 'Должна распознаться хотя бы 1 карточка');
      expect(list.first.ingredients.length, greaterThanOrEqualTo(1));
    });

    test('parseTechCardsFromExcel tehnologicheskie_kartiy_blyud.docx', () async {
      final bytes = await _loadFixture('tehnologicheskie_kartiy_blyud.docx');
      if (bytes == null) return;
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);
      expect(list, isNotEmpty, reason: 'Должна распознаться хотя бы 1 карточка');
    });
  });
}
