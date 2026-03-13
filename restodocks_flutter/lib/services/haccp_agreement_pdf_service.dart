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
СОГЛАШЕНИЕ О ПРИЗНАНИИ ЭЛЕКТРОННОЙ ПОДПИСИ

Работник ____________________________________________ (ФИО полностью)
должность: ____________________________________________
дата: «____» ______________ 20____ г.

настоящим удостоверяет, что ввод данных в электронные журналы и учётные формы системы Restodocks под своим учётным логином (логин и пароль) признаётся им равнозначным собственноручной подписи в соответствии с:

— Федеральным законом №63-ФЗ «Об электронной подписи» (РФ);
— Законом Республики Казахстан «Об электронном документе и электронной цифровой подписи» (применимо в РК);
— Законом Республики Беларусь «Об электронном документе и электронной цифровой подписи» (применимо в РБ);
— ТР ТС 021/2011 «О безопасности пищевой продукции» (ЕАЭС).

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
        build: (ctx) => pw.Column(
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
            pw.Text(
              agreementBody,
              style: pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }
}
