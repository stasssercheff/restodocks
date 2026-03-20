import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/employee.dart';
import '../models/establishment.dart';

enum HaccpOrderThirdPageMode {
  empty,
  filled,
}

class HaccpOrderPdfService {
  static pw.ThemeData? _theme;
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<pw.ThemeData> _getTheme() async {
    if (_theme != null) return _theme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _fontRegular = pw.Font.ttf(baseData);
    _fontBold = pw.Font.ttf(boldData);
    _theme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
      italic: _fontRegular!,
      boldItalic: _fontBold!,
    );
    return _theme!;
  }

  static String _employeeFullName(Employee e) {
    final parts = <String>[];
    if (e.fullName.trim().isNotEmpty) parts.add(e.fullName.trim());
    if (e.surname != null && e.surname!.trim().isNotEmpty) parts.add(e.surname!.trim());
    return parts.join(' ');
  }

  static String _positionDisplayRu(Employee e, Establishment establishment) {
    if (e.positionRole != null && e.positionRole!.isNotEmpty) {
      const roleToPosition = <String, String>{
        'executive_chef': 'Шеф-повар',
        'sous_chef': 'Су-шеф',
        'cook': 'Повар',
        'brigadier': 'Бригадир',
        'bartender': 'Бармен',
        'waiter': 'Официант',
        'bar_manager': 'Менеджер бара',
        'floor_manager': 'Менеджер зала',
        'general_manager': 'Управляющий',
      };
      return roleToPosition[e.positionRole!] ?? e.positionRole!;
    }

    // У владельца должность выбирается отдельным полем в карточке (positionRole == null),
    // поэтому используем реквизиты заведения.
    if (e.hasRole('owner')) {
      return (establishment.directorPosition ?? 'Генеральный директор').trim();
    }

    return '';
  }

  static String _directorFioOrUnderline(String? directorFio) {
    final v = (directorFio ?? '').trim();
    return v.isNotEmpty ? v : '______________';
  }

  static String _underline([String text = '______________']) => text;

  static Future<Uint8List> buildOrderPdfBytes({
    required Establishment establishment,
    required HaccpOrderThirdPageMode thirdPageMode,
    required List<Employee> selectedEmployees,
  }) async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);

    final textStyle = pw.TextStyle(fontSize: 10);
    final titleStyle = pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
    final sectionTitleStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);
    final smallStyle = pw.TextStyle(fontSize: 9);

    final directorFio = _directorFioOrUnderline(establishment.directorFio);
    final organizationName = (establishment.legalName ?? establishment.name).trim();

    // -------------------- Page 1 --------------------
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          // Оставляем как в шаблоне — заполняется вручную.
          final placeholderResponsible = '[Должность/ФИО]';
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ПРИКАЗ №____', style: titleStyle),
              pw.SizedBox(height: 6),
              pw.Text(
                '«О внедрении системы электронного учета и ведения производственной документации»',
                style: smallStyle,
              ),
              pw.SizedBox(height: 10),
              pw.Text('г. ____________ «__» __________ 202 г.', style: textStyle),
              pw.SizedBox(height: 12),
              pw.Text(
                'В целях оптимизации рабочих процессов, обеспечения оперативного контроля и сохранности данных, а также руководствуясь п. 2.22 и п. 3.8 СанПиН 2.3/2.4.3590-20,',
                style: textStyle,
              ),
              pw.SizedBox(height: 6),
              pw.Text('ПРИКАЗЫВАЮ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text(
                'Внедрить в деятельность $organizationName систему ведения производственной документации в электронном виде с использованием программного обеспечения (ПО) RestoDocks.\n\n'
                'Утвердить Перечень производственной документации, допущенной к ведению в электронном виде (Приложение №1 к настоящему Приказу).\n\n'
                'Установить, что ведение указанных в Приложении №1 журналов осуществляется преимущественно в электронном формате. Допускается временное ведение документации на бумажных носителях в случае технической необходимости или по решению ответственного лица.\n\n'
                'Установить, что идентификация сотрудника в ПО RestoDocks (уникальный логин и пароль) признается Сторонами использованием простой электронной подписи (ПЭП). Любая запись, внесенная под учетной записью сотрудника, приравнивается к его личной подписи на бумажном носителе.\n\n'
                'Назначить ответственным за контроль ведения, достоверность данных и своевременную выгрузку (печать) электронных журналов: $placeholderResponsible.\n\n'
                'Контроль за исполнением настоящего приказа оставляю за собой.',
                style: textStyle,
              ),
              pw.Spacer(),
              pw.SizedBox(height: 16),
              pw.Text('Руководитель заведения: ___________ /$directorFio/', style: textStyle),
              pw.Text('(Подпись) (ФИО)', style: smallStyle),
              pw.SizedBox(height: 6),
              pw.Text('М.П.', style: smallStyle),
            ],
          );
        },
      ),
    );

    // -------------------- Page 2 --------------------
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          final columnWidths = <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.2),
            1: const pw.FlexColumnWidth(2.1),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(2.0),
          };

          final headers = [
            '№',
            'Наименование журнала',
            'Форма ведения',
            'Ответственное лицо (должность)',
          ];

          final data = <List<dynamic>>[
            ['1', 'Гигиенический журнал (сотрудники)', 'Электронно / Бумажно', 'Шеф-повар / Су-шеф'],
            ['2', 'Журнал учета темп. режима холодильников', 'Электронно / Бумажно', 'Ответственный по цеху'],
            ['3', 'Журнал учета темп. и влажности складов', 'Электронно / Бумажно', 'Кладовщик / Шеф-повар'],
            ['4', 'Журнал бракеража готовой продукции', 'Электронно / Бумажно', 'Бракеражная комиссия'],
            ['5', 'Журнал бракеража скоропортящейся продукции', 'Электронно / Бумажно', 'Кладовщик / Су-шеф'],
            ['6', 'Учёт фритюрных жиров', 'Электронно / Бумажно', 'Повар горячего цеха'],
            ['7', 'Журнал учёта личных медицинских книжек', 'Электронно / Бумажно', 'Управляющий / Шеф'],
            ['8', 'Журнал учёта медосмотров', 'Электронно / Бумажно', 'Управляющий / Шеф'],
            ['9', 'Журнал учёта дезсредств и работ', 'Электронно / Бумажно', 'Шеф-повар'],
            ['10', 'Журнал мойки и дезинфекции оборудования', 'Электронно / Бумажно', 'Ответственный по цеху'],
            ['11', 'Журнал-график генеральных уборок', 'Электронно / Бумажно', 'Су-шеф'],
            ['12', 'Журнал проверки сит/фильтров и магнитов', 'Электронно / Бумажно', 'Повар заготовочного цеха'],
          ];

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Приложение №1 к Приказу №____ от «__» ________ 202 г.', style: sectionTitleStyle),
              pw.SizedBox(height: 8),
              pw.Text('ПЕРЕЧЕНЬ ПРОИЗВОДСТВЕННОЙ ДОКУМЕНТАЦИИ К ВЕДЕНИЮ В ЭЛЕКТРОННОМ ВИДЕ', style: sectionTitleStyle),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                cellPadding: const pw.EdgeInsets.all(3),
                cellHeight: 18,
                cellAlignment: pw.Alignment.topLeft,
                cellStyle: smallStyle,
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerPadding: const pw.EdgeInsets.all(3),
                headerHeight: 22,
                columnWidths: columnWidths,
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Данное приложение является неотъемлемой частью Приказа №____.', style: textStyle),
              pw.SizedBox(height: 26),
              pw.Text('УТВЕРЖДАЮ:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 8),
              pw.Text('Руководитель заведения: ___________ /$directorFio/ «» ________ 202 г.', style: textStyle),
              pw.Text('(Подпись) (ФИО) (Дата)', style: smallStyle),
              pw.SizedBox(height: 10),
              pw.Text('М.П.', style: smallStyle),
            ],
          );
        },
      ),
    );

    // -------------------- Page 3 --------------------
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          const rows = 25;
          final columnWidths = <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(0.18),
            1: const pw.FlexColumnWidth(1.9),
            2: const pw.FlexColumnWidth(1.35),
            3: const pw.FlexColumnWidth(0.85),
            4: const pw.FlexColumnWidth(0.95),
          };

          final headers = ['№', 'ФИО сотрудника', 'Должность', 'Дата ознакомления', 'Личная подпись'];

          final filled = thirdPageMode == HaccpOrderThirdPageMode.filled;
          final selected = filled ? selectedEmployees : const <Employee>[];

          final data = <List<dynamic>>[];
          for (var i = 0; i < rows; i++) {
            final e = i < selected.length ? selected[i] : null;
            final fio = e != null ? _employeeFullName(e) : _underline('______________');
            final position = e != null ? _positionDisplayRu(e, establishment) : _underline('______________');
            data.add([
              '${i + 1}',
              fio,
              position,
              _underline('______________'),
              _underline('______________'),
            ]);
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ЛИСТ ОЗНАКОМЛЕНИЯ СОТРУДНИКОВ С ПРИКАЗОМ №____ И ПРАВИЛАМИ ИСПОЛЬЗОВАНИЯ ПЭП', style: sectionTitleStyle),
              pw.SizedBox(height: 10),
              pw.Text(
                'Настоящим подтверждаю, что ознакомлен с Приказом №____ от «__» ________ 202 г. и правилами работы в ПО RestoDocks. '
                'Подтверждаю свое согласие на то, что использование моих персональных учетных данных (логина и пароля) признается использованием моей простой электронной подписи (ПЭП). '
                'Все записи, внесенные мной в электронные журналы, имеют юридическую силу, аналогичную моей рукописной подписи. '
                'Обязуюсь не передавать свои учетные данные третьим лицам.',
                style: textStyle,
              ),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                cellPadding: const pw.EdgeInsets.all(3),
                cellHeight: 16,
                cellAlignment: pw.Alignment.topLeft,
                cellStyle: smallStyle,
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerPadding: const pw.EdgeInsets.all(3),
                headerHeight: 22,
                columnWidths: columnWidths,
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Лист ознакомления является приложением к Приказу №____.', style: textStyle),
              pw.Spacer(),
              pw.SizedBox(height: 18),
              pw.Text('Ответственный за ведение листа: ___________ /___________________/', style: textStyle),
              pw.Text('(Подпись) (ФИО)', style: smallStyle),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}

