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
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restodocks/services/ai_service.dart';
import 'package:restodocks/services/ai_service_supabase.dart';
import 'package:restodocks/services/iiko_xlsx_sanitizer.dart';

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

    test('parseTtkByTemplate пф гц: наименование|Ед.изм|Норма закладки, несколько блоков', () {
      final rows = [
        ['Соус для пиццы п/ф', '', '', '', '', '', '', '', ''],
        ['', 'наименование', 'Ед.изм', 'Норма закладки', '', '', '', 'Технология приготовления'],
        ['1', 'Томаты с/с', 'кг', '1.1', '', '', ''],
        ['2', 'Масло оливковое п/ф', 'л', '0.038', '', '', ''],
        ['3', 'Соль', 'кг', '0.004', '', '', ''],
        ['Выход', '', 'кг', '0.99', '', '', ''],
        ['Песто пф', '', '', '', '', '', ''],
        ['', 'наименование', 'Ед.изм', 'Норма закладки', '', '', ''],
        ['1', 'Базилик пф', 'кг', '0.038', '', '', ''],
        ['2', 'Орех грецкий', 'кг', '0.01', '', '', ''],
        ['Выход', '', 'кг', '0.25', '', '', ''],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list.length, 2, reason: 'Got: ${list.map((c) => c.dishName).join(", ")}');
      expect(list[0].dishName, contains('Соус'));
      expect(list[0].ingredients.length, greaterThanOrEqualTo(3));
      expect(list[1].dishName, contains('Песто'));
      expect(list[1].ingredients.length, greaterThanOrEqualTo(2));
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
      if (await f.exists()) return f.readAsBytes();
      final f2 = File('test/$name');
      if (await f2.exists()) return f2.readAsBytes();
      return null;
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

    test('parseTechCardsFromExcel печенная свекла.xls (iiko/1С)', () async {
      final bytes = await _loadFixture('печенная свекла.xls');
      if (bytes == null) return; // fixture в test/fixtures/ или test/
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);
      expect(list, isNotEmpty, reason: 'Печеная свекла: должна распознаться карточка. Получено: ${list.length}');
      final beet = list.where((c) => (c.dishName ?? '').toLowerCase().contains('свекла')).toList();
      expect(beet, isNotEmpty, reason: 'Название должно содержать Свекла. Получено: ${list.map((c) => c.dishName).join(", ")}');
      expect(beet.first.ingredients.length, greaterThanOrEqualTo(2), reason: 'Ожидаем ингредиенты (Свекла печеная, Соус и т.д.)');
    });

    test('parseTechCardsFromExcel пф хц.xlsx (pf_hc fixture)', () async {
      final bytes = await _loadFixture('pf_hc.xlsx');
      if (bytes == null) return; // fixture может отсутствовать
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromExcel(bytes);
      expect(list, isNotEmpty, reason: 'Должна распознаться хотя бы 1 карточка');
      // Debug: печатаем что получили
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        final tech = c.technologyText != null && c.technologyText!.length > 20 ? 'yes' : 'no';
        final yld = c.yieldGrams?.toStringAsFixed(0) ?? '-';
        // ignore: avoid_print
        print('  ${i + 1}. ${c.dishName} | ingr:${c.ingredients.length} | tech:$tech | yield:$yld');
      }
      // Ожидаем 21 карточку, технология и выход
      expect(list.length, 21, reason: 'Ожидаем 21 карточку');
      final withTech = list.where((c) => c.technologyText != null && c.technologyText!.trim().isNotEmpty).length;
      final withYield = list.where((c) => c.yieldGrams != null && c.yieldGrams! > 0).length;
      expect(withTech, greaterThan(0), reason: 'Хотя бы часть карточек должна иметь технологию');
      expect(withYield, greaterThan(0), reason: 'Хотя бы часть карточек должна иметь выход');
    });

    test('parseTechCardsFromPdf ТК_на_Сливочный_крем (Shama.Book)', () async {
      final bytes = await _loadFixture('ТК_на_Сливочный_крем_для_мафинов_и_дэкоров_п_ф,_№_.pdf');
      if (bytes == null) return;
      final ai = AiServiceSupabase();
      final list = await ai.parseTechCardsFromPdf(bytes);
      expect(list, isNotEmpty, reason: 'Сливочный крем: должна распознаться карточка. reason=${AiServiceSupabase.lastParseTechCardPdfReason}');
      final cream = list.where((c) => (c.dishName ?? '').toLowerCase().contains('крем') || (c.dishName ?? '').toLowerCase().contains('сливоч')).toList();
      if (cream.isNotEmpty) {
        expect(cream.first.ingredients.length, greaterThanOrEqualTo(3), reason: 'Ожидаем Сыр, Сахар, Сливки, Соль, ваниль');
        if (cream.first.technologyText != null && cream.first.technologyText!.length > 20) {
          expect(cream.first.technologyText, contains('сахар'), reason: 'Технология должна содержать описание приготовления');
        }
      }
    });
  });

  group('parseTtkByTemplate pf_hc rows (direct)', () {
    List<List<String>> _xlsxToRows(Uint8List bytes) {
      String cellStr(dynamic v) {
        if (v == null) return '';
        if (v is num) return v.toString();
        // excel 4.x: TextCellValue.value can be String or TextSpan
        if (v.runtimeType.toString().contains('TextCellValue')) {
          final val = (v as dynamic).value;
          if (val is String) return val;
          try {
            final t = (val as dynamic).text;
            return t != null ? t.toString() : val.toString();
          } catch (_) {}
          return val.toString();
        }
        return v.toString();
      }
      try {
        final decodable = IikoXlsxSanitizer.ensureDecodable(bytes);
        final excel = Excel.decodeBytes(decodable.toList());
        final sheetName = excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
        if (sheetName == null) return [];
        final sheet = excel.tables[sheetName]!;
        final result = <List<String>>[];
        final rawRows = sheet.rows;
        if (rawRows.isEmpty && sheet.maxRows > 0) {
          for (var r = 0; r < sheet.maxRows; r++) {
            final row = <String>[];
            for (var c = 0; c < sheet.maxColumns; c++) {
              final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
              row.add(cellStr(cell.value).trim());
            }
            if (row.any((s) => s.trim().isNotEmpty)) result.add(row);
          }
        } else {
          for (final rawRow in rawRows) {
            final row = rawRow.map((c) => cellStr(c?.value).trim()).toList();
            if (row.any((s) => s.trim().isNotEmpty)) result.add(row);
          }
        }
        return result;
      } catch (_) {
        return [];
      }
    }

    test('пф хц из xlsx: Excel.decodeBytes → parseTtkByTemplate', () async {
      final f = File('test/fixtures/pf_hc.xlsx');
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      expect(bytes.length, greaterThan(100), reason: 'Файл должен быть непустым');
      final rows = _xlsxToRows(Uint8List.fromList(bytes));
      expect(rows.length, greaterThanOrEqualTo(5), reason: 'Excel должен вернуть строки (получено ${rows.length}, bytes=${bytes.length})');
      expect(rows[0][0], contains('Зеленый'), reason: 'Первая строка — название блюда');
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty, reason: 'Парсер должен распознать карточки из Excel-строк');
      expect(list.length, greaterThanOrEqualTo(5), reason: 'Ожидаем 5+ карточек');
    });

    test('пф хц структура: Зеленый микс → Сальса → Заправка', () {
      // Реальная структура из pf_hc.xlsx (первые блоки)
      final rows = [
        ['Зеленый микс п/ф', '', '', '', '', '', '', '', ''],
        ['', 'Наименование продукта', 'Ед.изм', 'Норма', '', '', '', '', 'Технология приготовления'],
        ['1', 'Шпинат п/ф', 'кг', '0.35', '', '', '', '', 'Зелень промыть в содо-сол'],
        ['2', 'Руккола п/ф', 'кг', '0.15', '', '', '', '', ''],
        ['3', 'Айсберг п/ф', 'кг', '0.2', '', '', '', '', ''],
        ['Выход', '', 'кг', '0.7', '', '', '', '', ''],
        ['Сальса п/ф', '', '', '', '', '', '', '', ''],
        ['№', 'Наименование', 'Ед.изм', '', '', '', '', '', ''],
        ['1', 'Оливки без косточек', 'гр', '100', '', '', '', '', 'Оливки, томаты черри,вяле'],
        ['2', 'Черри', 'гр', '100', '', '', '', '', ''],
        ['Выход', '', 'кг', '0.99', '', '', '', '', ''],
      ];
      final list = AiServiceSupabase.parseTtkByTemplate(rows);
      expect(list, isNotEmpty, reason: 'Прямой вызов parseTtkByTemplate должен распознать блоки');
      expect(list.length, greaterThanOrEqualTo(2), reason: 'Зеленый микс + Сальса минимум');
      expect(list[0].dishName, contains('Зеленый'));
      expect(list[0].ingredients.length, greaterThanOrEqualTo(3));
      expect(list[0].yieldGrams, isNotNull);
      expect(list[0].yieldGrams! > 0, true);
    });
  });
}
