import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;
import 'package:vision_text_recognition/vision_text_recognition.dart' as vision;

bool _overlapY(double y1, double h1, double y2, double h2) {
  final b1 = y1 + h1;
  final b2 = y2 + h2;
  return !(b1 < y2 || b2 < y1);
}

/// Собирает строку в порядке чтения (сверху вниз, слева направо), с табами между
/// далёкими по горизонтали фрагментами — ближе к колонкам таблицы ТТК.
String layoutFromVisionBlocks(
  List<vision.TextBlock> blocks, {
  double colGapNormalized = 0.022,
}) {
  final items = blocks
      .map((b) => (
            text: b.normalizedText,
            x: b.boundingBox.x,
            y: b.boundingBox.y,
            w: b.boundingBox.width,
            h: b.boundingBox.height,
          ))
      .where((e) => e.text.isNotEmpty)
      .toList();
  if (items.isEmpty) return '';

  final rows = <List<({String text, double x, double y, double w, double h})>>[];
  for (final b in items) {
    var placed = false;
    for (final row in rows) {
      final ref = row.first;
      if (_overlapY(b.y, b.h, ref.y, ref.h)) {
        row.add(b);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([b]);
  }

  rows.sort((a, b) => a.first.y.compareTo(b.first.y));
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
  }

  final lines = <String>[];
  for (final row in rows) {
    final parts = <String>[];
    for (var i = 0; i < row.length; i++) {
      if (i > 0) {
        final prev = row[i - 1];
        final cur = row[i];
        final gap = cur.x - (prev.x + prev.w);
        parts.add(gap > colGapNormalized ? '\t' : ' ');
      }
      parts.add(row[i].text);
    }
    lines.add(parts.join());
  }
  return lines.join('\n');
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// То же для ML Kit (Android / fallback iOS): координаты в пикселях.
String layoutFromMlKitRecognizedText(mlkit.RecognizedText text) {
  final lines = <mlkit.TextLine>[];
  for (final block in text.blocks) {
    lines.addAll(block.lines);
  }
  if (lines.isEmpty) return text.text.trim();

  final items = <({String text, double x, double y, double w, double h})>[];
  for (final line in lines) {
    final r = line.boundingBox;
    final t = line.text.trim();
    if (t.isEmpty) continue;
    items.add((
      text: t,
      x: r.left,
      y: r.top,
      w: r.width,
      h: r.height,
    ));
  }
  if (items.isEmpty) return text.text.trim();

  final medianH = _median(items.map((e) => e.h).toList());
  final colGapPx = math.max(12.0, medianH * 0.9);

  final rows = <List<({String text, double x, double y, double w, double h})>>[];
  for (final b in items) {
    var placed = false;
    for (final row in rows) {
      final ref = row.first;
      if (_overlapY(b.y, b.h, ref.y, ref.h)) {
        row.add(b);
        placed = true;
        break;
      }
    }
    if (!placed) rows.add([b]);
  }

  rows.sort((a, b) => a.first.y.compareTo(b.first.y));
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
  }

  final out = <String>[];
  for (final row in rows) {
    final parts = <String>[];
    for (var i = 0; i < row.length; i++) {
      if (i > 0) {
        final prev = row[i - 1];
        final cur = row[i];
        final gap = cur.x - (prev.x + prev.w);
        parts.add(gap > colGapPx ? '\t' : ' ');
      }
      parts.add(row[i].text);
    }
    out.add(parts.join());
  }
  return out.join('\n');
}
