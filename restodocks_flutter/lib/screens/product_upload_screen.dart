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

            // Тестовая карточка для быстрой проверки
            _UploadMethodCard(
              icon: Icons.bug_report,
              title: 'Тест (демо данные)',
              description: 'Загрузить тестовые продукты для проверки',
              color: Colors.orange,
              onTap: _isLoading ? null : () => _loadTestData(),
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
    print('DEBUG: Starting file upload');
    final loc = context.read<LocalizationService>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'xlsx', 'xls', 'rtf'],
      withData: true,
    );

    if (result == null || result.files.isEmpty || result.files.single.bytes == null) {
      print('DEBUG: No file selected or no data');
      return;
    }

    print('DEBUG: File selected: ${result.files.single.name}');
    final fileName = result.files.single.name.toLowerCase();
    final bytes = result.files.single.bytes!;

    if (fileName.endsWith('.txt')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      print('DEBUG: Processing text file, length: ${text.length}');
      await _processText(text, loc);
    } else if (fileName.endsWith('.rtf')) {
      final text = _extractTextFromRtf(utf8.decode(bytes, allowMalformed: true));
      print('DEBUG: Processing RTF file, extracted length: ${text.length}');
      await _processText(text, loc);
    } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
      print('DEBUG: Processing Excel file');
      await _processExcel(bytes, loc);
    } else {
      print('DEBUG: Unsupported file type: $fileName');
    }
  }

  Future<void> _showPasteDialog() async {
    print('DEBUG: Showing paste dialog');
    final loc = context.read<LocalizationService>();
    final controller = TextEditingController();

    // Предварительно вставим тестовый текст для проверки
    controller.text = '''Авокадо	₫99,000
Анчоус	₫1,360,000
Апельсин	₫50,000
Базилик	₫267,000
Баклажан	₫12,000''';

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
            onPressed: () => {
              print('DEBUG: Add button pressed, text length: ${controller.text.length}'),
              print('DEBUG: Text content: "${controller.text}"'),
              Navigator.of(ctx).pop(controller.text)
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    print('DEBUG: Paste dialog result: text length = ${text?.length ?? 0}');
    print('DEBUG: Text content: "${text ?? "null"}"');
    if (text != null && text.trim().isNotEmpty) {
      print('DEBUG: Processing pasted text');
      await _processText(text, loc);
    } else {
      print('DEBUG: No text to process - showing error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Текст не введен или пустой')),
        );
      }
    }
  }

  Future<void> _loadTestData() async {
    print('DEBUG: Loading test data');
    final loc = context.read<LocalizationService>();
    const testData = '''Авокадо	₫99,000
Базилик	₫267,000
Баклажан	₫12,000
Молоко	₫38,000
Картофель	₫25,000''';

    await _processText(testData, loc);
  }

  Future<void> _processText(String text, LocalizationService loc) async {
    print('DEBUG: ===== STARTING TEXT PROCESSING =====');
    print('DEBUG: Raw input text length: ${text.length}');
    print('DEBUG: Raw input text: "${text.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"');

    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    print('DEBUG: After splitting - found ${lines.length} lines:');
    lines.forEach((line) => print('DEBUG:   Line: "${line}"'));

    final items = lines.map(_parseLine).where((r) => r.name.isNotEmpty).toList();
    print('DEBUG: After parsing - ${items.length} valid items:');
    items.forEach((item) => print('DEBUG:   Item: name="${item.name}", price=${item.price}'));

    if (items.isEmpty) {
      print('DEBUG: No valid items found');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не найдено валидных продуктов в тексте')),
      );
      return;
    }

    // Для тестирования убираем диалог подтверждения
    print('DEBUG: Skipping confirmation dialog for testing');
    await _addProductsToNomenclature(items, loc);
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
    print('DEBUG: Starting to add ${items.length} products to nomenclature');
    setState(() => _isLoading = true);

    try {
      // Прямое добавление без диалога для тестирования
      print('DEBUG: Adding products directly without dialog');
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      final defCur = account.establishment?.defaultCurrency ?? 'VND';
      final sourceLang = loc.currentLanguageCode;
      final allLangs = LocalizationService.productLanguageCodes;

      print('DEBUG: Establishment ID: $estId, Currency: $defCur');

      if (estId == null) {
        print('DEBUG: No establishment ID found');
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
          print('DEBUG: Processing item: "${item.name}" price=${item.price}');

          // Создаем продукт
          final product = Product(
            id: const Uuid().v4(),
            name: item.name,
            category: 'manual',
            names: <String, String>{for (final c in allLangs) c: item.name},
            calories: null,
            protein: null,
            fat: null,
            carbs: null,
            unit: 'g',
            basePrice: item.price,
            currency: item.price != null ? defCur : null,
          );

          // Пытаемся добавить продукт
          try {
            await store.addProduct(product);
            print('DEBUG: Product "${item.name}" added to database');
          } catch (e) {
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              print('DEBUG: Product "${item.name}" already exists, skipping add');
              skipped++;
              continue;
            } else {
              print('DEBUG: Failed to add product "${item.name}": $e');
              failed++;
              continue;
            }
          }

          // Добавляем в номенклатуру
          try {
            await store.addToNomenclature(estId, product.id);
            print('DEBUG: Product "${item.name}" added to nomenclature');
            added++;
          } catch (e) {
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              print('DEBUG: Product "${item.name}" already in nomenclature');
              skipped++;
            } else {
              print('DEBUG: Failed to add to nomenclature "${item.name}": $e');
              failed++;
            }
          }

          // Небольшая задержка
          await Future.delayed(const Duration(milliseconds: 100));

        } catch (e) {
          print('DEBUG: Unexpected error processing "${item.name}": $e');
          failed++;
        }
      }

      print('DEBUG: Processing complete - added: $added, skipped: $skipped, failed: $failed');

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
    print('DEBUG: Parsing line: "$line"');
    final parts = line.split(RegExp(r'\t|\s{2,}'));
    print('DEBUG: Split into ${parts.length} parts: $parts');
    final name = parts.isNotEmpty ? parts[0].trim() : '';
    final priceStr = parts.length > 1 ? parts[1].trim() : '';

    double? price;
    if (priceStr.isNotEmpty) {
      // Убираем валюту и запятые
      final cleanPrice = priceStr.replaceAll(RegExp(r'[₫$€£руб.\s]'), '').replaceAll(',', '');
      price = double.tryParse(cleanPrice);
      print('DEBUG: Cleaned price "$priceStr" -> "$cleanPrice" -> $price');
    }

    final result = (name: name, price: price);
    print('DEBUG: Parsed result: name="$name", price=$price');
    return result;
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
