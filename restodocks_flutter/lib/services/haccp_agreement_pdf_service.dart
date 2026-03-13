import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Генерация PDF «Соглашение с сотрудником» о признании ввода данных под логином
/// личной подписью (Простая Электронная Подпись).
class HaccpAgreementPdfService {
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

  /// Текст соглашения для печати и подписания.
  static const String agreementBody = '''
Настоящим удостоверяет, что ввод данных в электронные журналы и учётные формы системы Restodocks под своим учётным логином (логин и пароль) признаётся им равнозначным собственноручной подписи в соответствии с:

— Национальным законодательством об электронной цифровой подписи (включая 63-ФЗ РФ, Закон об ЭЦП РК, РБ, РУз и др. государств СНГ);
— Международными стандартами безопасности пищевой продукции (HACCP / ХАССП);
— Техническим регламентом Таможенного союза ТР ТС 021/2011 "О безопасности пищевой продукции" (действует на всей территории ЕАЭС).

Работник обязуется соблюдать порядок учёта и не разглашать данные для входа в систему.

_____________________ / ____________________
   (подпись работника)         (расшифровка)
''';

  static Future<Uint8List> buildAgreementPdfBytes() async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          final textStyle = pw.TextStyle(fontSize: 10);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'СОГЛАШЕНИЕ С СОТРУДНИКОМ',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'О признании ввода данных в электронные журналы личной подписью',
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text('СОГЛАШЕНИЕ О ПРИЗНАНИИ ЭЛЕКТРОННОЙ ПОДПИСИ', style: textStyle),
              pw.SizedBox(height: 8),
              // Работник _____ (ФИО полностью) — на всю ширину строки
              pw.Row(
                children: [
                  pw.Text('Работник ', style: textStyle),
                  pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(width: 0.5, color: PdfColors.black),
                        ),
                      ),
                      height: 14,
                    ),
                  ),
                  pw.Text(' (ФИО полностью)', style: textStyle),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  pw.Text('должность: ', style: textStyle),
                  pw.Expanded(
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(width: 0.5, color: PdfColors.black),
                        ),
                      ),
                      height: 14,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Text('дата: «____» ______________ 20____ г.', style: textStyle),
              pw.SizedBox(height: 14),
              pw.Text(
                agreementBody,
                style: textStyle,
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
