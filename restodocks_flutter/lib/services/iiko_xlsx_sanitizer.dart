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

  /// Исправляет numFmt с id < 164 (Numbers, WPS, Google Sheets) для dart excel пакета.
  /// Вместо удаления — переназначает id на 164+, т.к. cellXfs ссылаются на старые id.
  static Uint8List sanitizeForExcelPackage(Uint8List bytes) {
    try {
      final arc = ZipDecoder().decodeBytes(bytes);
      final stylesEntry = arc.findFile('xl/styles.xml');
      if (stylesEntry == null) return bytes;

      var xml = utf8.decode(stylesEntry.content as List<int>);

      // Собираем numFmt с id < 164 и назначаем им новые id (164, 165, ...)
      final oldToNew = <int, int>{};
      var nextId = 164;
      final numFmtRegex = RegExp(r'<\w*:?numFmt\s+numFmtId="(\d+)"');
      for (final m in numFmtRegex.allMatches(xml)) {
        final id = int.tryParse(m.group(1) ?? '') ?? 999;
        if (id < 164 && !oldToNew.containsKey(id)) {
          oldToNew[id] = nextId++;
        }
      }
      if (oldToNew.isEmpty) return bytes;

      // Заменяем id в numFmts и во всех numFmtId="N" (cellXfs, cellStyleXfs)
      for (final e in oldToNew.entries.toList()..sort((a, b) => b.key.compareTo(a.key))) {
        xml = xml.replaceAll('numFmtId="${e.key}"', 'numFmtId="${e.value}"');
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
