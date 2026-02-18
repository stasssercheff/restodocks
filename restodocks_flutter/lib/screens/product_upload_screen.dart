import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/culinary_units.dart';
import '../models/models.dart';
import '../services/services.dart';

/// Экран для загрузки продуктов в номенклатуру
class ProductUploadScreen extends StatefulWidget {
  const ProductUploadScreen({super.key});

  @override
  State<ProductUploadScreen> createState() => _ProductUploadScreenState();
}

class _ProductUploadScreenState extends State<ProductUploadScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('upload_products')),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Text(
              'Добавьте продукты в номенклатуру вашего заведения',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Продукты будут добавлены в общую базу и станут доступны для создания ТТК и меню.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),

            // Способы загрузки
            Text(
              'Выберите способ загрузки:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Карточка загрузки из файла
            _UploadMethodCard(
              icon: Icons.file_upload,
              title: 'Из файла',
              description: 'Excel (.xlsx, .xls), Текст (.txt), RTF (.rtf)',
              color: Colors.blue,
              onTap: _isLoading ? null : () => _uploadFromFile(),
            ),

            const SizedBox(height: 12),

            // Карточка вставки текста
            _UploadMethodCard(
              icon: Icons.content_paste,
              title: 'Вставить текст',
              description: 'Скопировать и вставить список продуктов',
              color: Colors.green,
              onTap: _isLoading ? null : () => _showPasteDialog(),
            ),

            const SizedBox(height: 12),

            // Умная обработка текста с AI
            _UploadMethodCard(
              icon: Icons.smart_toy,
              title: 'AI обработка текста',
              description: 'ИИ разберет любой формат списка продуктов',
              color: Colors.purple,
              onTap: _isLoading ? null : () => _showSmartPasteDialog(),
            ),

            const SizedBox(height: 24),

            // Пример формата
            _FormatExample(),

            const SizedBox(height: 24),

            // Советы
            _TipsSection(),

            const SizedBox(height: 24),

            // Быстрые действия
            _QuickActions(),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadFromFile() async {
    final loc = context.read<LocalizationService>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'xlsx', 'xls', 'rtf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;

    final fileName = result.files.single.name.toLowerCase();
    final bytes = result.files.single.bytes!;

    if (fileName.endsWith('.txt')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      await _processText(text, loc);
    } else if (fileName.endsWith('.rtf')) {
      final text = _extractTextFromRtf(utf8.decode(bytes, allowMalformed: true));
      await _processText(text, loc);
    } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
      await _processExcel(bytes, loc);
    }
  }

  Future<void> _showPasteDialog() async {
    final loc = context.read<LocalizationService>();
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Вставить список продуктов'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вставьте список продуктов в поле ниже.\nКаждая строка = один продукт.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 15,
                decoration: const InputDecoration(
                  hintText: 'Пример:\nАвокадо\t₫99,000\nБазилик\t₫267,000\nМолоко\t₫38,000',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    if (text != null && text.trim().isNotEmpty) {
      await _processText(text, loc);
    }
  }

  Future<void> _showSmartPasteDialog() async {
    final controller = TextEditingController();
    final loc = context.read<LocalizationService>();

    // Пример различных форматов
    controller.text = '''Возможные форматы:

1. Название Цена
Авокадо 99000
Базилик 267000

2. Название - Цена
Анчоус - 1360000
Апельсин - 50000

3. Название: Цена
Баклажан: 12000
Молоко: 38000

4. С валютами
Авокадо ₫99,000
Базилик \$267,000
Молоко €38,000

5. Смешанный формат
Картофель - 25 000 руб.
Морковь 20.000₫
Лук: 20000''';

    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('AI обработка списка продуктов'),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ИИ автоматически разберет любой формат списка продуктов.\n'
                'Просто вставьте текст в любом формате:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Вставьте список продуктов здесь...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Обработать с AI'),
          ),
        ],
      ),
    );

    if (text != null && text.trim().isNotEmpty) {
      await _processTextWithAI(text, loc);
    }
  }

  Future<void> _processTextWithAI(String text, LocalizationService loc) async {

    setState(() => _isLoading = true);

    try {
      // Используем AI для извлечения продуктов из текста
      final aiService = context.read<AiServiceSupabase>();

      // Создаем запрос к AI для извлечения списка продуктов
      final prompt = '''
Извлеки список продуктов из этого текста. Для каждого продукта укажи:
- Название продукта
- Цену (если указана, число без валюты)
- Валюту (если указана)

Формат ответа: каждая строка "Название|Цена|Валюта"
Если цена или валюта не указаны, оставь пустым.

Примеры:
Авокадо|99000|VND
Базилик|267000|
Молоко||

Текст для обработки:
${text}
''';


      final response = await aiService.invoke('ai-generate-checklist', {
        'prompt': prompt
      });

      if (response == null || !response.containsKey('itemTitles')) {
        throw Exception('AI не вернул результат');
      }

      // Парсим результат
      final rawItems = response['itemTitles'] as List? ?? [];

      final items = <({String name, double? price})>[];
      for (final rawItem in rawItems) {
        try {
          if (rawItem is String && rawItem.contains('|')) {
            final parts = rawItem.split('|').map((s) => s.trim()).toList();
            if (parts.length >= 1 && parts[0].isNotEmpty) {
              final name = parts[0];
              double? price;

              if (parts.length >= 2 && parts[1].isNotEmpty) {
                // Пробуем разные форматы чисел
                final priceStr = parts[1].replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
                price = double.tryParse(priceStr);
              }

              items.add((name: name, price: price));
            }
          }
        } catch (e) {
          // Игнорируем ошибки парсинга
        }
      }

      if (items.isNotEmpty) {
        await _addProductsToNomenclature(items, loc);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI не смог извлечь продукты из текста')),
        );
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обработки текста AI: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _processText(String text, LocalizationService loc) async {
    // Определяем формат текста
    final format = _detectTextFormat(text);

    List<({String name, double? price})> items;

    if (format == 'ai_needed') {
      // Используем AI для сложных форматов
      return await _processTextWithAI(text, loc);
    } else {
      // Обычный парсинг
      final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty);
      items = lines.map(_parseLine).where((r) => r.name.isNotEmpty).toList();
    }

    if (items.isEmpty) {
      // Если обычный парсинг не сработал, пробуем AI
      return await _processTextWithAI(text, loc);
    }

    await _addProductsToNomenclature(items, loc);
  }

  String _detectTextFormat(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).take(5);

    // Проверяем на сложные форматы
    bool hasComplexFormat = false;

    for (final line in lines) {
      // Ищем признаки сложных форматов
      if (line.contains(' - ') ||
          line.contains(': ') ||
          line.contains('•') ||
          line.contains('(') && line.contains(')') ||
          RegExp(r'\d+\s*[a-zA-Zа-яА-Я]+\s*\d').hasMatch(line)) {
        hasComplexFormat = true;
        break;
      }
    }

    if (hasComplexFormat) {
      return 'ai_needed';
    }

    // Проверяем на табличный формат
    final tabLines = lines.where((line) => line.contains('\t')).length;
    if (tabLines > lines.length * 0.5) {
      return 'tab_delimited';
    }

    // Проверяем на формат с пробелами
    final spaceLines = lines.where((line) => RegExp(r'\s{2,}').hasMatch(line)).length;
    if (spaceLines > lines.length * 0.3) {
      return 'space_delimited';
    }

    return 'simple';
  }

  Future<void> _processExcel(Uint8List bytes, LocalizationService loc) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: не найдена таблица в файле')),
        );
        return;
      }

      final lines = <String>[];
      for (var i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        final name = row.length > 0 ? row[0]?.value?.toString() ?? '' : '';
        final price = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
        final unit = row.length > 2 ? row[2]?.value?.toString() ?? '' : 'г';

        if (name.trim().isNotEmpty) {
          lines.add('$name\t$price\t$unit');
        }
      }

      await _processText(lines.join('\n'), loc);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обработки Excel файла: $e')),
      );
    }
  }

  Future<void> _addProductsToNomenclature(List<({String name, double? price})> items, LocalizationService loc) async {
    setState(() => _isLoading = true);

    try {
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      final defCur = account.establishment?.defaultCurrency ?? 'VND';
      final sourceLang = loc.currentLanguageCode;
      final allLangs = LocalizationService.productLanguageCodes;

      if (estId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не найдено заведение')),
        );
        return;
      }

      int added = 0;
      int skipped = 0;
      int failed = 0;

      for (final item in items) {
        try {
        // Используем ИИ для улучшения данных продукта
        ProductVerificationResult? verification;
        try {
          final aiService = context.read<AiServiceSupabase>();
          verification = await aiService.verifyProduct(
            item.name,
            currentPrice: item.price,
          );
          print('DEBUG: AI verification successful for "${item.name}": calories=${verification?.suggestedCalories}, protein=${verification?.suggestedProtein}');
        } catch (aiError) {
          print('DEBUG: AI verification failed for "${item.name}": $aiError');
          verification = null;
        }

        // Используем проверенные ИИ данные или оригинальные
        final normalizedName = verification?.normalizedName ?? item.name;
        var names = <String, String>{for (final c in allLangs) c: normalizedName};

        // Проверяем питательные данные от AI
        double? calories = verification?.suggestedCalories;
        double? protein = verification?.suggestedProtein;
        double? fat = verification?.suggestedFat;
        double? carbs = verification?.suggestedCarbs;

        // Если AI дал данные, используем их приоритетно
        final hasValidNutritionFromAI = (calories != null && calories > 0) ||
                                       (protein != null && protein > 0) ||
                                       (fat != null && fat > 0) ||
                                       (carbs != null && carbs > 0);

        if (!hasValidNutritionFromAI) {
          // Fallback к Nutrition API только если AI не дал данные
          try {
            final nutritionService = context.read<NutritionApiService>();
            final nutritionResult = await nutritionService.fetchNutrition(normalizedName);

            if (nutritionResult != null && nutritionResult.hasData) {
              calories = calories ?? nutritionResult.calories;
              protein = protein ?? nutritionResult.protein;
              fat = fat ?? nutritionResult.fat;
              carbs = carbs ?? nutritionResult.carbs;
              print('DEBUG: Used Nutrition API fallback for "${normalizedName}": calories=$calories');
            }
          } catch (nutritionError) {
            print('DEBUG: Nutrition API failed for "${normalizedName}": $nutritionError');
          }
        } else {
          print('DEBUG: Using AI nutrition data for "${normalizedName}": ${calories}kcal, ${protein}g protein');
        }

          final product = Product(
            id: const Uuid().v4(),
            name: normalizedName,
            category: verification?.suggestedCategory ?? 'manual',
            names: names,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs,
            unit: verification?.suggestedUnit ?? 'g',
            basePrice: verification?.suggestedPrice ?? item.price,
            currency: (verification?.suggestedPrice ?? item.price) != null ? defCur : null,
          );

          // Пытаемся добавить продукт
          try {
            await store.addProduct(product);
          } catch (e) {
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              skipped++;
              continue;
            } else {
              failed++;
              continue;
            }
          }

          // Добавляем в номенклатуру
          try {
            await store.addToNomenclature(estId, product.id);
            added++;
          } catch (e) {
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              skipped++;
            } else {
              failed++;
            }
          }

          // Небольшая задержка
          await Future.delayed(const Duration(milliseconds: 100));

        } catch (e) {
          failed++;
        }
      }

      // Обновляем список продуктов
      await store.loadProducts();
      await store.loadNomenclature(estId);
      if (mounted) setState(() {});

      // Показываем результат
      final message = failed == 0
          ? 'Добавлено: ${added + skipped}'
          : 'Добавлено: ${added + skipped}, Ошибок: $failed';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
        );
      }

    } catch (e) {
      print('DEBUG: Error in direct processing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обработки: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  ({String name, double? price}) _parseLine(String line) {
    // Сначала попробуем найти паттерны с ценами в конце строки
    final pricePatterns = [
      RegExp(r'[\d,]+\s*[₫$€£руб.]?\s*$'), // число с опциональной валютой в конце
      RegExp(r'\d+\.\d+\s*[₫$€£руб.]?\s*$'), // десятичное число
      RegExp(r'\d{1,3}(?:,\d{3})*\s*[₫$€£руб.]?\s*$'), // число с разделителями тысяч
    ];

    String name = line.trim();
    double? price;

    for (final pattern in pricePatterns) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final pricePart = match.group(0)!.trim();
        name = line.substring(0, match.start).trim();

        // Очищаем цену от валюты и форматирования
        final cleanPrice = pricePart
            .replaceAll(RegExp(r'[₫$€£руб.\s]'), '')
            .replaceAll(',', '')
            .replaceAll(' ', '');

        price = double.tryParse(cleanPrice);
        if (price != null) break;
      }
    }

    // Если не нашли цену паттерном, пробуем старый способ с разделителями
    if (price == null) {
      final parts = line.split(RegExp(r'\t|\s{2,}|\s+\|\s+|\s*;\s*'));
      name = parts.isNotEmpty ? parts[0].trim() : line.trim();
      final priceStr = parts.length > 1 ? parts[1].trim() : '';

      if (priceStr.isNotEmpty) {
        final cleanPrice = priceStr.replaceAll(RegExp(r'[₫$€£руб.\s]'), '').replaceAll(',', '').replaceAll(' ', '');
        price = double.tryParse(cleanPrice);
      }
    }

    // Если имя пустое или содержит только цену, это ошибка
    if (name.isEmpty || RegExp(r'^\d').hasMatch(name)) {
      name = line.trim();
      price = null;
    }

    return (name: name, price: price);
  }

  String _extractTextFromRtf(String rtf) {
    // Удаляем заголовок RTF
    final rtfHeaderEnd = rtf.indexOf('\\viewkind');
    if (rtfHeaderEnd != -1) {
      rtf = rtf.substring(rtfHeaderEnd);
    }

    // Удаляем все команды в фигурных скобках (группы)
    rtf = rtf.replaceAll(RegExp(r'\{[^}]*\}'), '');

    // Удаляем оставшиеся RTF команды (начинаются с \)
    rtf = rtf.replaceAll(RegExp(r'\\[a-z]+\d*'), '');

    // Удаляем лишние пробелы и переносы строк
    rtf = rtf.replaceAll(RegExp(r'\s+'), ' ').trim();

    return rtf;
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Card(
      elevation: 1,
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rocket_launch, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Быстрые действия:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildQuickAction(
              context,
              'Посмотреть номенклатуру',
              'Проверить добавленные продукты',
              () => GoRouter.of(context).push('/products'),
            ),
            _buildQuickAction(
              context,
              'Создать ТТК',
              'Использовать новые продукты в рецептах',
              () => GoRouter.of(context).push('/tech-cards'),
            ),
            _buildQuickAction(
              context,
              'Создать меню',
              'Добавить блюда в меню ресторана',
              () => GoRouter.of(context).push('/menu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, String title, String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class _UploadMethodCard extends StatelessWidget {
  const _UploadMethodCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Пример формата данных:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Text(
                'Авокадо\t₫99,000\n'
                'Базилик\t₫267,000\n'
                'Баклажан\t₫12,000\n'
                'Молоко\t₫38,000\n'
                'Картофель\t₫25,000',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '• Название и цена разделяются табуляцией (Tab) или несколькими пробелами\n'
              '• Можно использовать любые символы валюты\n'
              '• Поддерживаются запятые в числах',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  'Полезные советы:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTip('Экспортируйте продукты из Excel в текстовый файл'),
            _buildTip('Или просто скопируйте список из любой таблицы'),
            _buildTip('ИИ автоматически исправит названия и определит категории'),
            _buildTip('Продукты добавятся в общую базу и вашу номенклатуру'),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: Colors.blue[700])),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.blue[700]),
            ),
          ),
        ],
      ),
    );
  }
}
