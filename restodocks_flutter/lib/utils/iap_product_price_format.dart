import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';

/// Форматирует цену In-App Purchase по [ProductDetails.currencyCode] и [ProductDetails.rawPrice].
///
/// Данные приходят из StoreKit (витрина Apple ID). Язык приложения не используется — чтобы
/// сумма и символ валюты совпадали с регионом учётной записи App Store, а не с локалью UI.
String formatIapPriceForAppleStorefront(ProductDetails product) {
  final code = product.currencyCode.trim().toUpperCase();
  if (code.isEmpty) return product.price;

  final locale = _localeForStorefrontCurrency(code);
  final digits = _fractionDigitsForCurrency(code);

  try {
    return NumberFormat.currency(
      locale: locale,
      name: code,
      decimalDigits: digits,
    ).format(product.rawPrice);
  } catch (_) {
    return product.price;
  }
}

/// Локаль для числового форматирования под типичную витрину валюты (группы разрядов, символ).
String _localeForStorefrontCurrency(String code) {
  switch (code) {
    case 'VND':
      return 'vi';
    case 'RUB':
      return 'ru';
    case 'USD':
      return 'en_US';
    case 'EUR':
      return 'de_DE';
    case 'GBP':
      return 'en_GB';
    case 'JPY':
      return 'ja';
    case 'KRW':
      return 'ko';
    case 'CNY':
      return 'zh_CN';
    case 'UAH':
      return 'uk';
    case 'KZT':
      return 'kk';
    case 'TRY':
      return 'tr';
    case 'PLN':
      return 'pl';
    case 'THB':
      return 'th';
    case 'IDR':
      return 'id';
    case 'MYR':
      return 'ms';
    case 'SGD':
      return 'en_SG';
    case 'AUD':
      return 'en_AU';
    case 'NZD':
      return 'en_NZ';
    case 'BRL':
      return 'pt_BR';
    case 'MXN':
      return 'es_MX';
    case 'INR':
      return 'en_IN';
    case 'AED':
      return 'ar_AE';
    case 'SAR':
      return 'ar_SA';
    case 'ILS':
      return 'he_IL';
    case 'CHF':
      return 'de_CH';
    case 'SEK':
      return 'sv';
    case 'NOK':
      return 'nb';
    case 'DKK':
      return 'da';
    case 'CZK':
      return 'cs';
    case 'HUF':
      return 'hu';
    case 'RON':
      return 'ro';
    case 'BGN':
      return 'bg';
    case 'AMD':
      return 'hy';
    case 'GEL':
      return 'ka';
    case 'AZN':
      return 'az';
    case 'BYN':
      return 'be';
    case 'TMT':
      return 'tk';
    case 'UZS':
      return 'uz';
    case 'KGS':
      return 'ky';
    case 'TJS':
      return 'tg';
    case 'MDL':
      return 'ro_MD';
    case 'ZAR':
      return 'en_ZA';
    case 'EGP':
      return 'ar_EG';
    case 'PHP':
      return 'en_PH';
    case 'CLP':
      return 'es_CL';
    case 'COP':
      return 'es_CO';
    case 'PEN':
      return 'es_PE';
    case 'ARS':
      return 'es_AR';
    default:
      return 'en_US';
  }
}

int _fractionDigitsForCurrency(String code) {
  switch (code) {
    case 'VND':
    case 'JPY':
    case 'KRW':
    case 'CLP':
    case 'ISK':
    case 'UGX':
    case 'VUV':
    case 'XAF':
    case 'XOF':
    case 'HUF':
    case 'IDR':
      return 0;
    default:
      return 2;
  }
}
