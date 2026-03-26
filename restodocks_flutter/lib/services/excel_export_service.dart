import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/models.dart';
import 'excel_file_saver_stub.dart'
    if (dart.library.html) 'excel_file_saver_web.dart' as file_saver;
import 'inventory_download.dart';

enum TechCardExportFormat { pdf, xlsx }
enum TechCardExportKind { withPrice, withoutPrice, actDevelopment }

class TechCardExportOptions {
  const TechCardExportOptions({
    required this.format,
    required this.kind,
    required this.languageCode,
    required this.establishmentName,
    required this.chefName,
    required this.chefPosition,
    required this.documentDate,
  });

  final TechCardExportFormat format;
  final TechCardExportKind kind;
  final String languageCode;
  final String establishmentName;
  final String chefName;
  final String chefPosition;
  final DateTime documentDate;

  bool get includePrice => kind == TechCardExportKind.withPrice;
  bool get isAct => kind == TechCardExportKind.actDevelopment;
}

/// Сервис для экспорта технологических карт в Excel файлы
class ExcelExportService {
  static final ExcelExportService _instance = ExcelExportService._internal();
  factory ExcelExportService() => _instance;
  ExcelExportService._internal();
  static pw.ThemeData? _pdfTheme;

  static Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfTheme != null) return _pdfTheme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final base = pw.Font.ttf(baseData);
    final bold = pw.Font.ttf(boldData);
    _pdfTheme = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: base,
      boldItalic: bold,
    );
    return _pdfTheme!;
  }

  // Удаляем "битые" управляющие символы, которые в PDF дают квадраты/иероглифы.
  String _pdfSafe(String input) {
    return input
        .replaceAll('\uFFFD', ' ')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
  }

  String _tr(String key, String lang) {
    final ru = lang == 'ru';
    const ruMap = {
      'title_ttk': 'Технологическая карта',
      'title_act': 'Акт проработки',
      'name': 'Название',
      'type': 'Тип',
      'category': 'Категория',
      'establishment': 'Заведение',
      'chef': 'Шеф-повар',
      'date': 'Дата',
      'technology': 'Технология приготовления',
      'product': 'Продукт',
      'gross': 'Брутто (г)',
      'waste': 'Отход (%)',
      'net': 'Нетто (г)',
      'method': 'Способ приготовления',
      'shrink': 'Ужарка (%)',
      'output': 'Выход (г)',
      'cost': 'Стоимость',
      'priceKg': 'Цена за кг',
      'total': 'Итого',
      'semi': 'Полуфабрикат',
      'dish': 'Блюдо',
    };
    const enMap = {
      'title_ttk': 'Technical Card',
      'title_act': 'Development Report',
      'name': 'Name',
      'type': 'Type',
      'category': 'Category',
      'establishment': 'Establishment',
      'chef': 'Chef',
      'date': 'Date',
      'technology': 'Cooking Technology',
      'product': 'Product',
      'gross': 'Gross (g)',
      'waste': 'Waste (%)',
      'net': 'Net (g)',
      'method': 'Cooking Method',
      'shrink': 'Shrink (%)',
      'output': 'Output (g)',
      'cost': 'Cost',
      'priceKg': 'Price per kg',
      'total': 'Total',
      'semi': 'Semi-finished',
      'dish': 'Dish',
    };
    return (ru ? ruMap : enMap)[key] ?? key;
  }

  Future<void> exportSingleTechCardAdvanced(
    TechCard techCard,
    TechCardExportOptions options,
  ) async {
    if (options.format == TechCardExportFormat.xlsx) {
      await _exportSingleTechCardXlsx(techCard, options);
      return;
    }
    await _exportSingleTechCardPdf(techCard, options);
  }

  /// Экспорт одной технологической карты
  Future<void> exportSingleTechCard(TechCard techCard) async {
    await exportSingleTechCardAdvanced(
      techCard,
      TechCardExportOptions(
        format: TechCardExportFormat.xlsx,
        kind: TechCardExportKind.withPrice,
        languageCode: 'ru',
        establishmentName: '',
        chefName: '',
        chefPosition: '',
        documentDate: techCard.createdAt,
      ),
    );
  }

  Future<void> _exportSingleTechCardXlsx(
    TechCard techCard,
    TechCardExportOptions options,
  ) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];
    final lang = options.languageCode;
    final title = options.isAct ? _tr('title_act', lang) : _tr('title_ttk', lang);

    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(title);
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('${_tr('name', lang)}:');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('${_tr('type', lang)}:');
    sheet.cell(CellIndex.indexByString('B3')).value =
        TextCellValue(techCard.isSemiFinished ? _tr('semi', lang) : _tr('dish', lang));
    sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('${_tr('category', lang)}:');
    sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));
    sheet.cell(CellIndex.indexByString('A5')).value = TextCellValue('${_tr('establishment', lang)}:');
    sheet.cell(CellIndex.indexByString('B5')).value = TextCellValue(options.establishmentName);
    sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('${_tr('chef', lang)}:');
    sheet.cell(CellIndex.indexByString('B6')).value =
        TextCellValue('${options.chefName} ${options.chefPosition}'.trim());
    sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue('${_tr('date', lang)}:');
    sheet.cell(CellIndex.indexByString('B7')).value =
        TextCellValue(DateFormat('dd.MM.yyyy').format(options.documentDate));

    final technology = techCard.getLocalizedTechnology(lang);
    if (technology.isNotEmpty) {
      sheet.cell(CellIndex.indexByString('A9')).value =
          TextCellValue('${_tr('technology', lang)}:');
      sheet.cell(CellIndex.indexByString('A10')).value = TextCellValue(technology);
    }

    int rowIndex = technology.isNotEmpty ? 12 : 9;
    sheet.cell(CellIndex.indexByString('A$rowIndex')).value = TextCellValue(_tr('product', lang));
    sheet.cell(CellIndex.indexByString('B$rowIndex')).value = TextCellValue(_tr('gross', lang));
    sheet.cell(CellIndex.indexByString('C$rowIndex')).value = TextCellValue(_tr('waste', lang));
    sheet.cell(CellIndex.indexByString('D$rowIndex')).value = TextCellValue(_tr('net', lang));
    sheet.cell(CellIndex.indexByString('E$rowIndex')).value = TextCellValue(_tr('method', lang));
    sheet.cell(CellIndex.indexByString('F$rowIndex')).value = TextCellValue(_tr('shrink', lang));
    sheet.cell(CellIndex.indexByString('G$rowIndex')).value = TextCellValue(_tr('output', lang));
    if (options.includePrice) {
      sheet.cell(CellIndex.indexByString('H$rowIndex')).value = TextCellValue(_tr('cost', lang));
      sheet.cell(CellIndex.indexByString('I$rowIndex')).value = TextCellValue(_tr('priceKg', lang));
    }

    for (int i = 0; i < techCard.ingredients.length; i++) {
      final ingredient = techCard.ingredients[i];
      final currentRow = rowIndex + i + 1;
      sheet.cell(CellIndex.indexByString('A$currentRow')).value =
          TextCellValue(_pdfSafe(ingredient.productName));
      sheet.cell(CellIndex.indexByString('B$currentRow')).value =
          DoubleCellValue(ingredient.grossWeight);
      sheet.cell(CellIndex.indexByString('C$currentRow')).value =
          DoubleCellValue(ingredient.primaryWastePct);
      sheet.cell(CellIndex.indexByString('D$currentRow')).value =
          DoubleCellValue(ingredient.effectiveGrossWeight);
      sheet.cell(CellIndex.indexByString('E$currentRow')).value =
          TextCellValue(_pdfSafe(ingredient.cookingProcessName ?? ''));
      sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(
          ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
      sheet.cell(CellIndex.indexByString('G$currentRow')).value =
          DoubleCellValue(ingredient.netWeight);
      if (options.includePrice) {
        sheet.cell(CellIndex.indexByString('H$currentRow')).value =
            DoubleCellValue(ingredient.cost);
        sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(
            ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
      }
    }

    final totalRow = rowIndex + techCard.ingredients.length + 1;
    final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
    final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

    sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('${_tr('total', lang)}:');
    sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
    if (options.includePrice) {
      sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
      sheet.cell(CellIndex.indexByString('I$totalRow')).value =
          DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);
    }

    final safeName = techCard.dishName.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final prefix = options.isAct ? 'Act' : 'TTK';
    final fileName = '${prefix}_$safeName.xlsx';
    _saveExcelFile(excel, fileName);
  }

  Future<void> _exportSingleTechCardPdf(
    TechCard techCard,
    TechCardExportOptions options,
  ) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(theme: theme);
    final lang = options.languageCode;
    final title = options.isAct ? _tr('title_act', lang) : _tr('title_ttk', lang);
    final technology = _pdfSafe(techCard.getLocalizedTechnology(lang));
    final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
    final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

    pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
      final safeText = _pdfSafe(text);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          safeText,
          textAlign: align,
          style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => [
          pw.Center(
            child: pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 10),
          pw.Text('${_tr('establishment', lang)}: ${options.establishmentName}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            '${_tr('chef', lang)}: ${options.chefName} ${options.chefPosition}'.trim(),
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text('${_tr('date', lang)}: ${DateFormat('dd.MM.yyyy').format(options.documentDate)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
          pw.Text('${_tr('name', lang)}: ${_pdfSafe(techCard.dishName)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            '${_tr('type', lang)}: ${techCard.isSemiFinished ? _tr('semi', lang) : _tr('dish', lang)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text('${_tr('category', lang)}: ${_getCategoryName(techCard.category)}', style: const pw.TextStyle(fontSize: 10)),
          if (technology.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('${_tr('technology', lang)}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(_pdfSafe(technology), style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.6),
              1: const pw.FlexColumnWidth(1.0),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.4),
              5: const pw.FlexColumnWidth(0.9),
              6: const pw.FlexColumnWidth(1.0),
              if (options.includePrice) 7: const pw.FlexColumnWidth(1.0),
              if (options.includePrice) 8: const pw.FlexColumnWidth(1.0),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell(_tr('product', lang), bold: true),
                  cell(_tr('gross', lang), bold: true, align: pw.TextAlign.center),
                  cell(_tr('waste', lang), bold: true, align: pw.TextAlign.center),
                  cell(_tr('net', lang), bold: true, align: pw.TextAlign.center),
                  cell(_tr('method', lang), bold: true),
                  cell(_tr('shrink', lang), bold: true, align: pw.TextAlign.center),
                  cell(_tr('output', lang), bold: true, align: pw.TextAlign.center),
                  if (options.includePrice) cell(_tr('cost', lang), bold: true, align: pw.TextAlign.center),
                  if (options.includePrice) cell(_tr('priceKg', lang), bold: true, align: pw.TextAlign.center),
                ],
              ),
              ...techCard.ingredients.map((ing) => pw.TableRow(children: [
                    cell(ing.productName),
                    cell(ing.grossWeight.toStringAsFixed(0), align: pw.TextAlign.center),
                    cell(ing.primaryWastePct.toStringAsFixed(1), align: pw.TextAlign.center),
                    cell(ing.effectiveGrossWeight.toStringAsFixed(0), align: pw.TextAlign.center),
                    cell(ing.cookingProcessName ?? ''),
                    cell(
                      (ing.cookingLossPctOverride ?? ing.weightLossPercentage).toStringAsFixed(1),
                      align: pw.TextAlign.center,
                    ),
                    cell(ing.netWeight.toStringAsFixed(0), align: pw.TextAlign.center),
                    if (options.includePrice) cell(ing.cost.toStringAsFixed(2), align: pw.TextAlign.center),
                    if (options.includePrice)
                      cell(
                        (ing.netWeight > 0 ? ing.cost * 1000 / ing.netWeight : 0).toStringAsFixed(2),
                        align: pw.TextAlign.center,
                      ),
                  ])),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  cell(_tr('total', lang), bold: true),
                  cell(''),
                  cell(''),
                  cell(''),
                  cell(''),
                  cell(''),
                  cell(totalNet.toStringAsFixed(0), bold: true, align: pw.TextAlign.center),
                  if (options.includePrice) cell(totalCost.toStringAsFixed(2), bold: true, align: pw.TextAlign.center),
                  if (options.includePrice)
                    cell(
                      (totalNet > 0 ? totalCost * 1000 / totalNet : 0).toStringAsFixed(2),
                      bold: true,
                      align: pw.TextAlign.center,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final safeName = techCard.dishName.replaceAll(RegExp(r'[^\w\s-]'), '_');
    final prefix = options.isAct ? 'Act' : 'TTK';
    await saveFileBytes('${prefix}_$safeName.pdf', await doc.save());
  }

  /// Экспорт выбранных технологических карт
  Future<void> exportSelectedTechCards(List<TechCard> techCards) async {
    final excel = Excel.createExcel();

    for (int cardIndex = 0; cardIndex < techCards.length; cardIndex++) {
      final techCard = techCards[cardIndex];
      final sheetName = techCard.dishName.length > 30
          ? techCard.dishName.substring(0, 27) + '...'
          : techCard.dishName;
      final sheet = excel[sheetName];

      // Заголовок
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Технологическая карта');
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Название:');
      sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
      sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Тип:');
      sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Категория:');
      sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));

      // Технология приготовления
      final technology = techCard.technologyLocalized?['ru'] ?? '';
      if (technology.isNotEmpty) {
        sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Технология приготовления:');
        sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
      }

      // Заголовки таблицы ингредиентов
      int rowIndex = technology.isNotEmpty ? 9 : 6;
      sheet.cell(CellIndex.indexByString('A${rowIndex}')).value = TextCellValue('Продукт');
      sheet.cell(CellIndex.indexByString('B${rowIndex}')).value = TextCellValue('Брутто (г)');
      sheet.cell(CellIndex.indexByString('C${rowIndex}')).value = TextCellValue('Отход (%)');
      sheet.cell(CellIndex.indexByString('D${rowIndex}')).value = TextCellValue('Нетто (г)');
      sheet.cell(CellIndex.indexByString('E${rowIndex}')).value = TextCellValue('Способ приготовления');
      sheet.cell(CellIndex.indexByString('F${rowIndex}')).value = TextCellValue('Ужарка (%)');
      sheet.cell(CellIndex.indexByString('G${rowIndex}')).value = TextCellValue('Выход (г)');
      sheet.cell(CellIndex.indexByString('H${rowIndex}')).value = TextCellValue('Стоимость');
      sheet.cell(CellIndex.indexByString('I${rowIndex}')).value = TextCellValue('Цена за кг');

      // Данные ингредиентов
      for (int i = 0; i < techCard.ingredients.length; i++) {
        final ingredient = techCard.ingredients[i];
        final currentRow = rowIndex + i + 1;

        sheet.cell(CellIndex.indexByString('A$currentRow')).value = TextCellValue(ingredient.productName);
        sheet.cell(CellIndex.indexByString('B$currentRow')).value = DoubleCellValue(ingredient.grossWeight);
        sheet.cell(CellIndex.indexByString('C$currentRow')).value = DoubleCellValue(ingredient.primaryWastePct);
        sheet.cell(CellIndex.indexByString('D$currentRow')).value = DoubleCellValue(ingredient.effectiveGrossWeight);
        sheet.cell(CellIndex.indexByString('E$currentRow')).value = TextCellValue(ingredient.cookingProcessName ?? '');
        sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
        sheet.cell(CellIndex.indexByString('G$currentRow')).value = DoubleCellValue(ingredient.netWeight);
        sheet.cell(CellIndex.indexByString('H$currentRow')).value = DoubleCellValue(ingredient.cost);
        sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
      }

      // Итого
      final totalRow = rowIndex + techCard.ingredients.length + 1;
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('Итого:');
      sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
      sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
      sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);
    }

    // Сохранение файла
    final fileName = 'ТТК_выбранные_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Экспорт всех технологических карт
  Future<void> exportAllTechCards(List<TechCard> techCards) async {
    final excel = Excel.createExcel();

    // Создаем лист со списком всех ТТК
    final indexSheet = excel['Список ТТК'];

    // Заголовки
    indexSheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Название');
    indexSheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Тип');
    indexSheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Категория');
    indexSheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Количество ингредиентов');
    indexSheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Общий выход (г)');
    indexSheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Общая стоимость');

    // Список ТТК
    for (int i = 0; i < techCards.length; i++) {
      final techCard = techCards[i];
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      indexSheet.cell(CellIndex.indexByString('A${i + 2}')).value = TextCellValue(techCard.dishName);
      indexSheet.cell(CellIndex.indexByString('B${i + 2}')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      indexSheet.cell(CellIndex.indexByString('C${i + 2}')).value = TextCellValue(_getCategoryName(techCard.category));
      indexSheet.cell(CellIndex.indexByString('D${i + 2}')).value = IntCellValue(techCard.ingredients.length);
      indexSheet.cell(CellIndex.indexByString('E${i + 2}')).value = DoubleCellValue(totalNet);
      indexSheet.cell(CellIndex.indexByString('F${i + 2}')).value = DoubleCellValue(totalCost);
    }

    // Создаем отдельные листы для каждой ТТК
    for (int cardIndex = 0; cardIndex < techCards.length; cardIndex++) {
      final techCard = techCards[cardIndex];
      final sheetName = techCard.dishName.length > 30
          ? techCard.dishName.substring(0, 27) + '...'
          : techCard.dishName;
      final sheet = excel[sheetName];

      // Заголовок
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Технологическая карта');
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Название:');
      sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
      sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Тип:');
      sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Категория:');
      sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));

      // Технология приготовления
      final technology = techCard.technologyLocalized?['ru'] ?? '';
      if (technology.isNotEmpty) {
        sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Технология приготовления:');
        sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
      }

      // Заголовки таблицы ингредиентов
      int rowIndex = technology.isNotEmpty ? 9 : 6;
      sheet.cell(CellIndex.indexByString('A${rowIndex}')).value = TextCellValue('Продукт');
      sheet.cell(CellIndex.indexByString('B${rowIndex}')).value = TextCellValue('Брутто (г)');
      sheet.cell(CellIndex.indexByString('C${rowIndex}')).value = TextCellValue('Отход (%)');
      sheet.cell(CellIndex.indexByString('D${rowIndex}')).value = TextCellValue('Нетто (г)');
      sheet.cell(CellIndex.indexByString('E${rowIndex}')).value = TextCellValue('Способ приготовления');
      sheet.cell(CellIndex.indexByString('F${rowIndex}')).value = TextCellValue('Ужарка (%)');
      sheet.cell(CellIndex.indexByString('G${rowIndex}')).value = TextCellValue('Выход (г)');
      sheet.cell(CellIndex.indexByString('H${rowIndex}')).value = TextCellValue('Стоимость');
      sheet.cell(CellIndex.indexByString('I${rowIndex}')).value = TextCellValue('Цена за кг');

      // Данные ингредиентов
      for (int i = 0; i < techCard.ingredients.length; i++) {
        final ingredient = techCard.ingredients[i];
        final currentRow = rowIndex + i + 1;

        sheet.cell(CellIndex.indexByString('A$currentRow')).value = TextCellValue(ingredient.productName);
        sheet.cell(CellIndex.indexByString('B$currentRow')).value = DoubleCellValue(ingredient.grossWeight);
        sheet.cell(CellIndex.indexByString('C$currentRow')).value = DoubleCellValue(ingredient.primaryWastePct);
        sheet.cell(CellIndex.indexByString('D$currentRow')).value = DoubleCellValue(ingredient.effectiveGrossWeight);
        sheet.cell(CellIndex.indexByString('E$currentRow')).value = TextCellValue(ingredient.cookingProcessName ?? '');
        sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
        sheet.cell(CellIndex.indexByString('G$currentRow')).value = DoubleCellValue(ingredient.netWeight);
        sheet.cell(CellIndex.indexByString('H$currentRow')).value = DoubleCellValue(ingredient.cost);
        sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
      }

      // Итого
      final totalRow = rowIndex + techCard.ingredients.length + 1;
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('Итого:');
      sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
      sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
      sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);
    }

    // Сохранение файла
    final fileName = 'Все_ТТК_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Сохранение Excel файла в браузере
  void _saveExcelFile(Excel excel, String fileName) {
    final bytes = excel.encode();
    if (bytes == null) return;
    file_saver.saveExcelBytes(Uint8List.fromList(bytes), fileName);
  }

  /// Получение названия категории на русском
  String _getCategoryName(String category) {
    const categoryNames = {
      'vegetables': 'Овощи',
      'fruits': 'Фрукты',
      'meat': 'Мясо',
      'seafood': 'Рыба',
      'dairy': 'Молочное',
      'grains': 'Крупы',
      'bakery': 'Выпечка',
      'pantry': 'Бакалея',
      'spices': 'Специи',
      'beverages': 'Напитки',
      'eggs': 'Яйца',
      'legumes': 'Бобовые',
      'nuts': 'Орехи',
      'misc': 'Разное',
    };
    return categoryNames[category] ?? category;
  }
}