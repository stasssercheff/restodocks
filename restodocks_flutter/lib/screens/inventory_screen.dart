import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/flutter_nav_bridge_stub.dart'
    if (dart.library.html) '../core/flutter_nav_bridge_web.dart' as flutter_nav;

import 'package:archive/archive.dart';
import '../utils/dev_log.dart';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../models/iiko_product.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../services/iiko_product_store.dart';
import '../services/draft_storage_service.dart';
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
  })  : assert(product != null ||
            techCard != null ||
            (freeName != null && freeName.isNotEmpty) ||
            productId != null ||
            techCardId != null),
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

  /// Продукт заведён по упаковке: есть вес упаковки.
  bool get hasPackage =>
      product?.packageWeightGrams != null && product!.packageWeightGrams! > 0;

  /// Текущая единица — упаковка или бутылка (пересчёт: кол-во × грамм/мл в упаковке).
  bool get isCountedByPackage => unitOverride == 'pkg' || unitOverride == 'btl';

  /// Вес одной упаковки в граммах.
  double get packageWeightGrams => product?.packageWeightGrams ?? 1.0;

  /// Для ПФ используем pfUnit: g → гр/g, иначе порц./pcs.
  String unitDisplay(String lang) {
    if (isPf) {
      final u = pfUnit ?? _pfUnitPcs;
      return u == _pfUnitGrams
          ? (lang == 'ru' ? 'гр' : 'g')
          : (lang == 'ru' ? 'порц.' : 'pcs');
    }
    if (unitOverride == 'btl') return lang == 'ru' ? 'бутылка' : 'bottle';
    if (isCountedByPackage) return lang == 'ru' ? 'упак.' : 'pkg';
    return CulinaryUnits.displayName(unit.toLowerCase(), lang);
  }

  /// В бланке инвентаризации вес показываем в граммах, не в кг.
  bool get isWeightInKg =>
      !isPf &&
      !isCountedByPackage &&
      (unit.toLowerCase() == 'kg' || unit == 'кг');

  String unitDisplayForBlank(String lang) {
    if (unitOverride == 'btl') return lang == 'ru' ? 'мл' : 'ml';
    if (isCountedByPackage) return lang == 'ru' ? 'г' : 'g';
    return isWeightInKg ? (lang == 'ru' ? 'гр' : 'g') : unitDisplay(lang);
  }

  double quantityDisplayAt(int i) =>
      isWeightInKg ? quantities[i] * 1000 : quantities[i];
  double get totalDisplay => isWeightInKg ? total * 1000 : total;

  /// Итоговый вес в граммах (для выгрузки): упаковки × вес упаковки
  double get totalWeightGrams {
    if (isCountedByPackage) return total * packageWeightGrams;
    if (isWeightInKg) return total * 1000.0;
    return total;
  }

  /// Сумма всех числовых значений строки (включая вторую ячейку и далее; последняя пустая — буфер для n+1).
  double get total {
    if (quantities.isEmpty) return 0.0;
    return quantities.fold(0.0, (a, b) => a + b);
  }

  _InventoryRow copyWith(
          {Product? product,
          TechCard? techCard,
          String? pfUnit,
          String? unitOverride}) =>
      _InventoryRow(
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
    with
        AutoSaveMixin<InventoryScreen>,
        InputChangeListenerMixin<InventoryScreen> {
  Timer?
      _serverAutoSaveTimer; // Таймер для автоматической отправки на сервер каждые 30 секунд
  final List<_InventoryRow> _rows = [];

  /// Продукты, перерасчитанные из ПФ (третья секция); заполняется при загрузке файла.
  List<Map<String, dynamic>>? _aggregatedFromFile;
  DateTime _date = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _completed = false;
  bool _isInputMode = false; // Режим ввода количества (клавиатура открыта)
  bool _hasInputFocus =
      false; // Фокус в ячейке/фильтре — для скрытия шапки на мобильном
  _InventorySort _sortMode = _InventorySort.alphabetAsc;
  _InventoryBlockFilter _blockFilter = _InventoryBlockFilter.all;
  final TextEditingController _nameFilterCtrl = TextEditingController();
  final FocusNode _nameFilterFocusNode = FocusNode();
  String _nameFilter = '';
  bool _stateRestored = false; // Флаг: предотвращает двойное восстановление
  bool _isLoadingProducts =
      true; // Показывать "Загрузка продуктов..." пока не завершился initScreen

  /// Сохранить данные немедленно в локальное хранилище (SharedPreferences/localStorage)
  void saveNow() {
    saveImmediately(); // Немедленно, без debounce — данные не потеряются при закрытии/падении
  }

  @override
  void initState() {
    super.initState();
    _startTime = TimeOfDay.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initScreen());
    _nameFilterCtrl
        .addListener(() => setState(() => _nameFilter = _nameFilterCtrl.text));
    _nameFilterFocusNode.addListener(() {
      setState(() => _hasInputFocus = _nameFilterFocusNode.hasFocus);
    });

    // Настроить автосохранение - сохранять чаще
    setOnInputChanged(() {
      // Сохранять немедленно при любом изменении
      saveNow();
    });

    // Тихая отправка на сервер каждые 10 секунд — данные не теряются даже в инкогнито
    _serverAutoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
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
      'rows': _rows
          .map((row) => {
                'productId': row.product?.id,
                'techCardId': row.techCard?.id,
                'freeName': row.freeName,
                'freeUnit': row.freeUnit,
                'quantities': row.quantities,
                'pfUnit': row.pfUnit,
                'unitOverride': row.unitOverride,
              })
          .toList(),
      'aggregatedFromFile': _aggregatedFromFile,
    };
  }

  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    if (_stateRestored) return; // уже восстановлено из _initScreen
    _stateRestored = true;
    setState(() {
      _date = DateTime.parse(data['date'] ?? DateTime.now().toIso8601String());
      _startTime = data['startTime'] != null && data['startTime'].isNotEmpty
          ? TimeOfDay.fromDateTime(
              DateTime.parse('2023-01-01 ${data['startTime']}'))
          : null;
      _endTime = data['endTime'] != null && data['endTime'].isNotEmpty
          ? TimeOfDay.fromDateTime(
              DateTime.parse('2023-01-01 ${data['endTime']}'))
          : null;
      _completed = data['completed'] ?? false;

      final sortModeName = data['sortMode'] ?? 'alphabetAsc';
      _sortMode = _InventorySort.values.firstWhere(
        (e) =>
            e.name == sortModeName ||
            (sortModeName == 'alphabet' && e == _InventorySort.alphabetAsc),
        orElse: () => _InventorySort.alphabetAsc,
      );
      if (_sortMode == _InventorySort.lastAdded)
        _sortMode = _InventorySort.alphabetAsc;

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
        final quantities = (rowMap['quantities'] as List<dynamic>?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            [0.0, 0.0];
        final productId = rowMap['productId'] as String?;
        final techCardId = rowMap['techCardId'] as String?;

        // Нормализуем quantities
        List<double> qty = List.from(quantities);
        if (rowMap['freeName'] != null && qty.isNotEmpty && qty.last != 0.0) {
          qty.add(0.0);
        } else if (rowMap['freeName'] != null && qty.isEmpty) {
          qty.addAll([0.0, 0.0]);
        }
        if (!rowMap.containsKey('freeName') &&
            productId == null &&
            techCardId == null) {
          // Пустая строка продукта/ПФ — оставляем как есть
        } else if (productId != null || techCardId != null) {
          if (qty.isEmpty)
            qty.addAll([0.0, 0.0]);
          else
            while (qty.length < 2) qty.add(0.0);
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
        .where((i) =>
            !_rows[i].isPf && _matchesNameFilter(_rows[i].productName(lang)))
        .toList();
    if (_sortMode == _InventorySort.alphabetAsc) {
      indices.sort((a, b) => _rows[a]
          .productName(lang)
          .toLowerCase()
          .compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => _rows[b]
          .productName(lang)
          .toLowerCase()
          .compareTo(_rows[a].productName(lang).toLowerCase()));
    }
    return indices;
  }

  /// Индексы строк-ПФ (из ТТК), отсортированы и отфильтрованы.
  List<int> get _pfIndices {
    final lang = context.read<LocalizationService>().currentLanguageCode;
    var indices = List.generate(_rows.length, (i) => i)
        .where((i) =>
            _rows[i].isPf && _matchesNameFilter(_rows[i].productName(lang)))
        .toList();
    if (_sortMode == _InventorySort.alphabetAsc) {
      indices.sort((a, b) => _rows[a]
          .productName(lang)
          .toLowerCase()
          .compareTo(_rows[b].productName(lang).toLowerCase()));
    } else {
      indices.sort((a, b) => _rows[b]
          .productName(lang)
          .toLowerCase()
          .compareTo(_rows[a].productName(lang).toLowerCase()));
    }
    return indices;
  }

  /// Порядок отображения: сначала продукты, потом ПФ (для обратной совместимости с нумерацией в Excel).
  List<int> get _displayOrder => [..._productIndices, ..._pfIndices];

  /// При открытии: если есть черновик — восстанавливаем без диалога.
  /// Порядок приоритетов: localStorage → Supabase → диалог.
  /// В инкогнито localStorage пуст — восстанавливаем с сервера.
  Future<void> _initScreen() async {
    final draftStorage = DraftStorageService();

    // Загружаем iiko-продукты и оба типа черновиков одновременно
    final iikoStore = context.read<IikoProductStore>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;

    final futures = await Future.wait([
      draftStorage.loadInventoryDraft(),
      draftStorage.loadIikoInventoryDraft(),
      if (estId != null) iikoStore.loadProducts(estId) else Future.value(null),
    ]);
    if (!mounted) return;
    if (_isLoadingProducts) setState(() => _isLoadingProducts = false);

    final stdDraft = futures[0] as Map<String, dynamic>?;
    final iikoDraft = futures[1] as Map<String, dynamic>?;

    final hasIikoProducts = iikoStore.hasProducts;
    final hasIikoDraft = iikoDraft != null && iikoDraft.isNotEmpty;
    final hasStdDraft = stdDraft != null && stdDraft.isNotEmpty;

    // Если есть iiko-продукты или iiko-черновик — показываем диалог выбора ВСЕГДА
    // (пользователь должен сам выбрать куда вернуться)
    if (hasIikoProducts || hasIikoDraft) {
      await _showModeDialog(
          hasIikoDraft: hasIikoDraft, hasStdDraft: hasStdDraft);
      return;
    }

    // iiko-продуктов нет — проверяем сервер (инкогнито / очищенный localStorage)
    final serverIikoDraft = await _loadIikoDraftFromServer();
    if (!mounted) return;
    if (serverIikoDraft != null) {
      await _showModeDialog(hasIikoDraft: true, hasStdDraft: hasStdDraft);
      return;
    }

    // iiko нет нигде — тихо восстанавливаем стандартный черновик (если есть)
    if (hasStdDraft) {
      _stateRestored = false;
      await restoreState(stdDraft!);
      return;
    }

    // Стандартный черновик на сервере (инкогнито)
    final serverStdDraft = await _loadDraftFromServer();
    if (!mounted) return;
    if (serverStdDraft != null && serverStdDraft.isNotEmpty) {
      _stateRestored = false;
      await restoreState(serverStdDraft);
      return;
    }

    // Черновиков нет — диалог (iiko-продуктов тоже нет, но показываем для консистентности)
    await _showModeDialog();
  }

  /// Проверяет наличие iiko-черновика на сервере (для инкогнито / очищенного localStorage).
  Future<Map<String, dynamic>?> _loadIikoDraftFromServer() async {
    try {
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      if (estId == null) return null;
      final row = await Supabase.instance.client
          .from('inventory_drafts')
          .select('draft_data')
          .eq('establishment_id', estId)
          .eq('draft_type', 'iiko_inventory')
          .maybeSingle();
      if (row == null) return null;
      return row['draft_data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Загружает стандартный черновик инвентаризации с Supabase.
  /// Работает даже в инкогнито — localStorage там пуст.
  Future<Map<String, dynamic>?> _loadDraftFromServer() async {
    try {
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      if (estId == null) return null;
      final row = await Supabase.instance.client
          .from('inventory_drafts')
          .select('draft_data')
          .eq('establishment_id', estId)
          .eq('draft_type', 'standard')
          .maybeSingle();
      if (row == null) return null;
      return row['draft_data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Диалог выбора режима инвентаризации при открытии экрана.
  /// [hasIikoDraft] — незавершённая iiko-инвентаризация сохранена.
  /// [hasStdDraft]  — незавершённая стандартная инвентаризация сохранена.
  Future<void> _showModeDialog(
      {bool hasIikoDraft = false, bool hasStdDraft = false}) async {
    if (!mounted) return;
    final iikoStore = context.read<IikoProductStore>();
    final hasIiko = iikoStore.hasProducts || hasIikoDraft;
    final employee = context.read<AccountManagerSupabase>().currentEmployee;
    final isHall =
        employee?.department == 'hall' || employee?.department == 'dining_room';

    Widget _continueBadge(BuildContext ctx) {
      final theme = Theme.of(ctx);
      return Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Продолжить',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Тип инвентаризации'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.list_alt, color: Colors.blue),
                title: Row(children: [
                  const Text('Стандартный'),
                  if (hasStdDraft) _continueBadge(ctx),
                ]),
                subtitle: Text(hasStdDraft
                    ? 'Незавершённая инвентаризация сохранена'
                    : 'Продукты из номенклатуры'),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                tileColor: Colors.blue.withOpacity(0.05),
                onTap: () => Navigator.of(ctx).pop('standard'),
              ),
              if (!isHall) ...[
                const SizedBox(height: 8),
                ListTile(
                  leading: Icon(Icons.table_chart_outlined,
                      color: hasIiko ? theme.colorScheme.primary : Colors.grey),
                  title: Row(children: [
                    const Text('Бланк iiko'),
                    if (hasIikoDraft) _continueBadge(ctx),
                  ]),
                  subtitle: Text(
                    hasIikoDraft
                        ? 'Незавершённая инвентаризация сохранена'
                        : hasIiko
                            ? 'Продукты из iiko-бланка · ${iikoStore.products.length} позиций'
                            : 'Сначала загрузите бланк iiko в «Загрузка продуктов»',
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  tileColor: hasIiko
                      ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.03),
                  onTap: hasIiko ? () => Navigator.of(ctx).pop('iiko') : null,
                ),
              ],
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    if (choice == 'iiko') {
      context.pushReplacement('/inventory-iiko');
    } else if (choice == 'standard') {
      // Если есть стандартный черновик — восстанавливаем его
      if (hasStdDraft) {
        final draftStorage = DraftStorageService();
        final savedDraft = await draftStorage.loadInventoryDraft();
        if (!mounted) return;
        if (savedDraft != null && savedDraft.isNotEmpty) {
          _stateRestored = false;
          await restoreState(savedDraft);
          return;
        }
      }
      _loadNomenclature();
    }
    // choice == null → пользователь не выбрал (нажал вне диалога) — ничего не делаем
  }

  /// Автоматическая подстановка: номенклатура заведения + полуфабрикаты (ТТК с типом ПФ).
  Future<void> _loadNomenclature() async {
    if (!mounted) return;
    setState(() => _isLoadingProducts = true);
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final techCardSvc = context.read<TechCardServiceSupabase>();
    final est = account.establishment;
    final estId = est?.dataEstablishmentId;
    if (estId == null) return;
    final results = await Future.wait([
      store.loadProducts(),
      store.loadNomenclature(estId),
      techCardSvc.getTechCardsForEstablishment(estId),
    ]);
    if (!mounted) return;
    final products = store.getNomenclatureProducts(estId);
    final techCards = results[2] as List<TechCard>;
    final pfOnly = techCards.where((tc) => tc.isSemiFinished).toList();
    if (!mounted) return;
    setState(() => _isLoadingProducts = false);
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
        if (_rows.any((r) => r.product?.id == p.id || r.productId == p.id))
          continue;
        _rows.add(_InventoryRow(
            product: p,
            techCard: null,
            quantities: List<double>.generate(minQtyCount, (_) => 0.0)));
      }
      for (final tc in pfOnly) {
        if (_rows.any((r) => r.techCard?.id == tc.id || r.techCardId == tc.id))
          continue;
        _rows.add(_InventoryRow(
            product: null,
            techCard: tc,
            quantities: List<double>.generate(minQtyCount, (_) => 0.0),
            pfUnit: _pfUnitPcs));
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
        final unit =
            (line.unit ?? 'g').trim().isEmpty ? 'g' : (line.unit ?? 'g');
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

  Future<void> _scanReceipt(
      BuildContext context, LocalizationService loc) async {
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
      SnackBar(
          content: Text(loc
              .t('inventory_receipt_scan_added')
              .replaceAll('%s', '${result.lines.length}'))),
    );
  }

  @override
  void dispose() {
    _nameFilterCtrl.dispose();
    _nameFilterFocusNode.dispose();
    _serverAutoSaveTimer?.cancel(); // Отменить таймер автосохранения на сервер
    super.dispose();
  }

  /// Автоматическая отправка данных на сервер каждые 30 секунд
  Future<void> _autoSaveToServer() async {
    if (_completed || _rows.isEmpty)
      return; // Не сохранять если завершено или пусто

    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) return;

      // Получить текущие данные
      final currentState = getCurrentState();

      // Отправить на сервер как черновик инвентаризации
      await _saveDraftToServer(establishmentId, currentState);

      devLog('📡 Auto-saved inventory draft to server');
    } catch (e) {
      // Тихая ошибка - не показывать пользователю
      devLog('⚠️ Failed to auto-save inventory draft: $e');
    }
  }

  /// Сохранить черновик инвентаризации на сервер
  Future<void> _saveDraftToServer(
      String establishmentId, Map<String, dynamic> data) async {
    try {
      final account = context.read<AccountManagerSupabase>();
      final employeeId = account.currentEmployee?.id;
      await Supabase.instance.client.from('inventory_drafts').upsert(
        {
          'establishment_id': establishmentId,
          'employee_id': employeeId,
          'draft_type': 'standard',
          'draft_data': data,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'establishment_id,draft_type',
      );
    } catch (_) {}
  }

  /// Минимум 2 пустых ячейки при открытии. При заполнении последней — добавляется ещё одна.
  int get _maxQuantityColumns {
    if (_rows.isEmpty) return 2;
    return _rows
        .map((r) => r.quantities.length)
        .fold<int>(2, (a, b) => a > b ? a : b);
  }

  void _addQuantityToRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    if (_rows[rowIndex].isFree) return;
    setState(() => _rows[rowIndex].quantities.add(0.0));
  }

  void _setPfUnit(int rowIndex, String unit) {
    if (rowIndex < 0 || rowIndex >= _rows.length || !_rows[rowIndex].isPf)
      return;
    setState(() {
      _rows[rowIndex] = _rows[rowIndex].copyWith(pfUnit: unit);
    });
    saveNow();
  }

  void _setProductUnit(int rowIndex, String unit) {
    if (rowIndex < 0 ||
        rowIndex >= _rows.length ||
        _rows[rowIndex].product == null) return;
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
            result[key]!['grossGrams'] =
                (result[key]!['grossGrams'] as double) + gross;
            result[key]!['netGrams'] =
                (result[key]!['netGrams'] as double) + net;
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
            final nestedYield =
                nested.yield > 0 ? nested.yield : nested.totalNetWeight;
            if (nestedYield > 0) {
              final nestedFactor = (ing.netWeight * factor) / nestedYield;
              addIngredients(nested.ingredients, nestedFactor);
            }
          }
        }
      }
    }

    for (final r in _rows) {
      if (!r.isPf ||
          r.techCard == null ||
          r.quantities.isEmpty ||
          r.quantities[0] <= 0) continue;
      final tc = r.techCard!;
      if (tc.ingredients.isEmpty) continue;
      final yieldVal = tc.yield > 0 ? tc.yield : tc.totalNetWeight;
      if (yieldVal <= 0) continue;
      final qty = r.quantities[0];
      final pfU = r.pfUnit ?? _pfUnitPcs;
      final factor = pfU == _pfUnitGrams
          ? qty / yieldVal
          : (qty * tc.portionWeight) / yieldVal;
      addIngredients(tc.ingredients, factor);
    }

    final list = result.values.toList();
    list.sort((a, b) =>
        (a['productName'] as String).compareTo(b['productName'] as String));
    return list;
  }

  void _addColumnToAll() {
    setState(() {
      for (final r in _rows) {
        if (!r.isFree) r.quantities.add(0.0);
      }
    });
  }

  void _onLastCellFocused(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length || _rows[rowIndex].isFree)
      return;
    setState(() => _rows[rowIndex].quantities.add(0.0));
  }

  /// При выходе из второй ячейки (после заполнения) — скролл выполняет tile через didUpdateWidget
  void _onCellFocusLost(int rowIndex, int colIndex) {
    if (rowIndex < 0 || rowIndex >= _rows.length || _rows[rowIndex].isFree)
      return;
    final row = _rows[rowIndex];
    if (row.quantities.length < 2 || colIndex != row.quantities.length - 2)
      return;
    if (row.quantities[colIndex] <= 0) return;
  }

  void _addProduct(Product p) {
    // Все новые продукты начинаются с 2 колонок
    final quantities = <double>[0.0, 0.0];
    setState(() {
      _rows.add(
          _InventoryRow(product: p, techCard: null, quantities: quantities));
    });
    saveNow(); // Сохранить немедленно при добавлении продукта
  }

  /// Обновление значения ячейки. При вводе в последнюю ячейку — добавляется новая колонка ко всем строкам (n+1).
  void _setQuantity(int rowIndex, int colIndex, double value) {
    if (rowIndex < 0 || rowIndex >= _rows.length) return;
    final row = _rows[rowIndex];
    if (colIndex < 0 || colIndex >= row.quantities.length) return;

    final oldValue = row.quantities[colIndex];

    // Обновляем значение напрямую
    row.quantities[colIndex] = value;

    // Вызываем setState только если значение действительно изменилось
    if (oldValue != value) {
      setState(() {});
    }

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

    final chefs =
        await account.getExecutiveChefsForEstablishment(establishment.id);
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
    final aggregatedProducts =
        _aggregateProductsFromPf(loc.currentLanguageCode);
    final payload = _buildPayload(
      establishment: establishment,
      employee: employee,
      endTime: endTime,
      lang: loc.currentLanguageCode,
      aggregatedProducts: aggregatedProducts,
    );
    final docService = InventoryDocumentService();
    final docSaved = await docService.save(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      recipientChefId: chef.id,
      recipientEmail: chef.email,
      payload: payload,
    );
    if (docSaved == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.t('inventory_document_save_error') ??
              'Не удалось сохранить инвентаризацию во входящие. Проверьте подключение.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Сохраняем инвентаризацию в историю перед установкой статуса
    try {
      final inventoryService = context.read<InventoryHistoryService>();
      await inventoryService.saveInventoryToHistory(
        establishmentId: establishment.id,
        employeeId: employee.id,
        inventoryData: {
          'rows': _rows
              .map((row) => {
                    'productId': row.product?.id,
                    'techCardId': row.techCard?.id,
                    'freeName': row.freeName,
                    'freeUnit': row.freeUnit,
                    'quantities': row.quantities,
                    'pfUnit': row.pfUnit,
                  })
              .toList(),
          'aggregatedProducts': aggregatedProducts,
          'payload': payload,
        },
        date: _date,
        startTime: _startTime,
        endTime: endTime,
        notes: 'Отправлено шефу ${chef.fullName}',
      );
      devLog('✅ Inventory saved to history');
    } catch (e) {
      devLog('⚠️ Failed to save inventory to history: $e');
      // Продолжаем выполнение, так как сохранение в историю не критично
    }

    if (mounted) setState(() => _endTime = endTime);

    // Выбор формата экспорта и языка сохранения. При отмене — остаёмся в режиме редактирования.
    try {
      final result = await _showExportFormatAndLanguageDialog(context, loc);
      if (result == null || !mounted)
        return; // Отмена — ячейки остаются доступны для заполнения

      if (result.format == 'excel') {
        final payloadForExport = _buildPayload(
          establishment: establishment,
          employee: employee,
          endTime: endTime,
          lang: result.lang,
          aggregatedProducts: _aggregateProductsFromPf(result.lang),
        );
        final bytes = _buildExcelBytes(payloadForExport, loc);
        if (bytes != null && bytes.isNotEmpty && mounted) {
          await _downloadExcel(bytes, payloadForExport, loc, 'xlsx');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.t('inventory_excel_downloaded'))),
            );
          }
        }
      } else if (result.format == 'csv') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV экспорт пока не реализован')),
          );
        }
      }
      // Не устанавливаем _completed и не очищаем черновик — можно довнести и сохранить снова
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${loc.t('inventory_document_saved')} (Экспорт: ${e.toString()})')),
        );
      }
    }
  }

  /// Начать новую инвентаризацию (очистить форму после завершённой).
  void _startNewInventory() {
    setState(() {
      _rows.clear();
      _aggregatedFromFile = null;
      _date = DateTime.now();
      _startTime = TimeOfDay.now();
      _endTime = null;
      _completed = false;
    });
    clearDraft();
    _loadNomenclature();
  }

  /// Вычислить стоимость для продукта по имени (используется для листа 2 при продуктах из ПФ).
  double _computeCostForProductByName(
    ProductStoreSupabase productStore,
    String? establishmentId,
    String productName,
    double totalGrams,
  ) {
    if (establishmentId == null || totalGrams <= 0) return 0.0;
    final nameLower = productName.trim().toLowerCase();
    if (nameLower.isEmpty) return 0.0;
    Product? product;
    for (final p in productStore.allProducts) {
      if (p.name.trim().toLowerCase() == nameLower) {
        product = p;
        break;
      }
      final names = p.names;
      if (names != null) {
        for (final v in names.values) {
          if (v?.toString().trim().toLowerCase() == nameLower) {
            product = p;
            break;
          }
        }
        if (product != null) break;
      }
    }
    if (product == null) return 0.0;
    final estPrice =
        productStore.getEstablishmentPrice(product.id, establishmentId)?.$1;
    final pricePerKg = product.computedPricePerKg ?? estPrice;
    if (pricePerKg == null || pricePerKg <= 0) return 0.0;
    return totalGrams / 1000.0 * pricePerKg;
  }

  /// Создание Excel с 2 листами: 1) продукты+ПФ+перерасчет, 2) все продукты включая ПФ
  List<int>? _buildExcelBytes(
      Map<String, dynamic> payload, LocalizationService loc) {
    final rows = payload['rows'] as List<dynamic>? ?? [];
    final maxCols = _maxQuantityColumns;
    ProductStoreSupabase? productStore;
    String? establishmentId;
    if (mounted) {
      try {
        productStore = context.read<ProductStoreSupabase>();
        establishmentId =
            context.read<AccountManagerSupabase>().establishment?.id;
      } catch (_) {}
    }
    try {
      final excel = Excel.createExcel();
      final numLabel = loc.t('inventory_excel_number');
      final nameLabel = loc.t('inventory_item_name');
      final unitLabel = loc.t('inventory_unit');
      final totalLabel = loc.t('inventory_excel_total');
      final sumLabel = loc.t('inventory_excel_sum') ?? 'Сумма';
      final fillLabel = loc.t('inventory_excel_fill_data');

      // ЛИСТ 1: Продукты + ПФ с итогами + перерасчет ПФ в брутто (объединенный)
      final sheet1 = excel['Продукты + ПФ'];
      final headerCells = <CellValue>[
        TextCellValue(numLabel),
        TextCellValue(nameLabel),
        TextCellValue(unitLabel),
        TextCellValue(sumLabel),
        TextCellValue(totalLabel),
      ];
      for (var c = 0; c < maxCols; c++) {
        headerCells.add(TextCellValue('$fillLabel ${c + 1}'));
      }
      sheet1.appendRow(headerCells);

      // 1. Только продукты (без ПФ), отсортированные по наименованию
      final productsOnly = (rows.map((e) => e as Map<String, dynamic>))
          .where((r) => !((r['productId'] as String?) ?? '').startsWith('pf_'))
          .toList()
        ..sort((a, b) => ((a['productName'] as String?) ?? '')
            .toLowerCase()
            .compareTo(((b['productName'] as String?) ?? '').toLowerCase()));
      var rowNum = 1;
      for (var i = 0; i < productsOnly.length; i++) {
        final r = productsOnly[i];
        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final price = (r['price'] as num?)?.toDouble();
        final quantities = r['quantities'] as List<dynamic>? ?? [];
        final rowCells = <CellValue>[
          IntCellValue(rowNum++),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(price ?? 0),
          DoubleCellValue(total.toDouble()),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length
              ? (quantities[c] as num?)?.toDouble() ?? 0.0
              : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet1.appendRow(rowCells);
      }

      // 2. Полуфабрикаты (ПФ) — отдельная секция под списком продуктов
      final pfRows = (rows.map((e) => e as Map<String, dynamic>))
          .where((r) => ((r['productId'] as String?) ?? '').startsWith('pf_'))
          .toList()
        ..sort((a, b) => ((a['productName'] as String?) ?? '')
            .toLowerCase()
            .compareTo(((b['productName'] as String?) ?? '').toLowerCase()));
      if (pfRows.isNotEmpty) {
        sheet1.appendRow([]);
        sheet1.appendRow([TextCellValue(loc.t('inventory_block_pf'))]);
        sheet1.appendRow(headerCells);
        rowNum = 1;
        for (var i = 0; i < pfRows.length; i++) {
          final r = pfRows[i];
          final name = r['productName'] as String? ?? '';
          final unit = r['unit'] as String? ?? '';
          final total = r['total'] as num? ?? 0;
          final price = (r['price'] as num?)?.toDouble();
          final quantities = r['quantities'] as List<dynamic>? ?? [];
          final rowCells = <CellValue>[
            IntCellValue(rowNum++),
            TextCellValue(name),
            TextCellValue(unit),
            DoubleCellValue(price ?? 0),
            DoubleCellValue(total.toDouble()),
          ];
          for (var c = 0; c < maxCols; c++) {
            final q = c < quantities.length
                ? (quantities[c] as num?)?.toDouble() ?? 0.0
                : 0.0;
            rowCells.add(DoubleCellValue(q));
          }
          sheet1.appendRow(rowCells);
        }
      }

      // 3. Перерасчет ПФ в брутто (объединенный - суммируем одинаковые продукты)
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
            groupedProducts[name]!['grossGrams'] =
                (groupedProducts[name]!['grossGrams'] as double) + gross;
            groupedProducts[name]!['netGrams'] =
                (groupedProducts[name]!['netGrams'] as double) + net;
          } else {
            groupedProducts[name] = {
              'productName': name,
              'grossGrams': gross,
              'netGrams': net,
            };
          }
        }

        final groupedList = groupedProducts.values.toList()
          ..sort((a, b) => ((a['productName'] as String?) ?? '')
              .toLowerCase()
              .compareTo(((b['productName'] as String?) ?? '').toLowerCase()));

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

      // ЛИСТ 2 (Итого): только продукты (без ПФ). ПФ развёрнуты в брутто по ТТК.
      final sheet2 = excel['Все продукты с ПФ'];
      sheet2.appendRow(headerCells); // Тот же заголовок

      // Собираем только продукты (без ПФ). ПФ учитываются через aggregated (брутто по ТТК).
      final allProducts = <String, Map<String, dynamic>>{};

      // Добавляем только продукты из номенклатуры (не ПФ, не свободные строки)
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i] as Map<String, dynamic>;
        final productId = r['productId'] as String? ?? '';
        // Пропускаем только ПФ (pf_xxx) — они развёрнуты в брутто через aggregated
        if (productId.startsWith('pf_')) continue;

        final name = r['productName'] as String? ?? '';
        final unit = r['unit'] as String? ?? '';
        final total = r['total'] as num? ?? 0;
        final quantities = r['quantities'] as List<dynamic>? ?? [];

        final priceVal = (r['price'] as num?)?.toDouble() ?? 0.0;
        if (allProducts.containsKey(name)) {
          // Суммируем количества и цену
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + total.toDouble();
          existing['price'] = (existing['price'] as double? ?? 0) + priceVal;
          final existingQuantities = existing['quantities'] as List<double>;
          for (var c = 0;
              c < quantities.length && c < existingQuantities.length;
              c++) {
            existingQuantities[c] += (quantities[c] as num?)?.toDouble() ?? 0.0;
          }
        } else {
          allProducts[name] = {
            'productName': name,
            'unit': unit,
            'total': total.toDouble(),
            'price': priceVal,
            'quantities': List<double>.from(
                quantities.map((q) => (q as num?)?.toDouble() ?? 0.0)),
          };
        }
      }

      // Добавляем продукты из перерасчета ПФ (развёрнуты в брутто по ТТК)
      for (final p in aggregated) {
        final name = (p['productName'] as String? ?? '').trim();
        final grossGrams = (p['grossGrams'] as num?)?.toDouble() ?? 0.0;

        if (allProducts.containsKey(name)) {
          // Суммируем к существующему продукту
          final existing = allProducts[name]!;
          existing['total'] = (existing['total'] as double) + grossGrams;
          final extraCost = (productStore != null && establishmentId != null)
              ? _computeCostForProductByName(
                  productStore, establishmentId, name, grossGrams)
              : 0.0;
          existing['price'] = (existing['price'] as double? ?? 0) + extraCost;
          // Для ПФ добавляем количество в первую колонку
          final quantities = existing['quantities'] as List<double>;
          if (quantities.isNotEmpty) {
            quantities[0] += grossGrams;
          } else {
            quantities.add(grossGrams);
          }
        } else {
          // Новый продукт только из ПФ — вычисляем стоимость по цене из номенклатуры/basePrice
          final cost = (productStore != null && establishmentId != null)
              ? _computeCostForProductByName(
                  productStore, establishmentId, name, grossGrams)
              : 0.0;
          allProducts[name] = {
            'productName': name,
            'unit': 'g', // брутто в граммах
            'total': grossGrams,
            'price': cost,
            'quantities': [grossGrams], // в первой колонке
          };
        }
      }

      // Выводим все продукты в алфавитном порядке по наименованию
      final sortedProducts = allProducts.values.toList()
        ..sort((a, b) => ((a['productName'] as String?) ?? '')
            .toLowerCase()
            .compareTo(((b['productName'] as String?) ?? '').toLowerCase()));

      double totalSumAll = 0.0;
      for (var i = 0; i < sortedProducts.length; i++) {
        final p = sortedProducts[i];
        final name = p['productName'] as String;
        final unit = p['unit'] as String;
        final total = p['total'] as double;
        final price = (p['price'] as num?)?.toDouble() ?? 0.0;
        totalSumAll += price;
        final quantities = p['quantities'] as List<double>;

        final rowCells = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(name),
          TextCellValue(unit),
          DoubleCellValue(price),
          DoubleCellValue(total),
        ];
        for (var c = 0; c < maxCols; c++) {
          final q = c < quantities.length ? quantities[c] : 0.0;
          rowCells.add(DoubleCellValue(q));
        }
        sheet2.appendRow(rowCells);
      }

      // Строка «Итого» по сумме внизу листа
      final totalSumLabel = loc.t('inventory_excel_total_sum') ?? 'Итого:';
      final totalRow = <CellValue>[
        TextCellValue(''),
        TextCellValue(totalSumLabel),
        TextCellValue(''),
        DoubleCellValue(totalSumAll),
        TextCellValue(''),
      ];
      for (var c = 0; c < maxCols; c++) totalRow.add(TextCellValue(''));
      sheet2.appendRow(totalRow);

      // Удаляем пустой лист по умолчанию, оставляем только «Продукты + ПФ» и «Все продукты с ПФ»
      excel.setDefaultSheet('Продукты + ПФ');
      for (final name in excel.tables.keys.toList()) {
        if (name != 'Продукты + ПФ' &&
            name != 'Все продукты с ПФ' &&
            excel.tables.keys.length > 2) {
          excel.delete(name);
          break;
        }
      }

      final out = excel.encode();
      return out != null && out.isNotEmpty ? out : null;
    } catch (e) {
      devLog('Error building Excel: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishment = account.establishment;
    final employee = account.currentEmployee;

    // Определяем режим ввода (клавиатура открыта). Обновляем только через addPostFrameCallback,
    // чтобы не мутировать state во время build — иначе на мобильной версии клавиатура закрывается.
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isKeyboardOpen = viewInsets.bottom > 0;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;

    // Обновляем _isInputMode только на десктопе — на мобильной setState при открытой клавиатуре
    // схлопывает layout и TextField теряет фокус → клавиатура закрывается.
    if (isKeyboardOpen && !_isInputMode && !isNarrow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            MediaQuery.viewInsetsOf(context).bottom > 0 &&
            !(MediaQuery.sizeOf(context).width < 600)) {
          setState(() => _isInputMode = true);
        }
      });
    } else if (!isKeyboardOpen && _isInputMode) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && MediaQuery.viewInsetsOf(context).bottom == 0) {
          setState(() => _isInputMode = false);
        }
      });
    }

    // collapseLayout: скрывать футер и шапку при клавиатуре. На мобильном viewInsets ненадёжен — по фокусу.
    final collapseLayout = (_isInputMode && !isNarrow) ||
        (isNarrow && (isKeyboardOpen || _hasInputFocus));
    // На мобильном при открытой клавиатуре скрываем строку с датой/именем (верхняя шапка),
    // но оставляем строку с фильтром — это делается без setState через isKeyboardOpen.
    final mobileKeyboardOpen = isNarrow && isKeyboardOpen;

    return Scaffold(
      appBar: (isNarrow && isKeyboardOpen)
          ? AppBar(
              leading: appBarBackButton(context),
              title: Text(
                loc.t('inventory_blank_title'),
                style: const TextStyle(fontSize: 16),
              ),
              toolbarHeight: 40,
              elevation: 0,
            )
          : _isInputMode
              ? AppBar(
                  leading: appBarBackButton(context),
                  title: Text(
                    loc.t('inventory_blank_title'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  toolbarHeight: 48,
                  elevation: 0,
                )
              : AppBar(
                  leading: appBarBackButton(context),
                  title: Text(loc.t('inventory_blank_title')),
                ),
      // Кнопка "Завершить" в bottomNavigationBar — Flutter поднимает её над клавиатурой автоматически.
      // Браузерный URL-бар (Safari/Chrome) остаётся ниже неё и не перекрывает таблицу.
      bottomNavigationBar: _buildFooter(loc, collapseLayout),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!collapseLayout)
                _buildHeader(
                  loc,
                  establishment,
                  employee,
                  collapseLayout: collapseLayout,
                  hideInfoRow: mobileKeyboardOpen,
                ),
              if (collapseLayout && !_completed && _rows.isNotEmpty)
                _buildCompactSearchBar(loc),
              if (!collapseLayout) const Divider(height: 1),
              if (collapseLayout && !_completed && _rows.isNotEmpty)
                const Divider(height: 1),
              Expanded(
                child: _buildTable(loc),
              ),
            ],
          ),
          if (!collapseLayout && !mobileKeyboardOpen)
            DataSafetyIndicator(isVisible: true),
        ],
      ),
    );
  }

  /// Компактная строка поиска (при открытой клавиатуре — как в iiko)
  Widget _buildCompactSearchBar(LocalizationService loc) {
    final theme = Theme.of(context);
    final sortAlphabetButton = IconButton(
      icon: const Icon(Icons.sort_by_alpha, size: 22),
      tooltip: _sortMode == _InventorySort.alphabetAsc
          ? (loc.t('inventory_sort_az') ?? 'А–Я')
          : (loc.t('inventory_sort_za') ?? 'Я–А'),
      onPressed: () => setState(() {
        _sortMode = _sortMode == _InventorySort.alphabetAsc
            ? _InventorySort.alphabetDesc
            : _InventorySort.alphabetAsc;
      }),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          sortAlphabetButton,
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _nameFilterCtrl,
              focusNode: _nameFilterFocusNode,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: loc.t('inventory_filter_name') ?? 'По названию',
                prefixIcon: Icon(Icons.search,
                    size: 22, color: theme.colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant, width: 1.5),
                ),
              ),
              style: const TextStyle(fontSize: 15),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  /// Шапка: дата_время начала_имя_должность_время завершения (компактно в 1 строку)
  Widget _buildHeader(
    LocalizationService loc,
    Establishment? establishment,
    Employee? employee, {
    bool collapseLayout = false,
    bool hideInfoRow = false,
  }) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final dateStr =
        '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    final startStr = _startTime != null
        ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
        : '—';
    final endStr = _endTime != null
        ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
        : null;
    final roleStr = employee != null && employee!.roles.isNotEmpty
        ? loc.roleDisplayName(employee!.roles.first)
        : '—';
    final headerLine =
        '$dateStr ${startStr} ${employee?.fullName ?? '—'} ($roleStr)${endStr != null ? ' $endStr' : ''}';
    final headerRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
            bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      child: Text(headerLine,
          style:
              theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
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
            width: narrow ? double.infinity : 240,
            child: TextField(
              controller: _nameFilterCtrl,
              focusNode: _nameFilterFocusNode,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: loc.t('inventory_filter_name') ?? 'По названию',
                prefixIcon: Icon(Icons.search,
                    size: 22, color: theme.colorScheme.onSurfaceVariant),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: theme.colorScheme.outlineVariant, width: 1.5),
                ),
              ),
              style: const TextStyle(fontSize: 15),
              onChanged: (_) => setState(() {}),
            ),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Строка с именем/должностью скрывается на мобильном при открытой клавиатуре
        if (!hideInfoRow) headerRow,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border:
                Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: narrow
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Строка с названием заведения и временем — скрывается при открытой клавиатуре
                      if (!collapseLayout && !hideInfoRow)
                        Row(
                          children: [
                            Icon(Icons.store,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                establishment?.name ?? '—',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () => _pickDate(context),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
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
                      if (sortAlphabetButton != null &&
                          nameFilterField != null) ...[
                        if (!hideInfoRow) const SizedBox(height: 6),
                        Row(
                          children: [
                            if (!collapseLayout) ...[
                              sortAlphabetButton!,
                              const SizedBox(width: 8)
                            ],
                            Expanded(child: nameFilterField!),
                          ],
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      if (sortAlphabetButton != null &&
                          nameFilterField != null) ...[
                        if (!collapseLayout) sortAlphabetButton!,
                        if (!collapseLayout) const SizedBox(width: 6),
                        nameFilterField!,
                        const SizedBox(width: 12),
                      ],
                      if (!collapseLayout) ...[
                        Icon(Icons.store,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            establishment?.name ?? '—',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (collapseLayout) const Spacer(),
                      InkWell(
                        onTap: () => _pickDate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
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
          ),
        ),
      ],
    );
  }

  Widget _buildTable(LocalizationService loc) {
    if (_isLoadingProducts) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Загрузка продуктов...'),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                loc.t('inventory_empty_hint'),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  /// Компактный нижний блок: не перекрывает таблицу, минимум высоты.
  /// [collapseLayout] — на десктопе при вводе скрываем футер. На мобильной при клавиатуре футер сдвигается вниз отступом (SizedBox выше), уходит под клавиатуру.
  Widget? _buildFooter(LocalizationService loc, bool collapseLayout) {
    if (collapseLayout) return null;

    final theme = Theme.of(context);
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
                onPressed: () => _complete(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(loc.t('inventory_complete')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _startNewInventory,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(loc.t('inventory_new')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableWithFixedColumn(LocalizationService loc) {
    final leftW = _leftWidth(context);

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
            // Номера колонок (без скролла — каждая строка скроллится сама)
            Expanded(child: _buildScrollableHeaderRow(loc)),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_blockFilter != _InventoryBlockFilter.pfOnly &&
                    _productIndices.isNotEmpty) ...[
                  _buildSectionHeaderRow(
                      loc, loc.t('inventory_block_products'), leftW),
                  ..._productIndices.asMap().entries.map((e) {
                    final lastIdx = _pfIndices.isNotEmpty
                        ? _pfIndices.last
                        : _productIndices.last;
                    return _buildScrollableDataRow(loc, e.value, e.key + 1,
                        isLastRow: e.value == lastIdx);
                  }),
                ],
                if (_blockFilter != _InventoryBlockFilter.productsOnly &&
                    _pfIndices.isNotEmpty) ...[
                  _buildSectionHeaderRow(
                      loc, loc.t('inventory_block_pf'), leftW),
                  ..._pfIndices.asMap().entries.map((e) {
                    final lastIdx = _pfIndices.last;
                    final rowNum = _blockFilter == _InventoryBlockFilter.pfOnly
                        ? e.key + 1
                        : _productIndices.length + e.key + 1;
                    return _buildScrollableDataRow(loc, e.value, rowNum,
                        isLastRow: e.value == lastIdx);
                  }),
                ],
                if (_aggregatedFromFile != null &&
                    _aggregatedFromFile!.isNotEmpty) ...[
                  _buildSectionHeaderRow(
                      loc, loc.t('inventory_pf_products_title'), leftW),
                  _buildAggregatedBlockRow(loc, leftW),
                ],
              ],
            ),
          ),
        ),
      ],
    );
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

  static const double _colNoWidth = 20; // Сужен с 28
  static const double _colUnitWidth = 48;
  static const double _colTotalWidth = 56;
  static const double _colQtyWidth = 48; // Сужен с 64
  static const double _colGap = 4; // Уменьшен с 10
  /// Высота заголовка секции (Продукты/ПФ) — для выравнивания фиксированной и прокручиваемой колонок.
  static const double _sectionHeaderHeight = 36;

  /// Фиксированная высота строки данных — для выравнивания ячеек ввода с текстом.
  static const double _dataRowHeight = 44;

  /// Ширина фиксированной части: #, Наименование, Мера, Итого (продукт зафиксирован слева).
  double _leftWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final base = (w * 0.42).clamp(140.0, 200.0);
    return base + _colGap + _colTotalWidth;
  }

  double _colNameWidth(BuildContext context) =>
      _leftWidth(context) -
      _colNoWidth -
      _colGap -
      _colUnitWidth -
      _colGap -
      _colTotalWidth;

  Widget _buildSectionHeaderRow(
      LocalizationService loc, String title, double leftW) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: leftW,
            child: _buildSectionHeader(loc, title, isFixed: true)),
        Expanded(child: SizedBox(height: _sectionHeaderHeight)),
      ],
    );
  }

  Widget _buildAggregatedBlockRow(LocalizationService loc, double leftW) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: leftW,
          decoration: BoxDecoration(
              border: Border(
                  right: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.3)))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFixedAggregatedHeaderRow(loc),
              ..._aggregatedFromFile!.asMap().entries.map(
                  (e) => _buildFixedAggregatedDataRow(loc, e.value, e.key + 1)),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildScrollableAggregatedHeaderRow(loc),
              ..._aggregatedFromFile!
                  .asMap()
                  .entries
                  .map((e) => _buildScrollableAggregatedDataRow(loc, e.value)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(LocalizationService loc, String title,
      {bool isFixed = false}) {
    final theme = Theme.of(context);
    final leftW = isFixed ? _leftWidth(context) : null;

    return SizedBox(
      height: _sectionHeaderHeight,
      width: leftW,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withOpacity(0.5),
          border: Border(
              bottom: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.3))),
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
          SizedBox(
              width: _colNoWidth,
              child: Text('#',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(
              width: _colNameWidth(context),
              child: Text(loc.t('inventory_item_name'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(
              width: _colUnitWidth,
              child: Text(loc.t('inventory_unit'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(
              width: _colTotalWidth,
              child: Text(loc.t('inventory_total'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
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
              padding:
                  EdgeInsets.only(right: colIndex < maxCols - 1 ? _colGap : 0),
              child: SizedBox(
                width: _colQtyWidth,
                child: Text('${colIndex + 1}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          if (!_completed) SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildFixedDataRow(
      LocalizationService loc, int actualIndex, int rowNumber) {
    final theme = Theme.of(context);
    final row = _rows[actualIndex];

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
          color: rowNumber.isEven
              ? theme.colorScheme.surface
              : theme.colorScheme.surfaceContainerLowest.withOpacity(0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
                width: _colNoWidth,
                child: Text('$rowNumber',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
            SizedBox(width: _colGap),
            SizedBox(
              width: _colNameWidth(context),
              child: Text(
                row.productName(loc.currentLanguageCode),
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
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
                              DropdownMenuItem(
                                  value: _pfUnitPcs,
                                  child: Text(
                                      loc.currentLanguageCode == 'ru'
                                          ? 'порц.'
                                          : 'pcs',
                                      style: theme.textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(
                                  value: _pfUnitGrams,
                                  child: Text(
                                      loc.currentLanguageCode == 'ru'
                                          ? 'гр'
                                          : 'g',
                                      style: theme.textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) =>
                                v != null ? _setPfUnit(actualIndex, v) : null,
                          ),
                        )
                      : _ProductUnitDropdown(
                          value: row.isCountedByPackage
                              ? (row.unitOverride ?? 'pkg')
                              : row.unit,
                          lang: loc.currentLanguageCode,
                          product: row.product,
                          onChanged: (v) => _setProductUnit(actualIndex, v),
                          theme: theme,
                        ))
                  : Text(row.unitDisplayForBlank(loc.currentLanguageCode),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
            ),
            SizedBox(width: _colGap),
            Container(
              width: _colTotalWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              child: Text(_formatQty(row.totalDisplay),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollableDataRow(
      LocalizationService loc, int actualIndex, int rowNumber,
      {bool isLastRow = false}) {
    final row = _rows[actualIndex];
    return _StandardInventoryRowTile(
      fixedPart: _buildFixedDataRow(loc, actualIndex, rowNumber),
      row: row,
      actualIndex: actualIndex,
      isLastRow: isLastRow,
      completed: _completed,
      formatQty: _formatQty,
      onSetQuantity: _setQuantity,
      onLastCellFocused: _onLastCellFocused,
      onCellFocusLost: _onCellFocusLost,
      onFocusChange: (hasFocus) => setState(() => _hasInputFocus = hasFocus),
      leftWidth: _leftWidth(context),
      colQtyWidth: _colQtyWidth,
      colGap: _colGap,
      dataRowHeight: _dataRowHeight,
      loc: loc,
    );
  }

  String _formatQty(double q) {
    if (q == q.truncateToDouble()) return q.toInt().toString();
    return q.toStringAsFixed(1);
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
          SizedBox(
              width: _colNoWidth,
              child: Text(loc.t('inventory_excel_number'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          Expanded(
              child: Text(loc.t('inventory_item_name'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
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
          SizedBox(
              width: 72,
              child: Text(loc.t('inventory_pf_gross_g'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
          SizedBox(width: _colGap),
          SizedBox(
              width: 72,
              child: Text(loc.t('inventory_pf_net_g'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildFixedAggregatedDataRow(
      LocalizationService loc, Map<String, dynamic> p, int rowNumber) {
    final theme = Theme.of(context);
    final name = p['productName'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          SizedBox(
              width: _colNoWidth,
              child: Text('$rowNumber',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
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

  Widget _buildScrollableAggregatedDataRow(
      LocalizationService loc, Map<String, dynamic> p) {
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
          SizedBox(
              width: 72,
              child: Text('$gross', style: theme.textTheme.bodyMedium)),
          SizedBox(width: _colGap),
          SizedBox(
              width: 72,
              child: Text('$net', style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  Future<void> _showProductPicker(
      BuildContext context, LocalizationService loc) async {
    final productStore = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final estId = est?.dataEstablishmentId;
    if (estId == null) return;
    await productStore.loadProducts();
    await productStore.loadNomenclature(estId);
    if (!mounted) return;

    final products = productStore.getNomenclatureProducts(estId);
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${loc.t('nomenclature')}: ${loc.t('no_products')}')),
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

  /// Диалог: формат экспорта (Excel/CSV) + язык сохранения файла.
  /// Возвращает (format, lang) или null при отмене.
  Future<({String format, String lang})?> _showExportFormatAndLanguageDialog(
    BuildContext context,
    LocalizationService loc,
  ) async {
    String selectedLang = loc.currentLanguageCode;
    return showDialog<({String format, String lang})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) => AlertDialog(
            title: Text(loc.t('inventory_export_dialog_title') ??
                'Сохранение на устройство'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.t('inventory_export_lang') ?? 'Язык сохранения:',
                    style: Theme.of(ctx2).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children:
                        LocalizationService.productLanguageCodes.map((code) {
                      return ChoiceChip(
                        label: Text(loc.getLanguageName(code)),
                        selected: selectedLang == code,
                        onSelected: (_) => setState(() => selectedLang = code),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx)
                    .pop((format: 'excel', lang: selectedLang)),
                child:
                    Text(loc.t('inventory_export_excel') ?? 'Сохранить Excel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop((format: 'csv', lang: selectedLang)),
                child: const Text('CSV'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadExcel(List<int> bytes, Map<String, dynamic> payload,
      LocalizationService loc, String extension) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ??
        DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.$extension';
    await saveFileBytes(fileName, bytes);
  }

  Future<void> _downloadCsv(String csvData, Map<String, dynamic> payload,
      LocalizationService loc) async {
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final date = header['date'] as String? ??
        DateTime.now().toIso8601String().split('T').first;
    final fileName = 'inventory_$date.csv';
    final bytes = utf8.encode(csvData);
    await saveFileBytes(fileName, bytes);
  }

  /// Цена строки: из номенклатуры заведения (establishment_products) или карточки продукта × итого.
  /// 100 руб/кг → 10 г = 1 руб.
  double? _computeRowPrice(_InventoryRow r, String establishmentId,
      ProductStoreSupabase productStore) {
    final p = r.product;
    if (p == null) return null;
    final estPrice =
        productStore.getEstablishmentPrice(p.id, establishmentId)?.$1;
    if (r.isCountedByPackage) {
      final pp = p.packagePrice ?? estPrice;
      if (pp == null) return null;
      return r.total * pp;
    }
    final u = (p.unit ?? 'g').toLowerCase();
    if (u == 'kg' || u == 'кг') {
      final pricePerKg = p.computedPricePerKg ?? estPrice;
      if (pricePerKg == null) return null;
      return r.totalWeightGrams / 1000.0 * pricePerKg;
    }
    if (u == 'g' || u == 'г') {
      final pricePerKg = p.computedPricePerKg ?? estPrice;
      if (pricePerKg == null) return null;
      return r.totalWeightGrams / 1000.0 * pricePerKg;
    }
    // pcs, шт, ml, l и т.д. — цена за единицу × количество
    final pricePerUnit = estPrice;
    if (pricePerUnit == null) return null;
    return r.total * pricePerUnit;
  }

  Map<String, dynamic> _buildPayload({
    required Establishment establishment,
    required Employee employee,
    required TimeOfDay endTime,
    required String lang,
    List<Map<String, dynamic>>? aggregatedProducts,
  }) {
    final loc = context.read<LocalizationService>();
    final roleKey =
        employee.roles.isNotEmpty ? 'role_${employee.roles.first}' : 'employee';
    final header = {
      'establishmentName': establishment.name,
      'employeeName': employee.fullName,
      'employeeRole': loc.tForLanguage(lang, roleKey) != roleKey
          ? loc.tForLanguage(lang, roleKey)
          : (employee.roleDisplayName),
      'department': employee.department,
      'date':
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      'timeStart': _startTime != null
          ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
          : null,
      'timeEnd':
          '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
    };
    final rows = _rows.map((r) {
      final id = r.product != null
          ? r.product!.id
          : r.techCard != null
              ? 'pf_${r.techCard!.id}'
              : 'free_${_rows.indexOf(r)}';
      final map = <String, dynamic>{
        'productId': id,
        'productName': r.productName(lang),
        'unit': r.isCountedByPackage
            ? (r.unitOverride == 'btl'
                ? (lang == 'ru' ? 'мл' : 'ml')
                : (lang == 'ru' ? 'г' : 'g'))
            : r.unitDisplayForBlank(lang),
        'quantities': r.isCountedByPackage
            ? r.quantities.map((q) => q * r.packageWeightGrams).toList()
            : r.isWeightInKg
                ? r.quantities.map((q) => q * 1000).toList()
                : r.quantities,
        'total': r.totalWeightGrams,
      };
      if (r.isCountedByPackage) {
        map['packageCount'] = r.total;
        map['packageWeightGrams'] = r.packageWeightGrams;
        map['unitRaw'] = r.unitOverride == 'btl'
            ? (lang == 'ru' ? 'бутылка' : 'bottle')
            : (lang == 'ru' ? 'упак.' : 'pkg');
      }
      if (r.isPf) map['pfUnit'] = r.pfUnit ?? _pfUnitPcs;
      // Цена: из номенклатуры заведения или карточки × итого
      final productStore = context.read<ProductStoreSupabase>();
      final price = _computeRowPrice(r, establishment.id, productStore);
      if (price != null && price > 0) map['price'] = price;
      return map;
    }).toList();
    return {
      'header': header,
      'rows': rows,
      'aggregatedProducts': aggregatedProducts ?? [],
      'sourceLang': lang,
    };
  }
}

/// Строка стандартной инвентаризации: [фикс.часть | скролл ячеек]. Скролл — per-row, как в iiko.
class _StandardInventoryRowTile extends StatefulWidget {
  const _StandardInventoryRowTile({
    required this.fixedPart,
    required this.row,
    required this.actualIndex,
    required this.isLastRow,
    required this.completed,
    required this.formatQty,
    required this.onSetQuantity,
    required this.onLastCellFocused,
    required this.onCellFocusLost,
    required this.onFocusChange,
    required this.leftWidth,
    required this.colQtyWidth,
    required this.colGap,
    required this.dataRowHeight,
    required this.loc,
  });

  final Widget fixedPart;
  final _InventoryRow row;
  final int actualIndex;
  final bool isLastRow;
  final bool completed;
  final String Function(double) formatQty;
  final void Function(int, int, double) onSetQuantity;
  final void Function(int) onLastCellFocused;
  final void Function(int, int) onCellFocusLost;
  final void Function(bool) onFocusChange;
  final double leftWidth;
  final double colQtyWidth;
  final double colGap;
  final double dataRowHeight;
  final LocalizationService loc;

  @override
  State<_StandardInventoryRowTile> createState() =>
      _StandardInventoryRowTileState();
}

class _StandardInventoryRowTileState extends State<_StandardInventoryRowTile> {
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    void doScroll() {
      if (_hScroll.hasClients) {
        _hScroll.animateTo(
          _hScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      doScroll();
      Future.delayed(const Duration(milliseconds: 350), doScroll);
    });
  }

  @override
  void didUpdateWidget(_StandardInventoryRowTile old) {
    super.didUpdateWidget(old);
    if (old.row.quantities.length < widget.row.quantities.length) {
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final qtyCols = row.quantities.length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: widget.leftWidth, child: widget.fixedPart),
          Expanded(
            child: SingleChildScrollView(
              controller: _hScroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                      bottom: BorderSide(
                          color: theme.dividerColor.withOpacity(0.5))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...List.generate(
                      qtyCols,
                      (colIndex) {
                        final isLastCell =
                            widget.isLastRow && colIndex == qtyCols - 1;
                        return Padding(
                          padding: EdgeInsets.only(
                              right:
                                  colIndex < qtyCols - 1 ? widget.colGap : 0),
                          child: SizedBox(
                            width: widget.colQtyWidth,
                            child: Center(
                              child: widget.completed
                                  ? Text(
                                      widget.formatQty(
                                          row.quantityDisplayAt(colIndex)),
                                      style: theme.textTheme.bodyMedium)
                                  : _QtyCell(
                                      key: ValueKey(
                                          'qty_${widget.actualIndex}_$colIndex'),
                                      value: row.quantities[colIndex],
                                      useGrams: row.isWeightInKg,
                                      onChanged: (v) => widget.onSetQuantity(
                                          widget.actualIndex, colIndex, v),
                                      textInputAction: isLastCell
                                          ? TextInputAction.done
                                          : TextInputAction.next,
                                      onFocusGained: () {
                                        widget.onFocusChange(true);
                                        if (colIndex == qtyCols - 1) {
                                          widget.onLastCellFocused(
                                              widget.actualIndex);
                                        }
                                      },
                                      onFocusLost: () {
                                        widget.onFocusChange(false);
                                        widget.onCellFocusLost(
                                            widget.actualIndex, colIndex);
                                        if (colIndex == qtyCols - 2 &&
                                            row.quantities[colIndex] > 0)
                                          _scrollToEnd();
                                      },
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Выпадающий список единицы измерения для продукта.
/// Ограничен данными продукта: шт — только при gramsPerPiece; упак — при packageWeightGrams.
class _ProductUnitDropdown extends StatelessWidget {
  const _ProductUnitDropdown({
    required this.value,
    required this.lang,
    required this.onChanged,
    required this.theme,
    this.product,
  });

  final String value;
  final String lang;
  final void Function(String) onChanged;
  final ThemeData theme;
  final Product? product;

  static const List<String> _baseUnits = ['g', 'kg', 'ml', 'l'];

  static List<String> _allowedUnits(Product? p) {
    final options = List<String>.from(_baseUnits);
    final hasGpp = p?.gramsPerPiece != null && p!.gramsPerPiece! > 0;
    if (hasGpp) {
      // Храним канонически как pcs, чтобы не было дублей в UI.
      options.add('pcs');
    }
    final hasPkg = p?.packageWeightGrams != null && p!.packageWeightGrams! > 0;
    if (hasPkg) {
      options.add('pkg');
      options.add('btl');
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final options = _allowedUnits(product);
    final normalized = value.trim().toLowerCase();
    final match =
        options.where((u) => u.toLowerCase() == normalized).firstOrNull;
    final displayValue = match ?? options.first;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: displayValue,
        isDense: true,
        isExpanded: true,
        items: options
            .map((u) => DropdownMenuItem(
                  value: u,
                  child: Text(
                    u == 'pkg'
                        ? (lang == 'ru' ? 'упак.' : 'pkg')
                        : u == 'btl'
                            ? (lang == 'ru' ? 'бутылка' : 'bottle')
                            : CulinaryUnits.displayName(u, lang),
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
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

  /// TextInputAction.next — «Далее» на клавиатуре переходит к следующей ячейке.
  final TextInputAction textInputAction;
  final VoidCallback? onFocusGained;
  final VoidCallback? onFocusLost;

  const _QtyCell({
    super.key,
    required this.value,
    this.useGrams = false,
    required this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onFocusGained,
    this.onFocusLost,
  });

  @override
  State<_QtyCell> createState() => _QtyCellState();
}

class _QtyCellState extends State<_QtyCell> {
  late TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  late double _currentValue;
  Timer? _updateTimer;

  double get _displayValueRaw =>
      widget.useGrams ? widget.value * 1000 : widget.value;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: _displayValue(_displayValueRaw));
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_QtyCell old) {
    super.didUpdateWidget(old);
    // Не восстанавливаем фокус принудительно — иначе при тапе по поиску/фильтру
    // фокус «убегает» обратно в ячейку и показывается цифровая клавиатура.
    // Обновляем текст только если значение изменилось извне и фокус не активен
    if (old.value != widget.value && !_focus.hasFocus) {
      _currentValue = widget.value;
      _controller.text = _displayValue(_displayValueRaw);
    }
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) {
      widget.onFocusGained?.call();
    } else {
      widget.onFocusLost?.call();
      // При потере фокуса применяем изменения
      final textValue = _controller.text.trim();
      final parsedValue =
          double.tryParse(textValue.replaceFirst(',', '.')) ?? 0;
      final actualValue = widget.useGrams ? parsedValue / 1000 : parsedValue;
      widget.onChanged(actualValue);
    }
  }

  String _displayValue(double v) {
    if (v == 0) return '';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(widget.useGrams ? 0 : 1);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: widget.textInputAction,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
        ],
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.2),
        decoration: InputDecoration(
          isDense: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        ),
        onChanged: (s) {
          // Обновляем локальное значение
          final v = double.tryParse(s.replaceFirst(',', '.')) ?? 0;
          _currentValue = widget.useGrams ? v / 1000 : v;

          // Откладываем применение изменений для избежания частых перестроений
          _updateTimer?.cancel();
          _updateTimer = Timer(const Duration(milliseconds: 150), () {
            if (mounted) {
              widget.onChanged(_currentValue);
            }
          });
        },
      ),
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
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
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
                  title:
                      Text(p.getLocalizedName(widget.loc.currentLanguageCode)),
                  subtitle: Text(
                      '${p.category} · ${CulinaryUnits.displayName((p.unit ?? 'g').trim().toLowerCase(), widget.loc.currentLanguageCode)}'),
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

// ─────────────────────────────────────────────────────────────────────────────
// ЭКРАН ИНВЕНТАРИЗАЦИИ iiko
// ─────────────────────────────────────────────────────────────────────────────

/// Строка iiko-инвентаризации: продукт из iiko_products + количество (одна ячейка).
// ══════════════════════════════════════════════════════════════════════════════
// iiko-инвентаризация
// ══════════════════════════════════════════════════════════════════════════════

/// Одна строка iiko-инвентаризации: продукт + список замеров (как в стандартной).
class _IikoInventoryRow {
  IikoProduct product;
  List<double> quantities; // список замеров, минимум 2

  _IikoInventoryRow({required this.product, List<double>? quantities})
      : quantities = quantities ?? [0.0, 0.0];

  /// Итого = сумма всех замеров
  double get total => quantities.fold(0.0, (a, b) => a + b);
}

/// Экран инвентаризации в режиме iiko.
/// - Автосохранение в localStorage при каждом изменении (AutoSaveMixin)
/// - 2 ячейки ввода + итого (как в стандартной инвентаризации)
/// - При сохранении — Excel той же структуры что входной бланк + отправка шефу
class InventoryIikoScreen extends StatefulWidget {
  const InventoryIikoScreen({super.key});

  @override
  State<InventoryIikoScreen> createState() => _InventoryIikoScreenState();
}

/// Глобальный реестр FocusNode для iiko-ячеек.
/// Каждый _IikoInventoryRowTileState регистрирует свои узлы при init и снимает при dispose.
/// _InventoryIikoScreenState.navigate() использует список для перехода между ячейками.
final List<FocusNode> _iikoCellFocusNodes = [];

class _InventoryIikoScreenState extends State<InventoryIikoScreen>
    with AutoSaveMixin<InventoryIikoScreen> {
  final List<_IikoInventoryRow> _rows = [];
  bool _isLoading = true;
  bool _completed = false;
  DateTime _date = DateTime.now();
  String _nameFilter = '';
  String? _selectedSheet; // активный лист (null = первый/все)
  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Временное хранилище данных черновика до загрузки продуктов
  Map<String, dynamic>? _pendingDraftData;

  // Метка времени последнего сохранения (для индикатора "Данные защищены")
  DateTime? _lastSavedAt;

  // ── AutoSaveMixin ──────────────────────────────────────────────────────────
  @override
  String get draftKey => 'iiko_inventory';

  @override
  Map<String, dynamic> getCurrentState() {
    return {
      'date': _date.toIso8601String(),
      'quantities': {
        for (final r in _rows)
          if (r.total > 0) r.product.id: r.quantities,
      },
    };
  }

  /// AutoSaveMixin вызывает это ДО загрузки продуктов (_rows пуст).
  /// Сохраняем данные во временную переменную, применяем в _applyDraft.
  @override
  Future<void> restoreState(Map<String, dynamic> data) async {
    _pendingDraftData = data;
    // Если продукты уже загружены — применяем сразу
    if (_rows.isNotEmpty) _applyDraft(data);
  }

  /// Применяет данные черновика к заполненным _rows.
  void _applyDraft(Map<String, dynamic> data) {
    if (!mounted) return;
    final dateStr = data['date'] as String?;
    final qtMap = data['quantities'] as Map<String, dynamic>?;
    setState(() {
      if (dateStr != null) _date = DateTime.tryParse(dateStr) ?? _date;
      if (qtMap != null) {
        for (final r in _rows) {
          final saved = qtMap[r.product.id];
          if (saved is List && saved.isNotEmpty) {
            r.quantities = saved.map((e) => (e as num).toDouble()).toList();
            if (r.quantities.length < 2) r.quantities.add(0.0);
          }
        }
      }
      _lastSavedAt = DateTime.now(); // черновик загружен — данные под защитой
    });
  }
  // ──────────────────────────────────────────────────────────────────────────

  /// Скрывать статус и кнопки при клавиатуре. На мобильном viewInsets часто 0,
  /// поэтому на узком экране скрываем по фокусу в поле.
  bool get _isKeyboardActive {
    if (!mounted) return false;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return true;
    if (MediaQuery.sizeOf(context).width >= 600) return false;
    return _searchFocusNode.hasFocus ||
        _iikoCellFocusNodes.any((n) => n.hasFocus);
  }

  @override
  void initState() {
    super.initState(); // AutoSaveMixin.initState регистрирует lifecycle-хуки
    _filterCtrl
        .addListener(() => setState(() => _nameFilter = _filterCtrl.text));
    _searchFocusNode.addListener(() => setState(() {}));
    _registerJsNavChannel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Подписываемся на store: когда restoreBlankFromStorage завершится и
      // обновит sheetName у продуктов — синхронизируем _rows
      final store = context.read<IikoProductStore>();
      store.addListener(_onStoreUpdated);
      _loadProducts();
      _startPeriodicServerSave();
    });
  }

  /// Регистрирует window._flutterNav(dir) — вызывается JS кнопками ▲▼.
  /// dir = 1 → следующая ячейка, dir = -1 → предыдущая.
  void _registerJsNavChannel() {
    flutter_nav.registerFlutterNav((dynamic dirArg) {
      if (!mounted) return;
      final dir = (dirArg is num) ? dirArg.toInt() : 1;
      _navigateCell(dir);
    });
  }

  void _navigateCell(int dir) {
    if (_iikoCellFocusNodes.isEmpty) return;
    // Найти текущий сфокусированный узел
    final currentIdx = _iikoCellFocusNodes.indexWhere((n) => n.hasFocus);
    final nextIdx = currentIdx < 0
        ? (dir > 0 ? 0 : _iikoCellFocusNodes.length - 1)
        : currentIdx + dir;
    if (nextIdx >= 0 && nextIdx < _iikoCellFocusNodes.length) {
      _iikoCellFocusNodes[nextIdx].requestFocus();
    }
  }

  /// Вызывается когда IikoProductStore нотифицирует (после restoreBlankFromStorage).
  /// Синхронизирует sheetName в _rows из актуального store.products.
  void _onStoreUpdated() {
    if (!mounted || _rows.isEmpty) return;
    final store = context.read<IikoProductStore>();
    final storeProducts = {for (final p in store.products) p.id: p};
    var changed = false;
    for (final row in _rows) {
      final fresh = storeProducts[row.product.id];
      if (fresh != null && fresh.sheetName != row.product.sheetName) {
        row.product = fresh;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _searchFocusNode.dispose();
    _serverSaveTimer?.cancel();
    _iikoCellFocusNodes.clear();
    flutter_nav.unregisterFlutterNav();
    // Отписываемся от store чтобы не вызывать setState после unmount
    try {
      context.read<IikoProductStore>().removeListener(_onStoreUpdated);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) return;
    final iikoStore = context.read<IikoProductStore>();

    // Всегда ждём и бланк, и продукты вместе — так _rows и sheetNames всегда синхронны.
    // restoreBlankFromStorage запускаем параллельно с loadProducts чтобы не блокировать.
    final blankFuture =
        iikoStore.restoreBlankFromStorage(establishmentId: estId);

    if (iikoStore.products.isEmpty) {
      // Продуктов нет в памяти — грузим из БД
      await iikoStore.loadProducts(estId);
    }

    // Ждём завершения бланка (нужен для корректных sheetName у продуктов)
    await blankFuture;

    if (!mounted) return;
    setState(() {
      _rows.clear();
      for (final p in iikoStore.products) {
        if (p.name.trim().isEmpty) continue;
        if (_isIikoHeaderRow(p.name)) continue;
        _rows.add(_IikoInventoryRow(product: p));
      }
      _isLoading = false;
    });
    // Применяем черновик — теперь _rows заполнен
    final draft = _pendingDraftData;
    if (draft != null) {
      _applyDraft(draft);
      _pendingDraftData = null;
    } else {
      // Черновик ещё не пришёл от AutoSaveMixin — загружаем явно из localStorage
      final draftStorage = DraftStorageService();
      final saved = await draftStorage.loadIikoInventoryDraft();
      if (saved != null && mounted) {
        _applyDraft(saved);
      } else if (estId != null) {
        // Запасной уровень — Supabase (если localStorage был очищен)
        await _tryRestoreFromServer(estId);
      }
    }
  }

  List<_IikoInventoryRow> get _filteredRows {
    final iikoStore = context.read<IikoProductStore>();
    final sheetNames = iikoStore.sheetNames;
    final hasSheets = sheetNames.length > 1;
    final activeSheet = (hasSheets && sheetNames.contains(_selectedSheet))
        ? _selectedSheet
        : (hasSheets ? sheetNames.first : null);

    var rows = _rows;
    if (hasSheets && activeSheet != null) {
      rows = rows.where((r) {
        final sn = r.product.sheetName;
        // Продукты без sheetName показываем на первом листе
        if (sn == null || sn.isEmpty) return activeSheet == sheetNames.first;
        return sn == activeSheet;
      }).toList();
    }
    if (_nameFilter.isEmpty) return rows;
    final q = _nameFilter.toLowerCase();
    return rows
        .where((r) =>
            r.product.displayName.toLowerCase().contains(q) ||
            r.product.name.toLowerCase().contains(q))
        .toList();
  }

  Timer? _serverSaveTimer;

  void _setQuantity(_IikoInventoryRow row, int colIndex, double value) {
    setState(() {
      row.quantities[colIndex] = value;
      // Добавляем ячейку если заполнили последнюю
      if (colIndex == row.quantities.length - 1 && value > 0) {
        row.quantities.add(0.0);
      }
    });
    scheduleSave(); // AutoSaveMixin — localStorage, 300мс
    // Обновляем метку после debounce (300мс)
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _lastSavedAt = DateTime.now());
    });
  }

  /// Периодическое сохранение в Supabase каждые 10с — работает даже в инкогнито.
  void _startPeriodicServerSave() {
    _serverSaveTimer?.cancel();
    _serverSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_completed) _saveIikoDraftToServer();
    });
  }

  Future<void> _saveIikoDraftToServer() async {
    if (_completed || _rows.isEmpty || !mounted) return;
    try {
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      final empId = account.currentEmployee?.id;
      if (estId == null) return;
      final data = getCurrentState();
      await Supabase.instance.client.from('inventory_drafts').upsert(
        {
          'establishment_id': estId,
          'employee_id': empId,
          'draft_type': 'iiko_inventory',
          'draft_data': data,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'establishment_id,draft_type',
      );
    } catch (_) {}
  }

  void _clearServerDraft() {
    if (!mounted) return;
    try {
      final account = context.read<AccountManagerSupabase>();
      final estId = account.establishment?.id;
      if (estId == null) return;
      Supabase.instance.client
          .from('inventory_drafts')
          .delete()
          .eq('establishment_id', estId)
          .eq('draft_type', 'iiko_inventory');
    } catch (_) {}
  }

  /// Восстанавливает iiko-черновик с сервера (инкогнито / очищенный localStorage).
  Future<void> _tryRestoreFromServer(String estId) async {
    try {
      final row = await Supabase.instance.client
          .from('inventory_drafts')
          .select('draft_data')
          .eq('establishment_id', estId)
          .eq('draft_type', 'iiko_inventory')
          .maybeSingle();
      if (row == null) return;
      final data = row['draft_data'] as Map<String, dynamic>?;
      if (data == null) return;
      if (mounted) _applyDraft(data);
    } catch (_) {}
  }

  /// Диалог подтверждения обнуления всех количеств.
  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Обнулить данные?'),
        content: const Text(
          'Все введённые количества будут сброшены. Продукты останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Обнулить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      for (final r in _rows) {
        r.quantities = [0.0, 0.0];
      }
      _completed = false;
      _lastSavedAt = null;
    });
    // Сбрасываем черновики
    await clearDraft();
    _clearServerDraft();
    if (mounted) scheduleSave();
  }

  Future<void> _saveAndExport() async {
    // Снимаем фокус чтобы зафиксировать последнее значение в активном поле
    FocusScope.of(context).unfocus();
    // Даём фреймворку обработать onEditingComplete / onChanged
    await Future.delayed(const Duration(milliseconds: 50));
    final bytes = await _buildIikoExcel();

    final date = _date;
    final fileName =
        'Инвентаризация_iiko_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}.xlsx';

    try {
      await _downloadBytes(bytes, fileName);

      // Отправляем шефу во входящие
      await _sendToChef(bytes, fileName);

      // Не очищаем черновик — можно довнести и сохранить снова

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено и отправлено шефу: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }

  /// Отправляет инвентаризацию во входящие шеф-повару.
  Future<void> _sendToChef(Uint8List bytes, String fileName) async {
    try {
      final account = context.read<AccountManagerSupabase>();
      final establishment = account.establishment;
      final employee = account.currentEmployee;
      if (establishment == null || employee == null) return;

      // Ищем шеф-повара/су-шефа/владельца в заведении (получатель во входящих)
      final allEmployees = await Supabase.instance.client
          .from('employees')
          .select()
          .eq('establishment_id', establishment.id)
          .or('roles.cs.{executive_chef},roles.cs.{owner},roles.cs.{sous_chef}');
      final chefList = allEmployees as List;
      if (chefList.isEmpty) return;
      final chef = chefList.first as Map<String, dynamic>;

      final dept = (employee.department == 'bar' ||
              employee.hasRole('bar_manager') ||
              employee.hasRole('bartender'))
          ? 'bar'
          : 'kitchen';
      final payload = {
        'type': 'iiko_inventory',
        'header': {
          'date': _date.toIso8601String(),
          'establishmentName': establishment.name,
          'employeeName': employee.fullName,
          'department': dept,
          'fileName': fileName,
          'totalPositions': _rows.length,
          'filledPositions': _rows.where((r) => r.total > 0).length,
        },
        // Сохраняем ВСЕ строки — чтобы во входящих отображались в т.ч. незаполненные
        'rows': _rows
            .map((r) => {
                  'code': r.product.code,
                  'name': r.product.name,
                  'unit': r.product.unit,
                  'groupName': r.product.groupName,
                  'sheetName': r.product.sheetName,
                  'quantities': r.quantities,
                  'total': r.total,
                })
            .toList(),
      };

      final docService = InventoryDocumentService();
      await docService.save(
        establishmentId: establishment.id,
        createdByEmployeeId: employee.id,
        recipientChefId: chef['id'] as String,
        recipientEmail: (chef['email'] as String?) ?? '',
        payload: payload,
      );
    } catch (e) {
      devLog('InventoryIiko._sendToChef error: $e');
      // Не прерываем — скачивание файла важнее
    }
  }

  Future<Uint8List> _buildIikoExcel() async {
    final iikoStore = context.read<IikoProductStore>();
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    // Если байты не в памяти — пробуем localStorage → Supabase Storage
    await iikoStore.restoreBlankFromStorage(establishmentId: estId);
    final origBytes = iikoStore.originalBlankBytes;
    final qtyCol = iikoStore.originalQuantityColumnIndex ?? 5;
    final sheetQtyCols = iikoStore.sheetQtyColumns;
    return origBytes != null
        ? _buildFromOriginal(origBytes, qtyCol, sheetQtyCols: sheetQtyCols)
        : _buildFallback();
  }

  /// Прямой байтовый патч xlsx без перепаковки ZIP.
  ///
  /// Алгоритм:
  ///  1. Находим sheet1.xml в ZIP через central directory
  ///  2. Декодируем (inflate) только этот файл
  ///  3. Патчим XML — ставим значения в колонку qty
  ///  4. Снова сжимаем (deflate) и вставляем в ZIP побайтово
  ///  5. Все остальные файлы остаются **ровно теми же битами** — ни один байт
  ///     не меняется → sheetFormatPr, sheetViews, mergedCells, styles
  ///     сохраняются 100% идентично оригиналу
  Uint8List _buildFromOriginal(
    Uint8List origBytes,
    int qtyCol, {
    Map<String, int> sheetQtyCols = const {},
  }) {
    // ── 1. Код → итого (по листам) ────────────────────────────────────────────
    final qtyBySheetCode = <String?, Map<String, double>>{};
    for (final r in _rows) {
      if (r.total > 0 && r.product.code != null) {
        final sheet = r.product.sheetName;
        qtyBySheetCode.putIfAbsent(sheet, () => {})[r.product.code!.trim()] =
            r.total;
      }
    }
    final qtyByCodeFlat = <String, double>{
      for (final m in qtyBySheetCode.values)
        for (final e in m.entries) e.key: e.value,
    };
    if (qtyByCodeFlat.isEmpty) return origBytes;

    // ── 2. Читаем ZIP ─────────────────────────────────────────────────────────
    final arc = ZipDecoder().decodeBytes(origBytes);

    String colLetter(int idx) {
      var result = '';
      var n = idx + 1;
      while (n > 0) {
        n--;
        result = String.fromCharCode(65 + n % 26) + result;
        n ~/= 26;
      }
      return result;
    }

    // sharedStrings
    final sharedStrings = <String>[];
    final ssEntry = arc.findFile('xl/sharedStrings.xml');
    if (ssEntry != null) {
      final ssXml = utf8.decode(ssEntry.content as List<int>);
      final siRe = RegExp(r'<si>(.*?)</si>', dotAll: true);
      final tRe = RegExp(r'<t[^>]*>([^<]*)</t>');
      for (final si in siRe.allMatches(ssXml)) {
        sharedStrings
            .add(tRe.allMatches(si.group(1)!).map((m) => m.group(1)!).join());
      }
    }

    // ── 3. Строим карту листов: displayName → { path, col } ───────────────────
    final wbEntry = arc.findFile('xl/workbook.xml');
    final relsEntry = arc.findFile('xl/_rels/workbook.xml.rels');
    final sheetInfos = <String, ({String path, int col})>{};

    if (wbEntry != null && relsEntry != null) {
      final wb = utf8.decode(wbEntry.content as List<int>);
      final rels = utf8.decode(relsEntry.content as List<int>);
      for (final sm in RegExp(r'<sheet\b([^>]*)/>').allMatches(wb)) {
        final attrs = sm.group(1)!;
        final nameM = RegExp(r'name="([^"]*)"').firstMatch(attrs);
        final rIdM = RegExp(r'r:id="([^"]*)"').firstMatch(attrs);
        if (nameM == null || rIdM == null) continue;
        final displayName = nameM.group(1)!;
        final rId = rIdM.group(1)!;
        final tM = RegExp('Id="$rId"[^>]*Target="([^"]+)"').firstMatch(rels);
        if (tM == null) continue;
        final t = tM.group(1)!;
        final path = t.startsWith('/') ? t.substring(1) : 'xl/$t';
        final col = sheetQtyCols[displayName] ?? qtyCol;
        sheetInfos[displayName] = (path: path, col: col);
      }
    }
    if (sheetInfos.isEmpty) {
      sheetInfos[''] = (path: 'xl/worksheets/sheet1.xml', col: qtyCol);
    }

    // ── 4. Патчим каждый лист ─────────────────────────────────────────────────
    String patchSheetXml(String xml, String sheetName, int sheetQtyCol) {
      final qtyByCode =
          qtyBySheetCode[sheetName] ?? qtyBySheetCode[null] ?? qtyByCodeFlat;
      if (qtyByCode.isEmpty) return xml;

      final qtyColLetter = colLetter(sheetQtyCol);
      int codeColIdx = 2;
      outer:
      for (final rowM
          in RegExp(r'<row r="(\d+)"[^>]*>(.*?)</row>', dotAll: true)
              .allMatches(xml)) {
        if (int.parse(rowM.group(1)!) > 20) break;
        for (final cm in RegExp(
                r'<c r="([A-Z]+)\d+"(?:[^>]*)t="s"(?:[^>]*)><v>(\d+)</v></c>')
            .allMatches(rowM.group(2)!)) {
          final idx = int.tryParse(cm.group(2)!) ?? -1;
          if (idx >= 0 && idx < sharedStrings.length) {
            final v = sharedStrings[idx].trim().toLowerCase();
            if (v == 'код' || v == 'code') {
              var ci = 0;
              for (final ch in cm.group(1)!.runes) ci = ci * 26 + (ch - 65 + 1);
              codeColIdx = ci - 1;
              break outer;
            }
          }
        }
      }
      final codeColLetter = colLetter(codeColIdx);
      devLog(
          '_buildFromOriginal[$sheetName]: codeCol=$codeColLetter qtyCol=$qtyColLetter');

      var patchedCount = 0;
      final result = xml.replaceAllMapped(
        RegExp(r'(<row r="(\d+)"[^>]*>)(.*?)(</row>)', dotAll: true),
        (m) {
          final rowOpen = m.group(1)!;
          final rowIdx = m.group(2)!;
          var rowBody = m.group(3)!;
          final rowClose = m.group(4)!;

          // Код может быть shared string (t="s") или число (бланки из Numbers)
          final codeCellRe = RegExp(
            '<c r="${RegExp.escape(codeColLetter)}$rowIdx"([^>]*)><v>([^<]+)</v></c>',
          );
          final codeM = codeCellRe.firstMatch(rowBody);
          if (codeM == null) return m.group(0)!;
          final attrs = codeM.group(1) ?? '';
          final val = codeM.group(2) ?? '';
          final String codeStr = attrs.contains('t="s"')
              ? ((int.tryParse(val) ?? -1) >= 0 &&
                      (int.tryParse(val) ?? -1) < sharedStrings.length
                  ? sharedStrings[int.parse(val)].trim()
                  : '')
              : val.trim();
          if (codeStr.isEmpty) return m.group(0)!;
          final qty = qtyByCode[codeStr];
          if (qty == null) return m.group(0)!;

          final qtyStr = qty == qty.roundToDouble()
              ? qty.toInt().toString()
              : qty
                  .toStringAsFixed(3)
                  .replaceAll(RegExp(r'0+$'), '')
                  .replaceAll(RegExp(r'\.$'), '');
          final cellRef = '$qtyColLetter$rowIdx';

          final selfM = RegExp('<c r="${RegExp.escape(cellRef)}"([^>]*)/>')
              .firstMatch(rowBody);
          final existM = RegExp(
            '<c r="${RegExp.escape(cellRef)}"([^>]*)>(.*?)</c>',
            dotAll: true,
          ).firstMatch(rowBody);

          if (selfM != null) {
            rowBody = rowBody.replaceFirst(selfM.group(0)!,
                '<c r="$cellRef"${selfM.group(1)!}><v>$qtyStr</v></c>');
          } else if (existM != null) {
            rowBody = rowBody.replaceFirst(existM.group(0)!,
                '<c r="$cellRef"${existM.group(1)!}><v>$qtyStr</v></c>');
          } else {
            final sM =
                RegExp('<c r="[A-Z]+$rowIdx" s="(\\d+)"').firstMatch(rowBody);
            final sAttr = sM != null ? ' s="${sM.group(1)}"' : '';
            rowBody += '<c r="$cellRef"$sAttr><v>$qtyStr</v></c>';
          }
          patchedCount++;
          return '$rowOpen$rowBody$rowClose';
        },
      );
      devLog('_buildFromOriginal[$sheetName]: patched $patchedCount rows');
      return result;
    }

    // Собираем патченные XML
    final patchedXmls = <String, String>{};
    for (final entry in sheetInfos.entries) {
      final sheetEntry = arc.findFile(entry.value.path);
      if (sheetEntry == null) continue;
      final xml = utf8.decode(sheetEntry.content as List<int>);
      patchedXmls[entry.value.path] =
          patchSheetXml(xml, entry.key, entry.value.col);
    }

    // ── 5. Заменяем листы в ZIP без перепаковки остальных файлов ─────────────
    Uint8List result = origBytes;
    for (final entry in patchedXmls.entries) {
      result = _zipReplaceFile(result, entry.key, utf8.encode(entry.value));
    }
    return result;
  }

  /// Заменяет один файл в ZIP-архиве без изменения остальных entries.
  /// Возвращает новые байты ZIP.
  Uint8List _zipReplaceFile(
      Uint8List zipBytes, String targetName, List<int> newContent) {
    // Сжимаем новые данные — raw DEFLATE (без zlib-заголовка и Adler32)
    // ZIP format требует именно raw deflate (метод 8), не zlib-обёртку
    final newCompressed = Deflate(newContent, level: 6).getBytes();
    final newCrc = _crc32(newContent);
    final newUncompSize = newContent.length;
    final newCompSize = newCompressed.length;
    final targetNameBytes = utf8.encode(targetName);

    // Собираем новый ZIP поэнтрийно
    final out = BytesBuilder();

    // Таблица: localHeaderOffset для central directory
    final cdEntries = <_ZipCdEntry>[];

    int pos = 0;
    final bd = ByteData.sublistView(zipBytes);

    int _readU16(int offset) => bd.getUint16(offset, Endian.little);
    int _readU32(int offset) => bd.getUint32(offset, Endian.little);
    void _writeU32(ByteData buf, int offset, int v) =>
        buf.setUint32(offset, v, Endian.little);

    while (pos < zipBytes.length - 4) {
      final sig = _readU32(pos);

      if (sig == 0x04034b50) {
        // Local file header
        final compMethod = _readU16(pos + 8);
        final crc32orig = _readU32(pos + 14);
        final compSizeOrig = _readU32(pos + 18);
        final uncompSizeOrig = _readU32(pos + 22);
        final nameLen = _readU16(pos + 26);
        final extraLen = _readU16(pos + 28);
        final name =
            utf8.decode(zipBytes.sublist(pos + 30, pos + 30 + nameLen));
        final dataOffset = pos + 30 + nameLen + extraLen;

        final isTarget = (name == targetName);
        final effectiveCompSize = isTarget ? newCompSize : compSizeOrig;
        final effectiveUncompSize = isTarget ? newUncompSize : uncompSizeOrig;
        final effectiveCrc = isTarget ? newCrc : crc32orig;
        final effectiveMethod = isTarget ? 8 : compMethod; // 8=deflate

        final localHeaderOffset = out.length;

        // Пишем local header с обновлёнными полями
        final lh = Uint8List(30 + nameLen + extraLen);
        final lhBd = ByteData.sublistView(lh);
        lhBd.setUint32(0, 0x04034b50, Endian.little); // sig
        lhBd.setUint16(4, _readU16(pos + 4), Endian.little); // version needed
        lhBd.setUint16(6, _readU16(pos + 6), Endian.little); // flags
        lhBd.setUint16(8, effectiveMethod, Endian.little); // compression
        lhBd.setUint16(10, _readU16(pos + 10), Endian.little); // mod time
        lhBd.setUint16(12, _readU16(pos + 12), Endian.little); // mod date
        lhBd.setUint32(14, effectiveCrc, Endian.little); // crc
        lhBd.setUint32(18, effectiveCompSize, Endian.little); // comp size
        lhBd.setUint32(22, effectiveUncompSize, Endian.little); // uncomp size
        lhBd.setUint16(26, nameLen, Endian.little);
        lhBd.setUint16(28, extraLen, Endian.little);
        lh.setRange(30, 30 + nameLen, zipBytes, pos + 30);
        if (extraLen > 0) {
          lh.setRange(30 + nameLen, 30 + nameLen + extraLen, zipBytes,
              pos + 30 + nameLen);
        }
        out.add(lh);

        if (isTarget) {
          // Вставляем новые сжатые данные
          out.add(newCompressed);
        } else {
          // Копируем оригинальные сжатые данные
          out.add(zipBytes.sublist(dataOffset, dataOffset + compSizeOrig));
        }

        // Запоминаем для central directory
        cdEntries.add(_ZipCdEntry(
          origOffset: pos,
          newOffset: localHeaderOffset,
          name: name,
          isTarget: isTarget,
          effectiveCrc: effectiveCrc,
          effectiveCompSize: effectiveCompSize,
          effectiveUncompSize: effectiveUncompSize,
          effectiveMethod: effectiveMethod,
        ));

        pos = dataOffset + compSizeOrig;
      } else if (sig == 0x02014b50) {
        // Central directory — перестраиваем
        break;
      } else if (sig == 0x06054b50) {
        // End of central directory
        break;
      } else {
        // Неизвестная сигнатура — прерываемся
        break;
      }
    }

    // Пишем central directory
    final cdStart = out.length;
    for (final entry in cdEntries) {
      final origCdPos = _findCdEntry(zipBytes, entry.name);
      if (origCdPos < 0) continue;
      final nameLen = _readU16(origCdPos + 28);
      final extraLen = _readU16(origCdPos + 30);
      final cmtLen = _readU16(origCdPos + 32);
      final cdEntrySize = 46 + nameLen + extraLen + cmtLen;

      final ce = Uint8List(cdEntrySize);
      ce.setRange(0, cdEntrySize, zipBytes, origCdPos);
      final ceBd = ByteData.sublistView(ce);
      // Обновляем поля
      ceBd.setUint16(10, entry.effectiveMethod, Endian.little);
      ceBd.setUint32(16, entry.effectiveCrc, Endian.little);
      ceBd.setUint32(20, entry.effectiveCompSize, Endian.little);
      ceBd.setUint32(24, entry.effectiveUncompSize, Endian.little);
      ceBd.setUint32(42, entry.newOffset, Endian.little); // local header offset
      out.add(ce);
    }
    final cdEnd = out.length;
    final cdSize = cdEnd - cdStart;

    // End of central directory record
    final eocd = Uint8List(22);
    final eocdBd = ByteData.sublistView(eocd);
    eocdBd.setUint32(0, 0x06054b50, Endian.little); // sig
    eocdBd.setUint16(4, 0, Endian.little); // disk num
    eocdBd.setUint16(6, 0, Endian.little); // disk cd start
    eocdBd.setUint16(8, cdEntries.length, Endian.little);
    eocdBd.setUint16(10, cdEntries.length, Endian.little);
    eocdBd.setUint32(12, cdSize, Endian.little);
    eocdBd.setUint32(16, cdStart, Endian.little);
    eocdBd.setUint16(20, 0, Endian.little); // comment length
    out.add(eocd);

    return out.toBytes();
  }

  /// Находит offset central directory entry для файла с именем [name].
  int _findCdEntry(Uint8List zipBytes, String name) {
    final bd = ByteData.sublistView(zipBytes);
    final nameBytes = utf8.encode(name);
    int pos = 0;
    while (pos < zipBytes.length - 4) {
      final sig = bd.getUint32(pos, Endian.little);
      if (sig == 0x02014b50) {
        final nameLen = bd.getUint16(pos + 28, Endian.little);
        if (nameLen == nameBytes.length) {
          bool match = true;
          for (int i = 0; i < nameLen; i++) {
            if (zipBytes[pos + 46 + i] != nameBytes[i]) {
              match = false;
              break;
            }
          }
          if (match) return pos;
        }
        final extraLen = bd.getUint16(pos + 30, Endian.little);
        final cmtLen = bd.getUint16(pos + 32, Endian.little);
        pos += 46 + nameLen + extraLen + cmtLen;
      } else if (sig == 0x04034b50) {
        final nameLen = bd.getUint16(pos + 26, Endian.little);
        final extraLen = bd.getUint16(pos + 28, Endian.little);
        final compSize = bd.getUint32(pos + 18, Endian.little);
        pos += 30 + nameLen + extraLen + compSize;
      } else {
        pos++;
      }
    }
    return -1;
  }

  /// CRC-32 (стандартный полином 0xEDB88320).
  int _crc32(List<int> data) {
    const poly = 0xEDB88320;
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ poly;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Проверяет, является ли строка заголовком таблицы (шапкой), а не товаром.
  /// Используется для фильтрации строк-заголовков которые могут попасть
  /// в БД при парсинге 2-го и последующих листов Excel.
  static bool _isIikoHeaderRow(String name) {
    final lower = name.trim().toLowerCase();
    const headers = [
      'наименование',
      'код',
      'ед. изм',
      'остаток',
      'бланк',
      'организация',
      'на дату',
      'склад',
      'группа',
      'товар'
    ];
    return headers.any((h) => lower == h || lower.startsWith(h));
  }

  String _cellStr(Sheet sheet, int row, int col) {
    try {
      final v = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;
      if (v == null) return '';
      if (v is TextCellValue) return v.value.text ?? '';
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) return v.value.toString();
      return v.toString();
    } catch (_) {
      return '';
    }
  }

  Uint8List _buildFallback() {
    final excel = Excel.createExcel();
    const sheetName = 'Инвентаризация';
    final sheet = excel[sheetName];

    int row = 7;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .value = TextCellValue('Товар');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
        .value = TextCellValue('Код');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        .value = TextCellValue('Наименование');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
        .value = TextCellValue('Ед. изм.');
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
        .value = TextCellValue('Остаток фактический');
    row++;

    String? lastGroup;
    for (final r in _rows) {
      final groupName = r.product.groupName ?? '';
      if (groupName != lastGroup) {
        lastGroup = groupName;
        if (groupName.isNotEmpty) {
          sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
              .value = TextCellValue(groupName);
          row++;
        }
      }
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(r.product.code ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = TextCellValue(r.product.name);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = TextCellValue(r.product.unit ?? '');
      if (r.total > 0) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = DoubleCellValue(r.total);
      }
      row++;
    }

    excel.setDefaultSheet(sheetName);
    return Uint8List.fromList(excel.save()!);
  }

  Future<void> _downloadBytes(Uint8List bytes, String fileName) async {
    try {
      await saveFileBytes(fileName, bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка скачивания: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountManagerSupabase>();
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final visibleRows = _filteredRows;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko',
                style: const TextStyle(fontSize: 16)),
            Text(
              account.establishment?.name ?? '',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: const [],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Загрузка продуктов...'),
                ],
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    // Вкладки листов (если > 1 листа в бланке)
                    Consumer<IikoProductStore>(
                      builder: (ctx, store, _) {
                        final sheetNames = store.sheetNames;
                        if (sheetNames.length <= 1)
                          return const SizedBox.shrink();
                        final activeSheet = sheetNames.contains(_selectedSheet)
                            ? _selectedSheet!
                            : sheetNames.first;
                        return _SheetTabBar(
                          sheetNames: sheetNames,
                          selected: activeSheet,
                          onSelect: (s) {
                            setState(() {
                              _selectedSheet = s;
                              // Синхронизируем sheetName в _rows из актуального store
                              // (store мог обновить sheetName после первоначальной загрузки _rows)
                              final storeProducts = {
                                for (final p in store.products) p.id: p
                              };
                              for (final row in _rows) {
                                final fresh = storeProducts[row.product.id];
                                if (fresh != null &&
                                    fresh.sheetName != row.product.sheetName) {
                                  row.product = fresh;
                                }
                              }
                            });
                          },
                        );
                      },
                    ),
                    // Поиск — всегда видим
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: TextField(
                        controller: _filterCtrl,
                        focusNode: _searchFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Поиск по наименованию...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    // Статус-строка — скрываем при фокусе (поиск или ячейка)
                    if (!_isKeyboardActive)
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withOpacity(0.5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'iiko · ${_rows.length} поз. · '
                              '${_date.day.toString().padLeft(2, '0')}.'
                              '${_date.month.toString().padLeft(2, '0')}.'
                              '${_date.year}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const Spacer(),
                            // Индикатор защиты данных
                            if (_lastSavedAt != null)
                              Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.green.withOpacity(0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.security,
                                        size: 12, color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Данные защищены',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _date,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null)
                                  setState(() => _date = picked);
                              },
                              child: const Text('Дата',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    // Шапка таблицы
                    _IikoInventoryHeader(
                      qtyCols: _rows.isEmpty
                          ? 2
                          : _rows
                              .map((r) => r.quantities.length)
                              .reduce((a, b) => a > b ? a : b),
                    ),
                    // Список строк — тап/скролл внутри не закрывает клавиатуру (refocus).
                    // Задержка 100ms: поиск refocus быстрее при скролле; ячейка успевает получить фокус.
                    Expanded(
                      child: visibleRows.isEmpty
                          ? const Center(child: Text('Нет позиций'))
                          : Listener(
                              onPointerDown: (_) {
                                final pf = FocusManager.instance.primaryFocus;
                                final isOurInput = pf != null &&
                                    (_iikoCellFocusNodes.contains(pf) ||
                                        pf == _searchFocusNode);
                                if (!isOurInput) return;
                                final nodeToRestore = pf!;
                                Future.delayed(
                                    const Duration(milliseconds: 100), () {
                                  if (!mounted) return;
                                  final current =
                                      FocusManager.instance.primaryFocus;
                                  if (current != null &&
                                      (_iikoCellFocusNodes.contains(current) ||
                                          current == _searchFocusNode)) return;
                                  nodeToRestore.requestFocus();
                                });
                              },
                              child: _IikoInventoryTable(
                                rows: visibleRows,
                                completed: _completed,
                                onQuantityChanged: _setQuantity,
                                onFocusChange: () => setState(() {}),
                              ),
                            ),
                    ),
                    // Кнопки внизу — скрываем при фокусе (поиск или ячейка)
                    if (!_isKeyboardActive)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.save_alt),
                                label: const Text('Сохранить и скачать xlsx'),
                                onPressed: _saveAndExport,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _confirmReset,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(
                                    color: theme.colorScheme.error
                                        .withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                              ),
                              child: const Text('Обнулить',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

// Ширина фиксированных колонок (единицы и итого уже для названий)
const double _iikoColName = 168; // Наименование (больше под длинные названия)
const double _iikoColUnit = 34; // Ед. изм. (−30%)
const double _iikoColTotal = 52; // Итого (чтобы слово влезало целиком)
const double _iikoColCell = 48; // Ячейка ввода (= _colQtyWidth)
const double _iikoColGap = 4; // Отступ между ячейками (= _colGap)

// ── Шапка таблицы ────────────────────────────────────────────────────────────
// Левая часть фиксирована (Наименование + Итого), правая скроллируется вместе со строками.
class _IikoInventoryHeader extends StatelessWidget {
  const _IikoInventoryHeader({required this.qtyCols});

  final int qtyCols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerBg = theme.colorScheme.surfaceContainerHighest.withOpacity(0.5);
    final borderClr = theme.dividerColor;
    final textStyle = theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface) ??
        const TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
    final border = BorderSide(color: borderClr);

    Widget hCell(String t, double w) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: headerBg,
            border: Border(right: border, bottom: border),
          ),
          child: Text(t, style: textStyle, textAlign: TextAlign.center),
        );

    return Container(
      decoration: BoxDecoration(
        border: Border(left: border, top: border),
        color: headerBg,
      ),
      child: Row(
        children: [
          hCell('Наименование', _iikoColName),
          hCell('Ед.', _iikoColUnit),
          hCell('Итого', _iikoColTotal),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: List.generate(
                  qtyCols,
                  (i) => hCell('№${i + 1}', _iikoColCell),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Таблица ──────────────────────────────────────────────────────────────────
class _IikoInventoryTable extends StatelessWidget {
  const _IikoInventoryTable({
    required this.rows,
    required this.completed,
    required this.onQuantityChanged,
    this.onFocusChange,
  });

  final List<_IikoInventoryRow> rows;
  final bool completed;
  final void Function(_IikoInventoryRow row, int colIndex, double qty)
      onQuantityChanged;
  final VoidCallback? onFocusChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String? lastGroup;
    final items = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final groupName = row.product.groupName ?? '';
      final groupDisplay = row.product.displayGroupName ?? '';
      if (groupName != lastGroup) {
        lastGroup = groupName;
        if (groupDisplay.isNotEmpty) {
          items.add(Container(
            width: double.infinity,
            color: theme.colorScheme.primaryContainer.withOpacity(0.25),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              groupDisplay,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary),
            ),
          ));
        }
      }
      items.add(_IikoInventoryRowTile(
        key: ValueKey(row.product.id),
        row: row,
        completed: completed,
        onChanged: (colIdx, qty) => onQuantityChanged(row, colIdx, qty),
        onFocusChange: onFocusChange,
      ));
    }
    // ListView (не builder) — все строки сразу в DOM,
    // Safari видит полную цепочку <input> и активирует кнопки ▲▼ в панели.
    // keyboardDismissBehavior.manual — на мобильном при прокрутке клавиатура не скрывается.
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      children: items,
    );
  }
}

// ── Строка с 2 ячейками и итого ──────────────────────────────────────────────
// ── Переключатель вкладок листов Excel ────────────────────────────────────────
class _SheetTabBar extends StatelessWidget {
  const _SheetTabBar({
    required this.sheetNames,
    required this.selected,
    required this.onSelect,
  });

  final List<String> sheetNames;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: sheetNames.map((name) {
            final isActive = name == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onSelect(name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Кнопка навигации ▲▼ ─────────────────────────────────────────────────────
// Критично для Safari iOS: кнопка не должна снимать фокус с TextField.
// Решение: mousedown.preventDefault() — стандартный браузерный способ сказать
// «не передавай фокус этому элементу». В Flutter Web это делается через
// dart:html addEventListener на платформенный элемент кнопки.
// Дополнительно GestureDetector.onTapDown (синхронный) запускает навигацию.

class _IikoInventoryRowTile extends StatefulWidget {
  const _IikoInventoryRowTile({
    super.key,
    required this.row,
    required this.completed,
    required this.onChanged,
    this.onFocusChange,
  });

  final _IikoInventoryRow row;
  final bool completed;
  final void Function(int colIndex, double qty) onChanged;
  final VoidCallback? onFocusChange;

  @override
  State<_IikoInventoryRowTile> createState() => _IikoInventoryRowTileState();
}

class _IikoInventoryRowTileState extends State<_IikoInventoryRowTile> {
  final List<TextEditingController> _ctrls = [];
  final List<FocusNode> _focusNodes = [];
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _syncControllers();
    _registerFocusNodes();
  }

  void _syncControllers() {
    // Создаём/обновляем контроллеры по числу ячеек
    while (_ctrls.length < widget.row.quantities.length) {
      final idx = _ctrls.length;
      final val = widget.row.quantities[idx];
      _ctrls.add(TextEditingController(text: val > 0 ? _fmt(val) : ''));
    }
  }

  void _syncFocusNodes() {
    while (_focusNodes.length < widget.row.quantities.length) {
      _focusNodes.add(FocusNode());
    }
  }

  void _notifyFocusChange() {
    if (mounted) widget.onFocusChange?.call();
  }

  void _registerFocusNodes() {
    _syncFocusNodes();
    _iikoCellFocusNodes.addAll(_focusNodes);
    for (final fn in _focusNodes) {
      fn.addListener(_notifyFocusChange);
    }
  }

  void _unregisterFocusNodes() {
    for (final fn in _focusNodes) {
      fn.removeListener(_notifyFocusChange);
    }
    for (final fn in _focusNodes) {
      _iikoCellFocusNodes.remove(fn);
    }
  }

  @override
  void didUpdateWidget(_IikoInventoryRowTile old) {
    super.didUpdateWidget(old);
    final qtys = widget.row.quantities;

    // Если добавилась новая ячейка — создаём контроллер, FocusNode и прокручиваем вправо
    final hadNewCell = _ctrls.length < qtys.length;
    while (_ctrls.length < qtys.length) {
      final idx = _ctrls.length;
      final val = qtys[idx];
      _ctrls.add(TextEditingController(text: val > 0 ? _fmt(val) : ''));
    }
    while (_focusNodes.length < qtys.length) {
      final fn = FocusNode();
      fn.addListener(_notifyFocusChange);
      _focusNodes.add(fn);
      _iikoCellFocusNodes.add(fn);
    }
    if (hadNewCell) _scrollToEnd();

    // Если количества были сброшены (обнуление) — обновляем текст контроллеров.
    // Сравниваем только если число ячеек не изменилось (иначе это добавление новой).
    if (old.row.quantities.length == qtys.length) {
      for (var i = 0; i < _ctrls.length && i < qtys.length; i++) {
        final expected = qtys[i] > 0 ? _fmt(qtys[i]) : '';
        // Обновляем только если значение реально изменилось и поле не в фокусе
        if (_ctrls[i].text != expected && !_ctrls[i].selection.isValid) {
          _ctrls[i].text = expected;
        }
      }
    }
  }

  @override
  void dispose() {
    _unregisterFocusNodes();
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final fn in _focusNodes) {
      fn.dispose();
    }
    _hScroll.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v
          .toStringAsFixed(3)
          .replaceAll(RegExp(r'0+$'), '')
          .replaceAll(RegExp(r'\.$'), '');

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hScroll.hasClients) {
        _hScroll.animateTo(
          _hScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.row.product.unit ?? '';
    final total = widget.row.total;
    final qtyCols = widget.row.quantities.length;

    final theme = Theme.of(context);
    final borderClr = theme.dividerColor;
    final cb = BorderSide(color: borderClr);

    // Ячейка ввода количества (48px, gap 4; растягивается по высоте строки)
    Widget numCell(int colIdx) {
      final ctrl = _ctrls[colIdx];
      final fn = colIdx < _focusNodes.length ? _focusNodes[colIdx] : null;
      return Padding(
        padding: EdgeInsets.only(right: colIdx < qtyCols - 1 ? _iikoColGap : 0),
        child: SizedBox(
          width: _iikoColCell,
          child: Center(
            child: TextField(
              controller: ctrl,
              focusNode: fn,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
                hintText: '—',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.3)),
              ),
              onChanged: (v) {
                final qty = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                widget.onChanged(colIdx, qty);
              },
              onSubmitted: (v) {
                final qty = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
                widget.onChanged(colIdx, qty);
              },
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(left: cb, bottom: cb),
      ),
      constraints:
          const BoxConstraints(minHeight: 44), // растёт при длинном названии
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // все колонки одной высоты
          children: [
            // ── Наименование ──
            Container(
              width: _iikoColName,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(border: Border(right: cb)),
              alignment: Alignment.centerLeft,
              child: Text(
                widget.row.product.displayName,
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── Ед. изм. ──
            Container(
              width: _iikoColUnit,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                border: Border(right: cb),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                unit,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── Итого ──
            Container(
              width: _iikoColTotal,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                border: Border(right: cb),
              ),
              child: Text(
                total > 0 ? _fmt(total) : '',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: total > 0 ? theme.colorScheme.primary : null),
              ),
            ),
            // ── Ячейки ввода — скроллируются вправо ──
            Expanded(
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(qtyCols, numCell),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Запись для перестройки central directory при ZIP-патче.
class _ZipCdEntry {
  final int origOffset;
  final int newOffset;
  final String name;
  final bool isTarget;
  final int effectiveCrc;
  final int effectiveCompSize;
  final int effectiveUncompSize;
  final int effectiveMethod;

  _ZipCdEntry({
    required this.origOffset,
    required this.newOffset,
    required this.name,
    required this.isTarget,
    required this.effectiveCrc,
    required this.effectiveCompSize,
    required this.effectiveUncompSize,
    required this.effectiveMethod,
  });
}
