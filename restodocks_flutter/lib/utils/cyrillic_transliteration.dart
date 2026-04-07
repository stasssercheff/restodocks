/// Транслитерация кириллицы в латиницу (для отображения ФИО в нерусском UI).
String transliterateRuToLatin(String input) {
  if (input.isEmpty) return input;
  final sb = StringBuffer();
  for (final unit in input.runes) {
    final ch = String.fromCharCode(unit);
    sb.write(_singleCharMap[ch] ?? ch);
  }
  return sb.toString();
}

/// Best-effort обратная транслитерация латиницы в кириллицу для русской локали UI.
/// Используется только для отображения имен, когда в базе латиница.
String transliterateLatinToRuBestEffort(String input) {
  if (input.isEmpty) return input;
  final out = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final rest = input.substring(i);
    String? mapped;
    var step = 1;
    for (final n in const [4, 3, 2]) {
      if (i + n > input.length) continue;
      final chunk = input.substring(i, i + n);
      mapped = _latinDigraphMap[chunk.toLowerCase()];
      if (mapped != null) {
        if (chunk[0].toUpperCase() == chunk[0]) {
          mapped = mapped[0].toUpperCase() + mapped.substring(1);
        }
        step = n;
        break;
      }
    }
    mapped ??= _latinSingleMap[rest[0].toLowerCase()] ?? rest[0];
    if (step == 1 && rest[0].toUpperCase() == rest[0] && mapped.length == 1) {
      mapped = mapped.toUpperCase();
    }
    out.write(mapped);
    i += step;
  }
  return out.toString();
}

/// Карта по ГОСТ 7.79-2000 (система B, упрощённо).
const Map<String, String> _singleCharMap = {
  'А': 'A',
  'а': 'a',
  'Б': 'B',
  'б': 'b',
  'В': 'V',
  'в': 'v',
  'Г': 'G',
  'г': 'g',
  'Д': 'D',
  'д': 'd',
  'Е': 'E',
  'е': 'e',
  'Ё': 'Yo',
  'ё': 'yo',
  'Ж': 'Zh',
  'ж': 'zh',
  'З': 'Z',
  'з': 'z',
  'И': 'I',
  'и': 'i',
  'Й': 'Y',
  'й': 'y',
  'К': 'K',
  'к': 'k',
  'Л': 'L',
  'л': 'l',
  'М': 'M',
  'м': 'm',
  'Н': 'N',
  'н': 'n',
  'О': 'O',
  'о': 'o',
  'П': 'P',
  'п': 'p',
  'Р': 'R',
  'р': 'r',
  'С': 'S',
  'с': 's',
  'Т': 'T',
  'т': 't',
  'У': 'U',
  'у': 'u',
  'Ф': 'F',
  'ф': 'f',
  'Х': 'Kh',
  'х': 'kh',
  'Ц': 'Ts',
  'ц': 'ts',
  'Ч': 'Ch',
  'ч': 'ch',
  'Ш': 'Sh',
  'ш': 'sh',
  'Щ': 'Shch',
  'щ': 'shch',
  'Ъ': '',
  'ъ': '',
  'Ы': 'Y',
  'ы': 'y',
  'Ь': '',
  'ь': '',
  'Э': 'E',
  'э': 'e',
  'Ю': 'Yu',
  'ю': 'yu',
  'Я': 'Ya',
  'я': 'ya',
};

const Map<String, String> _latinDigraphMap = {
  'shch': 'щ',
  'yo': 'ё',
  'zh': 'ж',
  'kh': 'х',
  'ts': 'ц',
  'ch': 'ч',
  'sh': 'ш',
  'yu': 'ю',
  'ya': 'я',
  'ye': 'е',
};

const Map<String, String> _latinSingleMap = {
  'a': 'а',
  'b': 'б',
  'v': 'в',
  'g': 'г',
  'd': 'д',
  'e': 'е',
  'z': 'з',
  'i': 'и',
  'y': 'й',
  'k': 'к',
  'l': 'л',
  'm': 'м',
  'n': 'н',
  'o': 'о',
  'p': 'п',
  'r': 'р',
  's': 'с',
  't': 'т',
  'u': 'у',
  'f': 'ф',
  'h': 'х',
  'c': 'к',
  'j': 'дж',
  'q': 'к',
  'w': 'в',
  'x': 'кс',
};
