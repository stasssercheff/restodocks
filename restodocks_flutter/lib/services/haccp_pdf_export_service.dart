import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/haccp_log.dart';
import '../models/haccp_log_type.dart';

/// Экспорт журналов ХАССП в PDF.
/// Обложка, шапка СанПиН, лист прошивки.
class HaccpPdfExportService {
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

  static pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Align(
          alignment: align == pw.TextAlign.center ? pw.Alignment.center : pw.Alignment.centerLeft,
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
      );

  static const _sanpinHealthHygiene = 'Приложение № 1 к СанПиН 2.3/2.4.3590-20';

  /// Официальные названия и подписи по рекомендуемым формам (как на образцах).
  /// Заголовки по формулировкам СанПиН 2.3/2.4.3590-20 (Приложения 1–5).
  static String _pdfTitle(HaccpLogType logType) {
    return switch (logType) {
      HaccpLogType.healthHygiene => 'Гигиенический журнал (сотрудники)',
      HaccpLogType.fridgeTemperature => 'Журнал учета температурного режима холодильного оборудования',
      HaccpLogType.warehouseTempHumidity => 'Журнал учета температуры и влажности в складских помещениях',
      HaccpLogType.finishedProductBrakerage => 'Журнал бракеража готовой пищевой продукции',
      HaccpLogType.incomingRawBrakerage => 'Журнал бракеража скоропортящейся пищевой продукции',
      HaccpLogType.fryingOil => 'Журнал учета использования фритюрных жиров',
      _ => logType.displayNameRu,
    };
  }

  /// Подпись под таблицей (как в шаблоне — правый верхний угол каждого листа).
  static String _pdfFooter(HaccpLogType logType) {
    return switch (logType) {
      HaccpLogType.healthHygiene => 'Приложение № 1 к СанПиН 2.3/2.4.3590-20',
      HaccpLogType.fridgeTemperature => 'Приложение № 2 к СанПиН 2.3/2.4.3590-20',
      HaccpLogType.warehouseTempHumidity => 'Приложение № 3 к СанПиН 2.3/2.4.3590-20',
      HaccpLogType.finishedProductBrakerage => 'Приложение № 4 к СанПиН 2.3/2.4.3590-20',
      HaccpLogType.incomingRawBrakerage => 'Приложение № 5 к СанПиН 2.3/2.4.3590-20',
      HaccpLogType.fryingOil => 'Приложение № 8 к СанПиН 2.3/2.4.3590-20',
      _ => 'СанПиН 2.3/2.4.3590-20',
    };
  }

  /// Гигиенический журнал: макет по образцу — графы как в рекомендуемой форме.
  static pw.Widget _buildHealthHygienePage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    (String name, String position) _parseEmp(String s) {
      final idx = s.lastIndexOf(', ');
      if (idx > 0) return (s.substring(0, idx).trim(), s.substring(idx + 2).trim());
      return (s, '');
    }

    const border = pw.BorderSide(color: PdfColors.black, width: 0.5);
    final tableBorder = pw.TableBorder(
      left: border,
      top: border,
      right: border,
      bottom: border,
      horizontalInside: border,
      verticalInside: border,
    );

