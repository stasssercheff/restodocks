import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import '../utils/dev_log.dart';
import 'package:flutter/foundation.dart';

/// Утилита для байтового патча xlsx-бланка iiko.
///
/// Патчит все листы бланка без изменения форматирования:
/// ищет строки по коду (shared string или число — Numbers хранит коды как числа),
/// записывает qty в колонку остатка.
///
/// Использование:
///   final bytes = IikoXlsxPatcher.patch(
///     origBytes:    origBytes,
///     defaultQtyCol: qtyCol,
///     sheetQtyCols: store.sheetQtyColumns,    // { sheetName → colIndex }
///     qtyByCode:    { 'КОД' → total },
///   );
class IikoXlsxPatcher {
  IikoXlsxPatcher._();

  /// Патчит оригинальный xlsx-бланк.
  ///
  /// [origBytes]      — байты оригинального файла.
  /// [defaultQtyCol]  — индекс колонки qty (0-based) для листов без записи в [sheetQtyCols].
  /// [sheetQtyCols]   — карта { displayName листа → индекс колонки qty }.
  /// [qtyByCode]      — карта { код товара → итого }.
  static Uint8List patch({
    required Uint8List origBytes,
    required int defaultQtyCol,
    required Map<String, double> qtyByCode,
    Map<String, int> sheetQtyCols = const {},
  }) {
    if (qtyByCode.isEmpty) return origBytes;

    final arc = ZipDecoder().decodeBytes(origBytes);

    String colLetter(int idx) {
      var result = '';
      var n = idx + 1;
      while (n > 0) {
        n--;
        result = String.fromCharCode(65 + n % 26) + result;
        n ~/= 26;
      }
      return result;
    }

    // sharedStrings
    final sharedStrings = <String>[];
    final ssEntry = arc.findFile('xl/sharedStrings.xml');
    if (ssEntry != null) {
      final ssXml = utf8.decode(ssEntry.content as List<int>);
      final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
      final tRe  = RegExp(r'<t[^>]*>([^<]*)</t>');
      for (final si in siRe.allMatches(ssXml)) {
        sharedStrings.add(
            tRe.allMatches(si.group(1)!).map((m) => m.group(1)!).join());
      }
    }

    // Строим карту: displayName листа → { path, qtyCol }
    final wbEntry   = arc.findFile('xl/workbook.xml');
    final relsEntry = arc.findFile('xl/_rels/workbook.xml.rels');
    final sheetInfos = <String, ({String path, int col})>{};

    if (wbEntry != null && relsEntry != null) {
      final wb   = utf8.decode(wbEntry.content   as List<int>);
      final rels = utf8.decode(relsEntry.content as List<int>);
      for (final sm in RegExp(r'<sheet\b([^>]*)/?>').allMatches(wb)) {
        final attrs = sm.group(1)!;
        final nameM = RegExp(r'name="([^"]*)"').firstMatch(attrs);
        final rIdM  = RegExp(r'r:id="([^"]*)"').firstMatch(attrs);
        if (nameM == null || rIdM == null) continue;
        final displayName = nameM.group(1)!;
        final rId = rIdM.group(1)!;
        final tM =
            RegExp('Id="$rId"[^>]*Target="([^"]+)"').firstMatch(rels);
        if (tM == null) continue;
        final t = tM.group(1)!;
        final path = t.startsWith('/') ? t.substring(1) : 'xl/$t';
        final col = sheetQtyCols[displayName] ?? defaultQtyCol;
        sheetInfos[displayName] = (path: path, col: col);
      }
    }
    if (sheetInfos.isEmpty) {
      sheetInfos[''] = (path: 'xl/worksheets/sheet1.xml', col: defaultQtyCol);
    }

    // Патчим каждый лист
    String patchSheetXml(String xml, String sheetName, int sheetQtyCol) {
      if (qtyByCode.isEmpty) return xml;

      final qtyColLetter = colLetter(sheetQtyCol);
      int codeColIdx = 2;
      outer:
      for (final rowM in RegExp(r'<row r="(\d+)"[^>]*>(.*?)</row>',
              dotAll: true)
          .allMatches(xml)) {
        if (int.parse(rowM.group(1)!) > 20) break;
        for (final cm in RegExp(
                r'<c r="([A-Z]+)\d+"(?:[^>]*)t="s"(?:[^>]*)><v>(\d+)</v></c>')
            .allMatches(rowM.group(2)!)) {
          final idx = int.tryParse(cm.group(2)!) ?? -1;
          if (idx >= 0 && idx < sharedStrings.length) {
            final v = sharedStrings[idx].trim().toLowerCase();
            if (v == 'код' || v == 'code') {
              var ci = 0;
              for (final ch in cm.group(1)!.runes) {
                ci = ci * 26 + (ch - 65 + 1);
              }
              codeColIdx = ci - 1;
              break outer;
            }
          }
        }
      }
      final codeColLetter = colLetter(codeColIdx);
      devLog(
          'IikoXlsxPatcher[$sheetName]: codeCol=$codeColLetter qtyCol=$qtyColLetter');

      var patchedCount = 0;
      final result = xml.replaceAllMapped(
        RegExp(r'(<row r="(\d+)"[^>]*>)(.*?)(</row>)', dotAll: true),
        (m) {
          final rowOpen  = m.group(1)!;
          final rowIdx   = m.group(2)!;
          var   rowBody  = m.group(3)!;
          final rowClose = m.group(4)!;

          // Код может быть shared string (t="s") или число (t="n"/нет — бланки из Numbers)
          final codeCellRe = RegExp(
            '<c r="${RegExp.escape(codeColLetter)}$rowIdx"([^>]*)><v>([^<]+)</v></c>',
          );
          final codeM = codeCellRe.firstMatch(rowBody);
          if (codeM == null) return m.group(0)!;
          final attrs = codeM.group(1) ?? '';
          final val = codeM.group(2) ?? '';
          final String codeStr = attrs.contains('t="s"')
              ? ((int.tryParse(val) ?? -1) >= 0 &&
                        (int.tryParse(val) ?? -1) < sharedStrings.length
                    ? sharedStrings[int.parse(val)].trim()
                    : '')
              : val.trim();
          if (codeStr.isEmpty) return m.group(0)!;
          final qty = qtyByCode[codeStr];
          if (qty == null) return m.group(0)!;

          final qtyStr = qty == qty.roundToDouble()
              ? qty.toInt().toString()
              : qty
                  .toStringAsFixed(3)
                  .replaceAll(RegExp(r'0+$'), '')
                  .replaceAll(RegExp(r'\.$'), '');
          final cellRef = '$qtyColLetter$rowIdx';

          final selfM = RegExp(
                  '<c r="${RegExp.escape(cellRef)}"([^>]*)/>').firstMatch(rowBody);
          final existM = RegExp(
            '<c r="${RegExp.escape(cellRef)}"([^>]*)>(.*?)</c>',
            dotAll: true,
          ).firstMatch(rowBody);

          if (selfM != null) {
            rowBody = rowBody.replaceFirst(
              selfM.group(0)!,
              '<c r="$cellRef"${selfM.group(1)!}><v>$qtyStr</v></c>',
            );
          } else if (existM != null) {
            rowBody = rowBody.replaceFirst(
              existM.group(0)!,
              '<c r="$cellRef"${existM.group(1)!}><v>$qtyStr</v></c>',
            );
          } else {
            final sM =
                RegExp('<c r="[A-Z]+$rowIdx" s="(\\d+)"').firstMatch(rowBody);
            final sAttr = sM != null ? ' s="${sM.group(1)}"' : '';
            rowBody += '<c r="$cellRef"$sAttr><v>$qtyStr</v></c>';
          }
          patchedCount++;
          return '$rowOpen$rowBody$rowClose';
        },
      );
      devLog('IikoXlsxPatcher[$sheetName]: patched $patchedCount rows');
      return result;
    }

    // Применяем патч ко всем листам
    Uint8List result = origBytes;
    for (final entry in sheetInfos.entries) {
      final sheetEntry = arc.findFile(entry.value.path);
      if (sheetEntry == null) continue;
      final xml = utf8.decode(sheetEntry.content as List<int>);
      final patched = patchSheetXml(xml, entry.key, entry.value.col);
      result = _zipReplaceFile(result, entry.value.path, utf8.encode(patched));
    }
    return result;
  }

