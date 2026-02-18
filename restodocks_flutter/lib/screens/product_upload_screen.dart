import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

import 'dart:async';

class _ProductUploadScreenState extends State<ProductUploadScreen> {
  bool _isLoading = false;
  String _loadingMessage = '';
  Timer? _loadingTimeoutTimer; // Таймер для предотвращения зависания загрузки

  void _setLoadingMessage(String message) {
    if (mounted) {
      setState(() => _loadingMessage = message);
    }
  }

  // Предотвращает зависание интерфейса в состоянии загрузки
  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _isLoading) {
        _addDebugLog('Loading timeout reached, resetting loading state');
        setState(() => _isLoading = false);
        _loadingMessage = '';
      }
    });
  }

  // Сбрасывает таймер таймаута
  void _cancelLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = null;
  }

  @override
  void dispose() {
    _cancelLoadingTimeout(); // Отменяем таймер при уничтожении виджета
    super.dispose();
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Загрузка продуктов'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Вернуться назад'),
            ),
            const SizedBox(height: 16),
            // Кнопка для тестирования API
            OutlinedButton(
              onPressed: () => _testApiCall(context),
              child: const Text('Тестировать API'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testApiCall(BuildContext context) async {
    try {
      _addDebugLog('Testing API call to establishment_products...');

      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;

      if (establishmentId == null) {
        _addDebugLog('No establishment ID available');
        return;
      }

      _addDebugLog('Establishment ID: $establishmentId');

      // Тестируем прямой вызов API
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('establishment_products')
          .select('product_id, price, currency')
          .eq('establishment_id', establishmentId)
          .limit(3);

      _addDebugLog('API Response: $response');
      _addDebugLog('Response type: ${response.runtimeType}');
      _addDebugLog('Response length: ${response.length}');

      if (response.isNotEmpty) {
        _addDebugLog('First item: ${response.first}');
        _addDebugLog('First item keys: ${response.first.keys.toList()}');
        _addDebugLog('First item types: ${response.first.values.map((v) => v.runtimeType).toList()}');
      }

    } catch (e, stackTrace) {
      _addDebugLog('API Test failed: $e');
      _addDebugLog('Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    _addDebugLog('ProductUploadScreen build called, _isLoading: $_isLoading');

    try {
      // Проверяем наличие провайдеров более безопасно
      final loc = context.watch<LocalizationService>();
      final account = context.watch<AccountManagerSupabase>();
      final aiService = context.read<AiService>();

      _addDebugLog('All providers available, isLoggedIn: ${account.isLoggedInSync}');

      // Проверяем авторизацию
      if (!account.isLoggedInSync) {
        _addDebugLog('Not logged in');
        return _buildErrorScreen('Необходимо войти в систему');
      }

      // Проверяем наличие заведения
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        _addDebugLog('No establishment');
        return _buildErrorScreen('Не найдено заведение');
      }

      _addDebugLog('ProductUploadScreen ready: establishmentId = $establishmentId');

      return _buildMainScreen(loc, account, aiService, establishmentId);
    } catch (e, stackTrace) {
      _addDebugLog('Critical error in build: $e\n$stackTrace');
      return _buildErrorScreen('Критическая ошибка: $e');
    }
  }

  Widget _buildMainScreen(
    LocalizationService loc,
    AccountManagerSupabase account,
    AiService aiService,
    String establishmentId,
  ) {

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('upload_products')),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          if (kDebugMode) ...[
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Показать логи отладки',
              onPressed: () => _showDebugLogs(context),
            ),
          ],
          // Кнопка с количеством логов
          if (kDebugMode && _debugLogs.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_debugLogs.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
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

            // Отладочные логи (только в debug режиме)
            if (kDebugMode) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Отладочные логи (${_debugLogs.length}):',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final logs = _debugLogs.join('\n');
                            await Clipboard.setData(ClipboardData(text: logs));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Все логи скопированы в буфер обмена')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Копировать все'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SelectableText(
                            _debugLogs.join('\n'),
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _debugLogs.clear()),
                          child: const Text('Очистить'),
                        ),
                        TextButton(
                          onPressed: () => _showDebugLogs(context),
                          child: const Text('Показать все'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Карточка загрузки из файла
            _UploadMethodCard(
              icon: Icons.file_upload,
              title: 'Из файла',
              description: 'Excel (.xlsx, .xls), CSV (.csv), Текст (.txt), RTF (.rtf)',
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

            const SizedBox(height: 12),

            // Простой импорт Excel (альтернативный)
            _UploadMethodCard(
              icon: Icons.table_chart,
              title: 'Простой импорт Excel',
              description: 'Базовая обработка Excel файлов с улучшенной обработкой ошибок',
              color: Colors.teal,
              onTap: _isLoading ? null : () => _uploadExcelSimple(),
            ),

            const SizedBox(height: 12),

            // Тестовая кнопка (только в debug режиме)
            if (kDebugMode) ...[
              _UploadMethodCard(
                icon: Icons.bug_report,
                title: 'Тест функций',
                description: 'Проверить работу экрана загрузки',
                color: Colors.red,
                onTap: () {
                  print('=== Test button pressed ===');
                  _addDebugLog('Тестовая кнопка нажата');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Тест пройден! Функции работают.')),
                  );
                },
              ),
            ],

            const SizedBox(height: 24),

            // Пример формата
            _FormatExample(),

            const SizedBox(height: 16),

            // Инструкция по конвертации Excel
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'Если Excel не загружается:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Откройте файл в Excel или Google Sheets'),
                    const Text('2. Выделите данные (Ctrl+A)'),
                    const Text('3. Скопируйте (Ctrl+C)'),
                    const Text('4. Используйте "Вставить текст" вместо файла'),
                    const SizedBox(height: 8),
                    Text(
                      'Или сохраните как CSV и загрузите как файл',
                      style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Кнопка тестирования парсинга
            if (kDebugMode) ElevatedButton.icon(
              onPressed: () {
                final testLine = 'Авокадо\t₫99,000';
                final result = _parseLine(testLine);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Тест парсинга: "$testLine" -> "${result.name}" @ ${result.price}')),
                );
              },
              icon: const Icon(Icons.bug_report),
              label: const Text('Тест парсинга'),
            ),

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

  Future<void> _uploadExcelSimple() async {
    print('=== _uploadExcelSimple called ===');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: false,
    );
    print('Excel simple picker result: ${result != null ? "files selected" : "cancelled"}');

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes != null) {
        final loc = context.read<LocalizationService>();
        await _processExcel(bytes, loc);
      }
    }
  }

  Future<void> _uploadFromFile() async {
    _addDebugLog('_uploadFromFile called');

    try {
      setState(() => _isLoading = true);
      _setLoadingMessage('Выбор файла...');
      _startLoadingTimeout(); // Предотвращаем зависание

      final loc = context.read<LocalizationService>();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'xlsx', 'xls', 'rtf', 'csv'],
        withData: true,
      );

      _addDebugLog('File picker result: ${result != null ? "files selected" : "cancelled"}');

      if (result == null || result.files.isEmpty || result.files.single.bytes == null) {
        _addDebugLog('File picker cancelled or no data');
        setState(() => _isLoading = false);
        return;
      }

    final fileName = result.files.single.name.toLowerCase();
    final bytes = result.files.single.bytes!;
    print('Processing file: $fileName');

    if (fileName.endsWith('.txt')) {
      print('Processing as TXT file');
      final text = utf8.decode(bytes, allowMalformed: true);
      await _processText(text, loc, true);
    } else if (fileName.endsWith('.rtf')) {
      final text = _extractTextFromRtf(utf8.decode(bytes, allowMalformed: true));
      await _processText(text, loc, true);
    } else if (fileName.endsWith('.csv')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
      // Конвертируем CSV в табличный формат
      final convertedLines = lines.map((line) {
        // Определяем разделитель
        if (line.contains(';')) {
          return line.split(';').map((cell) => cell.trim()).join('\t');
        } else if (line.contains(',')) {
          return line.split(',').map((cell) => cell.trim()).join('\t');
        } else {
          return line; // Уже в нужном формате
        }
      }).toList();
      await _processText(convertedLines.join('\n'), loc, true);
    } else if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
      await _processExcel(bytes, loc);
    }
    } catch (e, stackTrace) {
      _addDebugLog('Error in _uploadFromFile: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки файла: $e')),
        );
      }
    } finally {
      _cancelLoadingTimeout(); // Сбрасываем таймер
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showPasteDialog() async {
    _addDebugLog('_showPasteDialog called');

    try {
      setState(() => _isLoading = true);
      _setLoadingMessage('Открытие диалога...');
      _startLoadingTimeout(); // Предотвращаем зависание

      final loc = context.read<LocalizationService>();
      final controller = TextEditingController();
      bool addToNomenclature = true; // По умолчанию добавлять в номенклатуру

      _addDebugLog('Showing paste dialog...');
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
    } catch (e, stackTrace) {
      _addDebugLog('Error in _showPasteDialog: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка вставки текста: $e')),
        );
      }
    } finally {
      _cancelLoadingTimeout(); // Сбрасываем таймер
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showSmartPasteDialog() async {
    print('=== _showSmartPasteDialog called ===');
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
    print('=== _showIntelligentImportDialog called ===');
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
      final priceUpdateResults = importResults.where((r) =>
          r.matchResult.type == MatchType.priceUpdate).toList();

      if (priceUpdateResults.isNotEmpty) {
        // Показываем диалог для выбора режима обновления цен
        final updateMode = await _showPriceUpdateModeDialog(priceUpdateResults);
        if (updateMode == 'manual') {
          // Обрабатываем вручную - показываем диалог для каждого продукта
          await _processPriceUpdatesManually(importResults, importService, establishmentId, account);
        } else if (updateMode == 'all') {
          // Обновляем все цены автоматически
          await importService.processImportResults(
            importResults,
            {},
            establishmentId,
            account.establishment?.defaultCurrency ?? 'RUB',
          );
        }
        // Если null - пользователь отменил, ничего не делаем
      } else if (ambiguousResults.isNotEmpty) {
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

  Future<String?> _showPriceUpdateModeDialog(List<ProductImportResult> results) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Найдены продукты с измененными ценами'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Найдено ${results.length} продуктов, у которых цена отличается от существующей в номенклатуре.'),
            const SizedBox(height: 16),
            const Text('Выберите способ обновления:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('manual'),
            child: const Text('Обновить вручную'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('all'),
            child: const Text('Обновить все цены'),
          ),
        ],
      ),
    );
  }

  Future<void> _processPriceUpdatesManually(
    List<ProductImportResult> allResults,
    IntelligentProductImportService importService,
    String establishmentId,
    AccountManagerSupabase account,
  ) async {
    final resolutions = <String, String>{};

    // Обрабатываем только результаты с priceUpdate
    final priceUpdateResults = allResults.where((r) => r.matchResult.type == MatchType.priceUpdate).toList();

    for (final result in priceUpdateResults) {
      final updatePrice = await _showPriceUpdateDialog(result);
      if (updatePrice == true) {
        resolutions[result.fileName] = 'update';
      } else if (updatePrice == false) {
        resolutions[result.fileName] = 'skip';
      }
      // Если null - пользователь отменил весь процесс
      else {
        return;
      }
    }

    // Обрабатываем все результаты с resolutions
    await importService.processImportResults(
      allResults,
      resolutions,
      establishmentId,
      account.establishment?.defaultCurrency ?? 'RUB',
    );
  }

  Future<bool?> _showPriceUpdateDialog(ProductImportResult result) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Обновить цену продукта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Продукт: ${result.fileName}'),
            Text('Текущая цена в файле: ${result.filePrice}'),
            const SizedBox(height: 8),
            Text(
              'Продукт найден в номенклатуре, но цена отличается.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена импорта'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Пропустить'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Обновить цену'),
          ),
        ],
      ),
    );
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
    print('=== _processTextWithAI called ===');
    _addDebugLog('=== STARTING AI TEXT PROCESSING ===');
    _setLoadingMessage('Обрабатываем текст через ИИ...');

    setState(() => _isLoading = true);

    try {
      // Используем AI для извлечения продуктов из текста
      final aiService = context.read<AiService>();

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
      final checklistResult = await aiService.generateChecklistFromPrompt(prompt);
      _addDebugLog('AI response received');

      if (checklistResult == null || checklistResult.itemTitles.isEmpty) {
        throw Exception('AI не вернул результат');
      }

      // Парсим результат - itemTitles содержит строки в формате "Название|Цена|Валюта"
      final rawItems = checklistResult.itemTitles;

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
    print('=== _processText called ===');
    print('Text length: ${text.length}');
    print('Add to nomenclature: $addToNomenclature');
    _addDebugLog('=== STARTING TEXT PROCESSING ===');
    _addDebugLog('Text length: ${text.length} characters');
    _addDebugLog('Add to nomenclature: $addToNomenclature');
    _addDebugLog('Raw text preview (first 200 chars): "${text.substring(0, min(200, text.length))}"');

    // Проверяем основные параметры
    final account = context.read<AccountManagerSupabase>();
    final establishmentId = account.establishment?.id;
    print('User logged in: ${account.isLoggedInSync}');
    print('Establishment ID: $establishmentId');
    print('Services check - Account: ${account != null}, Establishment: ${account.establishment != null}');
    _addDebugLog('User logged in: ${account.isLoggedInSync}');
    _addDebugLog('Establishment ID: $establishmentId');

    if (!account.isLoggedInSync) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: пользователь не авторизован')),
      );
      return;
    }

    if (establishmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка: не найдено заведение')),
      );
      return;
    }

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
    print('=== _processExcel called ===');
    try {
      _addDebugLog('=== STARTING EXCEL PROCESSING ===');
      _addDebugLog('File size: ${bytes.length} bytes');

      // Проверка заголовка файла для определения типа
      String fileType = 'unknown';
      if (bytes.length >= 4) {
        final header = bytes.sublist(0, 4);
        if (header[0] == 0x50 && header[1] == 0x4B) {
          fileType = 'xlsx/zip'; // ZIP-based format (xlsx, docx, etc.)
        } else if (header[0] == 0xD0 && header[1] == 0xCF) {
          fileType = 'xls/ole'; // OLE format (xls)
        }
      }
      _addDebugLog('Detected file type: $fileType');

      late Excel excel;
      bool excelDecoded = false;
      try {
        excel = Excel.decodeBytes(bytes);
        _addDebugLog('Excel file decoded successfully');
        excelDecoded = true;
      } catch (excelError) {
        _addDebugLog('Excel decode error: $excelError');
        // Пробуем обработать как текст (CSV-подобный формат)
        _addDebugLog('Trying to process as text/CSV...');
        try {
          final textContent = String.fromCharCodes(bytes);
          await _processText(textContent, loc, true);
          return;
        } catch (textError) {
          _addDebugLog('Text processing also failed: $textError');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка чтения Excel файла: $excelError\nПопытка обработки как текст тоже неудачна.\nВозможно файл поврежден или имеет неподдерживаемый формат.\nТип файла: $fileType')),
          );
          return;
        }
      }

      if (!excelDecoded) return;

      if (excel.tables.isEmpty) {
        _addDebugLog('ERROR: No tables found in Excel file');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: файл Excel не содержит таблиц')),
        );
        return;
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      _addDebugLog('Processing sheet: $sheetName');

      if (sheet == null || sheet.rows.isEmpty) {
        _addDebugLog('ERROR: Sheet is null or empty');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: лист Excel пустой или недоступен')),
        );
        return;
      }

      _addDebugLog('Sheet has ${sheet.rows.length} rows');

      final lines = <String>[];
      int processedRows = 0;
      int errorRows = 0;

      try {
        for (var i = 0; i < sheet.rows.length; i++) {
          try {
            final row = sheet.rows[i];
            if (row == null || row.isEmpty) continue;

            final name = row.length > 0 ? row[0]?.value?.toString() ?? '' : '';
            final price = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
            final unit = row.length > 2 ? row[2]?.value?.toString() ?? '' : 'г';

            if (name.trim().isNotEmpty) {
              lines.add('$name\t$price\t$unit');
              processedRows++;
            }
          } catch (rowError) {
            _addDebugLog('Error processing row $i: $rowError');
            errorRows++;
            // Продолжаем обработку других строк
          }
        }
      } catch (sheetError) {
        _addDebugLog('Error accessing sheet rows: $sheetError');
        // Пробуем обработать как текст
        try {
          final textContent = String.fromCharCodes(bytes);
          await _processText(textContent, loc, true);
          return;
        } catch (textError) {
          _addDebugLog('Text processing fallback also failed: $textError');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка доступа к данным Excel: $sheetError\nFallback на текст тоже неудачен.')),
          );
          return;
        }
      }

      _addDebugLog('Processed $processedRows rows successfully, $errorRows rows had errors');
      _addDebugLog('Generated ${lines.length} product lines');

      if (lines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: не удалось извлечь ни одной строки с продуктами из Excel файла')),
        );
        return;
      }

      // Показываем превью первых строк
      final preview = lines.take(3).join('\n');
      _addDebugLog('Preview of extracted data:\n$preview');

      await _processText(lines.join('\n'), loc, true); // Для файлов всегда добавляем в номенклатуру
    } catch (e) {
      _addDebugLog('Standard Excel processing failed: $e');

      // Пробуем альтернативный метод
      _addDebugLog('Trying alternative CSV conversion method...');
      try {
        await _processExcelAsCsv(bytes, loc);
      } catch (csvError) {
        _addDebugLog('Alternative method also failed: $csvError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обработки Excel файла: $e\nАльтернативный метод также не сработал: $csvError\nПопробуйте:\n1. Сохранить файл как .xlsx из Excel\n2. Или скопируйте данные в текстовый формат')),
        );
      }
    }
  }

  /// Альтернативная обработка Excel через конвертацию в CSV
  Future<void> _processExcelAsCsv(Uint8List bytes, LocalizationService loc) async {
    try {
      _addDebugLog('=== TRYING EXCEL AS CSV CONVERSION ===');

      // Пробуем прочитать как CSV с разделителями табуляции или запятыми
      final content = String.fromCharCodes(bytes);
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        throw Exception('Файл пустой');
      }

      _addDebugLog('CSV conversion: found ${lines.length} lines');

      // Определяем разделитель
      final firstLine = lines.first;
      String separator = '\t'; // По умолчанию табуляция

      if (firstLine.contains(';')) {
        separator = ';';
        _addDebugLog('Detected semicolon separator');
      } else if (firstLine.contains(',')) {
        separator = ',';
        _addDebugLog('Detected comma separator');
      } else if (firstLine.contains('\t')) {
        _addDebugLog('Detected tab separator');
      }

      // Конвертируем в табличный формат
      final convertedLines = <String>[];
      for (final line in lines) {
        final parts = line.split(separator);
        if (parts.length >= 2) {
          final name = parts[0].trim();
          final price = parts.length > 1 ? parts[1].trim() : '';
          final unit = parts.length > 2 ? parts[2].trim() : 'г';

          if (name.isNotEmpty) {
            convertedLines.add('$name\t$price\t$unit');
          }
        }
      }

      _addDebugLog('Converted ${convertedLines.length} lines to tab format');

      if (convertedLines.isEmpty) {
        throw Exception('Не удалось конвертировать данные');
      }

      await _processText(convertedLines.join('\n'), loc, true);

    } catch (e) {
      _addDebugLog('CSV conversion failed: $e');
      throw Exception('Не удалось обработать файл даже как CSV: $e');
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

      // Обновляем список продуктов и номенклатуру
      _addDebugLog('Reloading products and nomenclature...');

      try {
        await store.loadProducts();
        _addDebugLog('Products loaded: ${store.allProducts.length}');
      } catch (e) {
        _addDebugLog('Error loading products: $e');
        // Продолжаем, даже если продукты не загрузились
      }

      try {
        await store.loadNomenclature(estId);
        _addDebugLog('Nomenclature loaded: ${store.nomenclatureProductIds.length}');
      } catch (e) {
        _addDebugLog('Error loading nomenclature: $e');
        // Показываем предупреждение, но не останавливаемся
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Предупреждение: не удалось загрузить номенклатуру ($e)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      if (mounted) setState(() {});

      // Показываем результат
      final message = failed == 0
          ? 'Добавлено: ${added + skipped}'
          : 'Добавлено: ${added + skipped}, Ошибок: $failed';

      print('DEBUG: Final result - Added: $added, Skipped: $skipped, Failed: $failed');

      // Сохраняем заказ в историю
      if (added > 0 || skipped > 0) {
        try {
          final orderService = context.read<OrderHistoryService>();
          final employeeId = account.currentEmployee?.id;

          if (employeeId != null) {
            await orderService.saveOrderToHistory(
              establishmentId: estId,
              employeeId: employeeId,
              orderData: {
                'items': items.map((item) => {
                  'name': item.name,
                  'price': item.price,
                }).toList(),
                'results': {
                  'added': added,
                  'skipped': skipped,
                  'failed': failed,
                },
                'addToNomenclature': addToNomenclature,
              },
            );
            print('DEBUG: Order saved to history');
          }
        } catch (e) {
          print('DEBUG: Failed to save order to history: $e');
          // Не показываем ошибку пользователю - история не критична
        }
      }

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
              : SingleChildScrollView(
                  child: SelectableText(
                    _debugLogs.join('\n'),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final logs = _debugLogs.join('\n');
              await Clipboard.setData(ClipboardData(text: logs));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Логи скопированы в буфер обмена')),
                );
              }
            },
            child: const Text('Копировать'),
          ),
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
