import 'dart:async';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../mixins/auto_save_mixin.dart';
import '../mixins/input_change_listener_mixin.dart';
import '../widgets/app_bar_home_button.dart';

/// Единица для ПФ в бланке: вес (г) или штуки/порции.
const String _pfUnitGrams = 'g';
const String _pfUnitPcs = 'pcs';

/// Строка бланка: продукт из номенклатуры, полуфабрикат (ТТК) или свободная строка (например, с чека).
class _InventoryRow {
  final Product? product;
  final TechCard? techCard;
  /// ID для восстановления из черновика (до загрузки номенклатуры).
  final String? productId;
  final String? techCardId;
  /// Свободная строка (распознанный чек): когда product и techCard оба null.
  final String? freeName;
  final String? freeUnit;
  final List<double> quantities;
  /// Для ПФ: единица в бланке — 'g' (граммы) или 'pcs' (порции/штуки). По умолчанию 'pcs'.
  final String? pfUnit;
  /// Переопределение единицы для продукта (null = использовать product.unit).
  final String? unitOverride;

  _InventoryRow({
    this.product,
    this.techCard,
    this.productId,
    this.techCardId,
    this.freeName,
    this.freeUnit,
    required this.quantities,
    this.pfUnit,
    this.unitOverride,
  })  : assert(product != null || techCard != null || (freeName != null && freeName.isNotEmpty) || productId != null || techCardId != null),
        assert(product == null || techCard == null);

  bool get isPf => techCard != null || techCardId != null;
  bool get isFree => product == null && techCard == null;

  String productName(String lang) {
    if (product != null) return product!.getLocalizedName(lang);
    if (techCard != null) return techCard!.getDisplayNameInLists(lang);
    return freeName ?? '';
  }

  /// Единица для отображения: unitOverride (продукт) или product.unit/freeUnit/pfUnit.
  String get unit {
    if (product != null && unitOverride != null) return unitOverride!;
    if (product != null) return product!.unit ?? 'g';
    return freeUnit ?? 'g';
  }
  /// Для ПФ используем pfUnit: g → гр/g, иначе порц./pcs.
  String unitDisplay(String lang) {
    if (isPf) {
      final u = pfUnit ?? _pfUnitPcs;
      return u == _pfUnitGrams ? (lang == 'ru' ? 'гр' : 'g') : (lang == 'ru' ? 'порц.' : 'pcs');
    }
    return CulinaryUnits.displayName(unit.toLowerCase(), lang);
  }

  /// В бланке инвентаризации вес показываем в граммах, не в кг.
  bool get isWeightInKg =>
      !isPf && (unit.toLowerCase() == 'kg' || unit == 'кг');
  String unitDisplayForBlank(String lang) =>
      isWeightInKg ? (lang == 'ru' ? 'гр' : 'g') : unitDisplay(lang);
  double quantityDisplayAt(int i) =>
      isWeightInKg ? quantities[i] * 1000 : quantities[i];
  double get totalDisplay => isWeightInKg ? total * 1000 : total;

  /// Сумма всех числовых значений строки (включая вторую ячейку и далее; последняя пустая — буфер для n+1).
  double get total {
    if (quantities.isEmpty) return 0.0;
    return quantities.fold(0.0, (a, b) => a + b);
  }

  _InventoryRow copyWith({Product? product, TechCard? techCard, String? pfUnit, String? unitOverride}) => _InventoryRow(
        product: product ?? this.product,
        techCard: techCard ?? this.techCard,
        productId: product != null ? null : productId,
        techCardId: techCard != null ? null : techCardId,
        freeName: freeName,
        freeUnit: freeUnit,
        quantities: quantities,
        pfUnit: pfUnit ?? this.pfUnit,
        unitOverride: unitOverride ?? this.unitOverride,
      );
}

enum _InventorySort { alphabetAsc, alphabetDesc, lastAdded }

/// Фильтр по типу строк: все, только продукты, только ПФ.
enum _InventoryBlockFilter { all, productsOnly, pfOnly }