  // ── ZIP low-level ─────────────────────────────────────────────────────────

  static Uint8List _zipReplaceFile(
      Uint8List zipBytes, String targetName, List<int> newContent) {
    final newCompressed = Deflate(newContent, level: 6).getBytes();
    final newCrc        = _crc32(newContent);
    final newUncompSize = newContent.length;
    final newCompSize   = newCompressed.length;

    final out       = BytesBuilder();
    final cdEntries = <_ZipCdEntry>[];

    int pos = 0;
    final bd = ByteData.sublistView(zipBytes);
    int _readU16(int o) => bd.getUint16(o, Endian.little);
    int _readU32(int o) => bd.getUint32(o, Endian.little);

    while (pos < zipBytes.length - 4) {
      final sig = _readU32(pos);
      if (sig == 0x04034b50) {
        final compMethod     = _readU16(pos + 8);
        final crc32orig      = _readU32(pos + 14);
        final compSizeOrig   = _readU32(pos + 18);
        final uncompSizeOrig = _readU32(pos + 22);
        final nameLen        = _readU16(pos + 26);
        final extraLen       = _readU16(pos + 28);
        final name           = utf8.decode(zipBytes.sublist(pos + 30, pos + 30 + nameLen));
        final dataOffset     = pos + 30 + nameLen + extraLen;

        final isTarget = (name == targetName);
        final effCompSize   = isTarget ? newCompSize   : compSizeOrig;
        final effUncompSize = isTarget ? newUncompSize : uncompSizeOrig;
        final effCrc        = isTarget ? newCrc        : crc32orig;
        final effMethod     = isTarget ? 8             : compMethod;

        final localHeaderOffset = out.length;

        final lh = Uint8List(30 + nameLen + extraLen);
        final lhBd = ByteData.sublistView(lh);
        lhBd.setUint32(0,  0x04034b50, Endian.little);
        lhBd.setUint16(4,  _readU16(pos + 4),  Endian.little);
        lhBd.setUint16(6,  _readU16(pos + 6),  Endian.little);
        lhBd.setUint16(8,  effMethod,           Endian.little);
        lhBd.setUint16(10, _readU16(pos + 10), Endian.little);
        lhBd.setUint16(12, _readU16(pos + 12), Endian.little);
        lhBd.setUint32(14, effCrc,              Endian.little);
        lhBd.setUint32(18, effCompSize,         Endian.little);
        lhBd.setUint32(22, effUncompSize,       Endian.little);
        lhBd.setUint16(26, nameLen,             Endian.little);
        lhBd.setUint16(28, extraLen,            Endian.little);
        lh.setRange(30, 30 + nameLen, zipBytes, pos + 30);
        if (extraLen > 0) {
          lh.setRange(30 + nameLen, 30 + nameLen + extraLen,
              zipBytes, pos + 30 + nameLen);
        }
        out.add(lh);
        out.add(isTarget
            ? newCompressed
            : zipBytes.sublist(dataOffset, dataOffset + compSizeOrig));

        cdEntries.add(_ZipCdEntry(
          newOffset: localHeaderOffset,
          name: name,
          isTarget: isTarget,
          effectiveCrc: effCrc,
          effectiveCompSize: effCompSize,
          effectiveUncompSize: effUncompSize,
          effectiveMethod: effMethod,
        ));
        pos = dataOffset + compSizeOrig;
      } else if (sig == 0x02014b50 || sig == 0x06054b50) {
        break;
      } else {
        break;
      }
    }

    // Central directory
    final cdStart = out.length;
    for (final entry in cdEntries) {
      final origCdPos = _findCdEntry(zipBytes, entry.name);
      if (origCdPos < 0) continue;
      final nameLen     = bd.getUint16(origCdPos + 28, Endian.little);
      final extraLen    = bd.getUint16(origCdPos + 30, Endian.little);
      final cmtLen      = bd.getUint16(origCdPos + 32, Endian.little);
      final cdEntrySize = 46 + nameLen + extraLen + cmtLen;

      final ce   = Uint8List(cdEntrySize);
      final ceBd = ByteData.sublistView(ce);
      ce.setRange(0, cdEntrySize, zipBytes, origCdPos);
      ceBd.setUint16(10, entry.effectiveMethod,     Endian.little);
      ceBd.setUint32(16, entry.effectiveCrc,        Endian.little);
      ceBd.setUint32(20, entry.effectiveCompSize,   Endian.little);
      ceBd.setUint32(24, entry.effectiveUncompSize, Endian.little);
      ceBd.setUint32(42, entry.newOffset,           Endian.little);
      out.add(ce);
    }
    final cdEnd  = out.length;
    final cdSize = cdEnd - cdStart;

    final eocd   = Uint8List(22);
    final eocdBd = ByteData.sublistView(eocd);
    eocdBd.setUint32(0,  0x06054b50,       Endian.little);
    eocdBd.setUint16(4,  0,                Endian.little);
    eocdBd.setUint16(6,  0,                Endian.little);
    eocdBd.setUint16(8,  cdEntries.length, Endian.little);
    eocdBd.setUint16(10, cdEntries.length, Endian.little);
    eocdBd.setUint32(12, cdSize,           Endian.little);
    eocdBd.setUint32(16, cdStart,          Endian.little);
    eocdBd.setUint16(20, 0,                Endian.little);
    out.add(eocd);
    return out.toBytes();
  }

