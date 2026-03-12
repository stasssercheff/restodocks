/// Детектор шаблона ТТК по координатам ячеек (A1, B3).
/// Берёт первые 20–30 строк и ищет маркеры для iiko, StoreHouse, ГОСТ и др.
class TtkTemplateDetector {
  TtkTemplateDetector._();

  /// A1 → row 0, col 0. B3 → row 2, col 1.
  static ({int row, int col}) _decodeCoords(String coords) {
    final m = RegExp(r'^([A-Z]+)(\d+)$', caseSensitive: false).firstMatch(coords.trim());
    if (m == null) return (row: 0, col: 0);
    var col = 0;
    for (var i = 0; i < (m.group(1) ?? '').length; i++) {
      col = col * 26 + ((m.group(1)!.toUpperCase().codeUnitAt(i)) - 64);
    }
    return (row: (int.tryParse(m.group(2) ?? '1') ?? 1) - 1, col: col - 1);
  }

  /// Сигнатуры: шаблон -> { ячейка: ожидаемое_значение (содержится в) }
  static const Map<String, Map<String, String>> signatures = {
    'iiko_standard': {
      'A2': 'Технико-технологическая карта',
      'A1': 'технологическая карта',
    },
    'iiko_short': {
      'A1': 'Наименование продукта',
      'B1': 'Брутто',
    },
    'storehouse_v4': {
      'E1': 'Калькуляционная карта',
      'B3': 'Номер документа',
    },
    'gost': {
      'B4': 'Утверждаю',
      'A10': 'Наименование',
    },
    'chef_excel_v1': {
      'A1': 'Рецептура',
      'C1': 'Выход',
    },
  };

  /// Определяет шаблон по первым строкам.
  static String detect(List<List<dynamic>> rows, {int maxRows = 30}) {
    for (final entry in signatures.entries) {
      bool matches = true;
      for (final cellEntry in entry.value.entries) {
        final pos = _decodeCoords(cellEntry.key);
        if (pos.row >= rows.length || pos.row < 0) {
          matches = false;
          break;
        }
        final row = rows[pos.row];
        if (row is! List || pos.col >= row.length || pos.col < 0) {
          matches = false;
          break;
        }
        final actual = (row[pos.col] ?? '').toString().trim().toLowerCase();
        final expected = cellEntry.value.toLowerCase();
        if (!actual.contains(expected)) {
          matches = false;
          break;
        }
      }
      if (matches) return entry.key;
    }
    return 'unknown';
  }
}
