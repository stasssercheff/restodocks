/// Единый список валют заведения (настройки, номенклатура, импорт).
/// [country] — для поиска по стране (русское название + латиница в [search]).
abstract final class EstablishmentCurrencyOptions {
  const EstablishmentCurrencyOptions._();

  static const List<Map<String, String>> all = [
    {
      'code': 'RUB',
      'symbol': '₽',
      'name': 'Российский рубль',
      'country': 'Россия',
      'search': 'russia россия rub'
    },
    {
      'code': 'USD',
      'symbol': r'$',
      'name': 'Доллар США',
      'country': 'США',
      'search': 'usa united states america доллар usd'
    },
    {
      'code': 'EUR',
      'symbol': '€',
      'name': 'Евро',
      'country': 'Еврозона',
      'search': 'euro europe eu евро'
    },
    {
      'code': 'GBP',
      'symbol': '£',
      'name': 'Фунт стерлингов',
      'country': 'Великобритания',
      'search': 'uk britain england gbp pound'
    },
    {
      'code': 'CHF',
      'symbol': 'Fr',
      'name': 'Швейцарский франк',
      'country': 'Швейцария',
      'search': 'switzerland chf'
    },
    {
      'code': 'JPY',
      'symbol': '¥',
      'name': 'Японская иена',
      'country': 'Япония',
      'search': 'japan jpy yen'
    },
    {
      'code': 'CNY',
      'symbol': '¥',
      'name': 'Китайский юань',
      'country': 'Китай',
      'search': 'china cny yuan renminbi'
    },
    {
      'code': 'VND',
      'symbol': '₫',
      'name': 'Вьетнамский донг',
      'country': 'Вьетнам',
      'search': 'vietnam viet nam vnd dong'
    },
    {
      'code': 'KZT',
      'symbol': '₸',
      'name': 'Казахстанский тенге',
      'country': 'Казахстан',
      'search': 'kazakhstan kzt'
    },
    {
      'code': 'UAH',
      'symbol': '₴',
      'name': 'Украинская гривна',
      'country': 'Украина',
      'search': 'ukraine uah'
    },
    {
      'code': 'BYN',
      'symbol': 'Br',
      'name': 'Белорусский рубль',
      'country': 'Беларусь',
      'search': 'belarus byn'
    },
    {
      'code': 'PLN',
      'symbol': 'zł',
      'name': 'Польский злотый',
      'country': 'Польша',
      'search': 'poland pln'
    },
    {
      'code': 'CZK',
      'symbol': 'Kč',
      'name': 'Чешская крона',
      'country': 'Чехия',
      'search': 'czech czk'
    },
    {
      'code': 'TRY',
      'symbol': '₺',
      'name': 'Турецкая лира',
      'country': 'Турция',
      'search': 'turkey turkiye try'
    },
    {
      'code': 'INR',
      'symbol': '₹',
      'name': 'Индийская рупия',
      'country': 'Индия',
      'search': 'india inr'
    },
    {
      'code': 'BRL',
      'symbol': r'R$',
      'name': 'Бразильский реал',
      'country': 'Бразилия',
      'search': 'brazil brl'
    },
    {
      'code': 'MXN',
      'symbol': r'$',
      'name': 'Мексиканское песо',
      'country': 'Мексика',
      'search': 'mexico mxn'
    },
    {
      'code': 'KRW',
      'symbol': '₩',
      'name': 'Южнокорейская вона',
      'country': 'Южная Корея',
      'search': 'korea south krw won'
    },
    {
      'code': 'SGD',
      'symbol': r'S$',
      'name': 'Сингапурский доллар',
      'country': 'Сингапур',
      'search': 'singapore sgd'
    },
    {
      'code': 'HKD',
      'symbol': r'HK$',
      'name': 'Гонконгский доллар',
      'country': 'Гонконг',
      'search': 'hong kong hkd'
    },
    {
      'code': 'THB',
      'symbol': '฿',
      'name': 'Тайский бат',
      'country': 'Таиланд',
      'search': 'thailand thb baht'
    },
    {
      'code': 'CAD',
      'symbol': r'C$',
      'name': 'Канадский доллар',
      'country': 'Канада',
      'search': 'canada cad'
    },
    {
      'code': 'AUD',
      'symbol': r'A$',
      'name': 'Австралийский доллар',
      'country': 'Австралия',
      'search': 'australia aud'
    },
    {
      'code': 'SEK',
      'symbol': 'kr',
      'name': 'Шведская крона',
      'country': 'Швеция',
      'search': 'sweden sek'
    },
    {
      'code': 'NOK',
      'symbol': 'kr',
      'name': 'Норвежская крона',
      'country': 'Норвегия',
      'search': 'norway nok'
    },
    {
      'code': 'DKK',
      'symbol': 'kr',
      'name': 'Датская крона',
      'country': 'Дания',
      'search': 'denmark dkk'
    },
    {
      'code': 'IDR',
      'symbol': 'Rp',
      'name': 'Индонезийская рупия',
      'country': 'Индонезия',
      'search': 'indonesia idr'
    },
    {
      'code': 'PHP',
      'symbol': '₱',
      'name': 'Филиппинское песо',
      'country': 'Филиппины',
      'search': 'philippines php'
    },
    {
      'code': 'MYR',
      'symbol': 'RM',
      'name': 'Малайзийский ринггит',
      'country': 'Малайзия',
      'search': 'malaysia myr'
    },
    {
      'code': 'AED',
      'symbol': 'د.إ',
      'name': 'Дирхам ОАЭ',
      'country': 'ОАЭ',
      'search': 'uae emirates dubai aed'
    },
    {
      'code': 'SAR',
      'symbol': '﷼',
      'name': 'Саудовский риал',
      'country': 'Саудовская Аравия',
      'search': 'saudi arabia sar'
    },
    {
      'code': 'ILS',
      'symbol': '₪',
      'name': 'Израильский шекель',
      'country': 'Израиль',
      'search': 'israel ils shekel'
    },
    {
      'code': 'EGP',
      'symbol': 'E£',
      'name': 'Египетский фунт',
      'country': 'Египет',
      'search': 'egypt egp'
    },
    {
      'code': 'ZAR',
      'symbol': 'R',
      'name': 'Южноафриканский рэнд',
      'country': 'ЮАР',
      'search': 'south africa zar'
    },
    {
      'code': 'NGN',
      'symbol': '₦',
      'name': 'Нигерийская найра',
      'country': 'Нигерия',
      'search': 'nigeria ngn'
    },
    {
      'code': 'GEL',
      'symbol': '₾',
      'name': 'Грузинский лари',
      'country': 'Грузия',
      'search': 'georgia gel'
    },
    {
      'code': 'AMD',
      'symbol': '֏',
      'name': 'Армянский драм',
      'country': 'Армения',
      'search': 'armenia amd'
    },
    {
      'code': 'AZN',
      'symbol': '₼',
      'name': 'Азербайджанский манат',
      'country': 'Азербайджан',
      'search': 'azerbaijan azn'
    },
    {
      'code': 'UZS',
      'symbol': 'soʻm',
      'name': 'Узбекский сум',
      'country': 'Узбекистан',
      'search': 'uzbekistan uzs'
    },
  ];

  static bool isKnownPreset(String code) =>
      all.any((c) => c['code'] == code.toUpperCase());

  /// Пресет из списка или `null` для произвольного трёхбуквенного кода.
  static Map<String, String>? presetForCode(String code) {
    final u = code.toUpperCase();
    for (final c in all) {
      if (c['code'] == u) return c;
    }
    return null;
  }

  /// Фильтр по коду, названию валюты, стране и полю search (латиница).
  static List<Map<String, String>> filterPresets(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<Map<String, String>>.from(all);
    return all.where((c) {
      final code = c['code']!.toLowerCase();
      final name = c['name']!.toLowerCase();
      final country = (c['country'] ?? '').toLowerCase();
      final search = (c['search'] ?? '').toLowerCase();
      return code.contains(q) ||
          name.contains(q) ||
          country.contains(q) ||
          search.contains(q);
    }).toList();
  }
}
