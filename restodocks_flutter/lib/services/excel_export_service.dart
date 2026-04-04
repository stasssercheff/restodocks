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
enum OrganolepticMode { template, custom }

class OrganolepticProperties {
  const OrganolepticProperties({
    required this.appearance,
    required this.consistency,
    required this.color,
    required this.tasteAndSmell,
  });

  final String appearance;
  final String consistency;
  final String color;
  final String tasteAndSmell;
}

class TechCardExportOptions {
  const TechCardExportOptions({
    required this.format,
    required this.kind,
    required this.languageCode,
    required this.establishmentName,
    required this.chefName,
    required this.chefPosition,
    required this.documentDate,
    required this.organolepticMode,
    required this.organoleptic,
  });

  final TechCardExportFormat format;
  final TechCardExportKind kind;
  final String languageCode;
  final String establishmentName;
  final String chefName;
  final String chefPosition;
  final DateTime documentDate;
  final OrganolepticMode organolepticMode;
  final OrganolepticProperties organoleptic;

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

  /// Подписи в PDF/XLSX: строго по языку документа (ru / es / остальное → en).
  String _tr(String key, String lang) {
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
      'organoleptic': 'Органолептические свойства',
      'appearance': 'Внешний вид',
      'consistency': 'Консистенция',
      'color_label': 'Цвет',
      'taste_smell': 'Вкус и запах',
      'index_sheet': 'Список ТТК',
      'idx_col_name': 'Название',
      'idx_col_type': 'Тип',
      'idx_col_category': 'Категория',
      'idx_col_ing_count': 'Количество ингредиентов',
      'idx_col_total_out': 'Общий выход (г)',
      'idx_col_total_cost': 'Общая стоимость',
    };
    const enMap = {
      'title_ttk': 'Technical specification (tech card)',
      'title_act': 'Development report',
      'name': 'Name',
      'type': 'Type',
      'category': 'Category',
      'establishment': 'Establishment',
      'chef': 'Chef',
      'date': 'Date',
      'technology': 'Cooking instructions',
      'product': 'Product',
      'gross': 'Gross (g)',
      'waste': 'Waste (%)',
      'net': 'Net (g)',
      'method': 'Cooking method',
      'shrink': 'Cooking loss (%)',
      'output': 'Yield (g)',
      'cost': 'Cost',
      'priceKg': 'Price per kg',
      'total': 'Total',
      'semi': 'Semi-finished',
      'dish': 'Dish',
      'organoleptic': 'Organoleptic properties',
      'appearance': 'Appearance',
      'consistency': 'Consistency',
      'color_label': 'Color',
      'taste_smell': 'Taste and smell',
      'index_sheet': 'Tech cards list',
      'idx_col_name': 'Name',
      'idx_col_type': 'Type',
      'idx_col_category': 'Category',
      'idx_col_ing_count': 'Ingredients count',
      'idx_col_total_out': 'Total yield (g)',
      'idx_col_total_cost': 'Total cost',
    };
    const esMap = {
      'title_ttk': 'Ficha técnica',
      'title_act': 'Acta de elaboración',
      'name': 'Nombre',
      'type': 'Tipo',
      'category': 'Categoría',
      'establishment': 'Establecimiento',
      'chef': 'Chef',
      'date': 'Fecha',
      'technology': 'Tecnología de elaboración',
      'product': 'Producto',
      'gross': 'Bruto (g)',
      'waste': 'Merma (%)',
      'net': 'Neto (g)',
      'method': 'Método de cocción',
      'shrink': 'Pérdida por cocción (%)',
      'output': 'Rendimiento (g)',
      'cost': 'Coste',
      'priceKg': 'Precio por kg',
      'total': 'Total',
      'semi': 'Semielaborado',
      'dish': 'Plato',
      'organoleptic': 'Propiedades organolépticas',
      'appearance': 'Aspecto',
      'consistency': 'Consistencia',
      'color_label': 'Color',
      'taste_smell': 'Sabor y olor',
      'index_sheet': 'Lista de fichas',
      'idx_col_name': 'Nombre',
      'idx_col_type': 'Tipo',
      'idx_col_category': 'Categoría',
      'idx_col_ing_count': 'Nº de ingredientes',
      'idx_col_total_out': 'Rendimiento total (g)',
      'idx_col_total_cost': 'Coste total',
    };
    final Map<String, String> primary;
    switch (lang) {
      case 'ru':
        primary = ruMap;
        break;
      case 'es':
        primary = esMap;
        break;
      default:
        primary = enMap;
    }
    return primary[key] ?? enMap[key] ?? key;
  }

  String _formatDocumentDate(DateTime d, String lang) {
    if (lang == 'ru') return DateFormat('dd.MM.yyyy').format(d);
    return DateFormat('dd/MM/yyyy').format(d);
  }

  String _transliterateRuToLatin(String input) {
    const map = {
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'e',
      'ж': 'zh',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'х': 'h',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'sch',
      'ъ': '',
      'ы': 'y',
      'ь': '',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
    };
    final b = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final lower = ch.toLowerCase();
      final repl = map[lower];
      if (repl == null) {
        b.write(ch);
      } else if (ch == lower) {
        b.write(repl);
      } else if (repl.isNotEmpty) {
        b.write('${repl[0].toUpperCase()}${repl.substring(1)}');
      }
    }
    return b.toString();
  }

  String _safeFilePart(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildExportFileName(
    TechCard techCard,
    TechCardExportOptions options, {
    required String ext,
  }) {
    final lang = options.languageCode;
    final title = options.isAct ? _tr('title_act', lang) : _tr('title_ttk', lang);
    final raw = '$title ${techCard.dishName}'.trim();
    final safe = _safeFilePart(raw);
    if (safe.isNotEmpty) return '$safe.$ext';

    final fallbackRaw = '${_transliterateRuToLatin(title)} ${_transliterateRuToLatin(techCard.dishName)}'.trim();
    final fallbackSafe = _safeFilePart(fallbackRaw);
    if (fallbackSafe.isNotEmpty) return '$fallbackSafe.$ext';
    return '${options.isAct ? 'Act' : 'TTK'}.$ext';
  }

  OrganolepticProperties defaultOrganolepticTemplate(String lang) {
    if (lang == 'ru') {
      return const OrganolepticProperties(
        appearance:
            'Ингредиенты приготовлены и выложены согласно технологии приготовления.',
        consistency: 'Характерная для данного вида продукта',
        color:
            'Естественный, свойственный входящим в состав ингредиентам. Без признаков заветривания или порчи.',
        tasteAndSmell:
            'Чистые, без посторонних привкусов и запахов. Вкус сбалансированный.',
      );
    }
    if (lang == 'es') {
      return const OrganolepticProperties(
        appearance:
            'Los ingredientes están preparados y emplatados según la tecnología de elaboración.',
        consistency: 'Propia de este tipo de producto.',
        color:
            'Natural, acorde a los ingredientes. Sin signos de resecamiento ni deterioro.',
        tasteAndSmell:
            'Limpios, sin sabores ni olores extraños. Sabor equilibrado.',
      );
    }
    return const OrganolepticProperties(
      appearance:
          'Ingredients are prepared and plated according to the cooking instructions.',
      consistency: 'Characteristic for this type of product.',
      color:
          'Natural, typical for the ingredients used. No signs of drying or spoilage.',
      tasteAndSmell:
          'Clean, without off-flavors or off-odors. Balanced taste.',
    );
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

  /// Экспорт одной технологической карты (язык подписей и текста — [languageCode]).
  Future<void> exportSingleTechCard(
    TechCard techCard, {
    required String languageCode,
  }) async {
    final lang = languageCode;
    await exportSingleTechCardAdvanced(
      techCard,
      TechCardExportOptions(
        format: TechCardExportFormat.xlsx,
        kind: TechCardExportKind.withPrice,
        languageCode: lang,
        establishmentName: '',
        chefName: '',
        chefPosition: '',
        documentDate: techCard.createdAt,
        organolepticMode: OrganolepticMode.template,
        organoleptic: defaultOrganolepticTemplate(lang),
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
    sheet.cell(CellIndex.indexByString('B4')).value =
        TextCellValue(_getCategoryName(techCard.category, lang));
    sheet.cell(CellIndex.indexByString('A5')).value = TextCellValue('${_tr('establishment', lang)}:');
    sheet.cell(CellIndex.indexByString('B5')).value = TextCellValue(options.establishmentName);
    sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('${_tr('chef', lang)}:');
    sheet.cell(CellIndex.indexByString('B6')).value =
        TextCellValue('${options.chefName} ${options.chefPosition}'.trim());
    sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue('${_tr('date', lang)}:');
    sheet.cell(CellIndex.indexByString('B7')).value =
        TextCellValue(_formatDocumentDate(options.documentDate, lang));

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

    if (options.isAct) {
      final start = totalRow + 2;
      sheet.cell(CellIndex.indexByString('A$start')).value =
          TextCellValue(_tr('organoleptic', lang));
      sheet.cell(CellIndex.indexByString('A${start + 1}')).value =
          TextCellValue('${_tr('appearance', lang)}: ${options.organoleptic.appearance}');
      sheet.cell(CellIndex.indexByString('A${start + 2}')).value = TextCellValue(
          '${_tr('consistency', lang)}: ${options.organoleptic.consistency}');
      sheet.cell(CellIndex.indexByString('A${start + 3}')).value =
          TextCellValue('${_tr('color_label', lang)}: ${options.organoleptic.color}');
      sheet.cell(CellIndex.indexByString('A${start + 4}')).value = TextCellValue(
          '${_tr('taste_smell', lang)}: ${options.organoleptic.tasteAndSmell}');
    }

    _saveExcelFile(
      excel,
      _buildExportFileName(techCard, options, ext: 'xlsx'),
    );
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
          pw.Text('${_tr('date', lang)}: ${_formatDocumentDate(options.documentDate, lang)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
          pw.Text('${_tr('name', lang)}: ${_pdfSafe(techCard.dishName)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            '${_tr('type', lang)}: ${techCard.isSemiFinished ? _tr('semi', lang) : _tr('dish', lang)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text('${_tr('category', lang)}: ${_getCategoryName(techCard.category, lang)}', style: const pw.TextStyle(fontSize: 10)),
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
          if (options.isAct) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              _tr('organoleptic', lang),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_tr('appearance', lang)}: ${_pdfSafe(options.organoleptic.appearance)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${_tr('consistency', lang)}: ${_pdfSafe(options.organoleptic.consistency)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${_tr('color_label', lang)}: ${_pdfSafe(options.organoleptic.color)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${_tr('taste_smell', lang)}: ${_pdfSafe(options.organoleptic.tasteAndSmell)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );

    await saveFileBytes(
      _buildExportFileName(techCard, options, ext: 'pdf'),
      await doc.save(),
    );
  }

  String _safeExcelSheetName(String raw) {
    var s = raw.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    if (s.length > 31) s = '${s.substring(0, 28)}...';
    return s.isEmpty ? 'Sheet' : s;
  }

  void _writeTechCardSheetBulk(
    Sheet sheet,
    TechCard techCard,
    String lang,
  ) {
    final title = _tr('title_ttk', lang);
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue(title);
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('${_tr('name', lang)}:');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
    sheet.cell(CellIndex.indexByString('A3')).value =
        TextCellValue('${_tr('type', lang)}:');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(
        techCard.isSemiFinished ? _tr('semi', lang) : _tr('dish', lang));
    sheet.cell(CellIndex.indexByString('A4')).value =
        TextCellValue('${_tr('category', lang)}:');
    sheet.cell(CellIndex.indexByString('B4')).value =
        TextCellValue(_getCategoryName(techCard.category, lang));

    final technology = techCard.getLocalizedTechnology(lang);
    if (technology.isNotEmpty) {
      sheet.cell(CellIndex.indexByString('A6')).value =
          TextCellValue('${_tr('technology', lang)}:');
      sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
    }

    var rowIndex = technology.isNotEmpty ? 9 : 6;
    sheet.cell(CellIndex.indexByString('A$rowIndex')).value =
        TextCellValue(_tr('product', lang));
    sheet.cell(CellIndex.indexByString('B$rowIndex')).value =
        TextCellValue(_tr('gross', lang));
    sheet.cell(CellIndex.indexByString('C$rowIndex')).value =
        TextCellValue(_tr('waste', lang));
    sheet.cell(CellIndex.indexByString('D$rowIndex')).value =
        TextCellValue(_tr('net', lang));
    sheet.cell(CellIndex.indexByString('E$rowIndex')).value =
        TextCellValue(_tr('method', lang));
    sheet.cell(CellIndex.indexByString('F$rowIndex')).value =
        TextCellValue(_tr('shrink', lang));
    sheet.cell(CellIndex.indexByString('G$rowIndex')).value =
        TextCellValue(_tr('output', lang));
    sheet.cell(CellIndex.indexByString('H$rowIndex')).value =
        TextCellValue(_tr('cost', lang));
    sheet.cell(CellIndex.indexByString('I$rowIndex')).value =
        TextCellValue(_tr('priceKg', lang));

    for (var i = 0; i < techCard.ingredients.length; i++) {
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
      sheet.cell(CellIndex.indexByString('H$currentRow')).value =
          DoubleCellValue(ingredient.cost);
      sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(
          ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
    }

    final totalRow = rowIndex + techCard.ingredients.length + 1;
    final totalNet =
        techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
    final totalCost =
        techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

    sheet.cell(CellIndex.indexByString('A$totalRow')).value =
        TextCellValue('${_tr('total', lang)}:');
    sheet.cell(CellIndex.indexByString('G$totalRow')).value =
        DoubleCellValue(totalNet);
    sheet.cell(CellIndex.indexByString('H$totalRow')).value =
        DoubleCellValue(totalCost);
    sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(
        totalNet > 0 ? totalCost * 1000 / totalNet : 0);
  }

  /// Экспорт выбранных технологических карт (подписи — [languageCode]).
  Future<void> exportSelectedTechCards(
    List<TechCard> techCards, {
    required String languageCode,
  }) async {
    final lang = languageCode;
    final excel = Excel.createExcel();

    for (final techCard in techCards) {
      final rawName = techCard.dishName;
      final sheetName = _safeExcelSheetName(
          rawName.length > 30 ? '${rawName.substring(0, 27)}...' : rawName);
      final sheet = excel[sheetName];
      _writeTechCardSheetBulk(sheet, techCard, lang);
    }

    final fileName = 'TTK_selected_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Экспорт всех технологических карт (подписи — [languageCode]).
  Future<void> exportAllTechCards(
    List<TechCard> techCards, {
    required String languageCode,
  }) async {
    final lang = languageCode;
    final excel = Excel.createExcel();

    final indexSheetName = _safeExcelSheetName(_tr('index_sheet', lang));
    final indexSheet = excel[indexSheetName];

    indexSheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue(_tr('idx_col_name', lang));
    indexSheet.cell(CellIndex.indexByString('B1')).value =
        TextCellValue(_tr('idx_col_type', lang));
    indexSheet.cell(CellIndex.indexByString('C1')).value =
        TextCellValue(_tr('idx_col_category', lang));
    indexSheet.cell(CellIndex.indexByString('D1')).value =
        TextCellValue(_tr('idx_col_ing_count', lang));
    indexSheet.cell(CellIndex.indexByString('E1')).value =
        TextCellValue(_tr('idx_col_total_out', lang));
    indexSheet.cell(CellIndex.indexByString('F1')).value =
        TextCellValue(_tr('idx_col_total_cost', lang));

    for (var i = 0; i < techCards.length; i++) {
      final techCard = techCards[i];
      final totalNet = techCard.ingredients
          .fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost =
          techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      indexSheet.cell(CellIndex.indexByString('A${i + 2}')).value =
          TextCellValue(techCard.dishName);
      indexSheet.cell(CellIndex.indexByString('B${i + 2}')).value =
          TextCellValue(
              techCard.isSemiFinished ? _tr('semi', lang) : _tr('dish', lang));
      indexSheet.cell(CellIndex.indexByString('C${i + 2}')).value =
          TextCellValue(_getCategoryName(techCard.category, lang));
      indexSheet.cell(CellIndex.indexByString('D${i + 2}')).value =
          IntCellValue(techCard.ingredients.length);
      indexSheet.cell(CellIndex.indexByString('E${i + 2}')).value =
          DoubleCellValue(totalNet);
      indexSheet.cell(CellIndex.indexByString('F${i + 2}')).value =
          DoubleCellValue(totalCost);
    }

    for (final techCard in techCards) {
      final rawName = techCard.dishName;
      final sheetName = _safeExcelSheetName(
          rawName.length > 30 ? '${rawName.substring(0, 27)}...' : rawName);
      final sheet = excel[sheetName];
      _writeTechCardSheetBulk(sheet, techCard, lang);
    }

    final fileName = 'TTK_all_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Сохранение Excel файла в браузере
  void _saveExcelFile(Excel excel, String fileName) {
    final bytes = excel.encode();
    if (bytes == null) return;
    file_saver.saveExcelBytes(Uint8List.fromList(bytes), fileName);
  }

  String _getCategoryName(String category, String lang) {
    const ru = {
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
    const en = {
      'vegetables': 'Vegetables',
      'fruits': 'Fruits',
      'meat': 'Meat',
      'seafood': 'Seafood',
      'dairy': 'Dairy',
      'grains': 'Grains',
      'bakery': 'Bakery',
      'pantry': 'Dry goods',
      'spices': 'Spices',
      'beverages': 'Beverages',
      'eggs': 'Eggs',
      'legumes': 'Legumes',
      'nuts': 'Nuts',
      'misc': 'Other',
    };
    const es = {
      'vegetables': 'Verduras',
      'fruits': 'Frutas',
      'meat': 'Carne',
      'seafood': 'Pescado y marisco',
      'dairy': 'Lácteos',
      'grains': 'Cereales',
      'bakery': 'Panadería',
      'pantry': 'Despensa',
      'spices': 'Especias',
      'beverages': 'Bebidas',
      'eggs': 'Huevos',
      'legumes': 'Legumbres',
      'nuts': 'Frutos secos',
      'misc': 'Varios',
    };
    final Map<String, String> m;
    switch (lang) {
      case 'ru':
        m = ru;
        break;
      case 'es':
        m = es;
        break;
      default:
        m = en;
    }
    return m[category] ?? category;
  }
}