    pw.Widget _headerCell(String text) => pw.Padding(
          padding: pw.EdgeInsets.all(2),
          child: pw.Center(
            child: pw.Text(text, style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          ),
        );

    final colWidths = {
      0: const pw.FlexColumnWidth(0.3),
      1: const pw.FlexColumnWidth(0.9),
      2: const pw.FlexColumnWidth(1.4),
      3: const pw.FlexColumnWidth(0.8),
      4: const pw.FlexColumnWidth(1.3),
      5: const pw.FlexColumnWidth(1.5),
      6: const pw.FlexColumnWidth(0.9),
      7: const pw.FlexColumnWidth(1.2),
    };

    final headerRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _headerCell('№ п/п'),
          _headerCell('Дата'),
          _headerCell('Ф. И. О. работника (последнее при наличии)'),
          _headerCell('Должность'),
          _headerCell('Подпись сотрудника об отсутствии признаков инфекционных заболеваний у сотрудника и членов семьи'),
          _headerCell('Подпись сотрудника об отсутствии заболеваний верхних дыхательных путей и гнойничковых заболеваний кожи рук и открытых поверхностей тела'),
          _headerCell('Результат осмотра медицинским работником (ответственным лицом) (допущен / отстранен)'),
          _headerCell('Подпись медицинского работника (ответственного лица)'),
        ],
      ),
    ];

    String col5(HaccpLog? log) {
      if (log == null) return '';
      if (log.statusOk == true) return 'Да';
      return '';
    }

    String col6(HaccpLog? log) {
      if (log == null) return '';
      if (log.status2Ok == true) return 'Да';
      if (log.status2Ok == false) return 'Нет';
      return '';
    }

    String col7(HaccpLog? log) {
      if (log == null) return '';
      return log.statusOk == true ? 'допущен' : (log.statusOk == false ? 'отстранен' : '');
    }

    final dateFmt = DateFormat('dd.MM.yyyy');

    final rowCount = logs.isEmpty ? 25 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      String name = '';
      String position = '';
      String creatorFull = '';
      if (log != null) {
        final parsed = HaccpLog.parseHealthHygieneDescription(log.description);
        final subjectId = parsed.subjectEmployeeId ?? log.createdByEmployeeId;
        final full = employeeIdToName[subjectId] ?? '';
        final parsedEmp = _parseEmp(full);
        name = parsedEmp.$1;
        position = parsed.positionOverride ?? parsedEmp.$2;
        creatorFull = employeeIdToName[log.createdByEmployeeId] ?? '';
      }
      headerRows.add(
        pw.TableRow(
          children: [
            _tableCell('${i + 1}'),
            _tableCell(log != null ? dateFmt.format(log.createdAt) : ''),
            _tableCell(name),
            _tableCell(position),
            _tableCell(col5(log)),
            _tableCell(col6(log)),
            _tableCell(col7(log)),
            _tableCell(creatorFull),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(border: tableBorder, columnWidths: colWidths, children: headerRows),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            'Рекомендуемая форма гигиенического журнала',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableCell(String text) => pw.Padding(
        padding: pw.EdgeInsets.all(3),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
        ),
      );

  static pw.TableBorder get _tableBorder {
    const b = pw.BorderSide(color: PdfColors.black, width: 0.5);
    return pw.TableBorder(left: b, top: b, right: b, bottom: b, horizontalInside: b, verticalInside: b);
  }

  static pw.Widget _headerCellSmall(String text) => pw.Padding(
        padding: pw.EdgeInsets.all(2),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        ),
      );

  /// Журнал температуры в холодильном оборудовании: помещение, оборудование, дни 1–30 (образец).
  static pw.Widget _buildFridgeTemperaturePage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    const dayCount = 30;
    final byEquipment = <String, Map<int, double>>{};
    for (final log in logs) {
      if (log.equipment == null || log.equipment!.isEmpty) continue;
      final day = log.createdAt.day;
      byEquipment.putIfAbsent(log.equipment!, () => {})[day] = log.value1 ?? 0;
    }
    final equipmentList = byEquipment.keys.toList()..sort();
    if (equipmentList.isEmpty) equipmentList.add('—');

    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(1.5),
      ...List.generate(dayCount, (i) => i + 2).asMap().map((i, _) => MapEntry(i + 2, const pw.FlexColumnWidth(0.35))),
    };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _headerCellSmall('Наименование производственного помещения'),
          _headerCellSmall('Наименование холодильного оборудования'),
          ...List.generate(dayCount, (d) => _headerCellSmall('${d + 1}')),
        ],
      ),
      ...equipmentList.map((equip) {
        final dayValues = byEquipment[equip] ?? {};
        return pw.TableRow(
          children: [
            _tableCell(equipmentList.isNotEmpty && equip == equipmentList.first ? establishmentName : ''),
            _tableCell(equip),
            ...List.generate(dayCount, (d) {
              final v = dayValues[d + 1];
              return _tableCell(v != null ? v.toStringAsFixed(0) : '');
            }),
          ],
        );
      }),
    ];
    while (rows.length < 8) {
      rows.add(pw.TableRow(
        children: [
          _tableCell(''),
          _tableCell(''),
          ...List.generate(dayCount, (_) => _tableCell('')),
        ],
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Table(border: _tableBorder, columnWidths: colWidths, children: rows),
        pw.SizedBox(height: 10),
        pw.Center(child: pw.Text(_pdfFooter(HaccpLogType.fridgeTemperature), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
      ],
    );
  }

  /// Журнал температурного режима: построчно по образцу docx (Дата, Время, Помещение/камера, Показатель сухой °С, Показатель влажности %, Ответственное лицо).
  static pw.Widget _buildTemperatureRowBasedPage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
    required bool includeHumidity,
  }) {
    final headerCells = <pw.Widget>[
      _headerCellSmall('№ п/п'),
      _headerCellSmall('Дата'),
      _headerCellSmall('Время'),
      _headerCellSmall('Помещение/камера'),
      _headerCellSmall('Показатель сухой, °С'),
    ];
    if (includeHumidity) {
      headerCells.add(_headerCellSmall('Показатель влажности, %'));
    }
    headerCells.add(_headerCellSmall('Ответственное лицо'));
    headerCells.add(_headerCellSmall('Подпись'));

    final colCount = headerCells.length;
    final colWidths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < colCount; i++) i: const pw.FlexColumnWidth(1.2),
    };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: headerCells,
      ),
    ];
    final dateFmt = DateFormat('dd.MM.yyyy');
    final timeFmt = DateFormat('HH:mm');
    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      final cells = <pw.Widget>[
        _tableCell('${i + 1}'),
        _tableCell(dateFmt.format(log.createdAt)),
        _tableCell(timeFmt.format(log.createdAt)),
        _tableCell(log.equipment ?? establishmentName),
        _tableCell(log.value1 != null ? log.value1!.toStringAsFixed(1) : ''),
      ];
      if (includeHumidity) {
        cells.add(_tableCell(log.value2 != null ? log.value2!.toStringAsFixed(0) : ''));
      }
      cells.add(_tableCell(employeeIdToName[log.createdByEmployeeId] ?? ''));
      cells.add(_tableCell(''));
      rows.add(pw.TableRow(children: cells));
    }
    const emptyRows = 15;
    for (var i = logs.length; i < emptyRows; i++) {
      rows.add(pw.TableRow(
        children: List.generate(colCount, (j) => _tableCell(j == 0 ? '${i + 1}' : '')),
      ));
    }

    return pw.Table(border: _tableBorder, columnWidths: colWidths, children: rows);
  }

  /// Приложение № 3: 5 обязательных колонок. Группировка по наименованию помещения. Шрифт Roboto — кириллица.
  static pw.Widget _buildWarehouseTempHumidityPage({
    required String establishmentName,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateFmt,
  }) {
    const colWidths = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(0.4),
      1: pw.FlexColumnWidth(1.2),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(0.9),
      4: pw.FlexColumnWidth(1.2),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall('№ п/п'),
        _headerCellSmall('Дата'),
        _headerCellSmall('Температура, °C'),
        _headerCellSmall('Относительная влажность, %'),
        _headerCellSmall('Подпись ответственного лица'),
      ],
    );

    final premisesList = logs
        .map((e) => e.equipment)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList();
    premisesList.sort();
    if (premisesList.isEmpty) premisesList.add('—');

    final children = <pw.Widget>[];
    for (final premises in premisesList) {
      final premLogs = premises == '—'
          ? logs.where((l) => l.equipment == null || l.equipment!.trim().isEmpty).toList()
          : logs.where((l) => l.equipment == premises).toList();
      premLogs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final rows = <pw.TableRow>[headerRow];
      for (var i = 0; i < premLogs.length; i++) {
        final log = premLogs[i];
        final sign = employeeIdToName[log.createdByEmployeeId] ?? '';
        rows.add(
          pw.TableRow(
            children: [
              _tableCell('${i + 1}'),
              _tableCell(dateFmt.format(log.createdAt)),
              _tableCell(log.value1 != null ? log.value1!.toStringAsFixed(0) : ''),
              _tableCell(log.value2 != null ? '${log.value2!.toStringAsFixed(0)}%' : ''),
              _tableCell(sign),
            ],
          ),
        );
      }
      children.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                'Наименование складского помещения: $premises',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Table(border: _tableBorder, columnWidths: colWidths, children: rows),
            pw.SizedBox(height: 16),
          ],
        ),
      );
    }
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: children);
  }

  /// Приложение 4: Журнал бракеража готовой пищевой продукции — макет как в образце.
  static pw.Widget _buildBrakerageFinishedProductPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(0.7),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(0.9),
      5: const pw.FlexColumnWidth(0.9),
      6: const pw.FlexColumnWidth(0.9),
      7: const pw.FlexColumnWidth(0.8),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall('Дата и час изготовления блюда'),
        _headerCellSmall('Время снятия бракеража'),
        _headerCellSmall('Наименование готового блюда'),
        _headerCellSmall('Результаты органолептической оценки'),
        _headerCellSmall('Разрешение к реализации'),
        _headerCellSmall('Подписи членов бракеражной комиссии'),
        _headerCellSmall('Результаты взвешивания порционных блюд'),
        _headerCellSmall('Примечание'),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 20 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateTimeFmt.format(log.createdAt) : ''),
            _tableCell(log?.timeBrakerage ?? ''),
            _tableCell(log?.productName ?? ''),
            _tableCell(log?.result ?? ''),
            _tableCell(log?.approvalToSell ?? ''),
            _tableCell(log?.commissionSignatures ?? ''),
            _tableCell(log?.weighingResult ?? ''),
            _tableCell(log?.note ?? ''),
          ],
        ),
      );
    }
    return pw.Table(border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Приложение 5: Журнал бракеража скоропортящейся пищевой продукции — макет как в образце.
  static pw.Widget _buildBrakerageIncomingRawPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(0.6),
      3: const pw.FlexColumnWidth(1),
      4: const pw.FlexColumnWidth(0.5),
      5: const pw.FlexColumnWidth(0.8),
      6: const pw.FlexColumnWidth(1),
      7: const pw.FlexColumnWidth(0.8),
      8: const pw.FlexColumnWidth(0.8),
      9: const pw.FlexColumnWidth(0.6),
      10: const pw.FlexColumnWidth(0.6),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall('Дата и час поступления'),
        _headerCellSmall('Наименование'),
        _headerCellSmall('Фасовка'),
        _headerCellSmall('Изготовитель/поставщик'),
        _headerCellSmall('Кол-во'),
        _headerCellSmall('№ документа'),
        _headerCellSmall('Органолептическая оценка'),
        _headerCellSmall('Условия хранения, срок реализации'),
        _headerCellSmall('Дата реализации'),
        _headerCellSmall('Подпись'),
        _headerCellSmall('Прим.'),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 20 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final dateSoldStr = log?.dateSold != null ? dateFmt.format(log!.dateSold!) : '';
      final empName = log != null ? (employeeIdToName[log.createdByEmployeeId] ?? '') : '';
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateTimeFmt.format(log.createdAt) : ''),
            _tableCell(log?.productName ?? ''),
            _tableCell(log?.packaging ?? ''),
            _tableCell(log?.manufacturerSupplier ?? ''),
            _tableCell(log?.quantityKg != null ? log!.quantityKg!.toStringAsFixed(2) : ''),
            _tableCell(log?.documentNumber ?? ''),
            _tableCell(log?.result ?? ''),
            _tableCell(log?.storageConditions ?? ''),
            _tableCell(dateSoldStr),
            _tableCell(empName),
            _tableCell(log?.note ?? ''),
          ],
        ),
      );
    }
    return pw.Table(border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Приложение 8: Журнал учета использования фритюрных жиров — макет как в образце.
  static pw.Widget _buildFryingOilPage({
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateFormat dateTimeFmt,
  }) {
    final dateFmt = DateFormat('dd.MM.yyyy');
    final timeFmt = DateFormat('HH:mm');
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(0.7),
      1: const pw.FlexColumnWidth(0.5),
      2: const pw.FlexColumnWidth(0.8),
      3: const pw.FlexColumnWidth(0.9),
      4: const pw.FlexColumnWidth(0.9),
      5: const pw.FlexColumnWidth(0.8),
      6: const pw.FlexColumnWidth(0.6),
      7: const pw.FlexColumnWidth(0.9),
      8: const pw.FlexColumnWidth(0.5),
      9: const pw.FlexColumnWidth(0.5),
      10: const pw.FlexColumnWidth(0.8),
    };
    final headerRow = pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: [
        _headerCellSmall('Дата'),
        _headerCellSmall('Время начала использования жира'),
        _headerCellSmall('Вид фритюрного жира'),
        _headerCellSmall('Органолептическая оценка на начало жарки'),
        _headerCellSmall('Тип жарочного оборудования'),
        _headerCellSmall('Вид продукции'),
        _headerCellSmall('Время окончания жарки'),
        _headerCellSmall('Органолептическая оценка по окончании жарки'),
        _headerCellSmall('Переходящий остаток, кг'),
        _headerCellSmall('Утилизированный жир, кг'),
        _headerCellSmall('Должность, Ф.И.О. контролера'),
      ],
    );
    final dataRows = <pw.TableRow>[headerRow];
    final rowCount = logs.isEmpty ? 15 : logs.length;
    for (var i = 0; i < rowCount; i++) {
      final log = i < logs.length ? logs[i] : null;
      final empName = log != null ? (log.commissionSignatures ?? employeeIdToName[log.createdByEmployeeId] ?? '') : '';
      dataRows.add(
        pw.TableRow(
          children: [
            _tableCell(log != null ? dateFmt.format(log.createdAt) : ''),
            _tableCell(log != null ? timeFmt.format(log.createdAt) : ''),
            _tableCell(log?.oilName ?? ''),
            _tableCell(log?.organolepticStart ?? ''),
            _tableCell(log?.fryingEquipmentType ?? ''),
            _tableCell(log?.fryingProductType ?? ''),
            _tableCell(log?.fryingEndTime ?? ''),
            _tableCell(log?.organolepticEnd ?? ''),
            _tableCell(log?.carryOverKg != null ? log!.carryOverKg!.toStringAsFixed(2) : ''),
            _tableCell(log?.utilizedKg != null ? log!.utilizedKg!.toStringAsFixed(2) : ''),
            _tableCell(empName),
          ],
        ),
      );
    }
    return pw.Table(border: _tableBorder, columnWidths: colWidths, children: dataRows);
  }

  /// Параметры экспорта.
  static Future<Uint8List> buildJournalPdf({
    required String establishmentName,
    required String journalTitle,
    required String sanpinRef,
    required HaccpLogType logType,
    required List<HaccpLog> logs,
    required Map<String, String> employeeIdToName,
    required DateTime dateFrom,
    required DateTime dateTo,
    bool includeCover = true,
    bool includeStitchingSheet = true,
  }) async {
    final theme = await _getTheme();
    final dateFmt = DateFormat('dd.MM.yyyy');
    final dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm');
    final isHealthHygiene = logType == HaccpLogType.healthHygiene;
    final sanpin = isHealthHygiene ? _sanpinHealthHygiene : sanpinRef;
    final title = _pdfTitle(logType);

    final doc = pw.Document(
      theme: theme,
      title: title,
      subject: 'Журнал учёта. Документ для просмотра и печати. Редактирование не допускается.',
      producer: 'Restodocks (СанПиН 2.3/2.4.3590-20)',
    );

    if (includeCover) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpin, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 32),
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text('Наименование организации', style: pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 4),
                    pw.Text(establishmentName, style: pw.TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.Text(
                  'Период: ${dateFmt.format(dateFrom)} — ${dateFmt.format(dateTo)}',
                  style: pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isHealthHygiene) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(24, 40, 24, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(sanpin, style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемый образец', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildHealthHygienePage(
                establishmentName: establishmentName,
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.fridgeTemperature) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(20, 40, 20, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемый образец', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildFridgeTemperaturePage(
                establishmentName: establishmentName,
                logs: logs,
                dateFrom: dateFrom,
                dateTo: dateTo,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.warehouseTempHumidity) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(20, 40, 20, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемый образец', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildWarehouseTempHumidityPage(
                establishmentName: establishmentName,
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateFmt: dateFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.finishedProductBrakerage) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемый образец', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildBrakerageFinishedProductPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.incomingRawBrakerage) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемый образец', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildBrakerageIncomingRawPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else if (logType == HaccpLogType.fryingOil) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          margin: pw.EdgeInsets.fromLTRB(16, 40, 16, 50),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text('Рекомендуемая форма контроля замены фритюрных жиров', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 8),
              _buildFryingOilPage(
                logs: logs,
                employeeIdToName: employeeIdToName,
                dateTimeFmt: dateTimeFmt,
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text(_pdfFooter(logType), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
            ],
          ),
        ),
      );
    } else {
      final colKeys = logs.isNotEmpty
          ? _collectColumnKeys(logs)
          : _defaultColumnKeysForType(logType);

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.fromLTRB(24, 50, 24, 40),
          header: (ctx) => pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(establishmentName, style: pw.TextStyle(fontSize: 9)),
              ),
            ],
          ),
          footer: (ctx) => pw.Center(
            child: pw.Text(
              _pdfFooter(logType),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
          build: (ctx) {
            final rows = <pw.TableRow>[
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('№', bold: true),
                  _cell('Дата и время', bold: true),
                  ...colKeys.map((k) => _cell(_humanKey(k), bold: true)),
                  _cell('ФИО, должность', bold: true),
                ],
              ),
            ];
            const blankRowCount = 25;
            final rowCount = logs.isEmpty ? blankRowCount : logs.length;
            for (var i = 0; i < rowCount; i++) {
              final cells = <pw.Widget>[
                _cell('${i + 1}'),
                _cell(logs.length > i ? dateTimeFmt.format(logs[i].createdAt) : ''),
                ...colKeys.map((k) => _cell(
                    logs.length > i ? (logs[i].toPdfRow()[k] ?? '') : '')),
                _cell(logs.length > i
                    ? (employeeIdToName[logs[i].createdByEmployeeId] ?? logs[i].createdByEmployeeId)
                    : ''),
              ];
              rows.add(pw.TableRow(children: cells));
            }
            return [
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black),
                columnWidths: {
                  0: const pw.FlexColumnWidth(0.5),
                  1: const pw.FlexColumnWidth(1.5),
                  ...Map.fromIterables(
                    List.generate(colKeys.length, (i) => 2 + i),
                    colKeys.map((_) => const pw.FlexColumnWidth(1.5)),
                  ),
                  colKeys.length + 2: const pw.FlexColumnWidth(2),
                },
                children: rows,
              ),
            ];
          },
        ),
      );
    }

    if (includeStitchingSheet) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(40),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Divider(),
              pw.SizedBox(height: 16),
              pw.Text(
                'В настоящем журнале пронумеровано и прошнуровано _____ листов.',
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text('М.П. _______________________ / [Подпись руководителя]', style: pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return doc.save();
  }

  static List<String> _collectColumnKeys(List<HaccpLog> logs) {
    final set = <String>{};
    for (final log in logs) {
      for (final k in log.toPdfRow().keys) {
        if (k.isNotEmpty) set.add(k);
      }
    }
    return set.toList()..sort();
  }

  /// Колонки для пустого бланка по типу журнала.
  static List<String> _defaultColumnKeysForType(HaccpLogType logType) {
    switch (logType.targetTable) {
      case HaccpLogTable.numeric:
        return switch (logType) {
          HaccpLogType.uvLamps => ['value1', 'note'],
          HaccpLogType.fridgeTemperature => ['value1', 'equipment', 'note'],
          HaccpLogType.warehouseTempHumidity => ['value1', 'value2', 'note'],
          HaccpLogType.disinfectantConcentration => ['value1', 'note'],
          _ => ['value1', 'value2', 'equipment', 'note'],
        };
      case HaccpLogTable.status:
        return switch (logType) {
          HaccpLogType.healthHygiene || HaccpLogType.pediculosis => ['status', 'note'],
          HaccpLogType.dishwasherControl => ['status', 'status2', 'note'],
          HaccpLogType.glassCeramicsBreakage => ['description', 'location'],
          HaccpLogType.emergencyIncidents => ['description', 'note'],
          _ => ['status', 'status2', 'description', 'location', 'note'],
        };
      case HaccpLogTable.quality:
        return switch (logType) {
          HaccpLogType.finishedProductBrakerage ||
          HaccpLogType.incomingRawBrakerage => ['product', 'result', 'note'],
          HaccpLogType.fryingOil => ['action', 'oil_name', 'note'],
          HaccpLogType.foodWaste => ['weight', 'reason', 'note'],
          HaccpLogType.disinsectionDeratization => ['agent', 'note'],
          _ => ['product', 'result', 'weight', 'reason', 'action', 'agent', 'concentration', 'note'],
        };
    }
  }

  static String _humanKey(String key) {
    const m = {
      'value1': 'Температура °C',
      'value2': 'Влажность %',
      'equipment': 'Наименование холодильного оборудования',
      'status': 'Результат осмотра (допущен/отстранен)',
      'status2': 'Органолептическая оценка',
      'description': 'Описание',
      'location': 'Место (цех)',
      'product': 'Наименование готового блюда / Наименование',
      'result': 'Результаты органолептической оценки / Результат бракеража',
      'weight': 'Вес, кг',
      'reason': 'Причина списания',
      'action': 'Действие (замена/долив)',
      'oil_name': 'Вид фритюрного жира (марка масла)',
      'agent': 'Средство',
      'concentration': 'Концентрация',
      'note': 'Примечание',
    };
    return m[key] ?? key;
  }
}
