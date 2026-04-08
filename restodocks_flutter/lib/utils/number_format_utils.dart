import 'package:intl/intl.dart';

/// Форматирование чисел с разделителем тысяч (пробел).
/// Используется для отображения сумм, цен, ставок и т.п.
class NumberFormatUtils {
  static final _formatInt = NumberFormat('#,##0', 'ru_RU');
  static final _formatDecimal = NumberFormat('#,##0.##', 'ru_RU');

  /// ISO 4217: валюты без денежных единиц меньше основной (как правило — без «копеек» в UI).
  static const Set<String> _zeroMinorUnitCodes = {
    'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'LAK',
    'MGA', 'PYG', 'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
    'IDR',
  };

  /// [currencySymbol] — запасной признак, если код в БД нестандартный (например только «₫»).
  static bool isZeroDecimalCurrency(String currencyCode,
      [String? currencySymbol]) {
    final c = currencyCode.trim().toUpperCase();
    if (c.length == 3 && _zeroMinorUnitCodes.contains(c)) return true;
    final sym = currencySymbol ?? '';
    if (sym == '₫' || sym == '\u20ab') return true;
    if (sym == '₩') return true;
    return false;
  }

  /// Форматирует целое или число без дробной части (суммы в VND и т.п.)
  static String formatInt(num value) {
    return _formatInt.format(value.round()).replaceAll('\u00A0', ' ');
  }

  /// Для валют без копеек: округление вверх, затем разделитель тысяч.
  static String formatIntCeil(num value) {
    if (value.isNaN) return _formatInt.format(0).replaceAll('\u00A0', ' ');
    return _formatInt.format(value.ceil()).replaceAll('\u00A0', ' ');
  }

  /// Форматирует число с возможными десятичными знаками
  static String formatDecimal(num value) {
    return _formatDecimal.format(value).replaceAll('\u00A0', ' ');
  }

  /// Форматирует сумму с учётом валюты: для VND/JPY/KRW и др. — без десятичных (округление вверх), иначе — с ними.
  static String formatSum(num value, String currency,
      [String? currencySymbol]) {
    return isZeroDecimalCurrency(currency, currencySymbol)
        ? formatIntCeil(value)
        : formatDecimal(value);
  }

  /// Число + символ (удобно для подписей цен).
  static String formatSumWithSymbol(num value, String currencyCode,
      String currencySymbol) {
    return '${formatSum(value, currencyCode, currencySymbol)} $currencySymbol';
  }
}