/// Бланк инвентаризации: продукты из номенклатуры и полуфабрикаты (ПФ) в одном документе.
/// Шапка (заведение, сотрудник, дата, время), таблица (#, Наименование, Мера, Итого, Количество).
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with AutoSaveMixin<InventoryScreen>, InputChangeListenerMixin<InventoryScreen> {
  final ScrollController _hScroll = ScrollController();
  Timer? _serverAutoSaveTimer; // Таймер для автоматической отправки на сервер каждые 30 секунд
  final List<_InventoryRow> _rows = [];
  /// Продукты, перерасчитанные из ПФ (третья секция); заполняется при загрузке файла.
  List<Map<String, dynamic>>? _aggregatedFromFile;
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _completed = false;
  bool _isInputMode = false; // Режим ввода количества (клавиатура открыта)
  _InventorySort _sortMode = _InventorySort.alphabetAsc;
  _InventoryBlockFilter _blockFilter = _InventoryBlockFilter.all;
  final TextEditingController _nameFilterCtrl = TextEditingController();
  String _nameFilter = '';

  /// Сохранить данные немедленно в локальное хранилище (SharedPreferences/localStorage)
  void saveNow() {
    saveImmediately(); // Немедленно, без debounce — данные не потеряются при закрытии/падении
  }

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNomenclature());
    _nameFilterCtrl.addListener(() {
      if (_nameFilter != _nameFilterCtrl.text) {
        setState(() => _nameFilter = _nameFilterCtrl.text);
      }
    });

    // Настроить автосохранение - сохранять чаще
    setOnInputChanged(() {
      // Сохранять немедленно при любом изменении
      saveNow();
    });

    // Настроить автоматическую отправку на сервер каждые 30 секунд
    _serverAutoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_completed) {
        _autoSaveToServer();
      }
    });
  }

  @override
  String get draftKey => 'inventory';

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'date': _date.toIso8601String(),
      'startTime': _startTime?.format(context) ?? '',
      'endTime': _endTime?.format(context) ?? '',
      'completed': _completed,
      'sortMode': _sortMode.name,
      'blockFilter': _blockFilter.name,
      'nameFilter': _nameFilter,
      'rows': _rows.map((row) => {
        'productId': row.product?.id,
        'techCardId': row.techCard?.id,
        'freeName': row.freeName,
        'freeUnit': row.freeUnit,
        'quantities': row.quantities,
        'pfUnit': row.pfUnit,
        'unitOverride': row.unitOverride,
      }).toList(),
      'aggregatedFromFile': _aggregatedFromFile,
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    setState(() {
      _date = DateTime.parse(data['date'] ?? DateTime.now().toIso8601String());
      _startTime = data['startTime'] != null && data['startTime'].isNotEmpty
          ? TimeOfDay.fromDateTime(DateTime.parse('2023-01-01 ${data['startTime']}'))
          : null;
      _endTime = data['endTime'] != null && data['endTime'].isNotEmpty
          ? TimeOfDay.fromDateTime(DateTime.parse('2023-01-01 ${data['endTime']}'))
          : null;
      _completed = data['completed'] ?? false;

      final sortModeName = data['sortMode'] ?? 'alphabetAsc';
      _sortMode = _InventorySort.values.firstWhere(
        (e) => e.name == sortModeName || (sortModeName == 'alphabet' && e == _InventorySort.alphabetAsc),
        orElse: () => _InventorySort.alphabetAsc,
      );
      if (_sortMode == _InventorySort.lastAdded) _sortMode = _InventorySort.alphabetAsc;

      final blockFilterName = data['blockFilter'] ?? 'all';
      _blockFilter = _InventoryBlockFilter.values.firstWhere(
        (e) => e.name == blockFilterName,
        orElse: () => _InventoryBlockFilter.all,
      );

      _nameFilter = data['nameFilter'] ?? '';
      _nameFilterCtrl.text = _nameFilter;

      // Восстановить строки (product/techCard будут подставлены в _loadNomenclature)
      final rowsData = data['rows'] as List<dynamic>? ?? [];
      _rows.clear();
      for (final rowData in rowsData) {
        final Map<String, dynamic> rowMap = rowData as Map<String, dynamic>;
        final quantities = (rowMap['quantities'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0];
        final productId = rowMap['productId'] as String?;
        final techCardId = rowMap['techCardId'] as String?;

        // Нормализуем quantities
        List<double> qty = List.from(quantities);
        if (rowMap['freeName'] != null && qty.isNotEmpty && qty.last != 0.0) {
          qty.add(0.0);
        } else if (rowMap['freeName'] != null && qty.isEmpty) {
          qty.addAll([0.0, 0.0]);
        }
        if (!rowMap.containsKey('freeName') && productId == null && techCardId == null) {
          // Пустая строка продукта/ПФ — оставляем как есть
        } else if (productId != null || techCardId != null) {
          if (qty.isEmpty) qty.addAll([0.0, 0.0]);
          else while (qty.length < 2) qty.add(0.0);
        }

        _rows.add(_InventoryRow(
          product: null,
          techCard: null,
          productId: productId,
          techCardId: techCardId,
          freeName: rowMap['freeName'],
          freeUnit: rowMap['freeUnit'],
          quantities: qty,
          pfUnit: rowMap['pfUnit'],
          unitOverride: rowMap['unitOverride'],
        ));
      }

      _aggregatedFromFile = data['aggregatedFromFile'];
    });

    // Перезагрузить номенклатуру для восстановления связей с продуктами и ТТК
    await _loadNomenclature();
  }

  bool _matchesNameFilter(String name) {
    if (_nameFilter.isEmpty) return true;
    return name.toLowerCase().contains(_nameFilter.toLowerCase());
  }

  /// Индексы строк-продуктов и свободных (номенклатура + с чека), отсортированы и отфильтрованы.
  List<int> get _productIndices {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    var indices = List.generate(_rows.length, (i) => i)
        .where((i) => !_rows[i].isPf && _matchesNameFilter(_rows[i].productName(lang)))
        .toList();
    if (_sortMode == _InventorySort.alphabetAsc) {
      indices.sort((a, b) => _rows[a].productName(lang).toLowerCase().compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => _rows[b].productName(lang).toLowerCase().compareTo(_rows[a].productName(lang).toLowerCase()));
    }
    return indices;
  }

  /// Индексы строк-ПФ (из ТТК), отсортированы и отфильтрованы.
  List<int> get _pfIndices {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    var indices = List.generate(_rows.length, (i) => i)
        .where((i) => _rows[i].isPf && _matchesNameFilter(_rows[i].productName(lang)))
        .toList();
    if (_sortMode == _InventorySort.alphabetAsc) {
      indices.sort((a, b) => _rows[a].productName(lang).toLowerCase().compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => _rows[b].productName(lang).toLowerCase().compareTo(_rows[a].productName(lang).toLowerCase()));
    }
    return indices;
  }

  /// Порядок отображения: сначала продукты, потом ПФ (для обратной совместимости с нумерацией в Excel).
  List<int> get _displayOrder => [..._productIndices, ..._pfIndices];

  /// Автоматическая подстановка: номенклатура заведения + полуфабрикаты (ТТК с типом ПФ).
  Future<void> _loadNomenclature() async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    await store.loadProducts();
    await store.loadNomenclature(estId);
    final techCards = await techCardSvc.getTechCardsForEstablishment(estId);
    if (!mounted) return;
    final products = store.getNomenclatureProducts(estId);
    final pfOnly = techCards.where((tc) => tc.isSemiFinished).toList();
    final productMap = {for (final p in products) p.id: p};
    final techCardMap = {for (final tc in pfOnly) tc.id: tc};
    setState(() {
      // Сначала разрешаем productId/techCardId в восстановленных строках
      for (var i = 0; i < _rows.length; i++) {
        final row = _rows[i];
        if (row.productId != null && row.product == null) {
          final p = productMap[row.productId];
          if (p != null) {
            _rows[i] = row.copyWith(product: p);
          }
        } else if (row.techCardId != null && row.techCard == null) {
          final tc = techCardMap[row.techCardId];
          if (tc != null) {
            _rows[i] = row.copyWith(techCard: tc);
          }
        }
      }
      // Все новые строки всегда начинаются с 2 колонок
      final minQtyCount = 2;

      // Добавляем недостающие продукты и ПФ
      for (final p in products) {
        if (_rows.any((r) => r.product?.id == p.id || r.productId == p.id)) continue;
        _rows.add(_InventoryRow(product: p, techCard: null, quantities: List<double>.filled(minQtyCount, 0.0)));
      }
      for (final tc in pfOnly) {
        if (_rows.any((r) => r.techCard?.id == tc.id || r.techCardId == tc.id)) continue;
        _rows.add(_InventoryRow(product: null, techCard: tc, quantities: List<double>.filled(minQtyCount, 0.0), pfUnit: _pfUnitPcs));
      }

      for (var i = 0; i < _rows.length; i++) {
        final row = _rows[i];
        while (row.quantities.length < 2) {
          row.quantities.add(0.0);
        }
      }
    });
  }

  /// Добавить строки из распознанного чека (ИИ).
  void _addReceiptLines(List<ReceiptLine> lines) {
    setState(() {
      for (final line in lines) {
        if (line.productName.trim().isEmpty) continue;
        final qty = line.quantity > 0 ? line.quantity : 1.0;
        final unit = (line.unit ?? 'g').trim().isEmpty ? 'g' : (line.unit ?? 'g');
        _rows.add(_InventoryRow(
          product: null,
          techCard: null,
          freeName: line.productName.trim(),
          freeUnit: unit,
          quantities: [qty, 0.0],
        ));
      }
    });
    scheduleSave(); // Автосохранение при добавлении строк из чека
  }

  Future<void> _scanReceipt(BuildContext context, LocalizationService loc) async {
    if (_completed) return;
    final imageService = ImageService();
    final xFile = await imageService.pickImageFromGallery();
    if (xFile == null || !mounted) return;
    final bytes = await imageService.xFileToBytes(xFile);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    final ai = context.read<AiService>();
    final result = await ai.recognizeReceipt(bytes);
    if (!mounted) return;
    if (result == null || result.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('inventory_receipt_scan_empty'))),
      );
      return;
    }
    _addReceiptLines(result.lines);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.t('inventory_receipt_scan_added').replaceAll('%s', '${result.lines.length}'))),
    );
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _nameFilterCtrl.dispose();
    _serverAutoSaveTimer?.cancel(); // Отменить таймер автосохранения на сервер
    super.dispose();
  }

  /// Автоматическая отправка данных на сервер каждые 30 секунд
  Future<void> _autoSaveToServer() async {
    if (_completed || _rows.isEmpty) return; // Не сохранять если завершено или пусто

    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) return;

      // Получить текущие данные
      final currentState = getCurrentState();

      // Отправить на сервер как черновик инвентаризации
      await _saveDraftToServer(establishmentId, currentState);

      print('📡 Auto-saved inventory draft to server');
    } catch (e) {
      // Тихая ошибка - не показывать пользователю
      print('⚠️ Failed to auto-save inventory draft: $e');
    }
  }

  /// Сохранить черновик инвентаризации на сервер
  Future<void> _saveDraftToServer(String establishmentId, Map<String, dynamic> data) async {
    try {
      final account = context.read<AccountManagerSupabase>();
      final employeeId = account.currentEmployee?.id;

      final draftData = {
        'establishment_id': establishmentId,
        'employee_id': employeeId,
        'draft_data': data,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Отправить в таблицу inventory_drafts
      await Supabase.instance.client
          .from('inventory_drafts')
          .upsert(
            draftData,
            onConflict: 'establishment_id',
          );

      print('✅ Auto-saved inventory draft to server');
    } catch (e) {
      print('⚠️ Failed to save inventory draft to server: $e');
      // Если сервер недоступен, данные все равно сохранены локально
    }
  }

  /// Минимум 2 пустых ячейки при открытии. При заполнении последней — добавляется ещё одна.
  int get _maxQuantityColumns {
    if (_rows.isEmpty) return 2;
    return _rows.map((r) => r.quantities.length).fold<int>(2, (a, b) => a > b ? a : b);
  }

  void _addQuantityToRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    if (_rows[rowIndex].isFree) return; // свободные строки — без добавления колонок
    setState(() {
      // Всегда добавляем пустую ячейку в конец
      _rows[rowIndex].quantities.add(0.0);
    });
  }

  void _setPfUnit(int rowIndex, String unit) {
    if (rowIndex < 0 || rowIndex >= _rows.length || !_rows[rowIndex].isPf) return;
    setState(() {
      _rows[rowIndex] = _rows[rowIndex].copyWith(pfUnit: unit);
    });
    saveNow();
  }

  void _setProductUnit(int rowIndex, String unit) {
    if (rowIndex < 0 || rowIndex >= _rows.length || _rows[rowIndex].product == null) return;
    setState(() {
      _rows[rowIndex] = _rows[rowIndex].copyWith(unitOverride: unit);
    });
    saveNow();
  }

  /// Перерасчёт ПФ в исходные продукты по ТТК (для третьей секции бланка).
  List<Map<String, dynamic>> _aggregateProductsFromPf(String lang) {
    final tcById = <String, TechCard>{};
    for (final r in _rows) {
      if (r.techCard != null) tcById[r.techCard!.id] = r.techCard!;
    }
    final result = <String, Map<String, dynamic>>{};

    void addIngredients(List<TTIngredient> ingredients, double factor) {
      for (final ing in ingredients) {
        if (ing.productId != null && ing.productName.isNotEmpty) {
          final key = ing.productId!;
          final gross = ing.grossWeight * factor;
          final net = ing.netWeight * factor;
          if (result.containsKey(key)) {
            result[key]!['grossGrams'] = (result[key]!['grossGrams'] as double) + gross;
            result[key]!['netGrams'] = (result[key]!['netGrams'] as double) + net;
          } else {
            result[key] = {
              'productId': key,
              'productName': ing.productName,
              'grossGrams': gross,
              'netGrams': net,
            };
          }
        } else if (ing.sourceTechCardId != null) {
          final nested = tcById[ing.sourceTechCardId!];
          if (nested != null) {
            final nestedYield = nested.yield > 0 ? nested.yield : nested.totalNetWeight;
            if (nestedYield > 0) {
              final nestedFactor = (ing.netWeight * factor) / nestedYield;
              addIngredients(nested.ingredients, nestedFactor);
            }
          }
        }
      }
    }

    for (final r in _rows) {
      if (!r.isPf || r.techCard == null || r.quantities.isEmpty || r.quantities[0] <= 0) continue;
      final tc = r.techCard!;
      if (tc.ingredients.isEmpty) continue;
      final yieldVal = tc.yield > 0 ? tc.yield : tc.totalNetWeight;
      if (yieldVal <= 0) continue;
      final qty = r.quantities[0];
      final pfU = r.pfUnit ?? _pfUnitPcs;
      final factor = pfU == _pfUnitGrams ? qty / yieldVal : (qty * tc.portionWeight) / yieldVal;
      addIngredients(tc.ingredients, factor);
    }

    final list = result.values.toList();
    list.sort((a, b) => (a['productName'] as String).compareTo(b['productName'] as String));
    return list;
  }

  void _addColumnToAll() {
    setState(() {
      for (final r in _rows) {
        if (!r.isFree) r.quantities.add(0.0);
      }
    });
  }

  void _addProduct(Product p) {
    // Все новые продукты начинаются с 2 колонок
    final quantities = List<double>.filled(2, 0.0);
    setState(() {
      _rows.add(_InventoryRow(product: p, techCard: null, quantities: quantities));
    });
    saveNow(); // Сохранить немедленно при добавлении продукта
  }

  /// Обновление значения ячейки. При вводе в последнюю ячейку — добавляется новая колонка ко всем строкам (n+1).
  void _setQuantity(int rowIndex, int colIndex, double value) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.quantities.length) return;

    setState(() {
      row.quantities[colIndex] = value;
      if (colIndex == row.quantities.length - 1) {
        _addColumnToAll();
      }
    });
    saveNow();
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
    });
    saveNow(); // Сохранить немедленно при удалении строки
  }

  Future<void> _pickDate(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: Locale(loc.currentLanguageCode),
    );
    if (picked != null) {
      setState(() => _date = picked);
      scheduleSave(); // Автосохранение при изменении даты
    }
  }

  Future<void> _complete(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('inventory_complete_confirm')),
        content: Text(loc.t('inventory_complete_confirm_detail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('inventory_complete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (establishment == null || employee == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_no_chef'))),
        );
      }
      return;
    }

    final chefs = await account.getExecutiveChefsForEstablishment(establishment.id);
    if (chefs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_no_chef'))),
        );
      }
      return;
    }

    final chef = chefs.first;
    final endTime = TimeOfDay.now();
    final aggregatedProducts = _aggregateProductsFromPf(loc.currentLanguageCode);
    final payload = _buildPayload(
      establishment: establishment,
      employee: employee,
      endTime: endTime,
      lang: loc.currentLanguageCode,
      aggregatedProducts: aggregatedProducts,
    );
    final docService = InventoryDocumentService();
    await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: chef.id,
      recipientEmail: chef.email,
      payload: payload,
    );

    // Сохраняем инвентаризацию в историю перед установкой статуса
    try {
      final inventoryService = context.read<InventoryHistoryService>();
      await inventoryService.saveInventoryToHistory(
        establishmentId: establishment.id,
        employeeId: employee.id,
        inventoryData: {
          'rows': _rows.map((row) => {
            'productId': row.product?.id,
            'techCardId': row.techCard?.id,
            'freeName': row.freeName,
            'freeUnit': row.freeUnit,
            'quantities': row.quantities,
            'pfUnit': row.pfUnit,
          }).toList(),
          'aggregatedProducts': aggregatedProducts,
          'payload': payload,
        },
        date: _date,
        startTime: _startTime,
        endTime: endTime,
        notes: 'Отправлено шефу ${chef.fullName}',
      );
      print('✅ Inventory saved to history');
    } catch (e) {
      print('⚠️ Failed to save inventory to history: $e');
      // Продолжаем выполнение, так как сохранение в историю не критично
    }

    if (mounted) {
      setState(() {
        _endTime = endTime;
        _completed = true;
      });
      // Очистка черновика после успешной отправки
      clearDraft();
    }

    // Генерация Excel и скачивание без почтового клиента
    try {
      final bytes = _buildExcelBytes(payload, loc);
      if (bytes != null && bytes.isNotEmpty && mounted) {
        await _downloadExcel(bytes, payload, loc);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inventory_excel_downloaded'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('inventory_document_saved')} (Excel: ${e.toString()})')),
        );
      }
    }
  }

  /// Столбцы Excel: номер, наименование, мера, итоговое количество, данные при заполнении (1, 2, ...)
  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final maxCols = _maxQuantityColumns;
    try {
      final excel = Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final fillLabel = loc.t('inventory_excel_fill_data');
      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }
      sheet.appendRow(headerCells);
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total.toDouble()),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? (quantities[c] as num?)?.toDouble() ?? 0.0 : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet.appendRow(rowCells);
      }

      // Третья секция: продукты, перерасчитанные из ПФ по ТТК
      final aggregated = payload['aggregatedProducts'] as List<dynamic>? ?? [];
      if (aggregated.isNotEmpty) {
        sheet.appendRow([]);
        sheet.appendRow([TextCellValue(loc.t('inventory_pf_products_title'))]);
        sheet.appendRow([
          TextCellValue(loc.t('inventory_excel_number')),
          TextCellValue(loc.t('inventory_item_name')),
          TextCellValue(loc.t('inventory_pf_gross_g')),
          TextCellValue(loc.t('inventory_pf_net_g')),
        ]);
        for (var i = 0; i < aggregated.length; i++) {
          final p = aggregated[i] as Map<String, dynamic>;
          sheet.appendRow([
            IntCellValue(i + 1),
            TextCellValue((p['productName'] as String? ?? '').toString()),
            IntCellValue(((p['grossGrams'] as num?)?.toDouble() ?? 0).round()),
            IntCellValue(((p['netGrams'] as num?)?.toDouble() ?? 0).round()),
          ]);
        }
      }

      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _downloadExcel(List<int> bytes, Map<String, dynamic> payload, LocalizationService loc) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ?? DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.xlsx';
    await saveFileBytes(fileName, bytes);
  }

  static String _cellStr(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) {
      final val = v.value;
      try {
        final t = (val as dynamic).text;
        if (t != null) return t is String ? t : t.toString();
      } catch (_) {}
      final String s = val is String ? val as String : (val ?? '').toString();
      return s;
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    return v.toString();
  }

  static double _cellNum(CellValue? v) {
    if (v == null) return 0;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is DoubleCellValue) return v.value;
    final s = _cellStr(v).replaceFirst(',', '.');
    return double.tryParse(s) ?? 0;
  }

  /// Загрузка заполненного бланка: первая таблица → _rows, третья секция → _aggregatedFromFile.
  Future<void> _loadFilledFile(BuildContext context, LocalizationService loc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null) return;
    final bytes = Uint8List.fromList(result.files.single.bytes!);
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    await store.loadProducts();
    await store.loadNomenclature(estId);
    final techCards = await techCardSvc.getTechCardsForEstablishment(estId);
    final pfOnly = techCards.where((tc) => tc.isSemiFinished).toList();
    final products = store.getNomenclatureProducts(estId);
    final lang = loc.currentLanguageCode;

    try {
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.isNotEmpty ? excel.tables.keys.first : null;
      if (sheetName == null) throw Exception('No sheet');
      final sheet = excel.tables[sheetName]!;
      final newRows = <_InventoryRow>[];
      List<Map<String, dynamic>>? aggregated = [];
      var r = 1;
      final maxRows = sheet.maxRows;
      final maxCols = sheet.maxColumns;

      while (r < maxRows) {
        final nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
        final name = _cellStr(nameCell.value).trim();
        if (name.isEmpty) {
          r++;
          continue;
        }
        if (name.toLowerCase().contains('продукт') && (name.toLowerCase().contains('пф') || name.toLowerCase().contains('перерасч'))) {
          r++;
          break;
        }
        final unitStr = _cellStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value).trim().toLowerCase();
        final total = _cellNum(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value);
        final quantities = <double>[];
        for (var c = 4; c < maxCols; c++) {
          final q = _cellNum(sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).value);
          if (c == 4 || q != 0 || quantities.isNotEmpty) quantities.add(q);
        }
        if (quantities.isEmpty) quantities.add(total);

        Product? product;
        TechCard? techCard;
        String? freeName;
        String? freeUnit;
        String? pfUnit;
        String? dishNameForPf;
        if (name.startsWith('ПФ ')) {
          dishNameForPf = name.substring(3).trim();
        } else if (name.endsWith(' (ПФ)')) {
          dishNameForPf = name.substring(0, name.length - 5).trim();
        }
        if (dishNameForPf != null) {
          techCard = pfOnly.cast<TechCard?>().firstWhere((t) => t?.getLocalizedDishName(lang) == dishNameForPf, orElse: () => null);
          if (techCard == null) {
            freeName = name;
            freeUnit = unitStr.contains('гр') || unitStr == 'g' ? 'g' : 'pcs';
          } else {
            pfUnit = (unitStr.contains('гр') || unitStr == 'g') ? _pfUnitGrams : _pfUnitPcs;
          }
        } else if (dishNameForPf == null) {
          product = products.cast<Product?>().firstWhere((p) => p?.getLocalizedName(lang) == name, orElse: () => null);
          if (product == null) {
            freeName = name;
            freeUnit = unitStr.contains('гр') || unitStr == 'g' ? 'g' : (unitStr.contains('порц') || unitStr == 'pcs' ? 'pcs' : unitStr);
          } else if ((product.unit ?? '').toLowerCase() == 'kg' || product.unit == 'кг') {
            for (var i = 0; i < quantities.length; i++) quantities[i] = quantities[i] / 1000;
          }
        }

        // Нормализуем quantities: всегда должна быть хотя бы одна пустая ячейка в конце для продуктов
        if (dishNameForPf == null && quantities.isNotEmpty && quantities.last != 0.0) {
          quantities.add(0.0);
        } else if (dishNameForPf == null && quantities.isEmpty) {
          quantities.add(0.0);
          quantities.add(0.0); // Для новых строк всегда две пустые ячейки
        }

        newRows.add(_InventoryRow(
          product: product,
          techCard: techCard,
          freeName: freeName,
          freeUnit: freeUnit,
          quantities: quantities,
          pfUnit: pfUnit,
        ));
        r++;
      }

      while (r < maxRows) {
        final a1 = _cellStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value).trim();
        if (a1.isEmpty) {
          r++;
          continue;
        }
        final a2 = _cellStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value).toLowerCase();
        if (a2.contains('брутто') || a2.contains('gross')) {
          r++;
          break;
        }
        r++;
      }

      while (r < maxRows) {
        final name = _cellStr(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value).trim();
        if (name.isEmpty) break;
        final gross = _cellNum(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value);
        final net = _cellNum(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value);
        aggregated!.add({'productName': name, 'grossGrams': gross, 'netGrams': net});
        r++;
      }
      if (aggregated != null && aggregated.isEmpty) aggregated = null;

      if (!mounted) return;
      setState(() {
        _rows.clear();
        _rows.addAll(newRows);
        _aggregatedFromFile = aggregated;
        _completed = false;
      });
      if (mounted) {
        final msg = loc.t('inventory_loaded').replaceAll('%s', '${newRows.length}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        final errMsg = loc.t('error_with_message').replaceAll('%s', e.toString());
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
      }
    }
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required TimeOfDay endTime,
    required String lang,
    List<Map<String, dynamic>>? aggregatedProducts,
  }) {
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'employeeRole': employee.roleDisplayName,
      'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'timeStart': _startTime != null
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
          : null,
      'timeEnd': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
    final rows = _rows.map((r) {
      final id = r.product != null
          ? r.product!.id
          : r.techCard != null
              ? 'pf_${r.techCard!.id}'
              : 'free_${_rows.indexOf(r)}';
      final useGrams = r.isWeightInKg;
      final map = <String, dynamic>{
        'productId': id,
        'productName': r.productName(lang),
        'unit': r.unitDisplayForBlank(lang),
        'quantities': useGrams ? r.quantities.map((q) => q * 1000).toList() : r.quantities,
        'total': useGrams ? r.total * 1000 : r.total,
      };
      if (r.isPf) map['pfUnit'] = r.pfUnit ?? _pfUnitPcs;
      return map;
    }).toList();
    return {
      'header': header,
      'rows': rows,
      'aggregatedProducts': aggregatedProducts ?? [],
    };
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    // Определяем режим ввода (клавиатура открыта или активно поле ввода)
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isKeyboardOpen = viewInsets.bottom > 0;
    // Не меняем _isInputMode слишком часто, чтобы не сбивать фокус
    if (isKeyboardOpen && !_isInputMode) {
      _isInputMode = true;
    } else if (!isKeyboardOpen && _isInputMode) {
      // Задержка перед выключением режима ввода
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && MediaQuery.viewInsetsOf(context).bottom == 0) {
          setState(() => _isInputMode = false);
        }
      });
    }

    return Scaffold(
      appBar: _isInputMode ? AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        title: Text(
          loc.t('inventory_blank_title'),
          style: const TextStyle(fontSize: 16),
        ),
        toolbarHeight: 48,
        elevation: 0,
        actions: [appBarHomeButton(context)],
      ) : AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inventory_blank_title')),
        actions: [appBarHomeButton(context)],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isInputMode) _buildHeader(loc, establishment, employee),
              if (!_isInputMode) const Divider(height: 1),
              Expanded(
                child: _buildTable(loc),
              ),
              if (!_isInputMode) const Divider(height: 1),
              _buildFooter(loc),
            ],
          ),
          if (!_isInputMode) DataSafetyIndicator(isVisible: true),
        ],
      ),
    );
  }

  /// Шапка: дата_время начала_имя_должность_время завершения (компактно в 1 строку)
  Widget _buildHeader(
    LocalizationService loc,
    Establishment? establishment,
    Employee? employee,
  ) {
    // В режиме ввода скрываем верхний информационный блок
    if (_isInputMode) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final dateStr = '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    final startStr = _startTime != null ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}' : '—';
    final endStr = _endTime != null ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}' : null;
    final roleStr = employee?.roleDisplayName ?? '—';
    final headerLine = '$dateStr ${startStr} ${employee?.fullName ?? '—'} ($roleStr)${endStr != null ? ' $endStr' : ''}';
    final headerRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      child: Text(headerLine, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
    );
    /// Кнопка переключения алфавитного порядка А–Я ↔ Я–А.
    final sortAlphabetButton = !_completed && _rows.isNotEmpty
        ? IconButton(
            icon: Icon(Icons.sort_by_alpha, size: 22),
            tooltip: _sortMode == _InventorySort.alphabetAsc
                ? (loc.t('inventory_sort_az') ?? 'А–Я')
                : (loc.t('inventory_sort_za') ?? 'Я–А'),
            onPressed: () => setState(() {
              _sortMode = _sortMode == _InventorySort.alphabetAsc
                  ? _InventorySort.alphabetDesc
                  : _InventorySort.alphabetAsc;
            }),
          )
        : null;
    final nameFilterField = !_completed && _rows.isNotEmpty
        ? SizedBox(
            width: narrow ? double.infinity : 160,
            child: TextField(
              controller: _nameFilterCtrl,
              decoration: InputDecoration(
                hintText: loc.t('inventory_filter_name') ?? 'По названию',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => setState(() {}),
            ),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        headerRow,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: narrow
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isInputMode) Row(
                    children: [
                      Icon(Icons.store, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          establishment?.name ?? '—',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => _pickDate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (sortAlphabetButton != null && nameFilterField != null && !_isInputMode) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        sortAlphabetButton,
                        const SizedBox(width: 8),
                        Expanded(child: nameFilterField),
                      ],
                    ),
                  ],
                  // В режиме ввода показываем только поле поиска
                  if (_isInputMode && narrow && nameFilterField != null) ...[
                    const SizedBox(height: 6),
                    nameFilterField,
                  ],
                ],
              )
            : Row(
                children: [
                  if (!_isInputMode) ...[
                    Icon(Icons.store, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        establishment?.name ?? '—',
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (_isInputMode) const Spacer(),
                  InkWell(
                    onTap: () => _pickDate(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_startTime?.hour.toString().padLeft(2, '0') ?? '—'}:${_startTime?.minute.toString().padLeft(2, '0') ?? '—'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (sortAlphabetButton != null && !_isInputMode) ...[
                    const SizedBox(width: 6),
                    sortAlphabetButton,
                    if (nameFilterField != null) ...[
                      const SizedBox(width: 6),
                      nameFilterField,
                    ],
                  ],
                  // В режиме ввода на desktop показываем поле поиска
                  if (_isInputMode && !narrow && nameFilterField != null) ...[
                    const SizedBox(width: 6),
                    nameFilterField,
                  ],
                ],
              ),
          ),
        ),
      ],
    );
  }

  static const double _colNoWidth = 28;
  static const double _colUnitWidth = 48;
  static const double _colTotalWidth = 56;
  static const double _colQtyWidth = 64;
  static const double _colGap = 10;
  /// Высота заголовка секции (Продукты/ПФ) — для выравнивания фиксированной и прокручиваемой колонок.
  static const double _sectionHeaderHeight = 36;
  /// Фиксированная высота строки данных — для выравнивания ячеек ввода с текстом.
  static const double _dataRowHeight = 44;

  /// Ширина фиксированной части: #, Наименование, Мера, Итого (продукт зафиксирован слева).
  double _leftWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final base = (w * 0.42).clamp(140.0, 200.0);
    return base + _colGap + _colTotalWidth;
  }

  double _colNameWidth(BuildContext context) =>
      _leftWidth(context) - _colNoWidth - _colGap - _colUnitWidth - _colGap - _colTotalWidth;

  Widget _buildTable(LocalizationService loc) {
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('inventory_empty_hint'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _showProductPicker(context, loc),
                icon: const Icon(Icons.add),
                label: Text(loc.t('inventory_add_product')),
              ),
            ],
          ),
        ),
      );
    }
    // По ТЗ: всегда таблица с фиксированным левым столбцом (продукты, мера, итого)
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildTableWithFixedColumn(loc),
    );
  }

  Widget _buildAggregatedHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: _isInputMode ? const EdgeInsets.symmetric(horizontal: 6, vertical: 3) : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text(loc.t('inventory_excel_number'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          Expanded(child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text(loc.t('inventory_pf_gross_g'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text(loc.t('inventory_pf_net_g'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildAggregatedDataRow(LocalizationService loc, Map<String, dynamic> p, int rowNumber, {bool compact = false}) {
    final theme = Theme.of(context);
    final name = p['productName'] as String? ?? '';
    final gross = ((p['grossGrams'] as num?)?.toDouble() ?? 0).round();
    final net = ((p['netGrams'] as num?)?.toDouble() ?? 0).round();
    return Container(
      padding: compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          SizedBox(width: _colGap),
          Expanded(child: Text(name, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text('$gross', style: theme.textTheme.bodyMedium)),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text('$net', style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(LocalizationService loc, String title, {bool isFixed = false}) {
    final theme = Theme.of(context);
    final leftW = isFixed ? _leftWidth(context) : null;

    return SizedBox(
      height: _sectionHeaderHeight,
      width: leftW,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.5),
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    final nameW = _colNameWidth(context);
    final qtyColsW = _maxQuantityColumns * (_colQtyWidth + _colGap) + 28;
    return Container(
      padding: _isInputMode ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4) : const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: nameW, child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis, maxLines: 1)),
          const SizedBox(width: _colGap),
          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
          const SizedBox(width: _colGap),
          SizedBox(width: qtyColsW, child: Text(loc.t('inventory_quantity'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildDataRow(LocalizationService loc, int actualIndex, int rowNumber, {bool compact = false}) {
    final theme = Theme.of(context);
    final row = _rows[actualIndex];
    final nameW = _colNameWidth(context);
    final maxCols = _maxQuantityColumns;
    final qtyCols = row.quantities.length;
    return InkWell(
      onLongPress: () {
        if (_completed) return;
        _removeRow(actualIndex);
      },
      child: Container(
        padding: compact ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2) : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          color: rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            SizedBox(width: _colGap),
            SizedBox(
              width: nameW,
              child: Text(
                row.productName(loc.currentLanguageCode),
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
            SizedBox(width: _colGap),
            SizedBox(
              width: _colUnitWidth,
              child: !_completed
                  ? (row.isPf
                      ? DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: row.pfUnit ?? _pfUnitPcs,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(value: _pfUnitPcs, child: Text(loc.currentLanguageCode == 'ru' ? 'порц.' : 'pcs', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: _pfUnitGrams, child: Text(loc.currentLanguageCode == 'ru' ? 'гр' : 'g', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => v != null ? _setPfUnit(actualIndex, v) : null,
                          ),
                        )
                      : _ProductUnitDropdown(
                          value: row.unit,
                          lang: loc.currentLanguageCode,
                          onChanged: (v) => _setProductUnit(actualIndex, v),
                          theme: theme,
                        ))
                  : Text(
                      row.unitDisplayForBlank(loc.currentLanguageCode),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            SizedBox(width: _colGap),
            Container(
              width: _colTotalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_formatQty(row.totalDisplay), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: _colGap),
            ...List.generate(
              maxCols,
              (colIndex) => Padding(
                padding: EdgeInsets.only(right: colIndex < maxCols - 1 ? _colGap : 0),
                child: SizedBox(
                  width: _colQtyWidth,
                  child: colIndex < qtyCols
                      ? (_completed
                          ? Text(_formatQty(row.quantityDisplayAt(colIndex)), style: theme.textTheme.bodyMedium)
                          : _QtyCell(
                              key: ValueKey('qty_${actualIndex}_$colIndex'),
                              value: row.quantities[colIndex],
                              useGrams: row.isWeightInKg,
                              onChanged: (v) => _setQuantity(actualIndex, colIndex, v),
                            ))
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
  }

  Widget _buildTableWithFixedColumn(LocalizationService loc) {
    final leftW = _leftWidth(context);
    final screenW = MediaQuery.of(context).size.width;
    final rightW = _maxQuantityColumns * (_colQtyWidth + _colGap) + 48;

    return Column(
      children: [
        // Fixed header row
        Row(
          children: [
            // Fixed left header
            Container(
              width: leftW,
              child: _buildFixedHeaderRow(loc),
            ),
            // Scrollable right header
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  width: rightW.clamp(screenW - leftW, double.infinity),
                  child: _buildScrollableHeaderRow(loc),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: leftW,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_blockFilter != _InventoryBlockFilter.pfOnly && _productIndices.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_block_products'), isFixed: true),
                        ..._productIndices.asMap().entries.map((e) => _buildFixedDataRow(loc, e.value, e.key + 1)),
                      ],
                      if (_blockFilter != _InventoryBlockFilter.productsOnly && _pfIndices.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_block_pf'), isFixed: true),
                        ..._pfIndices.asMap().entries.map((e) {
                          final rowNum = _blockFilter == _InventoryBlockFilter.pfOnly ? e.key + 1 : _productIndices.length + e.key + 1;
                          return _buildFixedDataRow(loc, e.value, rowNum);
                        }),
                      ],
                      if (_aggregatedFromFile != null && _aggregatedFromFile!.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_pf_products_title'), isFixed: true),
                        _buildFixedAggregatedHeaderRow(loc),
                        ..._aggregatedFromFile!.asMap().entries.map((e) => _buildFixedAggregatedDataRow(loc, e.value, e.key + 1)),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _hScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      width: rightW.clamp(screenW - leftW, double.infinity),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_blockFilter != _InventoryBlockFilter.pfOnly && _productIndices.isNotEmpty) ...[
                            SizedBox(height: _sectionHeaderHeight),
                            ..._productIndices.asMap().entries.map((e) => _buildScrollableDataRow(loc, e.value)),
                          ],
                          if (_blockFilter != _InventoryBlockFilter.productsOnly && _pfIndices.isNotEmpty) ...[
                            SizedBox(height: _sectionHeaderHeight),
                            ..._pfIndices.asMap().entries.map((e) => _buildScrollableDataRow(loc, e.value)),
                          ],
                          if (_aggregatedFromFile != null && _aggregatedFromFile!.isNotEmpty) ...[
                            SizedBox(height: _sectionHeaderHeight),
                            _buildScrollableAggregatedHeaderRow(loc),
                            ..._aggregatedFromFile!.asMap().entries.map((e) => _buildScrollableAggregatedDataRow(loc, e.value)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFixedHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('#', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: _colNameWidth(context), child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: _colUnitWidth, child: Text(loc.t('inventory_unit'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: _colTotalWidth, child: Text(loc.t('inventory_total'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildScrollableHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    final maxCols = _maxQuantityColumns;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          ...List.generate(
            maxCols,
            (colIndex) => Padding(
              padding: EdgeInsets.only(right: colIndex < maxCols - 1 ? _colGap : 0),
              child: SizedBox(
                width: _colQtyWidth,
                child: Text('${colIndex + 1}', textAlign: TextAlign.center, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          if (!_completed) SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildFixedDataRow(LocalizationService loc, int actualIndex, int rowNumber) {
    final theme = Theme.of(context);
    final row = _rows[actualIndex];

    return SizedBox(
      height: _dataRowHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          color: rowNumber.isEven ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colNameWidth(context),
            child: Text(
              row.productName(loc.currentLanguageCode),
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colUnitWidth,
            child: !_completed
                ? (row.isPf
                    ? DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: row.pfUnit ?? _pfUnitPcs,
                          isDense: true,
                          isExpanded: true,
                          items: [
                            DropdownMenuItem(value: _pfUnitPcs, child: Text(loc.currentLanguageCode == 'ru' ? 'порц.' : 'pcs', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: _pfUnitGrams, child: Text(loc.currentLanguageCode == 'ru' ? 'гр' : 'g', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => v != null ? _setPfUnit(actualIndex, v) : null,
                        ),
                      )
                    : _ProductUnitDropdown(
                        value: row.unit,
                        lang: loc.currentLanguageCode,
                        onChanged: (v) => _setProductUnit(actualIndex, v),
                        theme: theme,
                      ))
                : Text(row.unitDisplayForBlank(loc.currentLanguageCode), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: _colGap),
          Container(
            width: _colTotalWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            child: Text(_formatQty(row.totalDisplay), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildScrollableDataRow(LocalizationService loc, int actualIndex) {
    final theme = Theme.of(context);
    final row = _rows[actualIndex];
    final maxCols = _maxQuantityColumns;
    final qtyCols = row.quantities.length;

    return SizedBox(
      height: _dataRowHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          ...List.generate(
            maxCols,
            (colIndex) => Padding(
              padding: EdgeInsets.only(right: colIndex < maxCols - 1 ? _colGap : 0),
              child: SizedBox(
                width: _colQtyWidth,
                child: colIndex < qtyCols
                    ? (_completed
                        ? Text(_formatQty(row.quantityDisplayAt(colIndex)), style: theme.textTheme.bodyMedium)
                        : _QtyCell(
                            key: ValueKey('qty_${actualIndex}_$colIndex'),
                            value: row.quantities[colIndex],
                            useGrams: row.isWeightInKg,
                            onChanged: (v) => _setQuantity(actualIndex, colIndex, v),
                          ))
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildFixedAggregatedHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text(loc.t('inventory_excel_number'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          Expanded(child: Text(loc.t('inventory_item_name'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildScrollableAggregatedHeaderRow(LocalizationService loc) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(loc.t('inventory_pf_gross_g'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text(loc.t('inventory_pf_net_g'), style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildFixedAggregatedDataRow(LocalizationService loc, Map<String, dynamic> p, int rowNumber) {
    final theme = Theme.of(context);
    final name = p['productName'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('$rowNumber', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          SizedBox(width: _colGap),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableAggregatedDataRow(LocalizationService loc, Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final gross = ((p['grossGrams'] as num?)?.toDouble() ?? 0).round();
    final net = ((p['netGrams'] as num?)?.toDouble() ?? 0).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('$gross', style: theme.textTheme.bodyMedium)),
          SizedBox(width: _colGap),
          SizedBox(width: 72, child: Text('$net', style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// Компактный нижний блок: не перекрывает таблицу, минимум высоты.
  Widget _buildFooter(LocalizationService loc) {
    final theme = Theme.of(context);
    // В режиме ввода кнопка "Завершить" фиксируется над клавиатурой
    if (_isInputMode) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _completed ? null : () => _complete(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(
                  loc.t('inventory_complete'),
                  style: _isInputMode ? const TextStyle(fontSize: 14) : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductPicker(BuildContext context, LocalizationService loc) async {
    final productStore = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    await productStore.loadProducts();
    await productStore.loadNomenclature(estId);
    if (!mounted) return;

    final products = productStore.getNomenclatureProducts(estId);
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('nomenclature')}: ${loc.t('no_products')}')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ProductPickerSheet(
        products: products,
        loc: loc,
        onSelect: (p) {
          _addProduct(p);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }
}

/// Выпадающий список единицы измерения для продукта (отдельно от названия).
class _ProductUnitDropdown extends StatelessWidget {
  const _ProductUnitDropdown({
    required this.value,
    required this.lang,
    required this.onChanged,
    required this.theme,
  });

  final String value;
  final String lang;
  final void Function(String) onChanged;
  final ThemeData theme;

  static const List<String> _commonUnits = ['g', 'kg', 'pcs', 'шт', 'ml', 'l'];

  @override
  Widget build(BuildContext context) {
    final options = _commonUnits;
    final normalized = value.trim().toLowerCase();
    final match = options.where((u) => u.toLowerCase() == normalized).firstOrNull;
    final displayValue = match ?? 'g';
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: displayValue,
        isDense: true,
        isExpanded: true,
        items: options.map((u) => DropdownMenuItem(
          value: u,
          child: Text(
            CulinaryUnits.displayName(u, lang),
            style: theme.textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        )).toList(),
        onChanged: (v) => v != null ? onChanged(v) : null,
      ),
    );
  }
}

class _QtyCell extends StatefulWidget {
  final double value;
  /// true: отображать и вводить в граммах (значение хранится в кг, показываем value*1000).
  final bool useGrams;
  final void Function(double) onChanged;

  const _QtyCell({super.key, required this.value, this.useGrams = false, required this.onChanged});

  @override
  State<_QtyCell> createState() => _QtyCellState();
}

class _QtyCellState extends State<_QtyCell> {
  late TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  double get _displayValueRaw => widget.useGrams ? widget.value * 1000 : widget.value;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayValue(_displayValueRaw));
  }

  @override
  void didUpdateWidget(_QtyCell old) {
    super.didUpdateWidget(old);
    if ((old.value != widget.value || old.useGrams != widget.useGrams) && !_focus.hasFocus) {
      _controller.text = _displayValue(widget.useGrams ? widget.value * 1000 : widget.value);
    }
  }

  String _displayValue(double v) {
    if (v == 0) return '';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(widget.useGrams ? 0 : 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
      ],
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      ),
      onChanged: (s) {
        final v = double.tryParse(s.replaceFirst(',', '.')) ?? 0;
        widget.onChanged(widget.useGrams ? v / 1000 : v);
      },
    );
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final List<Product> products;
  final LocalizationService loc;
  final void Function(Product) onSelect;

  const _ProductPickerSheet({
    required this.products,
    required this.loc,
    required this.onSelect,
  });

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';
  List<Product> get _filtered {
    if (_query.isEmpty) return widget.products;
    final q = _query.toLowerCase();
    final lang = widget.loc.currentLanguageCode;
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.getLocalizedName(lang).toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: widget.loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final p = _filtered[i];
                return ListTile(
                  title: Text(p.getLocalizedName(widget.loc.currentLanguageCode)),
                  subtitle: Text('${p.category} · ${CulinaryUnits.displayName((p.unit ?? 'g').trim().toLowerCase(), widget.loc.currentLanguageCode)}'),
                  onTap: () => widget.onSelect(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
