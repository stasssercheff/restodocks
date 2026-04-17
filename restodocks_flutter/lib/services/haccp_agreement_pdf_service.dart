import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../legal/legal_compliance_provider.dart';
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

  /// Русский шаблон соглашения (fallback, если не передан [agreementBody]).
  static const String agreementBodyRu = '''
Настоящим подтверждается, что ввод данных в электронные журналы и учётные формы системы Restodocks под личным логином (логин и пароль) признаётся равнозначным собственноручной подписи в соответствии с:

— {{E_SIGNATURE_LAW}};
— {{SYSTEM_NAME}};
— {{FOOD_LAW}};
— {{DATA_PRIVACY_LAW}}.

Работник обязуется соблюдать порядок учёта и не разглашать данные для входа в систему.
''';

  static String _defaultEmployerPosition(Employee emp, {required bool isRu}) {
    if (emp.positionRole != null && emp.positionRole!.isNotEmpty) {
      final roleToPosition = isRu
          ? const {
              'owner': 'Генеральный директор',
              'executive_chef': 'Шеф-повар',
              'sous_chef': 'Су-шеф',
              'bar_manager': 'Менеджер бара',
              'floor_manager': 'Менеджер зала',
              'general_manager': 'Управляющий',
            }
          : const {
              'owner': 'General Director',
              'executive_chef': 'Executive Chef',
              'sous_chef': 'Sous Chef',
              'bar_manager': 'Bar Manager',
              'floor_manager': 'Floor Manager',
              'general_manager': 'General Manager',
            };
      final key = emp.positionRole!.trim().toLowerCase();
      if (roleToPosition.containsKey(key)) return roleToPosition[key]!;
      final normalized = key.replaceAll('_', ' ').trim();
      if (normalized.isEmpty) {
        return isRu ? 'Представитель работодателя' : 'Employer representative';
      }
      if (isRu) return normalized;
      return normalized
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase() + s.substring(1))
          .join(' ');
    }
    return emp.hasRole('owner')
        ? (isRu ? 'Генеральный директор' : 'General Director')
        : (isRu ? 'Представитель работодателя' : 'Employer representative');
  }

  static Future<Uint8List> buildAgreementPdfBytes({
    required Establishment establishment,
    required Employee employerEmployee,
    String? establishmentCountryCode,
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
    final isRuProfile = (establishmentCountryCode ?? '').toUpperCase() == 'RU';
    String fb(String ru, String en) => isRuProfile ? ru : en;
    final theme = await _getTheme();
    final doc = pw.Document(theme: theme);

    final headerStyle = pw.TextStyle(fontSize: 9, color: PdfColors.grey800);
    final empPosition = employerPositionLabel ??
        _defaultEmployerPosition(employerEmployee, isRu: isRuProfile);
    final empFullName = '${employerEmployee.fullName}${employerEmployee.surname != null ? ' ${employerEmployee.surname}' : ''}';
    final body = agreementBody != null
        ? agreementBody
        : LegalComplianceProvider.applyCompliancePlaceholders(
            agreementBodyRu,
            LegalComplianceProvider.complianceForLanguageCode('ru'),
          );

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
                      '${organizationLabel ?? fb('Организация', 'Organization')}: ${establishment.legalName ?? establishment.name}',
                      style: headerStyle,
                    ),
                    if (establishment.innBin != null && establishment.innBin!.isNotEmpty)
                      pw.Text('${innBinLabel ?? fb('ИНН/БИН', 'Tax ID')}: ${establishment.innBin}', style: headerStyle),
                    if (establishment.address != null && establishment.address!.isNotEmpty)
                      pw.Text('${addressLabel ?? fb('Адрес', 'Address')}: ${establishment.address}', style: headerStyle),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                documentTitle ?? fb('СОГЛАШЕНИЕ С СОТРУДНИКОМ', 'EMPLOYEE AGREEMENT'),
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                documentSubtitle ?? fb(
                  'О признании ввода данных в электронные журналы личной подписью',
                  'On recognizing entries in digital journals as personal signature',
                ),
                style: pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                agreementHeading ??
                    fb(
                      'СОГЛАШЕНИЕ О ПРИЗНАНИИ ЭЛЕКТРОННОЙ ПОДПИСИ',
                      'ELECTRONIC SIGNATURE ACKNOWLEDGEMENT',
                    ),
                style: textStyle,
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Text('${workerLabel ?? fb('Работник', 'Employee')} ', style: textStyle),
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
                  pw.Text(' ${workerFioHint ?? fb('(ФИО полностью)', '(full name)')}', style: textStyle),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                children: [
                  pw.Text('${positionLabel ?? fb('должность', 'position')}: ', style: textStyle),
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
              pw.Text(
                dateLine ??
                    fb(
                      'дата: «____» ______________ 20____ г.',
                      'date: "____" ______________ 20____',
                    ),
                style: textStyle,
              ),
              pw.SizedBox(height: 14),
              pw.Text(body, style: textStyle),
              pw.Spacer(),
              // Подписи сторон
              pw.Container(
                padding: pw.EdgeInsets.only(top: 24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${employerLabel ?? fb('Работодатель', 'Employer')}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('$empPosition ___________ / $empFullName ___________ /', style: textStyle),
                    pw.Text(
                      stampHint ??
                          fb('М.П. (место для печати)', 'Seal (if applicable)'),
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text('${workerSignLabel ?? fb('Работник', 'Employee')}:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
