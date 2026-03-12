import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';
import 'inventory_download.dart';
import 'product_store_supabase.dart';
import 'tech_card_service_supabase.dart';

/// Экспорт меню и карточек блюд в PDF.
/// Доступ: шеф/су-шеф (кухня), барменеджер (бар).
class MenuExportService {
  static pw.ThemeData? _pdfTheme;
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfTheme != null) return _pdfTheme!;
    final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _fontRegular = pw.Font.ttf(baseData);
    _fontBold = pw.Font.ttf(boldData);
    _pdfTheme = pw.ThemeData.withFont(
      base: _fontRegular!,
      bold: _fontBold!,
      italic: _fontRegular!,
      boldItalic: _fontBold!,
    );
    return _pdfTheme!;
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Построить PDF всего меню (все блюда с составом).
  static Future<Uint8List> buildMenuPdfBytes({
    required List<TechCard> dishes,
    required String Function(String) t,
    required String lang,
    required String currencySym,
    ProductStoreSupabase? productStore,
  }) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(theme: theme);
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(24),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(
                t('menu'),
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Paragraph(text: dateStr),
            pw.SizedBox(height: 16),
          ];
          for (final tc in dishes) {
            final ingredients = tc.ingredients.where((i) => !i.isPlaceholder || i.hasData).toList();
            final totalOutput = ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
            final totalCost = ingredients.fold<double>(0, (s, i) => s + i.cost);
            final technology = tc.getLocalizedTechnology(lang);

            widgets.add(pw.Header(level: 1, child: pw.Text(tc.dishName)));
            widgets.add(pw.SizedBox(height: 8));
            widgets.add(_buildIngredientsTable(
              ingredients: ingredients,
              t: t,
              lang: lang,
              currencySym: currencySym,
              showCost: true,
              totalOutput: totalOutput,
              totalCost: totalCost,
            ));
            if (tc.totalCalories > 0 || tc.totalProtein > 0 || tc.totalFat > 0 || tc.totalCarbs > 0) {
              final allergens = _allergensForDish(tc, productStore, lang);
              final kbju = t('kbju_allergens_in_dish')
                  .replaceFirst('%s', tc.totalCalories.round().toString())
                  .replaceFirst('%s', tc.totalProtein.toStringAsFixed(1))
                  .replaceFirst('%s', tc.totalFat.toStringAsFixed(1))
                  .replaceFirst('%s', tc.totalCarbs.toStringAsFixed(1))
                  .replaceFirst('%s', allergens);
              widgets.add(pw.Padding(
                padding: pw.EdgeInsets.only(top: 8),
                child: pw.Container(
                  padding: pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Text(kbju, style: const pw.TextStyle(fontSize: 9)),
                ),
              ));
              widgets.add(pw.SizedBox(height: 8));
            }
            if (technology.trim().isNotEmpty) {
              widgets.add(pw.Container(
                padding: pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(t('ttk_technology'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(technology, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ));
              widgets.add(pw.SizedBox(height: 20));
            }
          }
          return widgets;
        },
      ),
    );
    return doc.save();
  }

  /// Построить PDF одного блюда: карточка блюда + карточки всех ПФ с выходом на это блюдо.
  static Future<Uint8List> buildDishPdfBytes({
    required TechCard dish,
    required TechCardServiceSupabase techCardService,
    ProductStoreSupabase? productStore,
    required String Function(String) t,
    required String lang,
    required String currencySym,
  }) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(theme: theme);

    final ingredients = dish.ingredients.where((i) => !i.isPlaceholder || i.hasData).toList();
    final totalOutput = ingredients.fold<double>(0, (s, i) => s + i.outputWeight);
    final totalCost = ingredients.fold<double>(0, (s, i) => s + i.cost);
    final technology = dish.getLocalizedTechnology(lang);

    final dishPages = <pw.Widget>[
      pw.Header(level: 0, child: pw.Text(dish.dishName)),
      pw.SizedBox(height: 12),
      _buildIngredientsTable(
        ingredients: ingredients,
        t: t,
        lang: lang,
        currencySym: currencySym,
        showCost: true,
        totalOutput: totalOutput,
        totalCost: totalCost,
      ),
    ];
    if (dish.totalCalories > 0 || dish.totalProtein > 0 || dish.totalFat > 0 || dish.totalCarbs > 0) {
      final allergens = _allergensForDish(dish, productStore, lang);
      final kbju = t('kbju_allergens_in_dish')
          .replaceFirst('%s', dish.totalCalories.round().toString())
          .replaceFirst('%s', dish.totalProtein.toStringAsFixed(1))
          .replaceFirst('%s', dish.totalFat.toStringAsFixed(1))
          .replaceFirst('%s', dish.totalCarbs.toStringAsFixed(1))
          .replaceFirst('%s', allergens);
      dishPages.add(pw.Padding(
        padding: pw.EdgeInsets.only(top: 12),
        child: pw.Container(
          padding: pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Text(kbju, style: const pw.TextStyle(fontSize: 9)),
        ),
      ));
    }
    if (technology.trim().isNotEmpty) {
      dishPages.add(pw.Padding(
        padding: pw.EdgeInsets.only(top: 12),
        child: pw.Container(
          padding: pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(t('ttk_technology'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(technology, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ));
    }

    final pfIds = ingredients
        .where((i) => i.sourceTechCardId != null && i.sourceTechCardId!.isNotEmpty)
        .map((i) => MapEntry(i.sourceTechCardId!, i.outputWeight))
        .toList();
    final pfMap = <String, double>{};
    for (final e in pfIds) {
      pfMap[e.key] = (pfMap[e.key] ?? 0) + e.value;
    }

    final pfWidgets = <pw.Widget>[];
    for (final entry in pfMap.entries) {
      final pfTc = await techCardService.getTechCardById(entry.key);
      if (pfTc == null) continue;
      final outputForDish = entry.value;
      final pfIngredients = pfTc.ingredients.where((i) => !i.isPlaceholder || i.hasData).toList();
      final pfTotalOutput = pfIngredients.fold<double>(0, (s, i) => s + i.outputWeight);
      final pfTotalCost = pfIngredients.fold<double>(0, (s, i) => s + i.cost);
      final pfTech = pfTc.getLocalizedTechnology(lang);

      final pfOutputLabel = t('pf_output_for_dish').replaceFirst('%s', outputForDish.toStringAsFixed(0));

      pfWidgets.addAll([
        pw.SizedBox(height: 20),
        pw.Header(level: 1, child: pw.Text('${t('ttk_pf')}: ${pfTc.dishName}')),
        pw.Paragraph(text: pfOutputLabel),
        pw.SizedBox(height: 8),
        _buildIngredientsTable(
          ingredients: pfIngredients,
          t: t,
          lang: lang,
          currencySym: currencySym,
          showCost: true,
          totalOutput: pfTotalOutput,
          totalCost: pfTotalCost,
        ),
      ]);
      if (pfTc.totalCalories > 0 || pfTc.totalProtein > 0 || pfTc.totalFat > 0 || pfTc.totalCarbs > 0) {
        final allergens = _allergensForDish(pfTc, productStore, lang);
        final kbju = t('kbju_allergens_in_dish')
            .replaceFirst('%s', pfTc.totalCalories.round().toString())
            .replaceFirst('%s', pfTc.totalProtein.toStringAsFixed(1))
            .replaceFirst('%s', pfTc.totalFat.toStringAsFixed(1))
            .replaceFirst('%s', pfTc.totalCarbs.toStringAsFixed(1))
            .replaceFirst('%s', allergens);
        pfWidgets.add(pw.Padding(
          padding: pw.EdgeInsets.only(top: 8),
          child: pw.Container(
            padding: pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text(kbju, style: const pw.TextStyle(fontSize: 9)),
          ),
        ));
      }
      if (pfTech.trim().isNotEmpty) {
        pfWidgets.add(pw.Padding(
          padding: pw.EdgeInsets.only(top: 8),
          child: pw.Container(
            padding: pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(t('ttk_technology'), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(pfTech, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ));
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(24),
        build: (context) => [...dishPages, ...pfWidgets],
      ),
    );

    return doc.save();
  }

  static pw.Widget _buildIngredientsTable({
    required List<TTIngredient> ingredients,
    required String Function(String) t,
    required String lang,
    required String currencySym,
    required bool showCost,
    required double totalOutput,
    required double totalCost,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5),
        1: const pw.FlexColumnWidth(0.8),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(0.8),
        if (showCost) 5: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _cell(t('ttk_product'), bold: true),
            _cell(t('ttk_gross'), bold: true),
            _cell(t('ttk_net'), bold: true),
            _cell(t('ttk_cooking_method'), bold: true),
            _cell(t('ttk_output'), bold: true),
            if (showCost) _cell(t('ttk_cost'), bold: true),
          ],
        ),
        if (ingredients.isEmpty)
          pw.TableRow(
            children: List.generate(showCost ? 6 : 5, (_) => _cell(t('dash'))),
          )
        else
          ...ingredients.map((ing) => pw.TableRow(
                children: [
                  _cell(ing.sourceTechCardName ?? ing.productName),
                  _cell(ing.grossWeight > 0 ? ing.grossWeight.toStringAsFixed(0) : ''),
                  _cell(ing.netWeight > 0 ? ing.netWeight.toStringAsFixed(0) : ''),
                  _cell(ing.cookingProcessName ?? t('dash')),
                  _cell(ing.outputWeight > 0 ? ing.outputWeight.toStringAsFixed(0) : ''),
                  if (showCost) _cell(ing.cost > 0 ? '${ing.cost.toStringAsFixed(2)} $currencySym' : ''),
                ],
              )),
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell(t('ttk_total'), bold: true),
            _cell(''),
            _cell(''),
            _cell(''),
            _cell('${totalOutput.toStringAsFixed(0)} ${t('gram')}', bold: true),
            if (showCost) _cell('${totalCost.toStringAsFixed(2)} $currencySym', bold: true),
          ],
        ),
      ],
    );
  }

  static String _allergensForDish(TechCard tc, ProductStoreSupabase? store, String lang) {
    if (store == null) return lang == 'ru' ? 'нет' : 'none';
    final allergens = <String>[];
    for (final ing in tc.ingredients.where((i) => i.productId != null)) {
      final p = store.findProductForIngredient(ing.productId, ing.productName);
      if (p?.containsGluten == true && !allergens.contains('глютен')) allergens.add('глютен');
      if (p?.containsLactose == true && !allergens.contains('лактоза')) allergens.add('лактоза');
    }
    return allergens.isEmpty ? (lang == 'ru' ? 'нет' : 'none') : allergens.join(', ');
  }

  /// Сохранить PDF меню на устройство.
  static Future<String> saveMenuPdf({
    required List<TechCard> dishes,
    required String Function(String) t,
    required String lang,
    required String currencySym,
    ProductStoreSupabase? productStore,
  }) async {
    final bytes = await buildMenuPdfBytes(
      dishes: dishes,
      t: t,
      lang: lang,
      currencySym: currencySym,
      productStore: productStore,
    );
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'menu_$dateStr.pdf';
    await saveFileBytes(fileName, bytes);
    return fileName;
  }

  /// Сохранить PDF одного блюда (с ПФ) на устройство.
  static Future<String> saveDishPdf({
    required TechCard dish,
    required TechCardServiceSupabase techCardService,
    ProductStoreSupabase? productStore,
    required String Function(String) t,
    required String lang,
    required String currencySym,
  }) async {
    final bytes = await buildDishPdfBytes(
      dish: dish,
      techCardService: techCardService,
      productStore: productStore,
      t: t,
      lang: lang,
      currencySym: currencySym,
    );
    final safeName = dish.dishName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_').replaceAll(RegExp(r'\s+'), '_');
    final fileName = 'dish_${safeName}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
    await saveFileBytes(fileName, bytes);
    return fileName;
  }
}
