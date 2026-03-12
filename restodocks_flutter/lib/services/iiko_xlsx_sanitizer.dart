import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Утилита для исправления xlsx, которые не читаются Dart-пакетом excel.
///
/// Excel-пакет ожидает custom numFmtId >= 164. Файлы из Numbers (id=0), WPS, Google Sheets (id 41, 59 и т.д.)
/// вызывают ошибку "custom numFmtId starts at 164 but found a value of X".
///
/// Решение: удаляем все кастомные numFmt с id < 164 из numFmts перед парсингом.
class IikoXlsxSanitizer {
  IikoXlsxSanitizer._();

  /// Удаляет из xlsx кастомные numFmt с id < 164, чтобы excel-пакет смог прочитать файл.
  /// Возвращает исправленные байты или оригинал при ошибке.
  static Uint8List sanitizeForExcelPackage(Uint8List bytes) {
    try {
      final arc = ZipDecoder().decodeBytes(bytes);
      final stylesEntry = arc.findFile('xl/styles.xml');
      if (stylesEntry == null) return bytes;

      var xml = utf8.decode(stylesEntry.content as List<int>);

      // Удаляем все <numFmt numFmtId="N" ... /> где N < 164 (встроенные форматы Excel 0–163).
      // Dart excel ожидает только custom id >= 164.
      // Поддержка с namespace (ns0:numFmts) и без.
      if (xml.contains('numFmts')) {
        xml = xml.replaceAllMapped(
          RegExp(r'<\w*:?numFmt\s+numFmtId="(\d+)"[^/]*/>\s*'),
          (m) {
            final id = int.tryParse(m.group(1) ?? '') ?? 999;
            return id < 164 ? '' : m.group(0)!;
          },
        );
        // Обновляем count в numFmts (кол-во оставшихся)
        final remainingCount = RegExp(r'<\w*:?numFmt\s+numFmtId="\d+"[^/]*/>').allMatches(xml).length;
        xml = xml.replaceAllMapped(
          RegExp(r'(<\w*:?numFmts\s+count=")\d+(")'),
          (m) => '${m.group(1)}$remainingCount${m.group(2)}',
        );
      }
      // Заменяем контент в архиве (files — UnmodifiableListView, используем removeFile)
      final newContent = utf8.encode(xml);
      arc.removeFile(stylesEntry);
      arc.addFile(ArchiveFile(
        'xl/styles.xml',
        newContent.length,
        newContent,
      ));

      final out = ZipEncoder().encode(arc);
      return out != null ? Uint8List.fromList(out) : bytes;
    } catch (e) {
      return bytes;
    }
  }

  /// Возвращает байты, которые можно распарсить через Excel.decodeBytes.
  /// При ошибке (например, файл из Numbers) пробует санитизировать.
  static Uint8List ensureDecodable(Uint8List bytes) {
    try {
      Excel.decodeBytes(bytes.toList());
      return bytes;
    } catch (_) {
      final sanitized = sanitizeForExcelPackage(bytes);
      return sanitized;
    }
  }
}
