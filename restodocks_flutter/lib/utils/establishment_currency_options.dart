/// Единый список валют заведения (настройки, номенклатура, импорт).
abstract final class EstablishmentCurrencyOptions {
  const EstablishmentCurrencyOptions._();

  static const List<Map<String, String>> all = [
    {'code': 'RUB', 'symbol': '₽', 'name': 'Российский рубль'},
    {'code': 'USD', 'symbol': r'$', 'name': 'Доллар США'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Евро'},
    {'code': 'GBP', 'symbol': '£', 'name': 'Фунт стерлингов'},
    {'code': 'CHF', 'symbol': 'Fr', 'name': 'Швейцарский франк'},
    {'code': 'JPY', 'symbol': '¥', 'name': 'Японская иена'},
    {'code': 'CNY', 'symbol': '¥', 'name': 'Китайский юань'},
    {'code': 'VND', 'symbol': '₫', 'name': 'Вьетнамский донг'},
    {'code': 'KZT', 'symbol': '₸', 'name': 'Казахстанский тенге'},
    {'code': 'UAH', 'symbol': '₴', 'name': 'Украинская гривна'},
    {'code': 'BYN', 'symbol': 'Br', 'name': 'Белорусский рубль'},
    {'code': 'PLN', 'symbol': 'zł', 'name': 'Польский злотый'},
    {'code': 'CZK', 'symbol': 'Kč', 'name': 'Чешская крона'},
    {'code': 'TRY', 'symbol': '₺', 'name': 'Турецкая лира'},
    {'code': 'INR', 'symbol': '₹', 'name': 'Индийская рупия'},
    {'code': 'BRL', 'symbol': r'R$', 'name': 'Бразильский реал'},
    {'code': 'MXN', 'symbol': r'$', 'name': 'Мексиканское песо'},
    {'code': 'KRW', 'symbol': '₩', 'name': 'Южнокорейская вона'},
    {'code': 'SGD', 'symbol': r'S$', 'name': 'Сингапурский доллар'},
    {'code': 'HKD', 'symbol': r'HK$', 'name': 'Гонконгский доллар'},
    {'code': 'THB', 'symbol': '฿', 'name': 'Тайский бат'},
    {'code': 'CAD', 'symbol': r'C$', 'name': 'Канадский доллар'},
    {'code': 'AUD', 'symbol': r'A$', 'name': 'Австралийский доллар'},
    {'code': 'SEK', 'symbol': 'kr', 'name': 'Шведская крона'},
    {'code': 'NOK', 'symbol': 'kr', 'name': 'Норвежская крона'},
    {'code': 'DKK', 'symbol': 'kr', 'name': 'Датская крона'},
    {'code': 'IDR', 'symbol': 'Rp', 'name': 'Индонезийская рупия'},
    {'code': 'PHP', 'symbol': '₱', 'name': 'Филиппинское песо'},
    {'code': 'MYR', 'symbol': 'RM', 'name': 'Малайзийский ринггит'},
    {'code': 'AED', 'symbol': 'د.إ', 'name': 'Дирхам ОАЭ'},
    {'code': 'SAR', 'symbol': '﷼', 'name': 'Саудовский риал'},
    {'code': 'ILS', 'symbol': '₪', 'name': 'Израильский шекель'},
    {'code': 'EGP', 'symbol': 'E£', 'name': 'Египетский фунт'},
    {'code': 'ZAR', 'symbol': 'R', 'name': 'Южноафриканский рэнд'},
    {'code': 'NGN', 'symbol': '₦', 'name': 'Нигерийская найра'},
    {'code': 'GEL', 'symbol': '₾', 'name': 'Грузинский лари'},
    {'code': 'AMD', 'symbol': '֏', 'name': 'Армянский драм'},
    {'code': 'AZN', 'symbol': '₼', 'name': 'Азербайджанский манат'},
    {'code': 'UZS', 'symbol': 'soʻm', 'name': 'Узбекский сум'},
  ];

  static bool isKnownPreset(String code) =>
      all.any((c) => c['code'] == code.toUpperCase());
}