  static int _findCdEntry(Uint8List zipBytes, String name) {
    final bd        = ByteData.sublistView(zipBytes);
    final nameBytes = utf8.encode(name);
    int pos = 0;
    while (pos < zipBytes.length - 4) {
      final sig = bd.getUint32(pos, Endian.little);
      if (sig == 0x02014b50) {
        final nameLen = bd.getUint16(pos + 28, Endian.little);
        if (nameLen == nameBytes.length) {
          bool match = true;
          for (int i = 0; i < nameLen; i++) {
            if (zipBytes[pos + 46 + i] != nameBytes[i]) {
              match = false;
              break;
            }
          }
          if (match) return pos;
        }
        final extraLen = bd.getUint16(pos + 30, Endian.little);
        final cmtLen   = bd.getUint16(pos + 32, Endian.little);
        pos += 46 + nameLen + extraLen + cmtLen;
      } else if (sig == 0x04034b50) {
        final nameLen  = bd.getUint16(pos + 26, Endian.little);
        final extraLen = bd.getUint16(pos + 28, Endian.little);
        final compSize = bd.getUint32(pos + 18, Endian.little);
        pos += 30 + nameLen + extraLen + compSize;
      } else {
        pos++;
      }
    }
    return -1;
  }

  static int _crc32(List<int> data) {
    const poly = 0xEDB88320;
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ poly : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}

class _ZipCdEntry {
  final int    newOffset;
  final String name;
  final bool   isTarget;
  final int    effectiveCrc;
  final int    effectiveCompSize;
  final int    effectiveUncompSize;
  final int    effectiveMethod;

  const _ZipCdEntry({
    required this.newOffset,
    required this.name,
    required this.isTarget,
    required this.effectiveCrc,
    required this.effectiveCompSize,
    required this.effectiveUncompSize,
    required this.effectiveMethod,
  });
}
