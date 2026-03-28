import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/account_manager_supabase.dart';
import '../services/localization_service.dart';
import 'number_format_utils.dart';
import 'pos_order_totals.dart';

Future<pw.ThemeData> _posReceiptPdfTheme() async {
  final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
  final fontRegular = pw.Font.ttf(baseData);
  final fontBold = pw.Font.ttf(boldData);
  return pw.ThemeData.withFont(
    base: fontRegular,
    bold: fontBold,
    italic: fontRegular,
    boldItalic: fontBold,
  );
}

/// Пречек PDF: состав, скидка, сервис, итог (без фискальной подписи).
Future<void> sharePosOrderPreReceiptPdf({
  required BuildContext context,
  required PosOrder order,
  required List<PosOrderLine> lines,
  required LocalizationService loc,
}) async {
  final account = context.read<AccountManagerSupabase>();
  final est = account.establishment;
  final currency = est?.defaultCurrency ?? 'RUB';
  final sym = est?.currencySymbol ?? Establishment.currencySymbolFor(currency);
  final lang = loc.currentLanguageCode;
  final timeFmt = DateFormat.Hm(lang);
  final dateFmt = DateFormat.yMd(lang);

  var menuSub = 0.0;
  for (final l in lines) {
    final p = l.sellingPrice;
    if (p == null) continue;
    menuSub += l.quantity * p;
  }
  final totals = computePosOrderTotals(
    menuSubtotal: menuSub,
    orderFields: order,
  );

  String fmtMoney(double v) =>
      '${NumberFormatUtils.formatSum(v, currency)} $sym';

  final theme = await _posReceiptPdfTheme();
  final pdf = pw.Document(theme: theme);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(
          loc.t('pos_order_receipt_title'),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          loc.t('pos_table_number', args: {'n': '${order.tableNumber ?? 0}'}),
        ),
        if (order.floorName != null || order.roomName != null)
          pw.Text(
            [
              if (order.floorName != null && order.floorName!.trim().isNotEmpty)
                order.floorName,
              if (order.roomName != null && order.roomName!.trim().isNotEmpty)
                order.roomName,
            ].join(' · '),
          ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${dateFmt.format(order.createdAt.toLocal())} ${timeFmt.format(order.createdAt.toLocal())}',
        ),
        pw.Divider(),
        pw.Text(
          loc.t('pos_order_lines_heading'),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        ...lines.map((l) {
          final title = l.dishTitleForLang(lang);
          final lineSum = l.sellingPrice != null
              ? fmtMoney(l.quantity * l.sellingPrice!)
              : '—';
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '${_formatQty(l.quantity)} × $title',
                    maxLines: 3,
                  ),
                ),
                pw.Text(lineSum),
              ],
            ),
          );
        }),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(loc.t('pos_order_subtotal_menu_label')),
            pw.Text(fmtMoney(totals.menuSubtotal)),
          ],
        ),
        if (totals.discountAmount > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(loc.t('pos_order_discount_label')),
              pw.Text('- ${fmtMoney(totals.discountAmount)}'),
            ],
          ),
        if (totals.serviceAmount > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(loc.t('pos_order_service_amount_label')),
              pw.Text(fmtMoney(totals.serviceAmount)),
            ],
          ),
        if (totals.tipsAmount > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(loc.t('pos_order_tips_label')),
              pw.Text(fmtMoney(totals.tipsAmount)),
            ],
          ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              loc.t('pos_order_grand_total_label'),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              fmtMoney(totals.grandTotal),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          loc.t('pos_order_receipt_not_fiscal_hint'),
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: 'order-${order.id}.pdf',
  );
}

String _formatQty(double q) {
  final t = q.toStringAsFixed(2);
  return t.replaceFirst(RegExp(r'\.?0+$'), '');
}
