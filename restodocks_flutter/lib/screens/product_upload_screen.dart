import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/culinary_units.dart';
import '../models/models.dart';
import '../models/product_import_result.dart';
import '../services/services.dart';
import '../services/intelligent_product_import_service.dart';
import '../services/translation_service.dart';
import '../services/translation_manager.dart';

// Глобальная переменная для хранения debug логов
List<String> _debugLogs = [];

void _addDebugLog(String message) {
  final timestamp = DateTime.now().toIso8601String();
  _debugLogs.add('[$timestamp] $message');
  // Ограничиваем количество логов
  if (_debugLogs.length > 100) {
    _debugLogs.removeAt(0);
  }
}

/// Экран для загрузки продуктов в номенклатуру
class ProductUploadScreen extends StatefulWidget {
  const ProductUploadScreen({super.key});

  @override
  State<ProductUploadScreen> createState() => _ProductUploadScreenState();
}

class _ProductUploadScreenState extends State<ProductUploadScreen> {
  bool _isLoading = false;
  String _loadingMessage = '';

  void _setLoadingMessage(String message) {
    if (mounted) {
      setState(() => _loadingMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('upload_products')),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Показать логи отладки',
            onPressed: () => _showDebugLogs(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Индикатор загрузки
            if (_isLoading) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _loadingMessage.isNotEmpty ? _loadingMessage : 'Обработка...',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],

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

            const SizedBox(height: 12),

            // Интеллектуальный импорт Excel
            _UploadMethodCard(
              icon: Icons.analytics,
              title: 'Интеллектуальный импорт Excel',
              description: 'AI определение языка, fuzzy matching, авто-переводы на 5 языков',
              color: Colors.indigo,
              onTap: _isLoading ? null : () => _showIntelligentImportDialog(),
            ),

            const SizedBox(height: 24),

            // Пример формата
            _FormatExample(),

            const SizedBox(height: 24),

            // Тест парсинга
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Показать логи отладки для диагностики проблем',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _showDebugLogs(context),
                      child: const Text('Показать логи'),
                    ),
                  ],
                ),
              ),
            ],

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
      await _processText(text, loc, true);
    } else if (fileName.endsWith('.rtf')) {
      final text = _extractTextFromRtf(utf8.decode(bytes, allowMalformed: true));
      await _processText(text, loc, true);
    } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
      await _processExcel(bytes, loc);
    }
  }

  Future<void> _showPasteDialog() async {
    final loc = context.read<LocalizationService>();
    final controller = TextEditingController();
    bool addToNomenclature = true; // По умолчанию добавлять в номенклатуру

    final result = await showDialog<({String text, bool addToNomenclature})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
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
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: 'Пример:\nАвокадо\t₫99,000\nБазилик\t₫267,000\nМолоко\t₫38,000',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: Text('Добавить в номенклатуру заведения', style: Theme.of(context).textTheme.bodyMedium),
                  subtitle: Text('Продукты будут доступны для создания техкарт', style: Theme.of(context).textTheme.bodySmall),
                  value: addToNomenclature,
                  onChanged: (value) => setState(() => addToNomenclature = value ?? true),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
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
              onPressed: () => Navigator.of(ctx).pop((text: controller.text, addToNomenclature: addToNomenclature)),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.text.trim().isNotEmpty) {
      await _processText(result.text, loc, result.addToNomenclature);
    }
  }

  Future<void> _showSmartPasteDialog() async {
    final controller = TextEditingController();
    final loc = context.read<LocalizationService>();
    bool addToNomenclature = true; // По умолчанию добавлять в номенклатуру

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

    final result = await showDialog<({String text, bool addToNomenclature})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('AI обработка списка продуктов'),
          content: SizedBox(
            width: 600,
            height: 450,
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
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: Text('Добавить в номенклатуру заведения', style: Theme.of(context).textTheme.bodyMedium),
                  subtitle: Text('Продукты будут доступны для создания техкарт', style: Theme.of(context).textTheme.bodySmall),
                  value: addToNomenclature,
                  onChanged: (value) => setState(() => addToNomenclature = value ?? true),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
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
              onPressed: () => Navigator.of(ctx).pop((text: controller.text, addToNomenclature: addToNomenclature)),
              child: const Text('Обработать с AI'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.text.trim().isNotEmpty) {
      await _processTextWithAI(result.text, loc, result.addToNomenclature);
    }
  }

  Future<void> _showIntelligentImportDialog() async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final establishmentId = account.establishment?.id;

    if (establishmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не найдено заведение')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;

    final fileName = result.files.single.name;
    final bytes = result.files.single.bytes!;

    setState(() => _isLoading = true);

    try {
      final excel = Excel.decodeBytes(bytes);
      final importService = IntelligentProductImportService(
        aiService: context.read<AiServiceSupabase>(),
        translationService: TranslationService(
          aiService: context.read<AiServiceSupabase>(),
          supabase: context.read<SupabaseService>(),
        ),
        productStore: context.read<ProductStoreSupabase>(),
        techCardService: context.read<TechCardServiceSupabase>(),
      );

      final importResults = await importService.importFromExcel(
        excel,
        fileName,
        establishmentId,
        account.establishment?.defaultCurrency ?? 'RUB',
      );

      // Обрабатываем результаты
      final ambiguousResults = importResults.where((r) =>
          r.matchResult.type == MatchType.ambiguous).toList();

      if (ambiguousResults.isNotEmpty) {
        // Показываем модальное окно для разрешения неоднозначностей
        final resolutions = await _showAmbiguousMatchesDialog(ambiguousResults);
        if (resolutions != null) {
          await importService.processImportResults(
            importResults,
            resolutions,
            establishmentId,
            account.establishment?.defaultCurrency ?? 'RUB',
          );
        }
      } else {
        // Обрабатываем без неоднозначностей
        await importService.processImportResults(
          importResults,
          {},
          establishmentId,
          account.establishment?.defaultCurrency ?? 'RUB',
        );
      }

      // Показываем результаты
      final successCount = importResults.where((r) => r.error == null).length;
      final errorCount = importResults.where((r) => r.error != null).length;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импорт завершен: $successCount успешно, $errorCount ошибок')),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  Future<Map<String, String>?> _showAmbiguousMatchesDialog(List<ProductImportResult> ambiguousResults) async {
    final resolutions = <String, String>{};

    for (final result in ambiguousResults) {
      final resolution = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Неоднозначное совпадение'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Продукт из файла: ${result.fileName}'),
              Text('Найдено в базе: ${result.matchResult.existingProductName}'),
              const SizedBox(height: 16),
              const Text('Что сделать?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('replace'),
              child: const Text('Заменить существующий'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('create'),
              child: const Text('Создать новый'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Пропустить'),
            ),
          ],
        ),
      );

      if (resolution != null) {
        resolutions[result.fileName] = resolution;
      }
    }

    return resolutions.isNotEmpty ? resolutions : null;
  }

  Future<void> _processTextWithAI(String text, LocalizationService loc, bool addToNomenclature) async {
    _addDebugLog('=== STARTING AI TEXT PROCESSING ===');
    _setLoadingMessage('Обрабатываем текст через ИИ...');

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


      _addDebugLog('Sending AI request...');
      final response = await aiService.invoke('ai-generate-checklist', {
        'prompt': prompt
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _addDebugLog('AI request timed out after 30 seconds');
          throw Exception('AI request timed out');
        },
      );
      _addDebugLog('AI response received');

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
        await _addProductsToNomenclature(items, loc, addToNomenclature);
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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }


  Future<void> _processText(String text, LocalizationService loc, bool addToNomenclature) async {
    _addDebugLog('=== STARTING TEXT PROCESSING ===');
    _addDebugLog('Text length: ${text.length}');
    _addDebugLog('Add to nomenclature: $addToNomenclature');
    _addDebugLog('Raw text preview: "${text.substring(0, min(200, text.length))}"');

    _setLoadingMessage('Определяем формат текста...');

    // Определяем формат текста
    final format = _detectTextFormat(text);
    _addDebugLog('Detected format: $format');

    List<({String name, double? price})> items;

    if (format == 'ai_needed') {
      // Используем AI для сложных форматов
      return await _processTextWithAI(text, loc, addToNomenclature);
    } else {
      // Обычный парсинг
      _setLoadingMessage('Разбираем текст...');
      final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      _addDebugLog('=== PARSING ${lines.length} LINES ===');
      for (var i = 0; i < min(3, lines.length); i++) {
        _addDebugLog('Raw line ${i}: "${lines[i]}"');
      }

      final parsedResults = lines.map(_parseLine).toList();
      _addDebugLog('Parsed ${parsedResults.length} lines:');
      for (var i = 0; i < min(5, parsedResults.length); i++) {
        _addDebugLog('  Line ${i}: "${lines[i]}" -> name="${parsedResults[i].name}", price=${parsedResults[i].price}');
      }

      items = parsedResults.where((r) => r.name.isNotEmpty).toList();
      _addDebugLog('After filtering empty names: ${items.length} items remain (from ${parsedResults.length} parsed)');

      if (items.isEmpty) {
        _addDebugLog('ERROR: All items were filtered out! Check _parseLine logic.');
      } else {
        _addDebugLog('First 3 valid items:');
        for (var i = 0; i < min(3, items.length); i++) {
          _addDebugLog('  ${i}: "${items[i].name}" @ ${items[i].price}');
        }
      }
    }

    if (items.isEmpty) {
      _addDebugLog('WARNING: Basic parsing failed, trying AI processing');
      _setLoadingMessage('Обычный парсинг не сработал, пробуем ИИ...');
      // Если обычный парсинг не сработал, пробуем AI
      return await _processTextWithAI(text, loc, addToNomenclature);
    }

    _setLoadingMessage('Сохраняем ${items.length} продуктов...');
    await _addProductsToNomenclature(items, loc, addToNomenclature);
  }

  String _detectTextFormat(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).take(5);
    print('DEBUG: Detecting format for ${lines.length} sample lines');

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
    _addDebugLog('Tab detection: ${tabLines}/${lines.length} lines contain tabs');
    if (tabLines > lines.length * 0.5) {
      _addDebugLog('Detected tab-delimited format');
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
      late Excel excel;
      try {
        excel = Excel.decodeBytes(bytes);
      } catch (excelError) {
        _addDebugLog('Excel decode error: $excelError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка чтения Excel файла: $excelError')),
        );
        return;
      }
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

      await _processText(lines.join('\n'), loc, true); // Для файлов всегда добавляем в номенклатуру
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обработки Excel файла: $e')),
      );
    }
  }

  Future<void> _addProductsToNomenclature(List<({String name, double? price})> items, LocalizationService loc, bool addToNomenclature) async {
    _addDebugLog('=== STARTING PRODUCT CREATION ===');
    _addDebugLog('Items to process: ${items.length}');
    _addDebugLog('Add to nomenclature: $addToNomenclature');

    if (items.isEmpty) {
      _addDebugLog('ERROR: No items to process!');
      return;
    }
    _setLoadingMessage('Обрабатываем ${items.length} продуктов...');
    setState(() => _isLoading = true);

    try {
      final store = context.read<ProductStoreSupabase>();
      final account = context.read<AccountManagerSupabase>();

      // Проверяем инициализацию Supabase
      _addDebugLog('Checking Supabase initialization...');
      final estId = account.establishment?.id;
      final defCur = account.establishment?.defaultCurrency ?? 'VND';
      final sourceLang = loc.currentLanguageCode;
      final allLangs = LocalizationService.productLanguageCodes;

      print('DEBUG: Establishment ID: $estId, Default currency: $defCur');
      print('DEBUG: User logged in: ${account.isLoggedInSync}');

      if (!account.isLoggedInSync) {
        print('DEBUG: User not logged in!');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Пользователь не авторизован')),
        );
        return;
      }

      if (estId == null) {
        print('DEBUG: No establishment found!');
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
          _addDebugLog('AI verification successful for "${item.name}": calories=${verification?.suggestedCalories}, protein=${verification?.suggestedProtein}');
        } catch (aiError) {
          _addDebugLog('AI verification failed for "${item.name}": $aiError');
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
            final nutritionResult = await NutritionApiService.fetchNutrition(normalizedName);

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

          print('DEBUG: Created product: ${product.toJson()}');

          // Пытаемся добавить продукт
          try {
            print('DEBUG: Adding product "${product.name}" to database...');
            await store.addProduct(product);
            print('DEBUG: Successfully added product "${product.name}"');

            // Запускаем автоматический перевод для нового продукта
            final translationManager = TranslationManager(
              aiService: context.read<AiServiceSupabase>(),
              translationService: TranslationService(
                aiService: context.read<AiServiceSupabase>(),
                supabase: context.read<SupabaseService>(),
              ),
            );

            await translationManager.handleEntitySave(
              entityType: TranslationEntityType.product,
              entityId: product.id,
              textFields: {
                'name': product.name,
                if (product.names != null)
                  for (final entry in product.names!.entries)
                    'name_${entry.key}': entry.value,
              },
              sourceLanguage: 'ru', // TODO: определить язык из контекста
              userId: context.read<AccountManagerSupabase>().currentEmployee?.id,
            );
          } catch (e) {
            print('DEBUG: Failed to add product "${product.name}": $e');
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              print('DEBUG: Product "${product.name}" already exists, skipping');
              skipped++;
              continue;
            } else {
              print('DEBUG: Unexpected error adding "${product.name}": $e');
              failed++;
              continue;
            }
          }

          // Добавляем в номенклатуру только если выбрана эта опция
          if (addToNomenclature) {
            try {
              print('DEBUG: Adding product "${product.name}" to nomenclature...');
              await store.addToNomenclature(estId, product.id);
              added++;
              print('DEBUG: Successfully added "${product.name}" to nomenclature');
            } catch (e) {
              print('DEBUG: Failed to add "${product.name}" to nomenclature: $e');
              if (e.toString().contains('duplicate key') ||
                  e.toString().contains('already exists') ||
                  e.toString().contains('unique constraint')) {
                print('DEBUG: Product "${product.name}" already in nomenclature, skipping');
                skipped++;
              } else {
                print('DEBUG: Unexpected error adding "${product.name}" to nomenclature: $e');
                failed++;
              }
            }
          } else {
            // Продукт добавлен только в базу
            added++;
            print('DEBUG: Product "${product.name}" added to database only');
          }

          // Небольшая задержка
          await Future.delayed(const Duration(milliseconds: 100));

        } catch (e) {
          failed++;
        }
      }

      // Обновляем список продуктов
      print('DEBUG: Reloading products and nomenclature...');
      await store.loadProducts();
      await store.loadNomenclature(estId);
      print('DEBUG: Products loaded: ${store.allProducts.length}');
      print('DEBUG: Nomenclature loaded: ${store.nomenclatureProductIds.length}');
      if (mounted) setState(() {});

      // Показываем результат
      final message = failed == 0
          ? 'Добавлено: ${added + skipped}'
          : 'Добавлено: ${added + skipped}, Ошибок: $failed';

      print('DEBUG: Final result - Added: $added, Skipped: $skipped, Failed: $failed');

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
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
      }
    }
  }

  ({String name, double? price}) _parseLine(String line) {
    // Сначала попробуем найти паттерны с ценами в конце строки
    _addDebugLog('DEBUG: Parsing line: "${line.replaceAll('\t', '[TAB]')}"');

    // Тестовый вывод для отладки (можно удалить после тестирования)
    if (line.contains('Авокадо')) {
      _addDebugLog('TEST: Found avocado line, contains tab: ${line.contains('\t')}, length: ${line.length}');
    }
    final pricePatterns = [
      RegExp(r'[\d,]+\s*[₫$€£¥руб.]?\s*$'), // число с опциональной валютой в конце (добавил ¥ для японской йены)
      RegExp(r'\d+\.\d+\s*[₫$€£¥руб.]?\s*$'), // десятичное число
      RegExp(r'\d{1,3}(?:,\d{3})*\s*[₫$€£¥руб.]?\s*$'), // число с разделителями тысяч
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
            .replaceAll(RegExp(r'[₫$€£¥руб.\s]'), '')
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

    _addDebugLog('DEBUG: Parsed result: name="${name}", price=${price}');
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

  void _showDebugLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Логи отладки'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _debugLogs.isEmpty
              ? const Center(child: Text('Логов пока нет'))
              : ListView.builder(
                  itemCount: _debugLogs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _debugLogs[_debugLogs.length - 1 - index], // Показываем последние логи сверху
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _debugLogs.clear()),
            child: const Text('Очистить'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
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
