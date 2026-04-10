import 'ai_service.dart';

/// Разбор текста с чека без LLM: эвристики по строкам (название + количество).
class ReceiptTextHeuristicParser {
  static final _skipLine = RegExp(
    r'^(итого|всего|сумма|ндс|налог|оплата|сдача|фн|фд|рн|ккт|кассир|дата|время|чек|receipt|total|tax)\b',
    caseSensitive: false,
  );

  static List<ReceiptLine> parse(String text) {
    final out = <ReceiptLine>[];
    final seen = <String>{};
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      var line = raw.trim();
      if (line.length < 2) continue;
      if (_skipLine.hasMatch(line)) continue;
      if (RegExp(r'^\d{10,}$').hasMatch(line.replaceAll(RegExp(r'\s'), ''))) {
        continue;
      }

      ReceiptLine? parsed;
      final tabParts = line.split(RegExp(r'\t+'));
      if (tabParts.length >= 2) {
        parsed = _fromNameAndTail(
          tabParts.first.trim(),
          tabParts.sublist(1).join(' ').trim(),
        );
      }
      parsed ??= _fromSpacedLine(line);
      if (parsed == null) continue;
      final key = parsed.productName.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(parsed);
    }
    return out;
  }

  static ReceiptLine? _fromSpacedLine(String line) {
    final re = RegExp(
      r'^(.+?)[\s]{2,}([\d]+[.,]?\d*)\s*(шт|кг|г|л|мл|pcs|kg|g|l|ml)?\s*$',
      caseSensitive: false,
    );
    final m = re.firstMatch(line);
    if (m != null) {
      return _fromNameAndTail(m.group(1)!, '${m.group(2)} ${m.group(3) ?? ''}');
    }
    final tailNum = RegExp(
      r'^(.+?)\s+([\d]+[.,]?\d*)\s*(шт|кг|г|л|мл)?\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (tailNum != null) {
      return _fromNameAndTail(
        tailNum.group(1)!,
        '${tailNum.group(2)} ${tailNum.group(3) ?? ''}',
      );
    }
    return null;
  }

  static ReceiptLine? _fromNameAndTail(String nameRaw, String tail) {
    var name = nameRaw.trim();
    if (name.length < 2) return null;
    if (_isMostlyDigits(name)) return null;
    name = name.replaceAll(RegExp(r'^[Тт]\.?\s*'), '').trim();
    if (name.length < 2) return null;

    final qty = _parseQuantity(tail);
    final unit = _guessUnit('$name $tail');
    return ReceiptLine(
      productName: name,
      quantity: qty ?? 1.0,
      unit: unit,
      price: _parsePrice(tail),
    );
  }

  static bool _isMostlyDigits(String s) {
    final digits = s.replaceAll(RegExp(r'[^\d]'), '').length;
    return digits > s.length * 0.6;
  }

  static double? _parseQuantity(String tail) {
    final m = RegExp(r'([\d]+[.,]?\d*)').firstMatch(tail);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', '.'));
  }

  static double? _parsePrice(String tail) {
    final prices = RegExp(r'([\d]+[.,]\d{2})\b').allMatches(tail);
    double? best;
    for (final m in prices) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      if (v != null && v > 0) best = v;
    }
    return best;
  }

  static String? _guessUnit(String s) {
    final low = s.toLowerCase();
    if (low.contains('шт')) return 'pcs';
    if (low.contains('кг')) return 'kg';
    if (RegExp(r'\bг\b').hasMatch(low) || low.contains(' г ')) return 'g';
    if (low.contains('мл')) return 'ml';
    if (RegExp(r'\bл\b').hasMatch(low) || low.contains(' л ')) return 'l';
    return 'g';
  }
}
