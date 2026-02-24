import 'dart:async';
import 'dart:convert';
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

    // Тихая отправка на сервер каждые 15 секунд — данные не теряются при обрыве
    _serverAutoSaveTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
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

    // Выбор формата экспорта и генерация файла
    try {
      final format = await _showExportFormatDialog(context, loc);
      if (format == null || !mounted) return;

      if (format == 'excel') {
        final bytes = _buildExcelBytes(payload, loc);
        if (bytes != null && bytes.isNotEmpty && mounted) {
          await _downloadExcel(bytes, payload, loc, 'xlsx');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.t('inventory_excel_downloaded'))),
            );
          }
        }
      } else if (format == 'csv') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV экспорт пока не реализован')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('inventory_document_saved')} (Экспорт: ${e.toString()})')),
        );
      }
    }
  }

  /// Создание Excel с 2 листами: 1) продукты+ПФ+перерасчет, 2) все продукты включая ПФ
  List<int>? _buildExcelBytes(Map<String, dynamic> payload, LocalizationService loc) {
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final maxCols = _maxQuantityColumns;
    try {
      final excel = Excel.createExcel();
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final fillLabel = loc.t('inventory_excel_fill_data');

      // ЛИСТ 1: Продукты + ПФ с итогами + перерасчет ПФ в брутто (объединенный)
      final sheet1 = excel['Продукты + ПФ'];
      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }
      sheet1.appendRow(headerCells);

      // Добавляем все продукты и ПФ
      var rowNum = 1;
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        final rowCells = <CellValue>[
          IntCellValue(rowNum++),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total.toDouble()),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? (quantities[c] as num?)?.toDouble() ?? 0.0 : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet1.appendRow(rowCells);
      }

      // Перерасчет ПФ в брутто (объединенный - суммируем одинаковые продукты)
      final aggregated = payload['aggregatedProducts'] as List<dynamic>? ?? [];
      if (aggregated.isNotEmpty) {
        sheet1.appendRow([]);
        sheet1.appendRow([TextCellValue(loc.t('inventory_pf_products_title'))]);
        sheet1.appendRow([
          TextCellValue(loc.t('inventory_excel_number')),
          TextCellValue(loc.t('inventory_item_name')),
          TextCellValue(loc.t('inventory_pf_gross_g')),
          TextCellValue(loc.t('inventory_pf_net_g')),
        ]);

        // Группируем продукты по имени и суммируем
        final groupedProducts = <String, Map<String, dynamic>>{};
        for (final p in aggregated) {
          final name = (p['productName'] as String? ?? '').trim();
          final gross = (p['grossGrams'] as num?)?.toDouble() ?? 0.0;
          final net = (p['netGrams'] as num?)?.toDouble() ?? 0.0;

          if (groupedProducts.containsKey(name)) {
            groupedProducts[name]!['grossGrams'] = (groupedProducts[name]!['grossGrams'] as double) + gross;
            groupedProducts[name]!['netGrams'] = (groupedProducts[name]!['netGrams'] as double) + net;
          } else {
            groupedProducts[name] = {
              'productName': name,
              'grossGrams': gross,
              'netGrams': net,
            };
          }
        }

        final groupedList = groupedProducts.values.toList()
          ..sort((a, b) => (a['productName'] as String).compareTo(b['productName'] as String));

        for (var i = 0; i < groupedList.length; i++) {
          final p = groupedList[i];
          sheet1.appendRow([
            IntCellValue(i + 1),
            TextCellValue((p['productName'] as String? ?? '').toString()),
            IntCellValue((p['grossGrams'] as double).round()),
            IntCellValue((p['netGrams'] as double).round()),
          ]);
        }
      }

      // ЛИСТ 2: Все продукты включая данные из ПФ
      final sheet2 = excel['Все продукты с ПФ'];
      sheet2.appendRow(headerCells); // Тот же заголовок

      // Собираем все продукты (из основной номенклатуры + из перерасчета ПФ)
      final allProducts = <String, Map<String, dynamic>>{};

      // Добавляем продукты из основной таблицы
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];

        if (allProducts.containsKey(name)) {
          // Суммируем количества
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + total.toDouble();
          final existingQuantities = existing['quantities'] as List<double>;
          for (var c = 0; c < quantities.length && c < existingQuantities.length; c++) {
            existingQuantities[c] += (quantities[c] as num?)?.toDouble() ?? 0.0;
          }
        } else {
          allProducts[name] = {
            'productName': name,
            'unit': unit,
            'total': total.toDouble(),
            'quantities': List<double>.from(quantities.map((q) => (q as num?)?.toDouble() ?? 0.0)),
          };
        }
      }

      // Добавляем продукты из перерасчета ПФ (в брутто граммах)
      for (final p in aggregated) {
        final name = (p['productName'] as String? ?? '').trim();
        final grossGrams = (p['grossGrams'] as num?)?.toDouble() ?? 0.0;

        if (allProducts.containsKey(name)) {
          // Суммируем к существующему продукту
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + grossGrams;
          // Для ПФ добавляем количество в первую колонку
          final quantities = existing['quantities'] as List<double>;
          if (quantities.isNotEmpty) {
            quantities[0] += grossGrams;
          } else {
            quantities.add(grossGrams);
          }
        } else {
          // Новый продукт только из ПФ
          allProducts[name] = {
            'productName': name,
            'unit': 'g', // брутто в граммах
            'total': grossGrams,
            'quantities': [grossGrams], // в первой колонке
          };
        }
      }

      // Выводим все продукты в отсортированном порядке
      final sortedProducts = allProducts.values.toList()
        ..sort((a, b) => (a['productName'] as String).compareTo(b['productName'] as String));

      for (var i = 0; i < sortedProducts.length; i++) {
        final p = sortedProducts[i];
        final name = p['productName'] as String;
        final unit = p['unit'] as String;
        final total = p['total'] as double;
        final quantities = p['quantities'] as List<double>;

        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? quantities[c] : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet2.appendRow(rowCells);
      }

      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (e) {
      print('Error building Excel: $e');
      return null;
    }
  }

  /*
  /// Создание CSV данных (2 секции как в Excel)
  String? _buildCsvData(Map<String, dynamic> payload, LocalizationService loc) {
    final buffer = StringBuffer();
    buffer.writeln('CSV export - coming soon');
    buffer.writeln('Date: ${DateTime.now()}');
    return buffer.toString();
  }
  */

  Future<String?> _showExportFormatDialog(BuildContext context, LocalizationService loc) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Выберите формат экспорта'),
        content: Text('Выберите формат файла для экспорта инвентаризации:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('excel'),
            child: const Text('Excel (.xlsx)'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('csv'),
            child: const Text('CSV (.csv)'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadExcel(List<int> bytes, Map<String, dynamic> payload, LocalizationService loc, String extension) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ?? DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.$extension';
    await saveFileBytes(fileName, bytes);
  }

  Future<void> _downloadCsv(String csvData, Map<String, dynamic> payload, LocalizationService loc) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ?? DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.csv';
    final bytes = utf8.encode(csvData);
    await saveFileBytes(fileName, bytes);
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
