/// Семейные совпадения для ингредиентов ТТК, когда строка из iiko не совпадает
/// побуквенно с карточкой в номенклатуре («тростниковый песок» vs «Сахар тростниковый»).

/// Заменители сахара — не смешиваем с обычным сахаром.
bool _isSugarSubstituteQuery(String lower) {
  return lower.contains('заменит') ||
      lower.contains('substitute') ||
      lower.contains('stevia') ||
      lower.contains('стев') ||
      lower.contains('сахарин') ||
      lower.contains('saccharin') ||
      lower.contains('ксилит') ||
      lower.contains('xylitol') ||
      lower.contains('эритрит') ||
      lower.contains('erythritol') ||
      lower.contains('аспартам') ||
      lower.contains('aspartame') ||
      lower.contains('сукралоз') ||
      lower.contains('sucralose');
}

/// Запрос похож на сахар (песок, пудра, тростник, коричневый и т.д.).
bool isSugarFamilySearchString(String normalizedLower) {
  final l = normalizedLower.trim();
  if (l.isEmpty) return false;
  if (_isSugarSubstituteQuery(l)) return false;
  if (l.contains('сахар') || l.contains('sugar')) return true;
  if (l.contains('тростник')) return true;
  if (l.contains('сахарн')) return true;
  if (l.contains('пудра') &&
      (l.contains('сахар') ||
          l.contains('sugar') ||
          l.contains('icing') ||
          l.contains('айсинг'))) {
    return true;
  }
  if (l.contains('demerara') ||
      l.contains('muscovado') ||
      l.contains('мусковад')) {
    return true;
  }
  return false;
}

bool _productNameBlobContainsSugarFamily(String blobLower) {
  if (blobLower.isEmpty) return false;
  return blobLower.contains('сахар') ||
      blobLower.contains('sugar') ||
      blobLower.contains('тростник') ||
      blobLower.contains('сахарн') ||
      blobLower.contains('demerara') ||
      blobLower.contains('muscovado') ||
      blobLower.contains('мусковад');
}

/// Карточка номенклатуры относится к «семье сахара» (не сиропы не-сахарные).
bool isSugarFamilyProductNameBlob(String nameLower, Iterable<String> extraNamesLower) {
  final blob = [nameLower, ...extraNamesLower].join(' ');
  if (blob.isEmpty) return false;
  if (_isSugarSubstituteQuery(blob)) return false;
  if (!_productNameBlobContainsSugarFamily(blob)) return false;
  if (blob.contains('сироп') &&
      !blob.contains('сахар') &&
      !blob.contains('sugar') &&
      !blob.contains('глюкоз') &&
      !blob.contains('glucose') &&
      !blob.contains('тростник')) {
    return false;
  }
  return true;
}

/// Сколько значимых токенов из запроса встречается в названии продукта (для ранжирования).
int sugarQueryOverlapScore(String searchLower, String productBlobLower) {
  var score = 0;
  for (final w in searchLower.split(RegExp(r'\s+')).where((s) => s.length > 2)) {
    if (productBlobLower.contains(w)) score += 2;
  }
  return score;
}
