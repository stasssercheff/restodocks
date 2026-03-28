import '../models/nomenclature_item.dart';
import 'product_name_utils.dart';

/// Union–Find для кластеризации индексов.
class _UnionFind {
  _UnionFind(int n) : _p = List.generate(n, (i) => i);
  final List<int> _p;

  int find(int i) {
    while (_p[i] != i) {
      _p[i] = _p[_p[i]];
      i = _p[i];
    }
    return i;
  }

  void union(int a, int b) {
    a = find(a);
    b = find(b);
    if (a != b) _p[b] = a;
  }
}

/// Схожесть строк 0..1 (длина Левенштейна к более длинной строке).
double nomenclatureNameSimilarity(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final longer = a.length > b.length ? a : b;
  final shorter = a.length > b.length ? b : a;
  final d = _levenshtein(longer, shorter);
  return (longer.length - d) / longer.length;
}

int _levenshtein(String a, String b) {
  final matrix = List.generate(
    a.length + 1,
    (i) => List.generate(b.length + 1, (j) => 0),
  );
  for (var i = 0; i <= a.length; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    matrix[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
  }
  return matrix[a.length][b.length];
}

/// Группы дубликатов по номенклатуре: сначала одинаковый [normalizeProductAliasKey],
/// затем пары с схожестью ≥ [fuzzyThreshold] (без ИИ).
///
/// При [productItems.length] > [maxItemsForFuzzy] fuzzy-шаг пропускается (слишком тяжёлый O(n²)).
List<List<NomenclatureItem>> buildNomenclatureDuplicateGroups({
  required List<NomenclatureItem> productItems,
  required String languageCode,
  double fuzzyThreshold = 0.86,
  int maxItemsForFuzzy = 1400,
}) {
  if (productItems.length < 2) return [];

  final n = productItems.length;
  final labels = List<String>.generate(n, (i) {
    final it = productItems[i];
    return normalizeProductAliasKey(it.getLocalizedName(languageCode));
  });

  final uf = _UnionFind(n);

  final byLabel = <String, List<int>>{};
  for (var i = 0; i < n; i++) {
    final L = labels[i];
    if (L.isEmpty) continue;
    byLabel.putIfAbsent(L, () => []).add(i);
  }
  for (final list in byLabel.values) {
    for (var k = 1; k < list.length; k++) {
      uf.union(list[0], list[k]);
    }
  }

  if (n <= maxItemsForFuzzy) {
    for (var i = 0; i < n; i++) {
      if (labels[i].isEmpty) continue;
      for (var j = i + 1; j < n; j++) {
        if (labels[j].isEmpty) continue;
        if (uf.find(i) == uf.find(j)) continue;
        final sim = nomenclatureNameSimilarity(labels[i], labels[j]);
        if (sim >= fuzzyThreshold) {
          uf.union(i, j);
        }
      }
    }
  }

  final rootToIndices = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    final r = uf.find(i);
    rootToIndices.putIfAbsent(r, () => []).add(i);
  }

  final out = rootToIndices.values
      .where((ix) => ix.length >= 2)
      .map((ix) => ix.map((i) => productItems[i]).toList())
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return out;
}
