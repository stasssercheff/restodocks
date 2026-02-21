import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:xml/xml.dart';
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
  const ProductUploadScreen({super.key, this.defaultAddToNomenclature = true});

  /// По умолчанию true — добавлять в номенклатуру. false — только пополнение базы.
  final bool defaultAddToNomenclature;

  @override
  State<ProductUploadScreen> createState() => _ProductUploadScreenState();
}

class _ProductUploadScreenState extends State<ProductUploadScreen> {
  bool _isLoading = false;
  String _loadingMessage = '';
  int _loadingProgress = 0;
  int _loadingTotal = 0;
  Timer? _loadingTimeoutTimer; // Таймер для предотвращения зависания загрузки

  void _setLoadingMessage(String message) {
    if (mounted) {
      setState(() => _loadingMessage = message);
    }
  }

  // Предотвращает зависание интерфейса в состоянии загрузки
  void _startLoadingTimeout() {
    _loadingTimeoutTimer?.cancel();
    _loadingTimeoutTimer = Timer(const Duration(seconds: 90), () {
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                    if (_loadingTotal > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _loadingProgress / _loadingTotal,
                        backgroundColor: Colors.blue.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_loadingProgress / $_loadingTotal',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue.shade700),
                      ),
                    ],
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

            // Два способа загрузки
            Text(
              'Выберите способ:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 1. Загрузить из текста
            _UploadMethodCard(
              icon: Icons.edit_note,
              title: '1. Загрузить из текста',
              description: 'Вставьте список продуктов из Excel, мессенджера или заметок. '
                  'ИИ распознает формат, найдёт дубликаты, предложит сверку цен.',
              color: Colors.green,
              onTap: _isLoading ? null : () => _showTextUploadDialog(),
            ),
            const SizedBox(height: 12),

            // 2. Загрузить из файла
            _UploadMethodCard(
              icon: Icons.file_upload,
              title: '2. Загрузить из файла',
              description: 'Excel, CSV, текст (.txt, .rtf), Word (.docx), Apple Pages (.pages), Numbers (.numbers). '
                  'Модерация, поиск дубликатов ИИ, сверка цен.',
              color: Colors.blue,
              onTap: _isLoading ? null : () => _uploadFromFileUnified(),
            ),

            const SizedBox(height: 24),

            // Школа загрузки
            _UploadSchoolCard(),
          ],
        ),
      ),
    );
  }

  /// 1. Загрузить из текста — диалог вставки → _processWithDeferredModeration
  Future<void> _showTextUploadDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вставить список продуктов'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Вставьте список: из Excel (Ctrl+C), мессенджера, заметок. ИИ распознает формат.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Авокадо 99000\nБазилик 267000\nМолоко 38000',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Анализ'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;
    await _processWithDeferredModeration(text: result);
  }

  /// 2. Загрузить из файла — выбор файла → извлечение данных → _processWithDeferredModeration
  Future<void> _uploadFromFileUnified() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt', 'rtf', 'pages', 'numbers', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    final name = result.files.single.name.toLowerCase();
    List<String> rows = _extractRowsFromFile(bytes, name);

    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось извлечь данные. Попробуйте экспортировать в CSV или .xlsx.',
            ),
          ),
        );
      }
      return;
    }

    await _processWithDeferredModeration(rows: rows);
  }

  List<String> _extractRowsFromFile(Uint8List bytes, String name) {
    if (name.endsWith('.csv') || name.endsWith('.txt')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    if (name.endsWith('.rtf')) {
      final rtfContent = utf8.decode(bytes, allowMalformed: true);
      final rows = _extractRowsFromRtf(rtfContent);
      _addDebugLog('RTF processing: extracted ${rows.length} rows');
      for (var i = 0; i < min(5, rows.length); i++) {
        _addDebugLog('RTF row $i: "${rows[i]}"');
      }

      // Если RTF обработка не дала результатов, вернем то что есть
      // AI обработка будет выполнена позже в вызывающем коде

      return rows;
    }
    if (name.endsWith('.pages')) return _extractRowsFromPages(bytes);
    if (name.endsWith('.numbers')) return _extractRowsFromNumbers(bytes);
    if (name.endsWith('.docx')) return _extractRowsFromDocx(bytes);
    if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
      final rows = _extractRowsFromExcel(bytes);
      if (rows.isNotEmpty) return rows;
      final csvFallback = _tryCsvFallback(bytes);
      return csvFallback;
    }
    return [];
  }

  List<String> _extractRowsFromPages(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? xmlFile = archive.findFile('index.xml.gz') ?? archive.findFile('Index/Document.xml') ?? archive.findFile('index.xml');
      if (xmlFile == null) {
        for (final f in archive.files) {
          if (f.name.endsWith('.xml') && !f.name.contains('Preferences')) {
            xmlFile = f;
            break;
          }
        }
      }
      if (xmlFile == null) return [];
      var data = xmlFile.content as List<int>;
      if (xmlFile.name.endsWith('.gz')) {
        data = GZipDecoder().decodeBytes(data);
      }
      final xml = XmlDocument.parse(utf8.decode(data));
      final text = xml.descendants.where((n) => n is XmlText).map((n) => (n as XmlText).text.trim()).where((s) => s.isNotEmpty).join('\n');
      return text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      _addDebugLog('Pages extract error: $e');
      return [];
    }
  }

  List<String> _extractRowsFromNumbers(Uint8List bytes) {
    final excelRows = _extractRowsFromExcel(bytes);
    if (excelRows.isNotEmpty) return excelRows;
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files) {
        if (f.name.contains('Data') && f.name.endsWith('.xml') || f.name.contains('table') && f.name.endsWith('.xml')) {
          final xml = XmlDocument.parse(utf8.decode(f.content as List<int>));
          final rows = <String>[];
          for (final row in xml.findAllElements('row')) {
            final cells = row.findElements('cell').map((c) => c.innerText.trim()).toList();
            final line = cells.join('\t').trim();
            if (line.isNotEmpty && !_looksLikeGarbage(line)) rows.add(line);
          }
          if (rows.isNotEmpty) return rows;
        }
      }
      final anyXml = archive.files.where((f) => f.name.endsWith('.xml'));
      for (final f in anyXml) {
        try {
          final xml = XmlDocument.parse(utf8.decode(f.content as List<int>));
          final text = xml.descendants.where((n) => n is XmlText).map((n) => (n as XmlText).text.trim()).where((s) => s.isNotEmpty).join('\n');
          final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (lines.length >= 2) return lines;
        } catch (_) {}
      }
    } catch (e) {
      _addDebugLog('Numbers extract error: $e');
    }
    return [];
  }

  List<String> _extractRowsFromDocx(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final doc = archive.findFile('word/document.xml');
      if (doc == null) return [];
      final xml = XmlDocument.parse(utf8.decode(doc.content as List<int>));
      final paras = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 'p');
      final lines = <String>[];
      for (final p in paras) {
        final texts = p.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).toList();
        final line = texts.join('').trim();
        if (line.isNotEmpty) lines.add(line);
      }
      if (lines.isEmpty) {
        final allT = xml.descendants.whereType<XmlElement>().where((e) => e.localName == 't').map((e) => e.innerText).join(' ');
        if (allT.trim().isNotEmpty) return allT.split(RegExp(r'\s+')).where((s) => s.length > 1).toList();
      }
      return lines;
    } catch (e) {
      _addDebugLog('Docx extract error: $e');
      return [];
    }
  }

  /// Извлекает строки из Excel (xlsx/xls). Использует excel пакет, при ошибке — spreadsheet_decoder.
  List<String> _extractRowsFromExcel(Uint8List bytes) {
    final rows = _extractRowsFromExcelPackage(bytes);
    if (rows.isNotEmpty) return rows;
    return _extractRowsFromSpreadsheetDecoder(bytes);
  }

  List<String> _extractRowsFromExcelPackage(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes.toList());
      if (excel.tables.isEmpty) return [];
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;
      final rows = <String>[];
      for (var r = 0; r < sheet.maxRows; r++) {
        final parts = <String>[];
        for (var c = 0; c < sheet.maxColumns; c++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          parts.add(_excelCellToStr(cell.value));
        }
        final line = parts.join('\t').trim();
        if (line.isEmpty) continue;
        if (_looksLikeGarbage(line)) continue;
        rows.add(line);
      }
      return rows;
    } catch (e) {
      _addDebugLog('Excel package decode error: $e');
      return [];
    }
  }

  List<String> _extractRowsFromSpreadsheetDecoder(Uint8List bytes) {
    try {
      final decoder = SpreadsheetDecoder.decodeBytes(bytes.toList());
      if (decoder.tables.isEmpty) return [];
      final table = decoder.tables.values.first;
      final rows = <String>[];
      for (final row in table.rows) {
        final parts = row.map((c) => c?.toString().trim() ?? '').toList();
        final line = parts.join('\t').trim();
        if (line.isEmpty) continue;
        if (_looksLikeGarbage(line)) continue;
        rows.add(line);
      }
      return rows;
    } catch (e) {
      _addDebugLog('SpreadsheetDecoder error: $e');
      return [];
    }
  }

  static String _excelCellToStr(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) {
      return v.value.toString().trim();
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    return v.toString().trim();
  }

  List<String> _tryCsvFallback(Uint8List bytes) {
    if (bytes.length < 4) return [];
    if (bytes[0] == 0x50 && bytes[1] == 0x4B) return [];
    try {
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (lines.isEmpty) return [];
      if (_looksLikeGarbage(lines.first)) return [];
      return lines;
    } catch (_) {
      return [];
    }
  }

  static bool _looksLikeGarbage(String line) {
    if (line.length < 2) return true;
    if (line.startsWith('PK') || line.contains('.xml') || line.contains('workbook') ||
        line.contains('theme') || line.contains('[Content_Types]') ||
        RegExp(r'^[\x00-\x1f\x7f-\xff]+$').hasMatch(line)) return true;
    return false;
  }

  Future<void> _showImportWithModeration() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Импорт с модерацией'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Из файла'),
              subtitle: const Text('Excel, CSV'),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Вставить текст'),
              subtitle: const Text('Из мессенджеров, заметок'),
              onTap: () => Navigator.of(ctx).pop('text'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'file') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt', 'rtf', 'pages', 'numbers', 'docx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
      final bytes = result.files.single.bytes!;
      final name = result.files.single.name.toLowerCase();
      final rows = _extractRowsFromFile(bytes, name);
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось извлечь данные из файла')),
        );
        return;
      }
      await _processWithDeferredModeration(rows: rows);
    } else {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Вставить текст'),
          content: SizedBox(
            width: 500,
            child: TextField(
              controller: controller,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Вставьте список продуктов (название, цена, ед. изм.)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Анализ'),
            ),
          ],
        ),
      );
      if (result != null && result.trim().isNotEmpty) {
        await _processWithDeferredModeration(text: result);
      }
    }
  }

  Future<void> _processWithDeferredModeration({List<String>? rows, String? text}) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не найдено заведение')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    _startLoadingTimeout();
    _setLoadingMessage('Анализ данных ИИ...');

    try {
      // Используем локальный парсинг - надежный и быстрый
      List<ParsedProductItem> parsed = [];
      _setLoadingMessage('Разбор данных...');

      final rawLines = rows ?? text!.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      print('DEBUG: Processing ${rawLines.length} lines');
      for (var i = 0; i < rawLines.length; i++) {
        final line = rawLines[i];
        final r = _parseLine(line);
        print('DEBUG: Line $i: "$line" -> name: "${r.name}", price: ${r.price}');

        if (r.name.isNotEmpty) {
          parsed.add(ParsedProductItem(name: r.name, price: r.price, unit: null));
        }
      }

      print('DEBUG: Successfully parsed ${parsed.length} products');

      if (parsed.isEmpty) {
        _cancelLoadingTimeout();
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось извлечь продукты. Проверьте формат данных.')),
          );
        }
        return;
      }

      _setLoadingMessage('Сопоставление с базой...');
      final store = context.read<ProductStoreSupabase>();
      await store.loadNomenclature(est.id);
      final existingProducts = store.getNomenclatureProducts(est.id);
      final allProducts = store.allProducts;

      final moderationItems = <ModerationItem>[];
      final newNames = <String>[];
      final newIndices = <int>[];

      for (var i = 0; i < parsed.length; i++) {
        final p = parsed[i];
        final match = await _findMatch(p.name, p.price, existingProducts, allProducts, est.id, store);
        if (match.existingId != null) {
          moderationItems.add(ModerationItem(
            name: p.name,
            price: p.price,
            unit: p.unit,
            existingProductId: match.existingId,
            existingProductName: match.existingName,
            existingPrice: match.existingPrice,
            existingPriceFromEstablishment: match.existingPriceFromEstablishment,
            category: ModerationCategory.priceUpdate,
          ));
        } else {
          newNames.add(p.name);
          newIndices.add(moderationItems.length);
          moderationItems.add(ModerationItem(
            name: p.name,
            price: p.price,
            unit: p.unit,
            category: ModerationCategory.newProduct,
          ));
        }
      }

      if (newNames.isNotEmpty) {
        _setLoadingMessage('Исправление названий...');
        final ai = context.read<AiService>();
        final normalized = await ai.normalizeProductNames(newNames);
        if (mounted && normalized.length == newNames.length) {
          for (var j = 0; j < newIndices.length; j++) {
            final idx = newIndices[j];
            final norm = normalized[j];
            if (norm != moderationItems[idx].name) {
              moderationItems[idx] = moderationItems[idx].copyWith(
                normalizedName: norm,
                category: ModerationCategory.nameFix,
              );
            }
          }
        }
      }

      if (!mounted) return;
      _cancelLoadingTimeout();
      context.push('/import-review', extra: moderationItems);
    } catch (e) {
      if (mounted) {
        _cancelLoadingTimeout();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<({String? existingId, String? existingName, double? existingPrice, bool existingPriceFromEstablishment, bool priceDiff})> _findMatch(
    String name,
    double? price,
    List<Product> nomenclature,
    List<Product> allProducts,
    String establishmentId,
    ProductStoreSupabase store,
  ) async {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final p in nomenclature) {
      final pNames = [p.name, ...(p.names?.values ?? [])];
      for (final n in pNames) {
        final nNorm = n.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (nNorm == normalized) {
          // Получаем актуальную цену ТОЛЬКО из establishment_products
          final ep = store.getEstablishmentPrice(p.id, establishmentId);
          double? existingPrice = ep?.$1;
          final fromEstablishment = existingPrice != null;

          // Если цены нет в establishment_products, значит продукт есть в номенклатуре без цены
          // existingPrice остается null, что правильно - нет текущей цены для сравнения

          final priceDiff = price != null && existingPrice != null && (existingPrice - price).abs() > 0.01;
          return (existingId: p.id, existingName: p.name, existingPrice: existingPrice, existingPriceFromEstablishment: fromEstablishment, priceDiff: priceDiff);
        }
      }
    }
    return (existingId: null, existingName: null, existingPrice: null, existingPriceFromEstablishment: false, priceDiff: false);
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
      await _processText(text, loc, widget.defaultAddToNomenclature);
    } else if (fileName.endsWith('.rtf')) {
      final text = _extractTextFromRtf(utf8.decode(bytes, allowMalformed: true));
      await _processText(text, loc, widget.defaultAddToNomenclature);
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
      await _processText(convertedLines.join('\n'), loc, widget.defaultAddToNomenclature);
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
      bool addToNomenclature = widget.defaultAddToNomenclature;

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
    bool addToNomenclature = widget.defaultAddToNomenclature;

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

      // Перезагружаем номенклатуру чтобы цены в кэше соответствовали БД
      try {
        await context.read<ProductStoreSupabase>().loadNomenclature(establishmentId);
      } catch (_) {}

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
Ты - эксперт по обработке списков продуктов. Проанализируй этот текст и извлеки все продукты.

ПРАВИЛА ОБРАБОТКИ:
1. Ищи строки формата: "Название\t₫Цена" или "Название\tЦена₫" или "Название\tЦена"
2. Символ ₫ означает вьетнамские донги (VND)
3. Цены могут содержать запятые как разделители тысяч: 110,000 = 110000
4. Игнорируй пустые строки и заголовки

ФОРМАТ ВЫВОДА:
Каждая строка ровно в формате: "Название|ЦенаЧисло|Валюта"
- Название: точное название продукта
- ЦенаЧисло: число без запятых, точек и валюты (например: 110000)
- Валюта: VND для ₫, или пустое если не указано

ПРИМЕРЫ:
Авокадо|110000|VND
Базилик|267000|VND
Молоко||

Если цена содержит запятую (110,000) - преобразуй в число (110000).
Если валюта ₫ - укажи VND.

ТЕКСТ ДЛЯ ОБРАБОТКИ:
${text}
''';

      _addDebugLog('Sending AI request...');

      // Добавляем таймаут для AI запроса (30 секунд)
      final checklistResult = await aiService.generateChecklistFromPrompt(prompt).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _addDebugLog('AI request timed out after 30 seconds');
          throw Exception('AI processing timed out');
        },
      );

      _addDebugLog('AI response received');

      if (checklistResult == null || checklistResult.itemTitles.isEmpty) {
        throw Exception('AI не вернул результат');
      }

      // Парсим результат - itemTitles содержит строки в формате "Название|Цена|Валюта"
      final rawItems = checklistResult.itemTitles;
      _addDebugLog('AI returned ${rawItems.length} items');

      final items = <({String name, double? price})>[];
      for (final rawItem in rawItems) {
        try {
          if (rawItem is String && rawItem.contains('|')) {
            final parts = rawItem.split('|').map((s) => s.trim()).toList();
            _addDebugLog('Processing AI item: "$rawItem" -> parts: $parts');

            if (parts.length >= 1 && parts[0].isNotEmpty) {
              final name = parts[0];
              double? price;

              if (parts.length >= 2 && parts[1].isNotEmpty) {
                // Обрабатываем цену: убираем запятые, точки, пробелы
                final priceStr = parts[1]
                    .replaceAll(',', '')  // Убираем разделители тысяч
                    .replaceAll('.', '')  // Убираем десятичные точки
                    .replaceAll(' ', '')  // Убираем пробелы
                    .trim();

                price = double.tryParse(priceStr);
                _addDebugLog('Parsed price: "$priceStr" -> $price');
              }

              // Проверяем валюту - если VND и цена больше 1000, делим на 1000 (предполагаем копейки)
              if (parts.length >= 3 && parts[2] == 'VND' && price != null && price > 1000) {
                // Если цена слишком большая для VND (обычно до 1 млн), возможно это копейки
                if (price > 1000000) {
                  price = price / 1000; // Конвертируем из копеек в рубли/донги
                  _addDebugLog('Converted VND price from kopecks: $price');
                }
              }

              if (name.isNotEmpty) {
                items.add((name: name, price: price));
                _addDebugLog('Added item: "$name" @ $price');
              }
            }
          }
        } catch (e) {
          _addDebugLog('Error parsing AI item "$rawItem": $e');
        }
      }

      if (items.isNotEmpty) {
        // ОБНОВЛЯЕМ НОМЕНКЛАТУРУ ПЕРЕД ОБРАБОТКОЙ - КРИТИЧНО ДЛЯ ПРАВИЛЬНЫХ ЦЕН!
        final account = context.read<AccountManagerSupabase>();
        final store = context.read<ProductStoreSupabase>();
        final est = account.establishment;
        if (est != null) {
          _addDebugLog('Loading nomenclature before AI processing...');
          await store.loadNomenclature(est.id);
          _addDebugLog('Nomenclature loaded for AI processing, products: ${store.nomenclatureProductIds.length}');
        }

        // Инициализируем processingResults для всех продуктов
        final processingResults = <Map<String, dynamic>>[];
        for (final item in items) {
          processingResults.add({
            'name': item.name,
            'originalPrice': item.price,
            'oldPrice': null,
            'newPrice': item.price,
            'status': 'pending',
            'productId': null,
          });
        }

        await _addProductsToNomenclature(items, loc, addToNomenclature, processingResults);
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

    // Если формат требует AI обработки
    if (format == 'ai_needed') {
      return await _processTextWithAI(text, loc, addToNomenclature);
    }

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

    // Проверяем, есть ли товары с VND ценами - если да, но парсинг не сработал, используем AI
    final hasVNDInOriginal = text.contains('₫');
    final hasVNDParsed = items.any((item) => item.price != null && item.price! > 1000); // VND цены обычно > 1000

    if (hasVNDInOriginal && !hasVNDParsed) {
      _addDebugLog('WARNING: Text contains VND prices but parsing failed, switching to AI');
      return await _processTextWithAI(text, loc, addToNomenclature);
    }

    if (items.isEmpty) {
      _addDebugLog('ERROR: All items were filtered out! Check _parseLine logic.');
    } else {
      _addDebugLog('First 3 valid items:');
      for (var i = 0; i < min(3, items.length); i++) {
        _addDebugLog('  ${i}: "${items[i].name}" @ ${items[i].price}');
      }
    }

    if (items.isEmpty) {
      _addDebugLog('WARNING: Basic parsing failed, trying AI processing');
      _setLoadingMessage('Обычный парсинг не сработал, пробуем ИИ...');
      // Если обычный парсинг не сработал, пробуем AI
      return await _processTextWithAI(text, loc, addToNomenclature);
    }

    // ОБНОВЛЯЕМ НОМЕНКЛАТУРУ ПЕРЕД ОБРАБОТКОЙ - КРИТИЧНО ДЛЯ ПРАВИЛЬНЫХ ЦЕН!
    final store = context.read<ProductStoreSupabase>();
    final est = account.establishment;
    if (est != null) {
      _addDebugLog('Loading nomenclature before text processing...');
      await store.loadNomenclature(est.id);
      _addDebugLog('Nomenclature loaded for text processing, products: ${store.nomenclatureProductIds.length}');
    }

    _setLoadingMessage('Сохраняем ${items.length} продуктов...');

    // Инициализируем processingResults для всех продуктов
    final processingResults = <Map<String, dynamic>>[];
    for (final item in items) {
      processingResults.add({
        'name': item.name,
        'originalPrice': item.price,
        'oldPrice': null,
        'newPrice': item.price,
        'status': 'pending',
        'productId': null,
      });
    }

    await _addProductsToNomenclature(items, loc, addToNomenclature, processingResults);
  }

  String _detectTextFormat(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).take(5);
    print('DEBUG: Detecting format for ${lines.length} sample lines');

    // Проверяем на сложные форматы или форматы требующие AI
    bool hasComplexFormat = false;
    bool hasVNDPrices = false;

    for (final line in lines) {
      // Ищем признаки сложных форматов
      if (line.contains(' - ') ||
          line.contains(': ') ||
          line.contains('•') ||
          line.contains('(') && line.contains(')') ||
          RegExp(r'\d+\s*[a-zA-Zа-яА-Я]+\s*\d').hasMatch(line)) {
        hasComplexFormat = true;
      }

      // Проверяем на VND цены (₫)
      if (line.contains('₫')) {
        hasVNDPrices = true;
        hasComplexFormat = true; // VND форматы отправляем на AI
      }
    }

    if (hasComplexFormat) {
      _addDebugLog('Detected complex format (or VND prices), using AI processing');
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
          await _processText(textContent, loc, widget.defaultAddToNomenclature);
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
          await _processText(textContent, loc, widget.defaultAddToNomenclature);
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

      await _processText(lines.join('\n'), loc, widget.defaultAddToNomenclature);
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

      await _processText(convertedLines.join('\n'), loc, widget.defaultAddToNomenclature);

    } catch (e) {
      _addDebugLog('CSV conversion failed: $e');
      throw Exception('Не удалось обработать файл даже как CSV: $e');
    }
  }

  Future<void> _addProductsToNomenclature(List<({String name, double? price})> items, LocalizationService loc, bool addToNomenclature, List<Map<String, dynamic>> processingResults) async {
    _addDebugLog('=== STARTING PRODUCT CREATION ===');
    _addDebugLog('Items to process: ${items.length}');
    _addDebugLog('Add to nomenclature: $addToNomenclature');

    if (items.isEmpty) {
      _addDebugLog('ERROR: No items to process!');
      return;
    }
    _setLoadingMessage('Обрабатываем ${items.length} продуктов...');
    setState(() {
      _isLoading = true;
      _loadingTotal = items.length;
      _loadingProgress = 0;
    });

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
      int idx = 0;

      for (final item in items) {
        if (mounted) {
          setState(() {
            _loadingProgress = idx;
            _loadingMessage = 'Обрабатываем ${idx + 1} из ${items.length}: ${item.name}';
          });
        }
        idx++;
        try {
        // Используем ИИ для исправления опечаток и нормализации названия
        ProductVerificationResult? verification;
        String normalizedName = item.name;
        try {
          final aiService = context.read<AiServiceSupabase>();
          verification = await aiService.verifyProduct(
            item.name,
            currentPrice: item.price,
          );
          _addDebugLog('AI verification successful for "${item.name}": normalized="${verification?.normalizedName}", calories=${verification?.suggestedCalories}');

          // Используем нормализованное название от AI, если оно отличается
          if (verification?.normalizedName != null && verification!.normalizedName!.isNotEmpty) {
            normalizedName = verification!.normalizedName!;
            _addDebugLog('Using AI-normalized name: "${item.name}" -> "${normalizedName}"');
          }
        } catch (aiError) {
          _addDebugLog('AI verification failed for "${item.name}": $aiError');
          verification = null;
        }

        // Дополнительная локальная нормализация названий
        normalizedName = _normalizeProductName(normalizedName);
        var names = <String, String>{for (final c in allLangs) c: normalizedName};

        // ПРОВЕРКА НА СУЩЕСТВОВАНИЕ ПОХОЖЕГО ПРОДУКТА
        Product? existingProduct = await _findSimilarProduct(normalizedName, store);
        if (existingProduct != null) {
          _addDebugLog('Found similar existing product: "${existingProduct.name}" (ID: ${existingProduct.id})');

          // Если продукт найден, проверяем нужно ли обновлять цену
          if (item.price != null) {
            final oldPrice = existingProduct.basePrice;
            final newPrice = item.price;

            // Проверяем, отличается ли цена (с учетом округления до 2 знаков)
            final oldPriceRounded = (oldPrice ?? 0).roundToDouble();
            final newPriceRounded = newPrice.roundToDouble();

            if ((oldPrice == null && newPrice != null) || (oldPrice != null && (oldPriceRounded - newPriceRounded).abs() > 0.01)) {
              // Цена изменилась или была null - обновляем
              try {
                _addDebugLog('Updating price for existing product "${existingProduct.name}": $oldPrice -> $newPrice');
                await store.setEstablishmentPrice(estId, existingProduct.id, newPrice, defCur);

                // Добавляем в номенклатуру если нужно
                if (addToNomenclature) {
                  await store.addToNomenclature(estId, existingProduct.id, price: newPrice, currency: defCur);
                }

                skipped++;
                _addDebugLog('Successfully updated existing product price');

                // Находим и обновляем соответствующий продукт в результатах
                final existingResult = processingResults.firstWhere(
                  (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
                  orElse: () => <String, dynamic>{},
                );
                if (existingResult.isNotEmpty) {
                  existingResult['status'] = 'updated';
                  existingResult['oldPrice'] = oldPrice;
                  existingResult['newPrice'] = newPrice;
                  existingResult['productId'] = existingProduct.id;
                }

                continue; // Пропускаем создание нового продукта
              } catch (updateError) {
                _addDebugLog('Failed to update existing product price: $updateError');
                // Продолжаем с созданием нового продукта
              }
            } else {
              // Цена не изменилась - отмечаем как пропущенный и не показываем в результатах
              _addDebugLog('Price unchanged for "${existingProduct.name}": $oldPrice (keeping existing)');

              // Добавляем в номенклатуру если нужно (без изменения цены)
              if (addToNomenclature) {
                try {
                  await store.addToNomenclature(estId, existingProduct.id, price: oldPrice, currency: defCur);
                } catch (e) {
                  _addDebugLog('Failed to add to nomenclature: $e');
                }
              }

              // Отмечаем как успешно обработанный, но без изменений
              final existingResult = processingResults.firstWhere(
                (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
                orElse: () => <String, dynamic>{},
              );
              if (existingResult.isNotEmpty) {
                existingResult['status'] = 'no_change';
                existingResult['oldPrice'] = oldPrice;
                existingResult['newPrice'] = newPrice;
                existingResult['productId'] = existingProduct.id;
              }

              skipped++;
              continue; // Пропускаем создание нового продукта
            }
          }
        }

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
                'name': normalizedName,
                if (product.names != null)
                  for (final entry in product.names!.entries)
                    'name_${entry.key}': entry.value,
              },
              sourceLanguage: 'ru',
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
              await store.addToNomenclature(
                estId,
                product.id,
                price: product.basePrice,
                currency: product.currency ?? defCur,
              );
              added++;
              print('DEBUG: Successfully added "${product.name}" to nomenclature');

              // Находим и обновляем соответствующий продукт в результатах
              final existingResult = processingResults.firstWhere(
                (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
                orElse: () => <String, dynamic>{},
              );
              if (existingResult.isNotEmpty) {
                existingResult['status'] = 'added';
                existingResult['oldPrice'] = null;
                existingResult['newPrice'] = product.basePrice;
                existingResult['productId'] = product.id;
              }
            } catch (e) {
              print('DEBUG: Failed to add "${product.name}" to nomenclature: $e');
              if (e.toString().contains('duplicate key') ||
                  e.toString().contains('already exists') ||
                  e.toString().contains('unique constraint')) {
                print('DEBUG: Product "${product.name}" already in nomenclature, skipping');
                skipped++;
                // Обновляем статус продукта в результатах
                final existingResult = processingResults.firstWhere(
                  (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
                  orElse: () => <String, dynamic>{},
                );
                if (existingResult.isNotEmpty) {
                  existingResult['status'] = 'skipped';
                  existingResult['reason'] = 'already_exists';
                }
              } else {
                print('DEBUG: Unexpected error adding "${product.name}" to nomenclature: $e');
                failed++;
                // Обновляем статус продукта в результатах
                final existingResult = processingResults.firstWhere(
                  (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
                  orElse: () => <String, dynamic>{},
                );
                if (existingResult.isNotEmpty) {
                  existingResult['status'] = 'error';
                  existingResult['error'] = e.toString();
                }
              }
            }
          } else {
            // Продукт добавлен только в базу
            added++;
            print('DEBUG: Product "${product.name}" added to database only');

            // Находим и обновляем соответствующий продукт в результатах
            final existingResult = processingResults.firstWhere(
              (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
              orElse: () => <String, dynamic>{},
            );
            if (existingResult.isNotEmpty) {
              existingResult['status'] = 'added_db_only';
              existingResult['oldPrice'] = null;
              existingResult['newPrice'] = product.basePrice;
              existingResult['productId'] = product.id;
            }
          }

          // Небольшая задержка
          await Future.delayed(const Duration(milliseconds: 100));

        } catch (e) {
          failed++;
          // Обновляем статус продукта в результатах
          final existingResult = processingResults.firstWhere(
            (r) => _normalizeForComparison(r['name'] as String) == _normalizeForComparison(item.name),
            orElse: () => <String, dynamic>{},
          );
          if (existingResult.isNotEmpty) {
            existingResult['status'] = 'error';
            existingResult['error'] = e.toString();
          }
          _addDebugLog('Error processing product "${item.name}": $e');
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

      if (mounted) setState(() {
        _loadingProgress = items.length;
        _loadingMessage = 'Готово';
      });

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
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Загрузка завершена'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed == 0
                        ? 'Успешно обработано: ${added + skipped} продуктов.'
                        : 'Обработано: ${added + skipped}.\nОшибок: $failed.',
                  ),
                  if (processingResults.where((r) => r['status'] == 'no_change').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${processingResults.where((r) => r['status'] == 'no_change').length} продуктов без изменений цен',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Фильтруем результаты - показываем только те, где произошли изменения
                  final changedResults = processingResults.where((r) => r['status'] != 'no_change').toList();
                  if (changedResults.isNotEmpty) ...[
                    const Text(
                      'Детальные результаты:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: changedResults.length,
                        itemBuilder: (context, index) {
                          final result = changedResults[index];
                          final status = result['status'] as String;
                          final name = result['name'] as String;
                          final oldPrice = result['oldPrice'] as double?;
                          final newPrice = result['newPrice'] as double?;

                          String statusText;
                          Color statusColor;
                          String priceText = '';

                          switch (status) {
                            case 'added':
                              statusText = 'Добавлен';
                              statusColor = Colors.green;
                              priceText = newPrice != null ? '${newPrice.toStringAsFixed(0)} ${defCur}' : '';
                              break;
                            case 'added_db_only':
                              statusText = 'Добавлен (только в БД)';
                              statusColor = Colors.blue;
                              priceText = newPrice != null ? '${newPrice.toStringAsFixed(0)} ${defCur}' : '';
                              break;
                            case 'updated':
                              statusText = 'Цена обновлена';
                              statusColor = Colors.orange;
                              if (oldPrice != null && newPrice != null) {
                                priceText = '${oldPrice.toStringAsFixed(0)} → ${newPrice.toStringAsFixed(0)} ${defCur}';
                              } else if (newPrice != null) {
                                priceText = '${newPrice.toStringAsFixed(0)} ${defCur}';
                              }
                              break;
                            case 'skipped':
                              statusText = 'Пропущен';
                              statusColor = Colors.blue;
                              priceText = newPrice != null ? '${newPrice.toStringAsFixed(0)} ${defCur}' : '';
                              break;
                            case 'error':
                              statusText = 'Ошибка';
                              statusColor = Colors.red;
                              priceText = newPrice != null ? '${newPrice.toStringAsFixed(0)} ${defCur}' : '';
                              break;
                            case 'pending':
                              statusText = 'Ожидает';
                              statusColor = Colors.grey;
                              priceText = newPrice != null ? '${newPrice.toStringAsFixed(0)} ${defCur}' : '';
                              break;
                            default:
                              statusText = 'Неизвестно';
                              statusColor = Colors.grey;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    priceText,
                                    style: const TextStyle(fontSize: 12),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Результаты:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('• Новые продукты: $added'),
                    Text('• Обновлены цены: $skipped'),
                    if (failed > 0) Text('• Ошибок: $failed'),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Примечание: Для обновленных продуктов цены были изменены в соответствии с данными из файла.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
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
          _loadingProgress = 0;
          _loadingTotal = 0;
        });
      }
    }
  }

  /// Поиск похожего существующего продукта
  Future<Product?> _findSimilarProduct(String productName, ProductStoreSupabase store) async {
    try {
      // Получаем все продукты
      final allProducts = store.allProducts;

      // Нормализуем искомое название для сравнения
      final normalizedSearch = _normalizeForComparison(productName);

      for (final product in allProducts) {
        final normalizedExisting = _normalizeForComparison(product.name);

        // Проверяем точное совпадение после нормализации
        if (normalizedExisting == normalizedSearch) {
          return product;
        }

        // Проверяем на высокую схожесть (расстояние Левенштейна или простые метрики)
        final similarity = _calculateSimilarity(normalizedSearch, normalizedExisting);
        if (similarity > 0.8) { // 80% схожести
          _addDebugLog('High similarity found: "$normalizedSearch" vs "$normalizedExisting" (${(similarity * 100).round()}%)');
          return product;
        }
      }

      // Если не нашли с помощью простых методов, попробуем AI
      try {
        final aiService = context.read<AiServiceSupabase>();
        final prompt = '''
Проверь, есть ли в списке продуктов тот, который очень похож на "${productName}".

Список продуктов:
${allProducts.map((p) => p.name).join('\n')}

Если найдешь очень похожий продукт (с опечатками, синонимами или небольшими отличиями), верни только его название.
Если ничего похожего нет, верни пустую строку.

Примеры:
- "авокало" -> "Авокадо"
- "картошка" -> "Картофель"
- "говядина вырезка" -> "Говядина"
''';

        final result = await aiService.generateChecklistFromPrompt(prompt);
        if (result != null && result.itemTitles.isNotEmpty) {
          final aiSuggestion = result.itemTitles.first.trim();
          if (aiSuggestion.isNotEmpty && aiSuggestion != productName) {
            // Ищем продукт с таким названием
            final aiProduct = allProducts.firstWhere(
              (p) => p.name.toLowerCase() == aiSuggestion.toLowerCase(),
              orElse: () => null as Product,
            );
            if (aiProduct != null) {
              _addDebugLog('AI found similar product: "$productName" -> "$aiSuggestion"');
              return aiProduct;
            }
          }
        }
      } catch (aiError) {
        _addDebugLog('AI similarity check failed: $aiError');
      }

      return null;
    } catch (e) {
      _addDebugLog('Error in _findSimilarProduct: $e');
      return null;
    }
  }

  /// Нормализация названия для сравнения (убираем регистр, пробелы, пунктуацию)
  String _normalizeForComparison(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sа-яё]'), '') // Убираем пунктуацию, оставляем буквы и пробелы
        .replaceAll(RegExp(r'\s+'), ' ') // Нормализуем пробелы
        .trim();
  }

  /// Простая метрика схожести строк (0.0 - 1.0)
  double _calculateSimilarity(String str1, String str2) {
    if (str1 == str2) return 1.0;
    if (str1.isEmpty || str2.isEmpty) return 0.0;

    // Простая метрика: общие слова / общее количество слов
    final words1 = str1.split(' ').toSet();
    final words2 = str2.split(' ').toSet();
    final intersection = words1.intersection(words2).length;
    final union = words1.union(words2).length;

    return union > 0 ? intersection / union : 0.0;
  }

  /// Локальная нормализация названий продуктов
  String _normalizeProductName(String name) {
    String normalized = name.trim();

    // Исправить распространенные опечатки и стандартизировать
    final corrections = {
      // Фрукты и овощи
      'авокадо': 'Авокадо',
      'авокало': 'Авокадо',
      'абокадо': 'Авокадо',
      'картошка': 'Картофель',
      'картофель': 'Картофель',
      'картофель свежий': 'Картофель',
      'морковка': 'Морковь',
      'морковь': 'Морковь',
      'морковь свежая': 'Морковь',
      'лук': 'Лук репчатый',
      'лук репка': 'Лук репчатый',
      'лук репчатый': 'Лук репчатый',
      'томат': 'Томаты',
      'томаты': 'Томаты',
      'помидоры': 'Томаты',
      'огурец': 'Огурцы',
      'огурцы': 'Огурцы',
      'огурец свежий': 'Огурцы',
      'перец': 'Перец болгарский',
      'болгарский перец': 'Перец болгарский',
      'перец болгарский': 'Перец болгарский',
      'капуста': 'Капуста',
      'брокколи': 'Капуста брокколи',
      'капуста брокколи': 'Капуста брокколи',
      'зелень': 'Зелень',
      'укроп': 'Укроп',
      'петрушка': 'Петрушка',
      'кинза': 'Кинза',
      'базилик': 'Базилик',
      'розмарин': 'Розмарин',
      'тимьян': 'Тимьян',
      'чеснок': 'Чеснок',
      'имбирь': 'Имбирь',

      // Молочные продукты
      'молоко': 'Молоко',
      'молоко цельное': 'Молоко',
      'сыр': 'Сыр',
      'масло': 'Масло сливочное',
      'сливочное масло': 'Масло сливочное',
      'масло сливочное': 'Масло сливочное',
      'йогурт': 'Йогурт',
      'кефир': 'Кефир',
      'творог': 'Творог',
      'сметана': 'Сметана',
      'сливки': 'Сливки',

      // Мясо и рыба
      'курица': 'Курица',
      'курица грудка': 'Кура грудка филе',
      'кура грудка': 'Кура грудка филе',
      'говядина': 'Говядина',
      'говядина вырезка': 'Говядина',
      'свинина': 'Свинина',
      'рыба': 'Рыба',
      'лосось': 'Лосось',
      'семга': 'Семга',
      'форель': 'Форель',
      'тунец': 'Тунец',
      'креветки': 'Креветки',
      'осьминог': 'Осьминог',
      'кальмары': 'Кальмары',

      // Крупы и зерновые
      'рис': 'Рис',
      'гречка': 'Крупа гречневая',
      'овсянка': 'Каша овсянная',
      'пшенка': 'Каша пшенная',
      'перловка': 'Крупа перловая',
      'манка': 'Крупа манная',

      // Напитки и специи
      'соль': 'Соль',
      'перец черный': 'Перец черный молотый',
      'сахар': 'Сахар',
      'мед': 'Мед',
      'уксус': 'Уксус',
      'соус': 'Соус',

      // Хлебобулочные
      'хлеб': 'Хлеб',
      'батон': 'Батон',
      'багет': 'Багет',
    };

    // Применить исправления
    for (final entry in corrections.entries) {
      if (normalized.toLowerCase().contains(entry.key)) {
        normalized = entry.value;
        break;
      }
    }

    // Убрать лишние пробелы и заглавные буквы
    normalized = normalized.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');

    return normalized;
  }

  ({String name, double? price}) _parseLine(String line) {
    // Сначала попробуем найти паттерны с ценами в конце строки
    _addDebugLog('DEBUG: Parsing line: "${line.replaceAll('\t', '[TAB]')}"');

    // Тестовый вывод для отладки (можно удалить после тестирования)
    if (line.contains('Авокадо')) {
      _addDebugLog('TEST: Found avocado line, contains tab: ${line.contains('\t')}, length: ${line.length}');
    }
    // Важно: паттерн с валютой ПЕРЕД числом (₫99,000) идёт первым
    final pricePatterns = [
      RegExp(r'[₫$€£¥руб.]\s*[\d,\.]+\s*$'), // валюта перед числом: ₫99,000 или ₫ 99.000
      RegExp(r'[\d,]+\s*[₫$€£¥руб.]?\s*$'), // число с опциональной валютой в конце
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

  List<String> _extractRowsFromRtf(String rtfContent) {
    _addDebugLog('Starting RTF processing, content length: ${rtfContent.length}');

    // Сначала пробуем извлечь данные из таблиц RTF
    final tableRows = _extractTableDataFromRtf(rtfContent);
    if (tableRows.isNotEmpty) {
      _addDebugLog('Found ${tableRows.length} table rows in RTF');
      return tableRows;
    }

    // Если таблиц нет, используем обычную обработку текста
    final text = _extractTextFromRtf(rtfContent);
    _addDebugLog('Extracted text from RTF: "${text.substring(0, min(200, text.length))}"');

    // Разбиваем на строки и фильтруем
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // Дополнительная обработка для поиска паттернов продукт-цена
    final processedLines = <String>[];

    for (final line in lines) {
      // Ищем строки, которые выглядят как "Название\tЦена" или "Название Цена"
      if (_looksLikeProductLine(line)) {
        processedLines.add(line);
      } else {
        // Разбиваем сложные строки на отдельные продукты
        final subLines = _splitComplexLine(line);
        processedLines.addAll(subLines);
      }
    }

    _addDebugLog('Processed RTF into ${processedLines.length} product lines');
    return processedLines;
  }

  List<String> _extractTableDataFromRtf(String rtf) {
    final rows = <String>[];

    // Ищем RTF таблицы (группы \trowd)
    final tablePattern = RegExp(r'\\trowd.*?\\row', dotAll: true);
    final tables = tablePattern.allMatches(rtf);

    for (final tableMatch in tables) {
      final tableContent = tableMatch.group(0) ?? '';

      // Извлекаем ячейки из таблицы
      final cellPattern = RegExp(r'\\cell\s*([^\\]*(?:\\[^c][^e][^l][^l][^\\]*)*)');
      final cells = cellPattern.allMatches(tableContent);

      if (cells.length >= 2) {
        // Берем первые две ячейки (название и цена)
        final nameCell = _cleanRtfCell(cells.first.group(1) ?? '');
        final priceCell = cells.length > 1 ? _cleanRtfCell(cells.elementAt(1).group(1) ?? '') : '';

        if (nameCell.isNotEmpty) {
          final row = priceCell.isNotEmpty ? '$nameCell\t$priceCell' : nameCell;
          rows.add(row);
        }
      }
    }

    return rows;
  }

  bool _looksLikeProductLine(String line) {
    // Проверяем, выглядит ли строка как продукт с ценой
    return line.contains('\t') ||
           RegExp(r'\d+[,.]\d+').hasMatch(line) || // Десятичные числа
           RegExp(r'\d{3,}').hasMatch(line) || // Большие числа (цены)
           line.contains('₫') ||
           line.contains('\$') ||
           line.contains('руб') ||
           line.contains('€');
  }

  List<String> _splitComplexLine(String line) {
    final result = <String>[];

    // Разбиваем по запятым, если это список продуктов
    if (line.contains(',') && !line.contains('\t')) {
      final parts = line.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
      for (final part in parts) {
        if (_looksLikeProductLine(part)) {
          result.add(part);
        }
      }
    }

    // Если не смогли разбить, возвращаем оригинальную строку
    if (result.isEmpty && _looksLikeProductLine(line)) {
      result.add(line);
    }

    return result;
  }

  String _cleanRtfCell(String cellContent) {
    try {
      // Очищаем содержимое ячейки RTF от команд
      var cleaned = cellContent;

      // Обрабатываем специальные символы
      cleaned = cleaned.replaceAll('\\\'', '\'');
      cleaned = cleaned.replaceAll('\\~', ' ');
      cleaned = cleaned.replaceAll('\\-', '');
      cleaned = cleaned.replaceAll('\\_', '_');
      cleaned = cleaned.replaceAll('\\tab', '\t');

      // Удаляем RTF команды, но сохраняем текст
      cleaned = cleaned.replaceAllMapped(RegExp(r'\\[a-z]+\d*'), (match) {
        final cmd = match.group(0)!;
        // Специальные случаи
        if (cmd == '\\tab') return '\t';
        if (cmd == '\\par' || cmd == '\\line') return '\n';
        return '';
      });

      // Удаляем пустые группы, сохраняя содержимое
      cleaned = cleaned.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (match) {
        final content = match.group(1)!;
        // Если контент содержит текст, сохраняем его
        if (content.contains(RegExp(r'[а-яёa-z0-9]', caseSensitive: false))) {
          return content;
        }
        return '';
      });

      // Удаляем оставшиеся скобки и команды
      cleaned = cleaned.replaceAll(RegExp(r'[{}]+'), '');
      cleaned = cleaned.replaceAll('\\cell', '');
      cleaned = cleaned.replaceAll('\\row', '');

      // Нормализуем пробелы и очищаем
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

      return cleaned;
    } catch (e) {
      _addDebugLog('Error cleaning RTF cell: $e');
      return cellContent.replaceAll(RegExp(r'\\[^{]*'), '').replaceAll(RegExp(r'[{}]'), '').trim();
    }
  }

  String _extractTextFromRtf(String rtf) {
    try {
      _addDebugLog('Starting RTF text extraction, length: ${rtf.length}');

      // Сначала попробуем найти основной текстовый контент
      // Ищем паттерн \viewkind4 или другие индикаторы основного текста
      final viewkindIndex = rtf.indexOf('\\viewkind');
      if (viewkindIndex != -1) {
        rtf = rtf.substring(viewkindIndex);
      }

      // Удаляем шрифтовые таблицы и другие служебные группы
      rtf = rtf.replaceAll(RegExp(r'\\fonttbl\{[^}]*\}', caseSensitive: false), '');
      rtf = rtf.replaceAll(RegExp(r'\\colortbl\{[^}]*\}', caseSensitive: false), '');
      rtf = rtf.replaceAll(RegExp(r'\\stylesheet\{[^}]*\}', caseSensitive: false), '');
      rtf = rtf.replaceAll(RegExp(r'\\info\{[^}]*\}', caseSensitive: false), '');

      // Обрабатываем специальные символы
      rtf = rtf.replaceAll('\\\'', '\'');
      rtf = rtf.replaceAll('\\~', ' ');
      rtf = rtf.replaceAll('\\-', '');
      rtf = rtf.replaceAll('\\_', '_');

      // Заменяем \par и \line на переносы строк
      rtf = rtf.replaceAll('\\par', '\n');
      rtf = rtf.replaceAll('\\line', '\n');
      rtf = rtf.replaceAll('\\tab', '\t');

      // Удаляем оставшиеся RTF команды, но сохраняем текст между ними
      // Используем более аккуратный подход
      final commandPattern = RegExp(r'\\[a-z]+\d*');
      rtf = rtf.replaceAllMapped(commandPattern, (match) {
        final cmd = match.group(0)!;
        // Сохраняем пробелы после некоторых команд
        if (cmd.startsWith('\\ ') || cmd == '\\tab') {
          return '\t';
        }
        return '';
      });

      // Удаляем пустые группы, но сохраняем их содержимое
      rtf = rtf.replaceAllMapped(RegExp(r'\{([^{}]*)\}'), (match) {
        final content = match.group(1)!;
        // Если контент содержит текст, сохраняем его
        if (content.contains(RegExp(r'[а-яёa-z]', caseSensitive: false))) {
          return content;
        }
        return '';
      });

      // Финальная очистка
      rtf = rtf.replaceAll(RegExp(r'[{}]+'), '');
      rtf = rtf.replaceAll(RegExp(r'\s+'), ' ').trim();

      _addDebugLog('RTF extraction result: "${rtf.substring(0, min(100, rtf.length))}"');
      return rtf;
    } catch (e) {
      _addDebugLog('Error extracting text from RTF: $e');
      // Fallback: простое извлечение
      return rtf.replaceAll(RegExp(r'\\[^{]*'), '').replaceAll(RegExp(r'[{}]'), '').trim();
    }
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

/// Раскрывающийся блок «Школа загрузки» с инструкциями
class _UploadSchoolCard extends StatelessWidget {
  const _UploadSchoolCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.school, color: Theme.of(context).colorScheme.primary),
          title: Text(
            'Школа загрузки',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('Формат данных, типы файлов, модерация'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Формат данных:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Авокадо\t99000\nБазилик\t267000\nМолоко\t38000',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Название и цена — через Tab или пробелы. ИИ распознаёт запятые, символы валюты.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Text('Поддерживаемые файлы:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Excel (.xlsx, .xls), CSV, текст (.txt, .rtf), Word (.docx), Apple Pages, Numbers.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Text('Модерация:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'После загрузки откроется экран проверки. Там можно:\n'
                    '• Подтвердить или отклонить изменение цен\n'
                    '• Добавить новые продукты в номенклатуру\n'
                    '• Исправить названия, предложенные ИИ',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
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
