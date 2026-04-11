import 'package:excel/excel.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../utils/pos_sold_lines_to_products.dart';

/// Excel: 4 листа — позиции; продукты кухня; продукты бар; продукты все цеха.
class PosSalesExcelExportService {
  PosSalesExcelExportService._();
  static final PosSalesExcelExportService instance = PosSalesExcelExportService._();

  List<int>? build({
    required LocalizationService loc,
    required List<PosOrderLine> allLines,
    required Map<String, TechCard> tcById,
  }) {
    try {
      final excel = Excel.createExcel();

      final sheetPositions = excel['Позиции'];
      sheetPositions.appendRow([
        TextCellValue(loc.t('pos_sales_xlsx_col_dish')),
        TextCellValue(loc.t('pos_sales_xlsx_col_qty')),
        TextCellValue(loc.t('pos_sales_xlsx_col_subdivision')),
        TextCellValue(loc.t('pos_sales_xlsx_col_workshop')),
      ]);
      final sheet1rows = buildSheet1AggregatedRows(
        lines: allLines,
        tcById: tcById,
        loc: loc,
      );
      for (final r in sheet1rows) {
        sheetPositions.appendRow([
          TextCellValue(r.dishName),
          DoubleCellValue(r.quantity),
          TextCellValue(r.subdivisionLabel),
          TextCellValue(r.workshopLabel),
        ]);
      }

      void fillProductsSheet(String sheetName, PosSalesProductsFilter filter) {
        final sheet = excel[sheetName];
        final agg = aggregateSoldLinesToProducts(
          lines: allLines,
          tcById: tcById,
          filter: filter,
        );
        sheet.appendRow([
          TextCellValue(loc.t('inventory_excel_number')),
          TextCellValue(loc.t('inventory_item_name')),
          TextCellValue(loc.t('inventory_pf_gross_g')),
          TextCellValue(loc.t('inventory_pf_net_g')),
        ]);
        var i = 1;
        for (final p in agg) {
          sheet.appendRow([
            IntCellValue(i++),
            TextCellValue((p['productName'] as String?) ?? ''),
            IntCellValue(
                ((p['grossGrams'] as num?)?.toDouble() ?? 0).round()),
            IntCellValue(((p['netGrams'] as num?)?.toDouble() ?? 0).round()),
          ]);
        }
      }

      fillProductsSheet('Продукты кухня', PosSalesProductsFilter.kitchen);
      fillProductsSheet('Продукты бар', PosSalesProductsFilter.bar);
      fillProductsSheet('Продукты все цеха', PosSalesProductsFilter.all);

      excel.setDefaultSheet('Позиции');
      for (final name in excel.tables.keys.toList()) {
        if (name != 'Позиции' &&
            name != 'Продукты кухня' &&
            name != 'Продукты бар' &&
            name != 'Продукты все цеха') {
          excel.delete(name);
        }
      }

      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    }
  }
}
