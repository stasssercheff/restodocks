import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Утилита для исправления xlsx, экспортированных из Apple Numbers.
///
/// Numbers добавляет в styles.xml кастомный numFmt с numFmtId="0" (General),
/// что ломает Dart-пакет excel (ошибка: "custom numFmtId starts at 164 but found a value of 0").
///
/// Решение: удаляем невалидную запись из numFmts перед парсингом.
class IikoXlsxSanitizer {
  IikoXlsxSanitizer._();

  /// Удаляет из xlsx кастомный numFmt с id=0, чтобы excel-пакет смог прочитать файл.
  /// Возвращает исправленные байты или оригинал при ошибке.
  static Uint8List sanitizeForExcelPackage(Uint8List bytes) {
    try {
      final arc = ZipDecoder().decodeBytes(bytes);
      final stylesEntry = arc.findFile('xl/styles.xml');
      if (stylesEntry == null) return bytes;

      var xml = utf8.decode(stylesEntry.content as List<int>);

      // Удаляем <numFmt numFmtId="0" ... /> из numFmts.
      // Numbers добавляет кастомный General с id=0, что ломает Dart excel (ожидает custom id >= 164).
      // Поддержка с namespace (ns0:numFmts) и без.
      if (xml.contains('numFmtId="0"') && xml.contains('numFmts')) {
        // Удаляем элемент <numFmt numFmtId="0" ... /> (с поддержкой namespace)
        xml = xml.replaceAll(
          RegExp(r'<\w*:?numFmt\s+numFmtId="0"[^/]*/>\s*'),
          '',
        );
        // Обновляем count в numFmts
        xml = xml.replaceAllMapped(
          RegExp(r'(<\w*:?numFmts\s+count=")\d+(")'),
          (m) => '${m.group(1)}0${m.group(2)}',
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
