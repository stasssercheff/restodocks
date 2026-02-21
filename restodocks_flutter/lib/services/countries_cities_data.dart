import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Элемент списка стран: code + названия на 5 языках
class CountryItem {
  final String code;
  final String ru;
  final String en;
  final String es;
  final String de;
  final String fr;

  CountryItem({
    required this.code,
    required this.ru,
    required this.en,
    required this.es,
    required this.de,
    required this.fr,
  });

  String name(String lang) {
    switch (lang) {
      case 'ru': return ru;
      case 'en': return en;
      case 'es': return es;
      case 'de': return de;
      case 'fr': return fr;
      default: return en;
    }
  }
}

/// Элемент списка городов: id + названия на 5 языках
class CityItem {
  final String id;
  final String ru;
  final String en;
  final String es;
  final String de;
  final String fr;

  CityItem({
    required this.id,
    required this.ru,
    required this.en,
    required this.es,
    required this.de,
    required this.fr,
  });

  String name(String lang) {
    switch (lang) {
      case 'ru': return ru;
      case 'en': return en;
      case 'es': return es;
      case 'de': return de;
      case 'fr': return fr;
      default: return en;
    }
  }
}

/// Загрузка и кэш стран/городов из assets/data
class CountriesCitiesData {
  static List<CountryItem>? _countries;
  static Map<String, List<CityItem>>? _citiesByCountry;

  static Future<List<CountryItem>> loadCountries() async {
    if (_countries != null) return _countries!;
    final raw = await rootBundle.loadString('assets/data/countries.json');
    final list = jsonDecode(raw) as List<dynamic>;
    _countries = list.map((e) {
      final m = e as Map<String, dynamic>;
      return CountryItem(
        code: m['code']! as String,
        ru: m['ru']! as String,
        en: m['en']! as String,
        es: m['es']! as String,
        de: m['de']! as String,
        fr: m['fr']! as String,
      );
    }).toList();
    return _countries!;
  }

  static Future<Map<String, List<CityItem>>> loadCities() async {
    if (_citiesByCountry != null) return _citiesByCountry!;
    final raw = await rootBundle.loadString('assets/data/cities.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    _citiesByCountry = {};
    for (final e in map.entries) {
      final list = (e.value as List<dynamic>).map((c) {
        final m = c as Map<String, dynamic>;
        return CityItem(
          id: m['id']! as String,
          ru: m['ru']! as String,
          en: m['en']! as String,
          es: m['es']! as String,
          de: m['de']! as String,
          fr: m['fr']! as String,
        );
      }).toList();
      _citiesByCountry![e.key] = list;
    }
    return _citiesByCountry!;
  }

  static Future<List<CityItem>> citiesForCountry(String countryCode) async {
    final all = await loadCities();
    return all[countryCode] ?? [];
  }
}
