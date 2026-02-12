import 'dart:typed_data';
import 'dart:html' as html;
import 'package:excel/excel.dart' hide Border;
import '../models/models.dart';

/// Сервис для экспорта технологических карт в Excel файлы
class ExcelExportService {
  static final ExcelExportService _instance = ExcelExportService._internal();
  factory ExcelExportService() => _instance;
  ExcelExportService._internal();

  /// Экспорт одной технологической карты
  Future<void> exportSingleTechCard(TechCard techCard) async {
    final excel = Excel.createExcel();
    final sheet = excel['Технологическая карта'];

    // Заголовок
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Технологическая карта');
    sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Название:');
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
    sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Тип:');
    sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
    sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Категория:');
    sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));

    // Технология приготовления
    final technology = techCard.technologyLocalized?['ru'] ?? '';
    if (technology.isNotEmpty) {
      sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Технология приготовления:');
      sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
    }

    // Заголовки таблицы ингредиентов
    int rowIndex = technology.isNotEmpty ? 9 : 6;
    sheet.cell(CellIndex.indexByString('A${rowIndex}')).value = TextCellValue('Продукт');
    sheet.cell(CellIndex.indexByString('B${rowIndex}')).value = TextCellValue('Брутто (г)');
    sheet.cell(CellIndex.indexByString('C${rowIndex}')).value = TextCellValue('Отход (%)');
    sheet.cell(CellIndex.indexByString('D${rowIndex}')).value = TextCellValue('Нетто (г)');
    sheet.cell(CellIndex.indexByString('E${rowIndex}')).value = TextCellValue('Способ приготовления');
    sheet.cell(CellIndex.indexByString('F${rowIndex}')).value = TextCellValue('Ужарка (%)');
    sheet.cell(CellIndex.indexByString('G${rowIndex}')).value = TextCellValue('Выход (г)');
    sheet.cell(CellIndex.indexByString('H${rowIndex}')).value = TextCellValue('Стоимость');
    sheet.cell(CellIndex.indexByString('I${rowIndex}')).value = TextCellValue('Цена за кг');

    // Данные ингредиентов
    for (int i = 0; i < techCard.ingredients.length; i++) {
      final ingredient = techCard.ingredients[i];
      final currentRow = rowIndex + i + 1;

      sheet.cell(CellIndex.indexByString('A$currentRow')).value = TextCellValue(ingredient.productName);
      sheet.cell(CellIndex.indexByString('B$currentRow')).value = DoubleCellValue(ingredient.grossWeight);
      sheet.cell(CellIndex.indexByString('C$currentRow')).value = DoubleCellValue(ingredient.primaryWastePct);
      sheet.cell(CellIndex.indexByString('D$currentRow')).value = DoubleCellValue(ingredient.effectiveGrossWeight);
      sheet.cell(CellIndex.indexByString('E$currentRow')).value = TextCellValue(ingredient.cookingProcessName ?? '');
      sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
      sheet.cell(CellIndex.indexByString('G$currentRow')).value = DoubleCellValue(ingredient.netWeight);
      sheet.cell(CellIndex.indexByString('H$currentRow')).value = DoubleCellValue(ingredient.cost);
      sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
    }

    // Итого
    final totalRow = rowIndex + techCard.ingredients.length + 1;
    final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
    final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

    sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('Итого:');
    sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
    sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
    sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);

    // Сохранение файла
    final fileName = 'ТТК_${techCard.dishName.replaceAll(RegExp(r'[^\w\s-]'), '_')}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Экспорт выбранных технологических карт
  Future<void> exportSelectedTechCards(List<TechCard> techCards) async {
    final excel = Excel.createExcel();

    for (int cardIndex = 0; cardIndex < techCards.length; cardIndex++) {
      final techCard = techCards[cardIndex];
      final sheetName = techCard.dishName.length > 30
          ? techCard.dishName.substring(0, 27) + '...'
          : techCard.dishName;
      final sheet = excel[sheetName];

      // Заголовок
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Технологическая карта');
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Название:');
      sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
      sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Тип:');
      sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Категория:');
      sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));

      // Технология приготовления
      final technology = techCard.technologyLocalized?['ru'] ?? '';
      if (technology.isNotEmpty) {
        sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Технология приготовления:');
        sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
      }

      // Заголовки таблицы ингредиентов
      int rowIndex = technology.isNotEmpty ? 9 : 6;
      sheet.cell(CellIndex.indexByString('A${rowIndex}')).value = TextCellValue('Продукт');
      sheet.cell(CellIndex.indexByString('B${rowIndex}')).value = TextCellValue('Брутто (г)');
      sheet.cell(CellIndex.indexByString('C${rowIndex}')).value = TextCellValue('Отход (%)');
      sheet.cell(CellIndex.indexByString('D${rowIndex}')).value = TextCellValue('Нетто (г)');
      sheet.cell(CellIndex.indexByString('E${rowIndex}')).value = TextCellValue('Способ приготовления');
      sheet.cell(CellIndex.indexByString('F${rowIndex}')).value = TextCellValue('Ужарка (%)');
      sheet.cell(CellIndex.indexByString('G${rowIndex}')).value = TextCellValue('Выход (г)');
      sheet.cell(CellIndex.indexByString('H${rowIndex}')).value = TextCellValue('Стоимость');
      sheet.cell(CellIndex.indexByString('I${rowIndex}')).value = TextCellValue('Цена за кг');

      // Данные ингредиентов
      for (int i = 0; i < techCard.ingredients.length; i++) {
        final ingredient = techCard.ingredients[i];
        final currentRow = rowIndex + i + 1;

        sheet.cell(CellIndex.indexByString('A$currentRow')).value = TextCellValue(ingredient.productName);
        sheet.cell(CellIndex.indexByString('B$currentRow')).value = DoubleCellValue(ingredient.grossWeight);
        sheet.cell(CellIndex.indexByString('C$currentRow')).value = DoubleCellValue(ingredient.primaryWastePct);
        sheet.cell(CellIndex.indexByString('D$currentRow')).value = DoubleCellValue(ingredient.effectiveGrossWeight);
        sheet.cell(CellIndex.indexByString('E$currentRow')).value = TextCellValue(ingredient.cookingProcessName ?? '');
        sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
        sheet.cell(CellIndex.indexByString('G$currentRow')).value = DoubleCellValue(ingredient.netWeight);
        sheet.cell(CellIndex.indexByString('H$currentRow')).value = DoubleCellValue(ingredient.cost);
        sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
      }

      // Итого
      final totalRow = rowIndex + techCard.ingredients.length + 1;
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('Итого:');
      sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
      sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
      sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);
    }

    // Сохранение файла
    final fileName = 'ТТК_выбранные_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Экспорт всех технологических карт
  Future<void> exportAllTechCards(List<TechCard> techCards) async {
    final excel = Excel.createExcel();

    // Создаем лист со списком всех ТТК
    final indexSheet = excel['Список ТТК'];

    // Заголовки
    indexSheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Название');
    indexSheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Тип');
    indexSheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Категория');
    indexSheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Количество ингредиентов');
    indexSheet.cell(CellIndex.indexByString('E1')).value = TextCellValue('Общий выход (г)');
    indexSheet.cell(CellIndex.indexByString('F1')).value = TextCellValue('Общая стоимость');

    // Список ТТК
    for (int i = 0; i < techCards.length; i++) {
      final techCard = techCards[i];
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      indexSheet.cell(CellIndex.indexByString('A${i + 2}')).value = TextCellValue(techCard.dishName);
      indexSheet.cell(CellIndex.indexByString('B${i + 2}')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      indexSheet.cell(CellIndex.indexByString('C${i + 2}')).value = TextCellValue(_getCategoryName(techCard.category));
      indexSheet.cell(CellIndex.indexByString('D${i + 2}')).value = IntCellValue(techCard.ingredients.length);
      indexSheet.cell(CellIndex.indexByString('E${i + 2}')).value = DoubleCellValue(totalNet);
      indexSheet.cell(CellIndex.indexByString('F${i + 2}')).value = DoubleCellValue(totalCost);
    }

    // Создаем отдельные листы для каждой ТТК
    for (int cardIndex = 0; cardIndex < techCards.length; cardIndex++) {
      final techCard = techCards[cardIndex];
      final sheetName = techCard.dishName.length > 30
          ? techCard.dishName.substring(0, 27) + '...'
          : techCard.dishName;
      final sheet = excel[sheetName];

      // Заголовок
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Технологическая карта');
      sheet.cell(CellIndex.indexByString('A2')).value = TextCellValue('Название:');
      sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue(techCard.dishName);
      sheet.cell(CellIndex.indexByString('A3')).value = TextCellValue('Тип:');
      sheet.cell(CellIndex.indexByString('B3')).value = TextCellValue(techCard.isSemiFinished ? 'Полуфабрикат' : 'Блюдо');
      sheet.cell(CellIndex.indexByString('A4')).value = TextCellValue('Категория:');
      sheet.cell(CellIndex.indexByString('B4')).value = TextCellValue(_getCategoryName(techCard.category));

      // Технология приготовления
      final technology = techCard.technologyLocalized?['ru'] ?? '';
      if (technology.isNotEmpty) {
        sheet.cell(CellIndex.indexByString('A6')).value = TextCellValue('Технология приготовления:');
        sheet.cell(CellIndex.indexByString('A7')).value = TextCellValue(technology);
      }

      // Заголовки таблицы ингредиентов
      int rowIndex = technology.isNotEmpty ? 9 : 6;
      sheet.cell(CellIndex.indexByString('A${rowIndex}')).value = TextCellValue('Продукт');
      sheet.cell(CellIndex.indexByString('B${rowIndex}')).value = TextCellValue('Брутто (г)');
      sheet.cell(CellIndex.indexByString('C${rowIndex}')).value = TextCellValue('Отход (%)');
      sheet.cell(CellIndex.indexByString('D${rowIndex}')).value = TextCellValue('Нетто (г)');
      sheet.cell(CellIndex.indexByString('E${rowIndex}')).value = TextCellValue('Способ приготовления');
      sheet.cell(CellIndex.indexByString('F${rowIndex}')).value = TextCellValue('Ужарка (%)');
      sheet.cell(CellIndex.indexByString('G${rowIndex}')).value = TextCellValue('Выход (г)');
      sheet.cell(CellIndex.indexByString('H${rowIndex}')).value = TextCellValue('Стоимость');
      sheet.cell(CellIndex.indexByString('I${rowIndex}')).value = TextCellValue('Цена за кг');

      // Данные ингредиентов
      for (int i = 0; i < techCard.ingredients.length; i++) {
        final ingredient = techCard.ingredients[i];
        final currentRow = rowIndex + i + 1;

        sheet.cell(CellIndex.indexByString('A$currentRow')).value = TextCellValue(ingredient.productName);
        sheet.cell(CellIndex.indexByString('B$currentRow')).value = DoubleCellValue(ingredient.grossWeight);
        sheet.cell(CellIndex.indexByString('C$currentRow')).value = DoubleCellValue(ingredient.primaryWastePct);
        sheet.cell(CellIndex.indexByString('D$currentRow')).value = DoubleCellValue(ingredient.effectiveGrossWeight);
        sheet.cell(CellIndex.indexByString('E$currentRow')).value = TextCellValue(ingredient.cookingProcessName ?? '');
        sheet.cell(CellIndex.indexByString('F$currentRow')).value = DoubleCellValue(ingredient.cookingLossPctOverride ?? ingredient.weightLossPercentage);
        sheet.cell(CellIndex.indexByString('G$currentRow')).value = DoubleCellValue(ingredient.netWeight);
        sheet.cell(CellIndex.indexByString('H$currentRow')).value = DoubleCellValue(ingredient.cost);
        sheet.cell(CellIndex.indexByString('I$currentRow')).value = DoubleCellValue(ingredient.netWeight > 0 ? ingredient.cost * 1000 / ingredient.netWeight : 0);
      }

      // Итого
      final totalRow = rowIndex + techCard.ingredients.length + 1;
      final totalNet = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.netWeight);
      final totalCost = techCard.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);

      sheet.cell(CellIndex.indexByString('A$totalRow')).value = TextCellValue('Итого:');
      sheet.cell(CellIndex.indexByString('G$totalRow')).value = DoubleCellValue(totalNet);
      sheet.cell(CellIndex.indexByString('H$totalRow')).value = DoubleCellValue(totalCost);
      sheet.cell(CellIndex.indexByString('I$totalRow')).value = DoubleCellValue(totalNet > 0 ? totalCost * 1000 / totalNet : 0);
    }

    // Сохранение файла
    final fileName = 'Все_ТТК_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    _saveExcelFile(excel, fileName);
  }

  /// Сохранение Excel файла в браузере
  void _saveExcelFile(Excel excel, String fileName) {
    final bytes = excel.encode();
    if (bytes == null) return;

    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Получение названия категории на русском
  String _getCategoryName(String category) {
    const categoryNames = {
      'vegetables': 'Овощи',
      'fruits': 'Фрукты',
      'meat': 'Мясо',
      'seafood': 'Рыба',
      'dairy': 'Молочное',
      'grains': 'Крупы',
      'bakery': 'Выпечка',
      'pantry': 'Бакалея',
      'spices': 'Специи',
      'beverages': 'Напитки',
      'eggs': 'Яйца',
      'legumes': 'Бобовые',
      'nuts': 'Орехи',
      'misc': 'Разное',
    };
    return categoryNames[category] ?? category;
  }
}