import 'package:intl/intl.dart';

/// Форматирование чисел с разделителем тысяч (пробел).
/// Используется для отображения сумм, цен, ставок и т.п.
class NumberFormatUtils {
  static final _formatInt = NumberFormat('#,##0', 'ru_RU');
  static final _formatDecimal = NumberFormat('#,##0.##', 'ru_RU');

  /// Форматирует целое или число без дробной части (суммы в VND и т.п.)
  static String formatInt(num value) {
    return _formatInt.format(value.round()).replaceAll('\u00A0', ' ');
  }

  /// Форматирует число с возможными десятичными знаками
  static String formatDecimal(num value) {
    return _formatDecimal.format(value).replaceAll('\u00A0', ' ');
  }

  /// Форматирует сумму с учётом валюты: для VND/JPY/KRW — без десятичных, иначе — с ними
  static String formatSum(num value, String currency) {
    final noDecimals = {'VND', 'JPY', 'KRW'}.contains((currency).toUpperCase());
    return noDecimals ? formatInt(value) : formatDecimal(value);
  }
}
