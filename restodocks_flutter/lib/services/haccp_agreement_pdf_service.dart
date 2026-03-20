import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/establishment.dart';
import '../models/employee.dart';

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

  /// Русский текст соглашения (fallback).
  static const String agreementBodyRu = '''
Настоящим удостоверяет, что ввод данных в электронные журналы и учётные формы системы Restodocks под своим учётным логином (логин и пароль) признаётся им равнозначным собственноручной подписи в соответствии с:

— Национальным законодательством об электронной цифровой подписи (включая 63-ФЗ РФ, Закон об ЭЦП РК, РБ, РУз и др. государств СНГ);
— Международными стандартами безопасности пищевой продукции (HACCP / ХАССП);
— Техническим регламентом Таможенного союза ТР ТС 021/2011 "О безопасности пищевой продукции" (действует на всей территории ЕАЭС).

Работник обязуется соблюдать порядок учёта и не разглашать данные для входа в систему.
''';

  static String _employerPositionRu(Employee emp) {
    if (emp.positionRole != null && emp.positionRole!.isNotEmpty) {
      const roleToPosition = {
        'owner': 'Генеральный директор',
        'executive_chef': 'Шеф-повар',
        'sous_chef': 'Су-шеф',
        'bar_manager': 'Менеджер бара',
        'floor_manager': 'Менеджер зала',
        'general_manager': 'Управляющий',
      };
      return roleToPosition[emp.positionRole!] ?? emp.positionRole!;
    }
    return emp.hasRole('owner') ? 'Генеральный директор' : 'Представитель работодателя';
  }

  static Future<Uint8List> buildAgreementPdfBytes({
    required Establishment establishment,
    required Employee employerEmployee,
    String? organizationLabel,
    String? innBinLabel,
    String? addressLabel,
    String? documentTitle,
    String? documentSubtitle,
    String? agreementHeading,
    String? workerLabel,
    String? workerFioHint,
    String? positionLabel,
    String? dateLine,
    String? employerLabel,
    String? stampHint,
    String? workerSignLabel,
    String? agreementBody,
    String? employerPositionLabel,
  }) async {
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);

    final headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final empPosition = employerPositionLabel ?? _employerPositionRu(employerEmployee);
    final empFullName = '${employerEmployee.fullName}${employerEmployee.surname != null ? ' ${employerEmployee.surname}' : ''}';
    final body = agreementBody ?? agreementBodyRu;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(40),
        build: (ctx) {
          final textStyle = pw.TextStyle(fontSize: 10);
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Шапка — реквизиты
              pw.Container(
                padding: pw.EdgeInsets.only(bottom: 16),
                decoration: pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${organizationLabel ?? 'Организация'}: ${establishment.legalName ?? establishment.name}',
                      style: headerStyle,
                    ),
                    if (establishment.innBin != null && establishment.innBin!.isNotEmpty)
                      pw.Text('${innBinLabel ?? 'ИНН/БИН'}: ${establishment.innBin}', style: headerStyle),
                    if (establishment.address != null && establishment.address!.isNotEmpty)
                      pw.Text('${addressLabel ?? 'Адрес'}: ${establishment.address}', style: headerStyle),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                documentTitle ?? 'СОГЛАШЕНИЕ С СОТРУДНИКОМ',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                documentSubtitle ?? 'О признании ввода данных в электронные журналы личной подписью',
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text(agreementHeading ?? 'СОГЛАШЕНИЕ О ПРИЗНАНИИ ЭЛЕКТРОННОЙ ПОДПИСИ', style: textStyle),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Text('${workerLabel ?? 'Работник'} ', style: textStyle),
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
                  pw.Text(' ${workerFioHint ?? '(ФИО полностью)'}', style: textStyle),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  pw.Text('${positionLabel ?? 'должность'}: ', style: textStyle),
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
              pw.Text(dateLine ?? 'дата: «____» ______________ 20____ г.', style: textStyle),
              pw.SizedBox(height: 14),
              pw.Text(body, style: textStyle),
              pw.Spacer(),
              // Подписи сторон
              pw.Container(
                padding: pw.EdgeInsets.only(top: 24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${employerLabel ?? 'Работодатель'}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('$empPosition ___________ / $empFullName ___________ /', style: textStyle),
                    pw.Text(stampHint ?? 'М.П. (место для печати)', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.SizedBox(height: 16),
                    pw.Text('${workerSignLabel ?? 'Работник'}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('___________ / ___________ /', style: textStyle),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
