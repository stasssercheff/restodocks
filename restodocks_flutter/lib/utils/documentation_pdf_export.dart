import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// PDF просмотра документации: заголовок, тема, текст (plain).
Future<Uint8List> buildDocumentationPdfBytes({
  required String title,
  required String topic,
  required String bodyPlain,
}) async {
  final baseData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
  final fontRegular = pw.Font.ttf(baseData);
  final fontBold = pw.Font.ttf(boldData);
  final theme = pw.ThemeData.withFont(
    base: fontRegular,
    bold: fontBold,
    italic: fontRegular,
    boldItalic: fontBold,
  );

  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        if (topic.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            topic,
            style: pw.TextStyle(
              fontSize: 14,
              color: PdfColors.blue900,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Text(
          bodyPlain.trim().isEmpty ? '—' : bodyPlain,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.35),
        ),
      ],
    ),
  );
  return doc.save();
}
