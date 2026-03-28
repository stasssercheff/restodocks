/// Ключ локализации подзаголовка для `kitchen` / `bar` / `hall` в URL.
String? posDepartmentLabelKeyForRoute(String? dept) {
  switch (dept) {
    case 'kitchen':
      return 'kitchen';
    case 'bar':
      return 'bar';
    case 'hall':
      return 'dining_room';
    default:
      return null;
  }
}

/// Категории бара — как в [MenuScreen], для разделения строк заказа кухня/бар.
const posBarCategoriesForOrderRouting = {
  'beverages',
  'alcoholic_cocktails',
  'non_alcoholic_drinks',
  'hot_drinks',
  'drinks_pure',
  'snacks',
};

/// Строка относится к «барской» части меню (остальное — кухня/цех в широком смысле).
bool posLineIsBarDish(String category, List<String> sections) {
  return posBarCategoriesForOrderRouting.contains(category) ||
      sections.contains('bar');
}
