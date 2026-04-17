import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import '../utils/dev_log.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/iiko_product.dart';
import '../utils/number_format_utils.dart';
import '../utils/product_name_utils.dart';
import '../utils/nomenclature_duplicate_groups.dart';
import '../utils/establishment_currency_options.dart';
import '../services/iiko_product_store.dart';
import '../services/iiko_xlsx_sanitizer.dart';

import '../models/culinary_units.dart';
import '../models/product.dart';
import '../models/employee.dart';
import '../models/establishment.dart';
import '../models/cooking_process.dart';
import '../models/tt_ingredient.dart';
import '../models/tech_card.dart';
import '../models/menu_item.dart';
import '../models/checklist.dart';
import '../models/schedule_model.dart';
import '../models/order_list.dart';
import '../models/nomenclature_item.dart';
import '../models/translation.dart';
import '../services/account_manager.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/long_operation_progress_dialog.dart';
import '../widgets/establishment_currency_picker_dialog.dart';
import '../services/account_manager_supabase.dart';
import '../services/product_store.dart';
import '../services/product_store_supabase.dart';
import '../services/localization_service.dart';
import '../services/image_service.dart';
import '../services/tech_card_service.dart';
import '../services/tech_card_service_supabase.dart';
import '../services/inventory_document_service.dart';
import '../services/checklist_service_supabase.dart';
import '../services/nutrition_api_service.dart';
import '../services/supabase_service.dart';
import '../services/secure_storage_service.dart';
import '../services/theme_service.dart';
import '../services/translation_service.dart';
import '../services/translation_manager.dart';
import '../services/ai_service.dart';
import '../services/ai_service_supabase.dart';
import '../services/order_list_storage_service.dart';
import '../services/excel_export_service.dart';
import '../services/domain_validation_service.dart';
import '../services/translation_service.dart';
import '../services/inventory_download.dart';
import '../services/trial_device_save_kinds.dart';
import '../services/unit_system_preference_service.dart';
import '../utils/unit_converter.dart';

/// Экран номенклатуры: продукты и ПФ заведения с ценами
class NomenclatureScreen extends StatefulWidget {
  const NomenclatureScreen({super.key, this.department = 'general'});

  final String department;

  @override
  State<NomenclatureScreen> createState() => _NomenclatureScreenState();
}

enum _CatalogSort { nameAz, nameZa, priceAsc, priceDesc }

enum _NomenclatureFilter { all, products }

/// Единица измерения для отображения в номенклатуре: кг, шт, г, л и т.д. (не сырой "pcs"/"kg" из БД).
String _unitDisplay(
  String? unit,
  String lang, {
  required UnitSystem unitSystem,
}) {
  return UnitConverter.displayUnitLabel(unit, lang, unitSystem);
}

/// Диалог с прогрессом загрузки продуктов
class _UploadProgressDialog extends StatefulWidget {
  const _UploadProgressDialog({
    required this.items,
    required this.loc,
  });

  final List<({String name, double? price})> items;
  final LocalizationService loc;

  @override
  State<_UploadProgressDialog> createState() => _UploadProgressDialogState();
}

class _UploadProgressDialogState extends State<_UploadProgressDialog> {
  var _processed = 0;
  var _added = 0;
  var _skipped = 0; // Продукты, которые уже существуют
  var _failed = 0;
  var _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _startUpload();
  }

  Future<void> _startUpload() async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final translationService = TranslationService(
      aiService: context.read<AiServiceSupabase>(),
      supabase: context.read<SupabaseService>(),
    );
    final est = account.establishment;
    final estId =
        est != null && est.isBranch ? est.id : est?.dataEstablishmentId;

    if (estId == null) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.loc.t('no_establishment'))),
        );
      }
      return;
    }

    final defCur = account.establishment?.defaultCurrency ?? 'VND';
    final sourceLang = widget.loc.currentLanguageCode;
    final allLangs = LocalizationService.productLanguageCodes;

    for (final item in widget.items) {
      if (!mounted) return;

      setState(() => _processed++);

      try {
        // Используем ИИ для проверки и улучшения данных продукта
        ProductVerificationResult? verification;
        try {
          final aiService = context.read<AiServiceSupabase>();
          verification = await aiService.verifyProduct(
            item.name,
            currentPrice: item.price,
          );
        } catch (aiError) {
          // Если AI не работает, продолжаем без него
          devLog('AI verification failed for "${item.name}": $aiError');
          verification = null;
        }

        // Название не меняем — только как вставил пользователь. ИИ — КБЖУ и пр.
        final storedName = item.name.trim();
        var names = <String, String>{
          for (final c in allLangs) c: storedName
        };

        if (widget.items.length > 5) {
          for (final lang in allLangs) {
            if (lang == sourceLang) continue;
            final translated = await translationService.translate(
              entityType: TranslationEntityType.product,
              entityId: item.name,
              fieldName: 'name',
              text: storedName,
              from: sourceLang,
              to: lang,
            );
            if (translated != null && translated.trim().isNotEmpty) {
              names[lang] = translated.trim();
            }
          }
        }

        final normalizedLower = storedName.toLowerCase();

        // Проверяем, существует ли продукт с таким именем в базе (дедупликация)
        final existingInStore = store.allProducts
            .where(
              (p) => p.name.trim().toLowerCase() == normalizedLower,
            )
            .toList();

        if (existingInStore.isNotEmpty) {
          // Продукт уже есть — просто добавляем в номенклатуру
          final existingId = existingInStore.first.id;
          try {
            final ep = store.getEstablishmentPrice(existingId, estId);
            await store.addToNomenclature(estId, existingId,
                price: item.price ?? ep?.$1, currency: defCur);
          } catch (_) {}
          setState(() => _skipped++);
          continue;
        }

        // Подтягиваем КБЖУ: AI дал — используем, иначе fallback на Open Food Facts
        double? calories = verification?.suggestedCalories;
        double? protein;
        double? fat;
        double? carbs;
        bool? containsGluten;
        bool? containsLactose;
        final hasFullKbjuFromAi = (calories != null && calories > 0);
        if (!hasFullKbjuFromAi) {
          try {
            final nutrition =
                await NutritionApiService.fetchNutrition(storedName);
            if (nutrition != null && nutrition.hasData) {
              calories = calories ?? nutrition.calories;
              protein = nutrition.protein;
              fat = nutrition.fat;
              carbs = nutrition.carbs;
              containsGluten = nutrition.containsGluten;
              containsLactose = nutrition.containsLactose;
            }
          } catch (_) {}
        }

        final product = Product(
          id: const Uuid().v4(),
          name: storedName,
          category: verification?.suggestedCategory ?? 'manual',
          names: names,
          calories: calories,
          protein: protein,
          fat: fat,
          carbs: carbs,
          containsGluten: containsGluten,
          containsLactose: containsLactose,
          unit: verification?.suggestedUnit ?? 'g',
          basePrice: null,
          currency: defCur,
        );

        Product savedProduct;
        try {
          savedProduct = await store.addProduct(product);
        } catch (e) {
          if (e.toString().contains('duplicate key') ||
              e.toString().contains('already exists') ||
              e.toString().contains('unique constraint')) {
            // Продукт уже существует в БД, ищем по имени
            try {
              final supabaseClient = Supabase.instance.client;
              final existingProducts = await supabaseClient
                  .from('products')
                  .select('id')
                  .eq('name', product.name)
                  .limit(1);

              if (existingProducts.isNotEmpty) {
                final existingId = existingProducts[0]['id'] as String;
                await store.addToNomenclature(estId, existingId,
                    price: item.price);
                setState(() => _skipped++);
                continue;
              }
            } catch (findError) {
              devLog(
                  'Failed to find existing product "${product.name}": $findError');
            }
          }
          // Другая ошибка
          devLog('Failed to add product "${product.name}": $e');
          setState(() => _failed++);
          continue;
        }

        try {
          await store.addToNomenclature(estId, savedProduct.id,
              price: item.price ?? verification?.suggestedPrice,
              currency: defCur);
        } catch (e) {
          // Возможно продукт уже в номенклатуре - считаем это успехом
          if (e.toString().contains('duplicate key') ||
              e.toString().contains('already exists') ||
              e.toString().contains('unique constraint')) {
            setState(() => _skipped++);
            continue;
          }
          // Другая ошибка
          devLog('Failed to add to nomenclature "${product.name}": $e');
          setState(() => _failed++);
          continue;
        }

        setState(() => _added++);

        // Небольшая задержка чтобы не перегружать сервер
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        devLog('Unexpected error for "${item.name}": $e');
        setState(() => _failed++);
      }
    }

    setState(() => _isCompleted = true);

    // Автоматически закрываем диалог через 2 секунды
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pop();

      final msg = _failed == 0
          ? widget.loc
              .t('upload_added')
              .replaceAll('%s', '${_added + _skipped}')
          : '${widget.loc.t('upload_added').replaceAll('%s', '${_added + _skipped}')}. ${widget.loc.t('upload_failed').replaceAll('%s', '$_failed')}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.items.isEmpty ? 1.0 : _processed / widget.items.length;

    final loc = widget.loc;
    return AlertDialog(
      title: Text(loc.t('upload_products_processing')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(loc
              .t('upload_products_progress')
              .replaceFirst('%s', '$_processed')
              .replaceFirst('%s', '${widget.items.length}')),
          const SizedBox(height: 8),
          Text(loc.t('upload_products_checking'),
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            loc.t('upload_products_added').replaceFirst('%s', '$_added') +
                (_skipped > 0
                    ? loc
                        .t('upload_products_skipped')
                        .replaceFirst('%s', '$_skipped')
                    : '') +
                (_failed > 0
                    ? loc
                        .t('upload_products_failed')
                        .replaceFirst('%s', '$_failed')
                    : ''),
          ),
          if (_isCompleted) ...[
            const SizedBox(height: 16),
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            Text(loc.t('upload_products_done')),
          ],
        ],
      ),
      actions: _isCompleted
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(loc.t('close')),
              ),
            ]
          : null,
    );
  }
}

// Вкладки номенклатуры
enum _NomTab { nomenclature, newProducts, iiko }

class _NomenclatureScreenState extends State<NomenclatureScreen> {
  String _query = '';
  String? _category;
  // Фильтры номенклатуры
  _CatalogSort _nomSort = _CatalogSort.nameAz;
  _NomenclatureFilter _nomFilter = _NomenclatureFilter.all;
  bool _filterNoPrice = false;

  // Список элементов номенклатуры (продукты + ТТК ПФ)
  List<NomenclatureItem> _nomenclatureItems = [];
  bool _isLoading = true;
  Object? _loadError;
  bool _hasRunAutoTranslationThisSession = false;

  // Активная вкладка
  _NomTab _selectedTab = _NomTab.nomenclature;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<UnitSystemPreferenceService>().ensureScopeSynced();
      if (!mounted) return;
      await _ensureLoaded();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _ensureLoaded({bool skipAutoTranslation = false}) async {
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    // Филиал: объединённая номенклатура головного + филиала, цены филиала; идентификатор для операций — id филиала.
    final estId = est.isBranch ? est.id : est.dataEstablishmentId;
    if (estId == null) return;

    final techCardService = context.read<TechCardServiceSupabase>();

    if (mounted) setState(() => _loadError = null);

    try {
      await store.loadProducts(force: !store.hasFullProductCatalog);
      if (est.isBranch) {
        await store.loadNomenclatureForBranch(est.id, est.dataEstablishmentId!);
      } else {
        await store.loadNomenclature(estId);
      }

      // Загружаем элементы номенклатуры (продукты + ТТК ПФ)
      var items = await store.getAllNomenclatureItems(
        estId,
        techCardService,
        screenDepartment: widget.department,
      );
      // kitchen: отдел из БД уже учтён в ProductStore; bar/зал — по категории как раньше.
      if (widget.department == 'kitchen') {
        _nomenclatureItems = items;
      } else {
        _nomenclatureItems = _filterByDepartment(items, widget.department);
      }
    } catch (e) {
      devLog('❌ NomenclatureScreen: _ensureLoaded error: $e');
      if (mounted) {
        setState(() => _loadError = e);
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t(
                'nomenclature_load_error',
                args: {'error': '$e'},
              )),
              duration: const Duration(seconds: 6)),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      // Автоперевод только один раз за сессию или не сразу после неудачного прогона
      if (!skipAutoTranslation && !_hasRunAutoTranslationThisSession) {
        final loc = context.read<LocalizationService>();
        if (loc.currentLanguageCode != 'ru') {
          final needTranslate = _nomenclatureItems
              .where((i) => i.isProduct && _needsTranslation(i))
              .map((i) => i.product!)
              .toList();
          if (needTranslate.isNotEmpty) {
            _hasRunAutoTranslationThisSession = true;
            _runAutoTranslation(needTranslate);
          }
        }
      }
    }
  }

  /// Фоновый перевод продуктов (Edge Function DeepL). Fire-and-forget — без UI.
  void _runAutoTranslation(List<Product> list) {
    final store = context.read<ProductStoreSupabase>();
    for (final p in list) {
      if ((p.name).trim().isEmpty) continue;
      store.triggerTranslation(p.id);
    }
  }

  /// Категории продуктов/ПФ для подразделений. general = без фильтра (все).
  static const _barCategories = {
    'beverages',
    'alcoholic_cocktails',
    'non_alcoholic_drinks',
    'hot_drinks',
    'drinks_pure',
    'snacks'
  };

  List<NomenclatureItem> _filterByDepartment(
      List<NomenclatureItem> items, String department) {
    if (department == 'general') return items;
    if (department == 'hall' || department == 'dining_room')
      return items; // Зал видит всё
    if (department == 'bar') {
      return items.where((i) => _barCategories.contains(i.category)).toList();
    }
    // kitchen, banquet-catering и остальные — кухонные категории (всё кроме бара)
    return items.where((i) => !_barCategories.contains(i.category)).toList();
  }

  bool _iikoUploading = false;

  Future<void> _uploadIikoBlank() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) return;

    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final estId = acc.establishment?.id;
    if (estId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('establishment_not_found'))),
      );
      return;
    }

    if (mounted) setState(() => _iikoUploading = true);

    try {
      var bytes = result.files.single.bytes!;
      bytes = IikoXlsxSanitizer.ensureDecodable(bytes);

      // Первичный парсинг — проверяем нашёл ли авто все столбцы остатка
      final firstPass = _parseIikoBlank(bytes, estId);
      if (firstPass.products.isEmpty) {
        if (mounted) {
          setState(() => _iikoUploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.t('nomenclature_iiko_blank_unrecognized')),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      // Проверяем: для каких листов столбец остатка не был найден автоматически
      final excel = Excel.decodeBytes(bytes.toList());
      final sheetsNeedingManual = <String>[];
      for (final sheetName in firstPass.sheetNames) {
        final sheet = excel.tables[sheetName];
        if (sheet == null) continue;
        final detected = _detectColumns(sheet);
        if (detected.colQty == null) sheetsNeedingManual.add(sheetName);
      }

      // Если есть листы без авто-определения столбца — показываем диалог
      Map<String, int>? manualCols;
      if (sheetsNeedingManual.isNotEmpty) {
        if (mounted) setState(() => _iikoUploading = false);
        manualCols = await _showQtyColumnDialog(bytes, sheetsNeedingManual);
        if (manualCols == null) return; // пользователь отменил
        if (mounted) setState(() => _iikoUploading = true);
      }

      // Финальный парсинг с ручными столбцами (если были)
      final parsed = manualCols != null
          ? _parseIikoBlank(bytes, estId, manualQtyCols: manualCols)
          : firstPass;

      final iikoStore = context.read<IikoProductStore>();
      await iikoStore.replaceAll(
        estId,
        parsed.products,
        blankBytes: bytes,
        quantityColumnIndex: parsed.quantityCol,
        newSheetNames: parsed.sheetNames,
        newSheetQtyColumns: parsed.sheetQtyColumns,
      );

      if (mounted) {
        setState(() => _iikoUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.t(
                'nomenclature_iiko_loaded_count',
                args: {'count': '${parsed.products.length}'},
              ),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _iikoUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('product_upload_error_generic',
                args: {'error': '$e'})),
          ),
        );
      }
    }
  }

  static const _emptyParsed = (
    products: <IikoProduct>[],
    quantityCol: null as int?,
    dataStartRow: 0,
    sheetNames: <String>[],
    sheetQtyColumns: <String, int>{},
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Автоопределение столбцов: возвращает индекс по ключевым словам в строках
  // заголовка. Просматриваем первые [scanRows] строк листа.
  // ──────────────────────────────────────────────────────────────────────────
  static ({
    int colGroup,
    int colCode,
    int colName,
    int colUnit,
    int? colQty, // null = не найдено, нужен диалог
    int dataStart,
  }) _detectColumns(Sheet sheet, {int scanRows = 25}) {
    String cellStr(int col, int row) {
      final v = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;
      return _iikoExcelCellToStr(v).trim();
    }

    // Defaults (формат стандартного бланка iiko):
    // A=группа, C=код, D=наименование, E=ед.изм., F=остаток
    int colGroup = 0;
    int colCode = 2;
    int colName = 3;
    int colUnit = 4;
    int? colQty; // будет null если не найдено по заголовкам
    int dataStart = 8;

    final maxCols = sheet.maxColumns.clamp(0, 20);

    // Сканируем все строки заголовка — ищем строку с максимальным числом
    // совпадений ключевых слов (это надёжнее чем искать только "наименование")
    int bestScore = 0;
    int bestRow = -1;

    for (var r = 0; r < sheet.maxRows && r < scanRows; r++) {
      int score = 0;
      for (var c = 0; c < maxCols; c++) {
        final v = cellStr(c, r).toLowerCase();
        if (v.isEmpty) continue;
        if (v.contains('наименование') || v.contains('товар') || v == 'name')
          score += 3;
        if ((v.contains('код') &&
                !v.contains('штрих') &&
                !v.contains('баркод')) ||
            v == 'code' ||
            v == 'артикул' ||
            v.contains('external id') ||
            v == 'ext id' ||
            v == 'external_id') score += 2;
        if (v.contains('остаток') ||
            v.contains('фактич') ||
            v.contains('факт') ||
            v.contains('количеств') ||
            v.contains('кол-во') ||
            v.contains('кол.') ||
            v == 'qty' ||
            v == 'fact') score += 2;
        if ((v.contains('ед') && v.length < 12) ||
            v.contains('мера') ||
            v.contains('unit') ||
            v.startsWith('mea')) score += 1;
        if (v.contains('групп') || v == 'group') score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        bestRow = r;
      }
    }

    if (bestRow >= 0 && bestScore >= 3) {
      // Нашли строку заголовков — парсим конкретные столбцы
      // Сканируем bestRow и bestRow-1 (заголовки бывают в 2 строки)
      for (final scanRow in {bestRow, if (bestRow > 0) bestRow - 1}) {
        for (var c = 0; c < maxCols; c++) {
          final v = cellStr(c, scanRow).toLowerCase();
          if (v.isEmpty) continue;
          if ((v.contains('наименование') ||
                  v.contains('товар') ||
                  v == 'name') &&
              c != colGroup) colName = c;
          if ((v.contains('код') &&
                  !v.contains('штрих') &&
                  !v.contains('баркод')) ||
              v == 'code' ||
              v == 'артикул' ||
              v.contains('external id') ||
              v == 'ext id' ||
              v == 'external_id') colCode = c;
          if ((v.contains('ед') && v.length < 12) ||
              v.contains('мера') ||
              v.contains('unit') ||
              v.startsWith('mea')) colUnit = c;
          if (v.contains('остаток') ||
              v.contains('фактич') ||
              v.contains('факт') ||
              v.contains('количеств') ||
              v.contains('кол-во') ||
              v.contains('кол.') ||
              v == 'qty' ||
              v == 'fact') colQty = c;
          if (v.contains('групп') || v == 'group') colGroup = c;
        }
      }
      dataStart = bestRow + 1;
    }

    // Защита от коллизий столбцов
    // colName не должен совпадать с colGroup
    if (colName == colGroup) {
      colName = colCode + 1 == colGroup ? colCode + 2 : colCode + 1;
    }
    // colCode не должен совпадать с colName или colGroup
    if (colCode == colName) colCode = colName > 0 ? colName - 1 : colName + 1;
    // colUnit не должен совпадать с ключевыми столбцами
    if (colUnit == colCode || colUnit == colName || colUnit == colGroup) {
      colUnit =
          [colCode, colName, colGroup].reduce((a, b) => a > b ? a : b) + 1;
    }

    return (
      colGroup: colGroup,
      colCode: colCode,
      colName: colName,
      colUnit: colUnit,
      colQty: colQty,
      dataStart: dataStart,
    );
  }

  ({
    List<IikoProduct> products,
    int? quantityCol,
    int dataStartRow,
    List<String> sheetNames,
    Map<String, int> sheetQtyColumns,
  }) _parseIikoBlank(Uint8List bytes, String establishmentId,
      {Map<String, int>? manualQtyCols}) {
    try {
      final excel = Excel.decodeBytes(bytes.toList());
      if (excel.tables.isEmpty) return _emptyParsed;

      final allProducts = <IikoProduct>[];
      final parsedSheetNames = <String>[];
      final parsedSheetQtyCols = <String, int>{};
      int? firstQtyCol;
      int globalSortOrder = 0;

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName];
        if (sheet == null) continue;

        String cellStr(int col, int row) {
          final v = sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
              .value;
          return _iikoExcelCellToStr(v).trim();
        }

        final detected = _detectColumns(sheet);
        final colGroup = detected.colGroup;
        final colCode = detected.colCode;
        final colName = detected.colName;
        final colUnit = detected.colUnit;
        final dataStart = detected.dataStart;

        // Столбец остатка: сначала ручной (из диалога), потом авто, потом default=5
        final colQty = manualQtyCols?[sheetName] ?? detected.colQty ?? 5;

        final sheetProducts = <IikoProduct>[];
        String? currentGroupRaw;

        // Проверяем совпадает ли colGroup с colName (бывает при нестандартных бланках)
        // В этом случае группу определяем по строкам без кода (iiko-стиль)
        final groupIsInNameCol = colGroup == colName;

        for (var r = dataStart; r < sheet.maxRows; r++) {
          final codeVal = cellStr(colCode, r);
          final nameVal = cellStr(colName, r);
          final unitVal = cellStr(colUnit, r);
          // Группу читаем из отдельного столбца только если он не совпадает с именем
          final groupVal = groupIsInNameCol ? '' : cellStr(colGroup, r);

          // Строка является товаром если есть код
          if (codeVal.isNotEmpty) {
            // Иногда группа пишется в том же столбце что код — пропускаем такие строки
            // (признак: нет имени и нет единицы)
            if (nameVal.isEmpty && unitVal.isEmpty) {
              if (groupVal.isNotEmpty) currentGroupRaw = groupVal;
              continue;
            }
            if (nameVal.isEmpty) continue;
            // Пропускаем строки-заголовки (шапку), которые могут встречаться
            // на 2-м и последующих листах (напр. «Наименование», «Код» и т.д.)
            if (_isIikoHeaderRow(nameVal)) continue;
            if (groupVal.isNotEmpty) currentGroupRaw = groupVal;
            sheetProducts.add(IikoProduct(
              id: const Uuid().v4(),
              establishmentId: establishmentId,
              code: codeVal,
              name: nameVal,
              unit: unitVal.isNotEmpty ? unitVal : null,
              groupName: currentGroupRaw,
              sortOrder: globalSortOrder++,
              sheetName: sheetName,
            ));
            continue;
          }

          // Строка без кода — потенциальная строка группы
          if (nameVal.isNotEmpty && unitVal.isEmpty) {
            // В iiko-бланках строка группы: есть название, нет кода, нет единицы
            currentGroupRaw = nameVal;
          } else if (groupVal.isNotEmpty) {
            currentGroupRaw = groupVal;
          }
        }

        if (sheetProducts.isNotEmpty) {
          parsedSheetNames.add(sheetName);
          parsedSheetQtyCols[sheetName] = colQty;
          firstQtyCol ??= colQty;
          allProducts.addAll(sheetProducts);
        }
      }

      return (
        products: allProducts,
        quantityCol: firstQtyCol,
        dataStartRow: 0,
        sheetNames: parsedSheetNames,
        sheetQtyColumns: parsedSheetQtyCols,
      );
    } catch (e) {
      return _emptyParsed;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Диалог выбора столбца остатка — показывается когда авто не нашло столбец.
  // Отображает первые строки каждого листа с кнопками-столбцами.
  // Возвращает null если пользователь отменил.
  // ──────────────────────────────────────────────────────────────────────────
  Future<Map<String, int>?> _showQtyColumnDialog(
      Uint8List bytes, List<String> sheetNames) async {
    if (!mounted) return null;
    final excel = Excel.decodeBytes(bytes.toList());

    String cellStr(Sheet sheet, int col, int row) {
      final v = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value;
      return _iikoExcelCellToStr(v).trim();
    }

    // Для каждого листа пользователь выбирает столбец
    final result = <String, int>{};

    for (final sheetName in sheetNames) {
      final sheet = excel.tables[sheetName];
      if (sheet == null) continue;

      final detected = _detectColumns(sheet);
      if (detected.colQty != null) {
        // Авто нашло — не спрашиваем
        result[sheetName] = detected.colQty!;
        continue;
      }

      // Собираем превью: строки вокруг заголовка (до 3 строк заголовка + 3 данных)
      final maxCols = sheet.maxColumns.clamp(0, 12);
      final previewRows = <List<String>>[];
      final startPreview = (detected.dataStart - 2).clamp(0, sheet.maxRows - 1);
      for (var r = startPreview;
          r < sheet.maxRows && r < startPreview + 6;
          r++) {
        final row = <String>[];
        for (var c = 0; c < maxCols; c++) {
          row.add(cellStr(sheet, c, r));
        }
        previewRows.add(row);
      }

      // Получаем заголовки столбцов из строки заголовка
      final headerRow = detected.dataStart > 0
          ? List.generate(
              maxCols, (c) => cellStr(sheet, c, detected.dataStart - 1))
          : List.generate(maxCols, (c) => String.fromCharCode(65 + c));

      final selectedCol = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _QtyColumnPickerDialog(
          sheetName: sheetName,
          headerRow: headerRow,
          previewRows: previewRows,
          maxCols: maxCols,
        ),
      );

      if (selectedCol == null) return null; // пользователь отменил
      result[sheetName] = selectedCol;
    }

    return result;
  }

  static String _iikoExcelCellToStr(CellValue? v) {
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString().trim();
    if (v is DoubleCellValue) {
      // Целые числа (коды товаров) храним без .0
      final d = v.value;
      if (d == d.truncateToDouble()) return d.toInt().toString();
      return d.toString();
    }
    if (v is FormulaCellValue) {
      // Формула — берём вычисленное значение если есть
      return v.toString().replaceAll(RegExp(r'^Formula:\s*'), '').trim();
    }
    // Любой другой тип — в строку, убираем лишнее
    final s = v.toString().trim();
    // Убираем префикс типа который добавляет пакет excel ("TextCellValue: X")
    final colonIdx = s.indexOf(': ');
    if (colonIdx > 0 && colonIdx < 25) return s.substring(colonIdx + 2).trim();
    return s;
  }

  static bool _isIikoHeaderRow(String name) {
    final lower = name.toLowerCase();
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
    return headers.any((h) => lower.contains(h));
  }

  Future<void> _showDuplicates() async {
    final loc = context.read<LocalizationService>();
    final productItems = _nomenclatureItems.where((i) => i.isProduct).toList();

    if (productItems.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.t('duplicates_need_more'))),
      );
      return;
    }

    final duplicateGroups = buildNomenclatureDuplicateGroups(
      productItems: productItems,
      languageCode: loc.currentLanguageCode,
    );

    if (duplicateGroups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              loc.t('duplicates_none')),
          action: SnackBarAction(
            label: loc.t('duplicates_search_ai'),
            onPressed: () => _showDuplicatesWithAI(),
          ),
        ),
      );
      return;
    }

    await _openDuplicatesDialog(duplicateGroups, loc);
  }

  /// Edge `ai-find-duplicates` (лимит ~150 названий на стороне функции).
  Future<void> _showDuplicatesWithAI() async {
    final loc = context.read<LocalizationService>();
    final productItems = _nomenclatureItems.where((i) => i.isProduct).toList();

    if (productItems.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.t('duplicates_need_more'))),
      );
      return;
    }
    if (productItems.length > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('duplicates_ai_limit'))),
      );
      return;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                  child: Text(loc.t('duplicates_ai_progress'))),
            ],
          ),
        ),
      ),
    );

    try {
      final ai = context.read<AiServiceSupabase>();
      final payload = productItems
          .map((e) => (
                id: e.id,
                name: e.getLocalizedName(loc.currentLanguageCode),
              ))
          .toList();
      final idGroups = await ai.findDuplicates(payload);
      if (!mounted) return;
      Navigator.of(context).pop();

      final idToItem = {for (final i in productItems) i.id: i};
      final duplicateGroups = <List<NomenclatureItem>>[];
      for (final g in idGroups) {
        final items = <NomenclatureItem>[];
        for (final id in g) {
          final it = idToItem[id];
          if (it != null) items.add(it);
        }
        if (items.length >= 2) duplicateGroups.add(items);
      }

      if (duplicateGroups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  loc.t('duplicates_none'))),
        );
        return;
      }

      await _openDuplicatesDialog(duplicateGroups, loc, showAiOption: false);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('duplicates_ai_error')}: $e')),
        );
      }
    }
  }

  Future<void> _openDuplicatesDialog(
    List<List<NomenclatureItem>> duplicateGroups,
    LocalizationService loc, {
    bool showAiOption = true,
  }) async {
    final idToItem = {for (final i in _nomenclatureItems) i.id: i};

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _DuplicatesDialog(
        groups: duplicateGroups,
        loc: loc,
        showAiOption: showAiOption,
        onRequestAi: showAiOption
            ? () {
                Navigator.of(ctx).pop();
                _showDuplicatesWithAI();
              }
            : null,
        onRemove: (idsToRemove) async {
          final store = context.read<ProductStoreSupabase>();
          final est = context.read<AccountManagerSupabase>().establishment;
          final estId =
              est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
          if (estId == null) return;
          for (final id in idsToRemove) {
            final item = idToItem[id];
            if (item?.isProduct == true) {
              await store.removeFromNomenclature(estId, id);
            }
          }
          await _ensureLoaded(skipAutoTranslation: true);
          if (mounted) setState(() {});
        },
        onMergeProducts: (targetId, sourceIds) async {
          final store = context.read<ProductStoreSupabase>();
          await store.mergeProductsInto(targetId, sourceIds);
          await _ensureLoaded(skipAutoTranslation: true);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Widget _buildNomenclatureSkeletonLoading() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: 8, // Показываем 8 skeleton элементов
      itemBuilder: (context, index) {
        return const _NomenclatureSkeletonItem();
      },
    );
  }

  void _showEditProductForNomenclature(
      BuildContext context,
      Product p,
      ProductStoreSupabase store,
      LocalizationService loc,
      VoidCallback onRefresh,
      String estId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditDialog(
        product: p,
        store: store,
        loc: loc,
        establishmentId: estId,
        onSaved: onRefresh,
      ),
    );
  }

  void _showCreateProductDialog(LocalizationService loc) {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    final estId =
        est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
    if (estId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.t('no_establishment'))));
      return;
    }
    final store = context.read<ProductStoreSupabase>();
    final allLangs = LocalizationService.productLanguageCodes;
    final names = <String, String>{for (final c in allLangs) c: ''};
    final emptyProduct = Product(
      id: const Uuid().v4(),
      name: '',
      category: 'manual',
      names: names,
      calories: null,
      protein: null,
      fat: null,
      carbs: null,
      unit: 'g',
      basePrice: null,
      currency: account.establishment?.defaultCurrency ?? 'VND',
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditDialog(
        product: emptyProduct,
        store: store,
        loc: loc,
        establishmentId: estId,
        onSaved: () => _ensureLoaded(skipAutoTranslation: true)
            .then((_) => setState(() {})),
        isCreate: true,
      ),
    );
  }

  Future<void> _confirmRemoveForNomenclature(
      BuildContext context,
      Product p,
      ProductStoreSupabase store,
      LocalizationService loc,
      VoidCallback onRefresh,
      String estId) async {
    // Проверяем, используется ли продукт в ТТК — блокируем удаление из номенклатуры
    try {
      final techCardService = context.read<TechCardServiceSupabase>();
      final allTechCards = await techCardService.getAllTechCards();
      for (final tc in allTechCards) {
        if (tc.ingredients.any((ing) => ing.productId == p.id)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(loc.t('product_used_in_ttk_cannot_remove',
                      args: {'dish': tc.dishName}))),
            );
          }
          return;
        }
      }
    } catch (_) {}
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('remove_from_nomenclature')),
        content: Text(
          loc
              .t('remove_from_nomenclature_confirm')
              .replaceAll('%s', p.getLocalizedName(loc.currentLanguageCode)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(loc.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await store.removeFromNomenclature(estId, p.id);
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  String _buildProductSubtitle(BuildContext context, Product p,
      ProductStoreSupabase store, String estId, LocalizationService loc) {
    final loc = context.read<LocalizationService>();
    final unitPrefs = context.read<UnitSystemPreferenceService>();
    final establishmentPrice = store.getEstablishmentPrice(p.id, estId);
    final rawPrice = establishmentPrice?.$1;
    final accountManager = context.read<AccountManagerSupabase>();
    // Символ берём из валюты заведения, чтобы при смене валюты в настройках знак обновлялся
    final displayCurrency = accountManager.establishment?.defaultCurrency ??
        establishmentPrice?.$2 ??
        p.currency ??
        'VND';
    final currencySymbol = _currencySymbol(displayCurrency);

    // Цена в establishment_products и basePrice хранится за кг. Показываем как есть.
    String priceText;
    if (rawPrice != null) {
      final unit = (p.unit ?? 'g').trim().toLowerCase();
      if (unit == 'g' || unit == 'грамм' || unit == 'kg' || unit == 'кг') {
        if (unitPrefs.isImperial) {
          final perLb = rawPrice * 0.453592;
          priceText = '${NumberFormatUtils.formatInt(perLb)} $currencySymbol/lb';
        } else {
          priceText = loc
              .t('price_per_kg')
              .replaceFirst('%s', NumberFormatUtils.formatInt(rawPrice))
              .replaceFirst('%s', currencySymbol);
        }
      } else {
        priceText =
            '${NumberFormatUtils.formatInt(rawPrice)} $currencySymbol/${_unitDisplay(p.unit, loc.currentLanguageCode, unitSystem: unitPrefs.unitSystem)}';
      }
    } else {
      priceText = loc.t('price_not_set');
    }

    final hideCategory = p.category == 'misc' ||
        p.category == 'manual' ||
        p.category == 'imported';

    // «доп от филиала» — продукт добавлен только в номенклатуру филиала
    final branchOnly = store.isBranchOnlyProduct(p.id);
    final base =
        hideCategory ? priceText : '${_categoryLabel(p.category)} · $priceText';
    if (branchOnly) {
      final label = loc.t('branch_only_product_label');
      return '$base · $label';
    }
    return base;
  }

  String _currencySymbol(String currency) =>
      Establishment.currencySymbolFor(currency);

  String _buildTechCardSubtitle(BuildContext context, TechCard tc) {
    final loc = context.read<LocalizationService>();
    // Рассчитываем стоимость за кг для ТТК
    if (tc.ingredients.isEmpty) {
      return loc
          .t('pf_price_not_calculated')
          .replaceFirst('%s', tc.yield.toStringAsFixed(0));
    }

    final totalCost =
        tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
    final totalOutput =
        tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.outputWeight);
    final costPerKg = totalOutput > 0 ? (totalCost / totalOutput) * 1000 : 0;
    final sym = _currencySymbol(
        context.read<AccountManagerSupabase>().establishment?.defaultCurrency ??
            'VND');

    return loc
        .t('pf_price_per_kg')
        .replaceFirst('%s', NumberFormatUtils.formatInt(costPerKg))
        .replaceFirst('%s', sym)
        .replaceFirst('%s', tc.yield.toStringAsFixed(0));
  }

  bool _needsKbju(NomenclatureItem item) {
    if (item.isTechCard) return false; // ТТК не нуждаются в КБЖУ
    final p = item.product!;
    if (p.kbjuManuallyConfirmed) return false;
    return (p.calories == null || p.calories == 0) &&
        p.protein == null &&
        p.fat == null &&
        p.carbs == null;
  }

  bool _canShowNutrition(BuildContext context) {
    final account = context.read<AccountManagerSupabase>();
    return account.hasProSubscription;
  }

  bool _needsTranslation(NomenclatureItem item) {
    if (item.isTechCard) return false; // ТТК не нуждаются в переводе имен
    final p = item.product!;
    final allLangs = LocalizationService.productLanguageCodes;
    final n = p.names;
    if (n == null || n.isEmpty) return true;
    if (allLangs.any((c) => (n[c] ?? '').trim().isEmpty)) return true;
    // Ручные продукты с одинаковым текстом во всех языках — не переведены
    if (p.category == 'manual') {
      final vals = allLangs
          .map((c) => (n[c] ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (vals.length <= 1) return true;
    }
    return false;
  }

  Future<void> _loadKbjuForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadKbjuProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted)
      _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
  }

  Future<void> _loadTranslationsForAll(
      BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadTranslationsProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted)
      _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
  }

  Future<void> _verifyWithAi(
      BuildContext context, List<Product> list, String estId) async {
    if (!context.mounted || list.isEmpty) return;
    final ai = context.read<AiService>();
    final store = context.read<ProductStoreSupabase>();
    final loc = context.read<LocalizationService>();
    List<_VerifyProductItem> results = [];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _VerifyProductsProgressDialog(
        list: list,
        store: store,
        estId: estId,
        aiService: ai,
        loc: loc,
        onComplete: (r) {
          results = r;
          Navigator.of(ctx).pop();
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (!context.mounted) return;
    final withSuggestions = results.where((e) => e.hasAnySuggestion).toList();
    if (withSuggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('verify_no_suggestions'))));
      _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => _VerifyProductsResultsDialog(
        items: withSuggestions,
        store: store,
        estId: estId,
        loc: loc,
        onApplied: () {
          Navigator.of(ctx).pop();
          _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(loc.t('verify_applied'))));
          }
        },
      ),
    );
    if (context.mounted)
      _ensureLoaded(skipAutoTranslation: true).then((_) => setState(() {}));
  }

  Widget _tabChip(_NomTab tab, String label) {
    final isSelected = _selectedTab == tab;
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _selectedTab = tab),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final account = context.watch<AccountManagerSupabase>();
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final est = account.establishment;
    // Филиал: работа с номенклатурой и ценами по id филиала (головное — dataEstablishmentId).
    final estId =
        est != null && est.isBranch ? est.id : est?.dataEstablishmentId;
    final canEdit =
        account.currentEmployee?.canEditChecklistsAndTechCards ?? false;
    final isBranch = est?.isBranch ?? false;
    final currencySymbol = account.establishment?.currencySymbol ??
        Establishment.currencySymbolFor(
            account.establishment?.defaultCurrency ?? 'VND');

    // Фильтруем элементы номенклатуры
    var nomItems = _nomenclatureItems.where((item) {
      // Фильтр по типу
      if (_nomFilter == _NomenclatureFilter.products && item.isTechCard)
        return false;

      // Фильтр «без цены»: только продукты/ПФ без указанной цены
      if (_filterNoPrice) {
        if (item.isProduct) {
          final ep = store.getEstablishmentPrice(item.product!.id, estId);
          final price = ep?.$1;
          if (price != null) return false;
        } else {
          if (item.price != null) return false;
        }
      }

      // Фильтр по категории (только для продуктов)
      if (_category != null &&
          item.isProduct &&
          item.product!.category != _category) return false;

      // Поисковый запрос
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return item.name.toLowerCase().contains(q) ||
            item
                .getLocalizedName(loc.currentLanguageCode)
                .toLowerCase()
                .contains(q);
      }
      return true;
    }).toList();

    // Сортируем
    nomItems = _sortNomenclatureItems(nomItems, _nomSort,
        lang: loc.currentLanguageCode);

    // «Новые» — продукты без цены (из загрузки ТТК и т.д.), для проверки и внесения цены/единицы
    final newItems = _nomenclatureItems.where((item) {
      if (item.isProduct) {
        final ep = store.getEstablishmentPrice(item.product!.id, estId);
        return ep?.$1 == null;
      }
      return item.price == null;
    }).where((item) {
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return item.name.toLowerCase().contains(q) ||
            item
                .getLocalizedName(loc.currentLanguageCode)
                .toLowerCase()
                .contains(q);
      }
      return true;
    }).toList();
    final newItemsSorted = _sortNomenclatureItems(newItems, _nomSort,
        lang: loc.currentLanguageCode);

    final iikoStore = context.watch<IikoProductStore>();
    final estId2 = account.dataEstablishmentId ?? '';

    final canCreateProduct = (_selectedTab == _NomTab.nomenclature ||
        _selectedTab == _NomTab.newProducts);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _scrollToTop,
          child: Text(loc.t('nomenclature')),
        ),
        actions: [
          // Счётчик: показываем для активной вкладки
          if (_selectedTab == _NomTab.nomenclature ||
              _selectedTab == _NomTab.newProducts)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _selectedTab == _NomTab.newProducts
                      ? '${newItemsSorted.length}'
                      : '${nomItems.length}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          if (_selectedTab == _NomTab.nomenclature ||
              _selectedTab == _NomTab.newProducts) ...[
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _showNomenclatureExcelExportDialog(loc),
              tooltip: loc.t('nomenclature_excel_export_title'),
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: () => _importNomenclatureExcel(loc),
              tooltip: loc.t('nomenclature_excel_import_tooltip'),
            ),
            IconButton(
              icon: const Icon(Icons.warning),
              onPressed: () => _showDuplicates(),
              tooltip: loc.t('tooltip_show_duplicates'),
            ),
            PopupMenuButton<String>(
              tooltip: loc.t('add'),
              icon: const Icon(Icons.add),
              onSelected: (v) {
                if (v == 'create') {
                  _showCreateProductDialog(loc);
                  return;
                }
                if (v == 'upload') {
                  context.push('/products/upload');
                  return;
                }
              },
              itemBuilder: (ctx) {
                final accent = Theme.of(ctx).colorScheme.primary;
                return [
                  PopupMenuItem(
                    value: 'create',
                    child: Row(
                      children: [
                        Icon(Icons.add_box_outlined, size: 20, color: accent),
                        const SizedBox(width: 10),
                        Text(
                          loc.t('create_product'),
                          style: TextStyle(color: accent, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'upload',
                    child: Row(
                      children: [
                        Icon(Icons.upload_file, size: 20, color: accent),
                        const SizedBox(width: 10),
                        Text(
                          loc.t('upload_products'),
                          style: TextStyle(color: accent, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ];
              },
            ),
            IconButton(
              icon: const Icon(Icons.attach_money),
              onPressed: account.establishment != null
                  ? () => _showCurrencyDialog(context, loc, account, store)
                  : null,
              tooltip: loc.t('default_currency'),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _ensureLoaded(skipAutoTranslation: true);
              if (mounted) setState(() {});
            },
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: PrimaryScrollController(
        controller: _scrollController,
        child: Column(
          children: [
            // ── Переключатель вкладок (FilterChip, как в Входящих) ──────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _tabChip(_NomTab.nomenclature, loc.t('nomenclature')),
                    const SizedBox(width: 8),
                    _tabChip(_NomTab.newProducts, loc.t('nomenclature_new')),
                    if (widget.department != 'hall' &&
                        widget.department != 'dining_room') ...[
                      const SizedBox(width: 8),
                      _tabChip(_NomTab.iiko, 'iiko'),
                    ],
                    if (_selectedTab == _NomTab.nomenclature ||
                        _selectedTab == _NomTab.newProducts) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: Icon(
                          Icons.money_off,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: Text(
                          loc.t(
                            'nomenclature_filter_without_price',
                            args: {'symbol': currencySymbol},
                          ),
                        ),
                        selected: _filterNoPrice,
                        showCheckmark: false,
                        onSelected: (v) => setState(() => _filterNoPrice = v),
                        selectedColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.straighten, size: 16),
                        label: Text(unitPrefs.isImperial ? 'US Imperial' : 'Metric'),
                        selected: unitPrefs.isImperial,
                        showCheckmark: false,
                        onSelected: (v) => unitPrefs.setUnitSystem(
                          v ? UnitSystem.imperial : UnitSystem.metric,
                        ),
                        selectedColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Контент активной вкладки ─────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _selectedTab.index,
                children: [
                  // Вкладка 0: стандартная номенклатура
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: loc.t('search'),
                                      prefixIcon: const Icon(Icons.search),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    onChanged: (v) =>
                                        setState(() => _query = v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<_CatalogSort>(
                                  icon: const Icon(Icons.sort),
                                  tooltip: loc
                                      .t('sort_name_az')
                                      .split(' ')
                                      .take(2)
                                      .join(' '),
                                  onSelected: (s) =>
                                      setState(() => _nomSort = s),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: _CatalogSort.nameAz,
                                        child: Text(loc.t('sort_name_az'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.nameZa,
                                        child: Text(loc.t('sort_name_za'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.priceAsc,
                                        child: Text(loc.t('sort_price_asc'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.priceDesc,
                                        child: Text(loc.t('sort_price_desc'))),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _isLoading
                            ? _buildNomenclatureSkeletonLoading()
                            : _NomenclatureTab(
                                items: nomItems,
                                store: store,
                                estId: estId ?? '',
                                canRemove: true,
                                loc: loc,
                                sort: _nomSort,
                                filterType: _nomFilter,
                                loadError: _loadError,
                                onRetry: () =>
                                    _ensureLoaded(skipAutoTranslation: true)
                                        .then((_) => setState(() {})),
                                onSortChanged: (s) =>
                                    setState(() => _nomSort = s),
                                onFilterTypeChanged: (f) =>
                                    setState(() => _nomFilter = f),
                                onRefresh: () =>
                                    _ensureLoaded(skipAutoTranslation: true)
                                        .then((_) => setState(() {})),
                                onSwitchToCatalog: () =>
                                    _showCreateProductDialog(loc),
                                onEditProduct: (ctx, p) =>
                                    _showEditProductForNomenclature(
                                        ctx,
                                        p,
                                        store,
                                        loc,
                                        () => _ensureLoaded(
                                                skipAutoTranslation: true)
                                            .then((_) => setState(() {})),
                                        estId ?? ''),
                                onRemoveProduct: (ctx, p) =>
                                    _confirmRemoveForNomenclature(
                                        ctx,
                                        p,
                                        store,
                                        loc,
                                        () => _ensureLoaded(
                                                skipAutoTranslation: true)
                                            .then((_) => setState(() {})),
                                        estId ?? ''),
                                onLoadKbju: (ctx, list) =>
                                    _loadKbjuForAll(ctx, list),
                                onVerifyWithAi: (ctx, list) =>
                                    _verifyWithAi(ctx, list, estId ?? ''),
                                onNeedsKbju: (item) => _needsKbju(item),
                                onNeedsTranslation: (item) =>
                                    _needsTranslation(item),
                                onCanShowNutrition: (context) =>
                                    _canShowNutrition(context),
                                onBuildProductSubtitle:
                                    (context, p, store, estId, loc) =>
                                        _buildProductSubtitle(
                                            context, p, store, estId, loc),
                                onBuildTechCardSubtitle: (tc) =>
                                    _buildTechCardSubtitle(context, tc),
                              ),
                      ),
                    ],
                  ),

                  // Вкладка 1: «Новые» — продукты без цены (из ТТК и т.д.)
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (newItemsSorted.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  loc.t('nomenclature_new_empty'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              )
                            else
                              Text(
                                loc.t('nomenclature_new_hint'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: loc.t('search'),
                                      prefixIcon: const Icon(Icons.search),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                    onChanged: (v) =>
                                        setState(() => _query = v),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<_CatalogSort>(
                                  icon: const Icon(Icons.sort),
                                  tooltip: loc
                                      .t('sort_name_az')
                                      .split(' ')
                                      .take(2)
                                      .join(' '),
                                  onSelected: (s) =>
                                      setState(() => _nomSort = s),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: _CatalogSort.nameAz,
                                        child: Text(loc.t('sort_name_az'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.nameZa,
                                        child: Text(loc.t('sort_name_za'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.priceAsc,
                                        child: Text(loc.t('sort_price_asc'))),
                                    PopupMenuItem(
                                        value: _CatalogSort.priceDesc,
                                        child: Text(loc.t('sort_price_desc'))),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _isLoading
                            ? _buildNomenclatureSkeletonLoading()
                            : _NomenclatureTab(
                                items: newItemsSorted,
                                store: store,
                                estId: estId ?? '',
                                canRemove: true,
                                loc: loc,
                                sort: _nomSort,
                                filterType: _nomFilter,
                                loadError: _loadError,
                                onRetry: () =>
                                    _ensureLoaded(skipAutoTranslation: true)
                                        .then((_) => setState(() {})),
                                onSortChanged: (s) =>
                                    setState(() => _nomSort = s),
                                onFilterTypeChanged: (f) =>
                                    setState(() => _nomFilter = f),
                                onRefresh: () =>
                                    _ensureLoaded(skipAutoTranslation: true)
                                        .then((_) => setState(() {})),
                                onSwitchToCatalog: () =>
                                    _showCreateProductDialog(loc),
                                onEditProduct: (ctx, p) =>
                                    _showEditProductForNomenclature(
                                        ctx,
                                        p,
                                        store,
                                        loc,
                                        () => _ensureLoaded(
                                                skipAutoTranslation: true)
                                            .then((_) => setState(() {})),
                                        estId ?? ''),
                                onRemoveProduct: (ctx, p) =>
                                    _confirmRemoveForNomenclature(
                                        ctx,
                                        p,
                                        store,
                                        loc,
                                        () => _ensureLoaded(
                                                skipAutoTranslation: true)
                                            .then((_) => setState(() {})),
                                        estId ?? ''),
                                onLoadKbju: (ctx, list) =>
                                    _loadKbjuForAll(ctx, list),
                                onVerifyWithAi: (ctx, list) =>
                                    _verifyWithAi(ctx, list, estId ?? ''),
                                onNeedsKbju: (item) => _needsKbju(item),
                                onNeedsTranslation: (item) =>
                                    _needsTranslation(item),
                                onCanShowNutrition: (context) =>
                                    _canShowNutrition(context),
                                onBuildProductSubtitle:
                                    (context, p, store, estId, loc) =>
                                        _buildProductSubtitle(
                                            context, p, store, estId, loc),
                                onBuildTechCardSubtitle: (tc) =>
                                    _buildTechCardSubtitle(context, tc),
                              ),
                      ),
                    ],
                  ),

                  // Вкладка 2: iiko-продукты
                  _IikoNomenclatureTab(
                    store: iikoStore,
                    establishmentId: estId2,
                    onUpload: _uploadIikoBlank,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Product> _sortProducts(List<Product> list, _CatalogSort sort,
      {String lang = 'ru'}) {
    final copy = List<Product>.from(list);
    switch (sort) {
      case _CatalogSort.nameAz:
        copy.sort((a, b) => _sortKeyForName(a.getLocalizedName(lang))
            .compareTo(_sortKeyForName(b.getLocalizedName(lang))));
        break;
      case _CatalogSort.nameZa:
        copy.sort((a, b) => _sortKeyForName(b.getLocalizedName(lang))
            .compareTo(_sortKeyForName(a.getLocalizedName(lang))));
        break;
      case _CatalogSort.priceAsc:
      case _CatalogSort.priceDesc:
        // Сортировка по цене — в _sortNomenclatureItems (NomenclatureItem.price)
        copy.sort((a, b) => 0);
        break;
    }
    return copy;
  }

  /// Ключ сортировки: для русского — соус/специя и т.п. идут по слову-типу;
  /// для других языков — простая алфавитная.
  static String _sortKeyForName(String name) {
    final lower = name.trim().toLowerCase();
    // Применяем русскую логику только если текст содержит кириллицу
    final hasCyrillic = lower.runes.any((r) => r >= 0x0400 && r <= 0x04FF);
    if (hasCyrillic) {
      const words = [
        'соус',
        'специя',
        'смесь',
        'приправа',
        'маринад',
        'подлива',
        'паста',
        'масло'
      ];
      for (final w in words) {
        final idx = lower.indexOf(w);
        if (idx >= 0) {
          final before = idx > 0 ? lower.substring(0, idx).trim() : '';
          final after = idx + w.length < lower.length
              ? lower.substring(idx + w.length).trim()
              : '';
          final rest = [before, after].where((s) => s.isNotEmpty).join(' ');
          return '$w ${rest.isEmpty ? '' : rest}'.trim();
        }
      }
    }
    return lower;
  }

  List<NomenclatureItem> _sortNomenclatureItems(
      List<NomenclatureItem> list, _CatalogSort sort,
      {String lang = 'ru'}) {
    final products = list.where((item) => item.isProduct).toList();
    final techCards = list.where((item) => item.isTechCard).toList();

    void sortGroup(List<NomenclatureItem> group) {
      switch (sort) {
        case _CatalogSort.nameAz:
          group.sort((a, b) => _sortKeyForName(a.getLocalizedName(lang))
              .compareTo(_sortKeyForName(b.getLocalizedName(lang))));
          break;
        case _CatalogSort.nameZa:
          group.sort((a, b) => _sortKeyForName(b.getLocalizedName(lang))
              .compareTo(_sortKeyForName(a.getLocalizedName(lang))));
          break;
        case _CatalogSort.priceAsc:
          group.sort((a, b) => (a.price ?? 0).compareTo(b.price ?? 0));
          break;
        case _CatalogSort.priceDesc:
          group.sort((a, b) => (b.price ?? 0).compareTo(a.price ?? 0));
          break;
      }
    }

    sortGroup(products);
    sortGroup(techCards);
    return [...products, ...techCards];
  }

  String _categoryLabel(String c) {
    const map = {
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
      'misc': '',
      'manual': '',
      'imported': '',
    };
    return map[c] ?? c;
  }

  ({String name, double? price}) _parseLine(String line) {
    // Сначала пробуем разделить по табуляции
    var parts = line.split('\t');
    if (parts.length < 2) {
      // Если нет табуляции, пробуем разделить по множественным пробелам
      parts = line.split(RegExp(r'\s{2,}'));
    }
    if (parts.length < 2) {
      // Если нет множественных пробелов, пробуем найти последнюю цифру в строке
      final lastSpaceIndex = line.lastIndexOf(' ');
      if (lastSpaceIndex > 0) {
        final name = line.substring(0, lastSpaceIndex).trim();
        final pricePart = line.substring(lastSpaceIndex + 1).trim();
        final priceStr = pricePart
            .replaceAll('₫', '')
            .replaceAll(',', '')
            .replaceAll(' ', '')
            .trim();
        final price = double.tryParse(priceStr);
        return (name: name, price: price);
      }
      return (name: line.trim(), price: null);
    }

    final name = parts[0].trim();
    if (name.isEmpty) return (name: '', price: null);

    final priceStr = parts[1]
        .replaceAll('₫', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();
    final price = double.tryParse(priceStr);
    return (name: name, price: price);
  }

  Future<void> _showNomenclatureExcelExportDialog(
      LocalizationService loc) async {
    final options = LocalizationService.productLanguageCodes;
    var selected = options.contains(loc.currentLanguageCode)
        ? loc.currentLanguageCode
        : options.first;

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(loc.t('nomenclature_excel_export_title')),
          content: DropdownButtonFormField<String>(
            value: selected,
            items: options
                .map((code) => DropdownMenuItem(
                      value: code,
                      child: Text(code.toUpperCase()),
                    ))
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setLocalState(() => selected = value);
            },
            decoration: InputDecoration(
              labelText: loc.t('nomenclature_excel_export_language_label'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(loc.t('nomenclature_excel_export_action')),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _exportNomenclatureExcel(loc, chosen);
  }

  Future<void> _exportNomenclatureExcel(
      LocalizationService loc, String languageCode) async {
    final account = context.read<AccountManagerSupabase>();
    final store = context.read<ProductStoreSupabase>();
    final estId = account.dataEstablishmentId;
    if (estId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('no_establishment'))),
      );
      return;
    }

    await store.loadProducts(force: true);
    await store.loadNomenclature(estId);
    final products = store.getNomenclatureProducts(estId);
    if (products.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('nomenclature_empty'))),
      );
      return;
    }

    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];
    final headers = <String>[
      'display_name',
      'price',
      'unit',
      'id',
      'category',
      'name_default',
      'names_json',
      'currency',
      'calories',
      'protein',
      'fat',
      'carbs',
      'contains_gluten',
      'contains_lactose',
      'kbju_manually_confirmed',
      'package_price',
      'package_weight_grams',
      'grams_per_piece',
      'primary_waste_pct',
      'supplier_ids_json',
    ];

    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }

    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      final row = i + 1;
      final values = <Object?>[
        p.getLocalizedName(languageCode),
        p.basePrice,
        p.unit ?? '',
        p.id,
        p.category,
        p.name,
        jsonEncode(p.names ?? const <String, String>{}),
        p.currency ?? '',
        p.calories,
        p.protein,
        p.fat,
        p.carbs,
        p.containsGluten,
        p.containsLactose,
        p.kbjuManuallyConfirmed,
        p.packagePrice,
        p.packageWeightGrams,
        p.gramsPerPiece,
        p.primaryWastePct,
        jsonEncode(p.supplierIds ?? const <String>[]),
      ];
      for (var c = 0; c < values.length; c++) {
        final v = values[c];
        final cell =
            sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
        if (v == null) {
          cell.value = TextCellValue('');
        } else if (v is num) {
          cell.value = DoubleCellValue(v.toDouble());
        } else if (v is bool) {
          cell.value = TextCellValue(v ? 'true' : 'false');
        } else {
          cell.value = TextCellValue(v.toString());
        }
      }
    }

    final fileName =
        'nomenclature_restodocks_${languageCode}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final bytes = excel.encode();
    if (bytes == null) return;
    final est = account.establishment;
    if (est != null && account.isTrialOnlyWithoutPaid) {
      await account.trialIncrementDeviceSaveOrThrow(
        establishmentId: est.id,
        docKind: TrialDeviceSaveKinds.nomenclature,
      );
    }
    await saveFileBytes(fileName, Uint8List.fromList(bytes));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Выгружено: ${products.length} позиций')),
    );
  }

  Future<void> _importNomenclatureExcel(LocalizationService loc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.bytes == null) return;

    final bytes = result.files.single.bytes!;
    try {
      final excel = Excel.decodeBytes(bytes.toList());
      if (excel.tables.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('excel_no_sheet_in_file'))));
        return;
      }
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loc.t('file_empty'))));
        return;
      }

      final header = sheet.rows.first
          .map((c) => (c?.value?.toString() ?? '').trim().toLowerCase())
          .toList();
      final hasRestodocksFormat =
          header.contains('display_name') && header.contains('names_json');
      if (!hasRestodocksFormat) {
        await _addProductsFromExcel(bytes, loc);
        return;
      }

      final account = context.read<AccountManagerSupabase>();
      final store = context.read<ProductStoreSupabase>();
      final estId = account.dataEstablishmentId;
      if (estId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('no_establishment'))),
        );
        return;
      }

      await store.loadProducts(force: true);
      await store.loadNomenclature(estId);
      final existing = store.getNomenclatureProducts(estId);
      final byId = {for (final p in existing) p.id: p};
      final byName = {
        for (final p in existing) _normalizeImportName(p.name): p,
      };

      int added = 0;
      int updated = 0;
      int failed = 0;

      String cellAt(List<Data?> row, int index) =>
          index < row.length ? (row[index]?.value?.toString() ?? '').trim() : '';
      double? toDouble(String s) => s.isEmpty ? null : double.tryParse(s);
      bool? toBoolNullable(String s) {
        final v = s.trim().toLowerCase();
        if (v.isEmpty) return null;
        if (v == 'true' || v == '1' || v == 'yes') return true;
        if (v == 'false' || v == '0' || v == 'no') return false;
        return null;
      }

      Map<String, String> parseNames(String raw, String fallbackName) {
        if (raw.trim().isEmpty) return {loc.currentLanguageCode: fallbackName};
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final map = <String, String>{};
            decoded.forEach((k, v) {
              final key = k.toString().trim();
              final val = v?.toString().trim() ?? '';
              if (key.isNotEmpty && val.isNotEmpty) map[key] = val;
            });
            if (map.isNotEmpty) return map;
          }
        } catch (_) {}
        return {loc.currentLanguageCode: fallbackName};
      }

      List<String>? parseSuppliers(String raw) {
        if (raw.trim().isEmpty) return null;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            final ids = decoded
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();
            return ids.isEmpty ? null : ids;
          }
        } catch (_) {}
        return null;
      }

      int col(String key) => header.indexOf(key);
      final cDisplay = col('display_name');
      final cPrice = col('price');
      final cUnit = col('unit');
      final cId = col('id');
      final cCategory = col('category');
      final cNameDefault = col('name_default');
      final cNamesJson = col('names_json');
      final cCurrency = col('currency');
      final cCalories = col('calories');
      final cProtein = col('protein');
      final cFat = col('fat');
      final cCarbs = col('carbs');
      final cContainsGluten = col('contains_gluten');
      final cContainsLactose = col('contains_lactose');
      final cKbjuConfirmed = col('kbju_manually_confirmed');
      final cPackagePrice = col('package_price');
      final cPackageWeight = col('package_weight_grams');
      final cGramsPerPiece = col('grams_per_piece');
      final cPrimaryWaste = col('primary_waste_pct');
      final cSupplierIds = col('supplier_ids_json');

      for (var r = 1; r < sheet.rows.length; r++) {
        final row = sheet.rows[r];
        final displayName = cellAt(row, cDisplay);
        final nameDefault = cellAt(row, cNameDefault);
        final productName = nameDefault.isNotEmpty ? nameDefault : displayName;
        if (productName.isEmpty) continue;
        try {
          final rawId = cellAt(row, cId);
          final category = cellAt(row, cCategory);
          final names = parseNames(cellAt(row, cNamesJson), productName);
          final model = Product(
            id: rawId.isNotEmpty ? rawId : const Uuid().v4(),
            name: productName,
            category: category.isNotEmpty ? category : 'manual',
            names: names,
            calories: toDouble(cellAt(row, cCalories)),
            protein: toDouble(cellAt(row, cProtein)),
            fat: toDouble(cellAt(row, cFat)),
            carbs: toDouble(cellAt(row, cCarbs)),
            kbjuManuallyConfirmed:
                toBoolNullable(cellAt(row, cKbjuConfirmed)) ?? false,
            containsGluten: toBoolNullable(cellAt(row, cContainsGluten)),
            containsLactose: toBoolNullable(cellAt(row, cContainsLactose)),
            basePrice: toDouble(cellAt(row, cPrice)),
            currency: cellAt(row, cCurrency).isEmpty
                ? null
                : cellAt(row, cCurrency),
            packagePrice: toDouble(cellAt(row, cPackagePrice)),
            packageWeightGrams: toDouble(cellAt(row, cPackageWeight)),
            gramsPerPiece: toDouble(cellAt(row, cGramsPerPiece)),
            unit: cellAt(row, cUnit).isEmpty ? null : cellAt(row, cUnit),
            primaryWastePct: toDouble(cellAt(row, cPrimaryWaste)),
            supplierIds: parseSuppliers(cellAt(row, cSupplierIds)),
          );

          final matched = (rawId.isNotEmpty ? byId[rawId] : null) ??
              byName[_normalizeImportName(productName)];
          if (matched != null) {
            await store.updateProduct(model.copyWith(id: matched.id));
            await store.addToNomenclature(estId, matched.id);
            updated++;
          } else {
            final saved = await store.addProduct(model);
            await store.addToNomenclature(estId, saved.id);
            added++;
          }
        } catch (_) {
          failed++;
        }
      }

      await store.loadProducts(force: true);
      await store.loadNomenclature(estId);
      if (mounted) setState(() {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Импорт завершен: добавлено $added, обновлено $updated, ошибок $failed'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.t(
        'excel_file_process_error',
        args: {'error': '$e'},
      ))));
    }
  }

  String _normalizeImportName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\sа-яё]'), '')
        .trim();
  }

  // Удалены дублированные функции загрузки продуктов:
  // _showUploadDialog, _showPasteDialog, _uploadFromTxt
  // Теперь используется единый экран загрузки продуктов
  // Fix for Vercel build issue

  static const _addProductCategories = [
    'manual',
    'vegetables',
    'fruits',
    'meat',
    'seafood',
    'dairy',
    'grains',
    'bakery',
    'pantry',
    'spices',
    'beverages',
    'eggs',
    'legumes',
    'nuts',
    'misc'
  ];
  static const _addProductUnits = ['g', 'kg', 'pcs', 'ml', 'L'];

  Future<void> _showAddProductDialog(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final estId = account.dataEstablishmentId;
    if (estId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.t('no_establishment'))));
      return;
    }
    final store = context.read<ProductStoreSupabase>();
    final result =
        await showDialog<({String name, String category, String unit})>(
      context: context,
      builder: (ctx) => _AddProductDialog(
        loc: loc,
        categories: _addProductCategories,
        units: _addProductUnits,
        store: store,
      ),
    );
    if (result == null || result.name.trim().isEmpty || !mounted) return;
    final translationManager = context.read<TranslationManager>();
    final defCur = account.establishment?.defaultCurrency ?? 'VND';
    final sourceName = result.name.trim();
    final sourceLang = loc.currentLanguageCode;
    final names = <String, String>{sourceLang: sourceName};
    // Подтягиваем КБЖУ из Open Food Facts
    double? calories;
    double? protein;
    double? fat;
    double? carbs;
    bool? containsGluten;
    bool? containsLactose;
    try {
      final nutrition = await NutritionApiService.fetchNutrition(sourceName);
      if (nutrition != null && nutrition.hasData) {
        calories = nutrition.calories;
        protein = nutrition.protein;
        fat = nutrition.fat;
        carbs = nutrition.carbs;
        containsGluten = nutrition.containsGluten;
        containsLactose = nutrition.containsLactose;
      }
    } catch (_) {}
    final product = Product(
      id: const Uuid().v4(),
      name: sourceName,
      category: result.category,
      names: names,
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      containsGluten: containsGluten,
      containsLactose: containsLactose,
      unit: result.unit,
      basePrice: null,
      currency: null,
    );
    try {
      final savedProduct = await store.addProduct(product);
      await store.addToNomenclature(estId, savedProduct.id);
      // Запускаем перевод фоново — не блокируем UI
      translationManager
          .generateTranslationsForProduct(sourceName, sourceLang)
          .then((translations) async {
        if (translations.length > 1) {
          final updatedNames =
              Map<String, String>.from(savedProduct.names ?? {})
                ..addAll(translations);
          final updatedProduct = savedProduct.copyWith(names: updatedNames);
          try {
            await store.updateProduct(updatedProduct);
          } catch (_) {}
        }
      });
      await store.loadProducts(force: true);
      await store.loadNomenclature(estId);
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.t('product_added'))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  /// Извлекает обычный текст из RTF файла
  String _extractTextFromRtf(String rtfContent) {
    // Удаляем все RTF управляющие последовательности
    // Это упрощенная версия - удаляем все фигурные скобки и их содержимое, а также другие RTF команды
    var text = rtfContent;

    // Удаляем заголовок RTF
    final rtfHeaderEnd = text.indexOf('\\viewkind');
    if (rtfHeaderEnd != -1) {
      text = text.substring(rtfHeaderEnd);
    }

    // Удаляем все команды в фигурных скобках (группы)
    text = text.replaceAll(RegExp(r'\{[^}]*\}'), '');

    // Удаляем оставшиеся RTF команды (начинаются с \)
    text = text.replaceAll(RegExp(r'\\[a-z]+\d*'), '');

    // Удаляем лишние пробелы и переносы строк
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  Future<void> _addProductsFromExcel(
      Uint8List bytes, LocalizationService loc) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('excel_no_sheet_in_file'))));
        return;
      }

      final lines = <String>[];
      for (var i = 0; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        // Берем первые 3 колонки: название, цена, единица
        final name = row.length > 0 ? row[0]?.value?.toString() ?? '' : '';
        final price = row.length > 1 ? row[1]?.value?.toString() ?? '' : '';
        final unit = row.length > 2 ? row[2]?.value?.toString() ?? '' : 'г';

        if (name.trim().isNotEmpty) {
          lines.add('$name\t$price\t$unit');
        }
      }

      final text = lines.join('\n');
      if (text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(loc.t('file_empty'))));
        return;
      }
      await _addProductsFromText(text, loc);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t(
                'excel_file_process_error',
                args: {'error': '$e'},
              ))));
    }
  }

  Future<void> _addProductsFromText(
      String text, LocalizationService loc) async {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    final items =
        lines.map(_parseLine).where((r) => r.name.isNotEmpty).toList();

    // Отладка
    if (!mounted) return;
    final sampleLines = lines.take(2).join('\n');
    final sampleItems =
        items.take(2).map((item) => '${item.name}: ${item.price}').join(', ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        loc.t(
          'nomenclature_parse_debug_snackbar',
          args: {
            'lines_count': '${lines.length}',
            'valid_count': '${items.length}',
            'sample_lines': sampleLines,
            'sample_items': sampleItems,
          },
        ),
      ),
      duration: const Duration(seconds: 8),
    ));

    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(loc.t('no_rows_to_add'))));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('upload_list')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.t('upload_confirm').replaceAll('%s', '${items.length}')),
            const SizedBox(height: 4),
            Text(
              loc.t('upload_add_to_nomenclature_hint'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('upload_txt_format'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(loc.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(loc.t('save'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Показываем диалог с прогрессом загрузки
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _UploadProgressDialog(
        items: items,
        loc: loc,
      ),
    );

    // Обновляем список после загрузки
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est != null) {
      await store.loadProducts(force: true);
      if (est.isBranch) {
        await store.loadNomenclatureForBranch(est.id, est.dataEstablishmentId!);
      } else {
        await store.loadNomenclature(est.dataEstablishmentId!);
      }
    }
    if (mounted) setState(() {});
  }

  void _showCurrencyDialog(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase account,
    ProductStoreSupabase store,
  ) {
    final est = account.establishment!;
    showEstablishmentCurrencyPickerDialog(
      context: context,
      loc: loc,
      currentCode: est.defaultCurrency,
      onApply: (code) async {
        final updated = est.copyWith(
          defaultCurrency: code,
          updatedAt: DateTime.now(),
        );
        try {
          await account.updateEstablishment(updated);
          await store.syncEstablishmentNomenclatureCurrency(
            updated.productsEstablishmentId,
            updated.defaultCurrency,
          );
          if (context.mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.t('currency_saved'))),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(loc.t(
                  'nomenclature_save_error',
                  args: {'error': '$e'},
                )),
              ),
            );
          }
          rethrow;
        }
      },
    );
  }
}

class _DuplicatesDialog extends StatefulWidget {
  const _DuplicatesDialog({
    required this.groups,
    required this.loc,
    required this.onRemove,
    this.showAiOption = true,
    this.onRequestAi,
    this.onMergeProducts,
  });

  final List<List<NomenclatureItem>> groups;
  final LocalizationService loc;
  final Future<void> Function(List<String> idsToRemove) onRemove;
  final bool showAiOption;
  final VoidCallback? onRequestAi;

  /// Слияние в БД: один эталон [targetId], строки [sourceIds] удаляются после переноса ссылок.
  final Future<void> Function(String targetId, List<String> sourceIds)?
      onMergeProducts;

  @override
  State<_DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends State<_DuplicatesDialog> {
  final Set<String> _selectedToRemove = {};
  bool _saving = false;

  void _selectAllExceptFirst() {
    setState(() {
      _selectedToRemove.clear();
      for (final group in widget.groups) {
        for (var i = 1; i < group.length; i++) {
          _selectedToRemove.add(group[i].id);
        }
      }
    });
  }

  Future<void> _applyRemoval() async {
    if (_selectedToRemove.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onRemove(_selectedToRemove.toList());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyMerge() async {
    final merge = widget.onMergeProducts;
    if (merge == null) return;
    final loc = widget.loc;
    for (final group in widget.groups) {
      final kept =
          group.where((i) => !_selectedToRemove.contains(i.id)).toList();
      if (kept.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
                  content: Text(loc.t('duplicates_merge_need_one_kept'))),
        );
        return;
      }
      final removed =
          group.where((i) => _selectedToRemove.contains(i.id)).toList();
      if (removed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.t('duplicates_merge_pick_per_group'))),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      for (final group in widget.groups) {
        final kept = group.firstWhere((i) => !_selectedToRemove.contains(i.id));
        final sources =
            group.where((i) => _selectedToRemove.contains(i.id)).map((i) => i.id).toList();
        if (sources.isEmpty) continue;
        await merge(kept.id, sources);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.loc.t('duplicates_title')),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.loc.t('duplicates_hint'),
              style: theme.textTheme.bodySmall,
            ),
            if (widget.onMergeProducts != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.loc.t('duplicates_hint_merge'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (widget.showAiOption && widget.onRequestAi != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : widget.onRequestAi,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(widget.loc.t('duplicates_search_ai')),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: widget.groups.length,
                itemBuilder: (context, gi) {
                  final group = widget.groups[gi];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.loc.t('duplicates_group_n',
                                args: {'n': '${gi + 1}'}),
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.colorScheme.primary),
                          ),
                          ...group.map((item) => CheckboxListTile(
                                value: _selectedToRemove.contains(item.id),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedToRemove.add(item.id);
                                    } else {
                                      _selectedToRemove.remove(item.id);
                                    }
                                  });
                                },
                                title: Text(
                                  item.name,
                                  style: TextStyle(
                                    fontWeight: group.indexOf(item) == 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: item.price != null
                                    ? Text(
                                        '${item.price} ${Establishment.currencySymbolFor(item.currency ?? context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND')}')
                                    : null,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                dense: true,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(widget.loc.t('cancel')),
        ),
        TextButton(
          onPressed: _saving ? null : _selectAllExceptFirst,
          child: Text(widget.loc.t('duplicates_remove_all')),
        ),
        if (widget.onMergeProducts != null) ...[
          OutlinedButton(
            onPressed: _saving || _selectedToRemove.isEmpty
                ? null
                : _applyRemoval,
            child: Text(widget.loc.t('duplicates_nomenclature_only')),
          ),
          FilledButton(
            onPressed: _saving || _selectedToRemove.isEmpty ? null : _applyMerge,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.loc.t('duplicates_merge_catalog')),
          ),
        ] else
          FilledButton(
            onPressed:
                _saving || _selectedToRemove.isEmpty ? null : _applyRemoval,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.loc.t('duplicates_apply')),
          ),
      ],
    );
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({
    required this.loc,
    required this.categories,
    required this.units,
    required this.store,
  });

  final LocalizationService loc;
  final List<String> categories;
  final List<String> units;
  final ProductStoreSupabase store;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  TextEditingController? _nameController;
  late String _category;
  late String _unit;
  bool _recognizing = false;

  @override
  void initState() {
    super.initState();
    _category = 'manual';
    _unit = 'g';
  }

  Future<void> _recognize() async {
    final name = _nameController?.text.trim() ?? '';
    if (name.isEmpty) return;
    setState(() => _recognizing = true);
    final ai = context.read<AiService>();
    final result = await ai.recognizeProduct(name);
    if (!mounted) {
      setState(() => _recognizing = false);
      return;
    }
    setState(() {
      _recognizing = false;
      if (result != null) {
        if (result.suggestedCategory != null &&
            widget.categories.contains(result.suggestedCategory)) {
          _category = result.suggestedCategory!;
        }
        if (result.suggestedUnit != null &&
            widget.units.contains(result.suggestedUnit)) {
          _unit = result.suggestedUnit!;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.loc.t('add_product')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.trim().toLowerCase();
                if (query.isEmpty) return const Iterable<String>.empty();
                final qStripped = stripIikoPrefix(query).toLowerCase();
                return widget.store.allProducts
                    .map((p) =>
                        p.getLocalizedName(widget.loc.currentLanguageCode))
                    .where((name) {
                  final n = name.toLowerCase();
                  final nStripped = stripIikoPrefix(name).toLowerCase();
                  return n.contains(query) ||
                      n.contains(qStripped) ||
                      nStripped.contains(query) ||
                      nStripped.contains(qStripped);
                }).take(15);
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _nameController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: widget.loc.t('product_name'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _recognize(),
                );
              },
              onSelected: (value) {
                _nameController?.text = value;
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final opt = options.elementAt(i);
                        return InkWell(
                          onTap: () => onSelected(opt),
                          child: ListTile(
                            dense: true,
                            title:
                                Text(opt, style: const TextStyle(fontSize: 14)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _recognizing ? null : _recognize,
              icon: _recognizing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(widget.loc.t('ai_product_recognize')),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                  labelText: widget.loc.t('column_category'),
                  border: const OutlineInputBorder()),
              items: widget.categories
                  .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                          c == 'manual' ? widget.loc.t('category_manual') : c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'manual'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _unit,
              decoration: InputDecoration(
                  labelText: widget.loc.t('unit'),
                  border: const OutlineInputBorder()),
              items: widget.units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _unit = v ?? 'g'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(widget.loc.t('cancel'))),
        FilledButton(
          onPressed: () {
            final name = _nameController?.text.trim() ?? '';
            if (name.isEmpty) return;
            Navigator.of(context)
                .pop((name: name, category: _category, unit: _unit));
          },
          child: Text(widget.loc.t('save')),
        ),
      ],
    );
  }
}

class _NomenclatureTab extends StatefulWidget {
  const _NomenclatureTab({
    super.key,
    required this.items,
    required this.store,
    required this.estId,
    required this.canRemove,
    required this.loc,
    required this.sort,
    required this.filterType,
    this.loadError,
    this.onRetry,
    required this.onSortChanged,
    required this.onFilterTypeChanged,
    required this.onRefresh,
    required this.onSwitchToCatalog,
    required this.onEditProduct,
    required this.onRemoveProduct,
    required this.onLoadKbju,
    required this.onVerifyWithAi,
    required this.onNeedsKbju,
    required this.onNeedsTranslation,
    required this.onCanShowNutrition,
    required this.onBuildProductSubtitle,
    required this.onBuildTechCardSubtitle,
  });

  final List<NomenclatureItem> items;
  final ProductStoreSupabase store;
  final String estId;
  final bool canRemove;
  final LocalizationService loc;
  final _CatalogSort sort;
  final _NomenclatureFilter filterType;
  final Object? loadError;
  final VoidCallback? onRetry;
  final void Function(_CatalogSort) onSortChanged;
  final void Function(_NomenclatureFilter) onFilterTypeChanged;
  final VoidCallback onRefresh;
  final VoidCallback onSwitchToCatalog;
  final void Function(BuildContext, Product) onEditProduct;
  final void Function(BuildContext, Product) onRemoveProduct;
  final void Function(BuildContext, List<Product>) onLoadKbju;
  final void Function(BuildContext, List<Product>) onVerifyWithAi;
  final bool Function(NomenclatureItem) onNeedsKbju;
  final bool Function(NomenclatureItem) onNeedsTranslation;
  final bool Function(BuildContext) onCanShowNutrition;
  final String Function(BuildContext, Product, ProductStoreSupabase, String,
      LocalizationService) onBuildProductSubtitle;
  final String Function(TechCard) onBuildTechCardSubtitle;

  static String _categoryLabel(String c) {
    const map = {
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
      'misc': '',
      'manual': '',
      'imported': '',
    };
    return map[c] ?? c;
  }

  @override
  State<_NomenclatureTab> createState() => _NomenclatureTabState();
}

class _NomenclatureTabState extends State<_NomenclatureTab> {
  @override
  Widget build(BuildContext context) {
    // Слушаем изменения валюты, чтобы цены в подзаголовках обновились без перезахода
    context.watch<AccountManagerSupabase>();

    if (widget.items.isEmpty) {
      return _NomenclatureEmpty(
        loc: widget.loc,
        loadError: widget.loadError,
        onRetry: widget.onRetry,
        onSwitchToCatalog: widget.onSwitchToCatalog,
      );
    }

    final needsKbju = widget.items
        .where((item) =>
            item.isProduct &&
            item.product!.category == 'manual' &&
            widget.onNeedsKbju(item))
        .toList();
    final needsTranslation =
        widget.items.where((item) => widget.onNeedsTranslation(item)).toList();
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: widget.items.length,
            itemBuilder: (_, i) {
              final item = widget.items[i];
              if (item.isProduct) {
                final p = item.product!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        (i + 1).toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    title: Text(
                        p.getLocalizedName(widget.loc.currentLanguageCode)),
                    subtitle: Text(
                      widget.onBuildProductSubtitle(
                          context, p, widget.store, widget.estId, widget.loc),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: widget.loc.t('edit_product'),
                          onPressed: () => widget.onEditProduct(context, p),
                        ),
                        if (widget.canRemove)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.red),
                            tooltip: widget.loc.t('remove_from_nomenclature'),
                            onPressed: () => widget.onRemoveProduct(context, p),
                          ),
                      ],
                    ),
                    onTap: () => widget.onEditProduct(context, p),
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero),
                  ),
                );
              }
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: null,
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (i + 1).toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(
                      item.getLocalizedName(widget.loc.currentLanguageCode)),
                  subtitle: Text(
                    widget.onBuildTechCardSubtitle(item.techCard!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const SizedBox.shrink(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NomenclatureEmpty extends StatelessWidget {
  const _NomenclatureEmpty({
    required this.loc,
    this.loadError,
    this.onRetry,
    required this.onSwitchToCatalog,
  });

  final LocalizationService loc;
  final Object? loadError;
  final VoidCallback? onRetry;
  final VoidCallback onSwitchToCatalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              loadError != null
                  ? Icons.cloud_off_outlined
                  : Icons.inventory_2_outlined,
              size: 64,
              color: loadError != null
                  ? theme.colorScheme.error
                  : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            if (loadError != null) ...[
              Text(
                loc.t('nomenclature_load_error'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loadError.toString(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(loc.t('retry')),
              ),
            ] else ...[
              Text(
                loc.t('nomenclature_empty'),
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('add_from_catalog'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onSwitchToCatalog,
                icon: const Icon(Icons.add),
                label: Text(loc.t('add_from_catalog')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddAllProgressDialog extends StatefulWidget {
  const _AddAllProgressDialog({
    required this.list,
    required this.store,
    required this.estId,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final String estId;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_AddAllProgressDialog> createState() => _AddAllProgressDialogState();
}

class _AddAllProgressDialogState extends State<_AddAllProgressDialog> {
  int _done = 0;
  bool _finished = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      if (_error != null) break;
      try {
        final ep = widget.store.getEstablishmentPrice(p.id, widget.estId);
        await widget.store.addToNomenclature(
          widget.estId,
          p.id,
          price: ep?.$1,
          currency: ep?.$2 ?? p.currency,
        );
        if (!mounted) return;
        setState(() => _done++);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e);
        widget.onError(e);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(
          widget.loc.t('add_all_to_nomenclature').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '$_done / $total',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${widget.loc.t('error')}: $_error',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadKbjuProgressDialog extends StatefulWidget {
  const _LoadKbjuProgressDialog({
    required this.list,
    required this.store,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_LoadKbjuProgressDialog> createState() =>
      _LoadKbjuProgressDialogState();
}

class _LoadKbjuProgressDialogState extends State<_LoadKbjuProgressDialog> {
  int _done = 0;
  int _updated = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      try {
        final result = await NutritionApiService.fetchNutrition(
            p.getLocalizedName(widget.loc.currentLanguageCode));
        if (!mounted) return;
        if (result != null && result.hasData) {
          final updated = p.copyWith(
            calories: result.calories ?? p.calories,
            protein: result.protein ?? p.protein,
            fat: result.fat ?? p.fat,
            carbs: result.carbs ?? p.carbs,
          );
          await widget.store.updateProduct(updated);
          if (!mounted) return;
          setState(() => _updated++);
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('load_kbju_for_all').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text('$_done / $total',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Один результат верификации продукта ИИ для отображения в диалоге
class _VerifyProductItem {
  const _VerifyProductItem({required this.product, this.result});
  final Product product;
  final ProductVerificationResult? result;

  bool get hasAnySuggestion =>
      result != null &&
      (result!.suggestedPrice != null ||
          result!.suggestedCalories != null ||
          result!.suggestedProtein != null ||
          result!.suggestedFat != null ||
          result!.suggestedCarbs != null);
}

class _VerifyProductsProgressDialog extends StatefulWidget {
  const _VerifyProductsProgressDialog({
    required this.list,
    required this.store,
    required this.estId,
    required this.aiService,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final String estId;
  final AiService aiService;
  final LocalizationService loc;
  final void Function(List<_VerifyProductItem>) onComplete;
  final void Function(Object) onError;

  @override
  State<_VerifyProductsProgressDialog> createState() =>
      _VerifyProductsProgressDialogState();
}

class _VerifyProductsProgressDialogState
    extends State<_VerifyProductsProgressDialog> {
  int _done = 0;
  final List<_VerifyProductItem> _results = [];
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      try {
        final ep = widget.store.getEstablishmentPrice(p.id, widget.estId);
        final nutrition = (p.calories != null ||
                p.protein != null ||
                p.fat != null ||
                p.carbs != null)
            ? NutritionResult(
                calories: p.calories,
                protein: p.protein,
                fat: p.fat,
                carbs: p.carbs,
              )
            : null;
        final result = await widget.aiService.verifyProduct(
          p.getLocalizedName(widget.loc.currentLanguageCode),
          currentPrice: ep?.$1,
          currentNutrition: nutrition,
        );
        if (!mounted) return;
        _results.add(_VerifyProductItem(product: p, result: result));
      } catch (e) {
        if (!mounted) return;
        _results.add(_VerifyProductItem(product: p, result: null));
        widget.onError(e);
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
    widget.onComplete(List.from(_results));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('verify_with_ai').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '$_done / $total',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VerifyProductsResultsDialog extends StatelessWidget {
  const _VerifyProductsResultsDialog({
    required this.items,
    required this.store,
    required this.estId,
    required this.loc,
    required this.onApplied,
  });

  final List<_VerifyProductItem> items;
  final ProductStoreSupabase store;
  final String estId;
  final LocalizationService loc;
  final VoidCallback onApplied;

  Future<void> _applyOne(BuildContext context, _VerifyProductItem item) async {
    final p = item.product;
    final r = item.result!;
    Product updated = p;
    if (r.suggestedPrice != null) {
      await store.addToNomenclature(estId, p.id, price: r.suggestedPrice);
    }
    if (r.suggestedCalories != null ||
        r.suggestedProtein != null ||
        r.suggestedFat != null ||
        r.suggestedCarbs != null) {
      final saneCal = NutritionApiService.saneCaloriesForProduct(
        p.getLocalizedName(loc.currentLanguageCode),
        r.suggestedCalories,
      );
      updated = updated.copyWith(
        calories: saneCal ?? updated.calories,
        protein: r.suggestedProtein ?? updated.protein,
        fat: r.suggestedFat ?? updated.fat,
        carbs: r.suggestedCarbs ?? updated.carbs,
      );
    }
    await store.updateProduct(updated);
    if (context.mounted) onApplied();
  }

  Future<void> _applyAll(BuildContext context) async {
    for (final item in items) {
      if (item.result == null || !item.hasAnySuggestion) continue;
      final p = item.product;
      final r = item.result!;
      Product updated = p;
      if (r.suggestedPrice != null)
        await store.addToNomenclature(estId, p.id, price: r.suggestedPrice);
      if (r.suggestedCalories != null ||
          r.suggestedProtein != null ||
          r.suggestedFat != null ||
          r.suggestedCarbs != null) {
        final saneCal = NutritionApiService.saneCaloriesForProduct(
          p.getLocalizedName(loc.currentLanguageCode),
          r.suggestedCalories,
        );
        updated = updated.copyWith(
          calories: saneCal ?? updated.calories,
          protein: r.suggestedProtein ?? updated.protein,
          fat: r.suggestedFat ?? updated.fat,
          carbs: r.suggestedCarbs ?? updated.carbs,
        );
      }
      await store.updateProduct(updated);
    }
    if (context.mounted) onApplied();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(loc.t('verify_results')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t('verify_results_hint'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: items.length > 5 ? 320 : null,
              child: ListView.builder(
                shrinkWrap: items.length <= 5,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final p = item.product;
                  final r = item.result!;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.getLocalizedName(loc.currentLanguageCode),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (r.suggestedPrice != null) ...[
                            Builder(builder: (ctx) {
                              final ep =
                                  store.getEstablishmentPrice(p.id, estId);
                              final currentPrice = ep?.$1;
                              if (r.suggestedPrice == currentPrice)
                                return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                    '${loc.t('price')}: ${currentPrice != null ? NumberFormatUtils.formatDecimal(currentPrice) : '—'} → ${NumberFormatUtils.formatDecimal(r.suggestedPrice!)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              );
                            }),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonal(
                              onPressed: () => _applyOne(context, item),
                              child: Text(loc.t('apply')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.t('close'))),
        FilledButton(
          onPressed: () => _applyAll(context),
          child: Text(loc.t('apply_all')),
        ),
      ],
    );
  }
}

class _LoadTranslationsProgressDialog extends StatefulWidget {
  const _LoadTranslationsProgressDialog({
    required this.list,
    required this.store,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onComplete;
  final void Function(Object) onError;

  @override
  State<_LoadTranslationsProgressDialog> createState() =>
      _LoadTranslationsProgressDialogState();
}

class _LoadTranslationsProgressDialogState
    extends State<_LoadTranslationsProgressDialog> {
  int _done = 0;
  int _updated = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    for (final p in widget.list) {
      try {
        if ((p.name).trim().isEmpty) {
          setState(() => _done++);
          continue;
        }
        final result = await widget.store.translateProductAwait(p.id);
        if (result != null && result.length > (p.names?.length ?? 0)) {
          if (!mounted) return;
          setState(() => _updated++);
        }
      } catch (e) {
        widget.onError(e);
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _finished = true);
    if (widget.list.isNotEmpty && _updated == 0) {
      widget.onError(Exception(
          'Ни один перевод не получен. Проверьте интернет или попробуйте позже.'));
    }
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(
          widget.loc.t('translate_names_for_all').replaceAll('%s', '$total')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: _finished ? 1.0 : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text('$_done / $total',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CatalogTab extends StatelessWidget {
  const _CatalogTab({
    required this.products,
    required this.store,
    required this.estId,
    required this.loc,
    required this.sort,
    required this.filterManual,
    required this.filterGlutenFree,
    required this.filterLactoseFree,
    required this.onSortChanged,
    required this.onFilterManualChanged,
    required this.onFilterGlutenChanged,
    required this.onFilterLactoseChanged,
    required this.onRefresh,
    required this.onUpload,
    required this.onPaste,
    required this.onAddProduct,
  });

  final List<Product> products;
  final ProductStoreSupabase store;
  final String estId;
  final LocalizationService loc;
  final _CatalogSort sort;
  final bool filterManual;
  final bool filterGlutenFree;
  final bool filterLactoseFree;
  final void Function(_CatalogSort) onSortChanged;
  final void Function(bool) onFilterManualChanged;
  final void Function(bool) onFilterGlutenChanged;
  final void Function(bool) onFilterLactoseChanged;
  final VoidCallback onRefresh;
  final VoidCallback onUpload;
  final VoidCallback onPaste;
  final VoidCallback onAddProduct;

  String _categoryLabel(String c) {
    const map = {
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
      'misc': '',
      'manual': '',
      'imported': '',
    };
    return map[c] ?? c;
  }

  Future<void> _loadKbjuForAll(BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadKbjuProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  Future<void> _addAllToNomenclature(
      BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AddAllProgressDialog(
        list: list,
        store: store,
        estId: estId,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                  content: Text(loc
                      .t('add_all_done')
                      .replaceAll('%s', '${list.length}'))),
            );
          }
        },
        onError: (e) {
          Navigator.of(ctx).pop();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
  }

  bool _needsKbju(Product p) {
    if (p.kbjuManuallyConfirmed) return false;
    return (p.calories == null || p.calories == 0) &&
        p.protein == null &&
        p.fat == null &&
        p.carbs == null;
  }

  bool _needsTranslation(Product p) {
    final allLangs = LocalizationService.productLanguageCodes;
    final n = p.names;
    if (n == null || n.isEmpty) return true;
    if (allLangs.any((c) => (n[c] ?? '').trim().isEmpty)) return true;
    // Ручные продукты с одинаковым текстом во всех языках — не переведены
    if (p.category == 'manual') {
      final vals = allLangs
          .map((c) => (n[c] ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (vals.length <= 1) return true;
    }
    return false;
  }

  Future<void> _loadTranslationsForAll(
      BuildContext context, List<Product> list) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _LoadTranslationsProgressDialog(
        list: list,
        store: store,
        loc: loc,
        onComplete: () {
          Navigator.of(ctx).pop();
          onRefresh();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx)
                .showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(loc
                    .t('error_with_message')
                    .replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  static final Set<String> _triggeredTranslationIds = {};

  @override
  Widget build(BuildContext context) {
    final notInNom =
        products.where((p) => !store.isInNomenclature(p.id)).toList();
    final needsKbju = store.allProducts
        .where((p) => p.category == 'manual' && _needsKbju(p))
        .toList();
    final needsTranslation =
        store.allProducts.where(_needsTranslation).toList();
    // Фоновый автоперевод — один раз на продукт за сессию
    if (needsTranslation.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final p in needsTranslation) {
          if (p.name.trim().isEmpty) continue;
          if (_triggeredTranslationIds.add(p.id))
            store.triggerTranslation(p.id);
        }
      });
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: onPaste,
                tooltip: loc.t('paste_list_tooltip'),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file),
                onPressed: onUpload,
                tooltip: loc.t('upload_list_tooltip'),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: onAddProduct,
                tooltip: loc.t('add_product'),
              ),
              PopupMenuButton<_CatalogSort>(
                icon: const Icon(Icons.sort),
                tooltip: loc.t('inventory_sort_label'),
                onSelected: onSortChanged,
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: _CatalogSort.nameAz,
                      child: Text(loc.t('sort_name_az'))),
                  PopupMenuItem(
                      value: _CatalogSort.nameZa,
                      child: Text(loc.t('sort_name_za'))),
                  PopupMenuItem(
                      value: _CatalogSort.priceAsc,
                      child: Text(loc.t('sort_price_asc'))),
                  PopupMenuItem(
                      value: _CatalogSort.priceDesc,
                      child: Text(loc.t('sort_price_desc'))),
                ],
              ),
            ],
          ),
        ),
        if (notInNom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FilledButton.tonalIcon(
              onPressed: () => _addAllToNomenclature(context, notInNom),
              icon: const Icon(Icons.add_circle, size: 20),
              label: Text(loc
                  .t('add_all_to_nomenclature')
                  .replaceAll('%s', '${notInNom.length}')),
            ),
          ),
        Expanded(
          child: store.allProducts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Справочник пуст',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Загрузите список или вставьте текст (название + таб + цена).',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: onUpload,
                          icon: const Icon(Icons.upload_file),
                          label: Text(loc.t('upload_list')),
                        ),
                      ],
                    ),
                  ),
                )
              : products.isEmpty
                  ? Center(
                      child: Text(
                        'По запросу ничего не найдено',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.grey[600]),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: products.length,
                      itemBuilder: (_, i) {
                        final p = products[i];
                        final inNom = store.isInNomenclature(p.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: inNom
                                  ? Colors.green.shade100
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              child: Icon(
                                inNom ? Icons.check : Icons.add,
                                color: inNom
                                    ? Colors.green
                                    : Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                                p.getLocalizedName(loc.currentLanguageCode)),
                            subtitle: Text(
                              () {
                                final cat = _categoryLabel(p.category);
                                final unit = _unitDisplay(
                                  p.unit,
                                  loc.currentLanguageCode,
                                  unitSystem: context
                                      .read<UnitSystemPreferenceService>()
                                      .unitSystem,
                                );
                                return cat.isEmpty ? unit : '$cat · $unit';
                              }(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: loc.t('edit_product'),
                                  onPressed: () => _showEditProduct(context, p),
                                ),
                                if (inNom)
                                  Chip(
                                    label: Text(loc.t('nomenclature'),
                                        style: const TextStyle(fontSize: 11)),
                                  )
                                else
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _addToNomenclature(context, p),
                                    child: Text(loc.t('add_to_nomenclature')),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showEditProduct(BuildContext context, Product p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProductEditDialog(
        product: p,
        store: store,
        loc: loc,
        establishmentId: estId,
        onSaved: onRefresh,
      ),
    );
  }

  Future<void> _addToNomenclature(BuildContext context, Product p) async {
    try {
      final establishmentPrice = store.getEstablishmentPrice(p.id, estId);
      final price = establishmentPrice?.$1;
      await store.addToNomenclature(estId, p.id,
          price: price, currency: establishmentPrice?.$2);
      // Если продукт ещё не переведён — запускаем перевод фоново
      final names = p.names ?? {};
      final hasAllLangs = names['ru'] != null &&
          names['en'] != null &&
          names['ru'] != names['en'];
      if (!hasAllLangs) {
        store.triggerTranslation(p.id);
      }
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  Future<void> _fetchKbju(BuildContext context, Product p) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(SnackBar(content: Text(loc.t('kbju_searching'))));
    final result = await NutritionApiService.fetchNutrition(
        p.getLocalizedName(loc.currentLanguageCode));
    if (!context.mounted) return;
    if (result == null || !result.hasData) {
      scaffold.showSnackBar(SnackBar(content: Text(loc.t('kbju_not_found'))));
      return;
    }
    try {
      final updated = p.copyWith(
        calories: result.calories ?? p.calories,
        protein: result.protein ?? p.protein,
        fat: result.fat ?? p.fat,
        carbs: result.carbs ?? p.carbs,
        containsGluten: result.containsGluten ?? p.containsGluten,
        containsLactose: result.containsLactose ?? p.containsLactose,
      );
      await store.updateProduct(updated);
      onRefresh();
      var fmt = loc.t('kbju_result_format');
      fmt = fmt.replaceFirst('%s', '${result.calories?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.protein?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.fat?.round() ?? 0}');
      fmt = fmt.replaceFirst('%s', '${result.carbs?.round() ?? 0}');
      final msg = fmt;
      scaffold.showSnackBar(SnackBar(content: Text(msg)));
    } on DuplicateProductNameException {
      scaffold.showSnackBar(SnackBar(
          content: Text(loc.t('product_name_duplicate'))));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(
          content: Text(
              loc.t('error_with_message').replaceAll('%s', e.toString()))));
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// Карточка продукта — редактирование или создание (пустая карточка)
class _ProductEditDialog extends StatefulWidget {
  const _ProductEditDialog({
    required this.product,
    required this.store,
    required this.loc,
    this.establishmentId,
    required this.onSaved,
    this.isCreate = false,
  });

  final Product product;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final String? establishmentId;
  final bool isCreate;
  final VoidCallback onSaved;

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _packagePriceController;
  late final TextEditingController _packageWeightController;
  late final TextEditingController _gramsPerPieceController;
  bool _checkingName = false;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _wastePctController;
  late String _unit;
  late String _currency;
  late bool _containsGluten;
  late bool _containsLactose;
  late bool _kbjuManuallyConfirmed;
  // true = цена за упаковку (pkg), false = цена за кг/ед
  bool _priceByPackage = false;
  List<PriceHistoryEntry> _priceHistory = [];
  bool _priceHistoryLoaded = false;
  bool _switchingUnitSystem = false;

  String _unitSystemTitle(LocalizationService loc, bool imperial) {
    if (loc.currentLanguageCode == 'ru') {
      return imperial ? 'Система: US Imperial' : 'Система: Metric';
    }
    return imperial ? 'System: US Imperial' : 'System: Metric';
  }

  void _reformatWeightControllersForSystem({
    required UnitSystem from,
    required UnitSystem to,
  }) {
    final pkg = _parseNum(_packageWeightController.text);
    if (pkg != null && pkg > 0) {
      final canonical = UnitConverter.fromDisplay(
        displayValue: pkg,
        canonicalUnit: 'g',
        system: from,
      );
      final shown = UnitConverter.toDisplay(
        canonicalValue: canonical,
        canonicalUnit: 'g',
        system: to,
      ).value;
      _packageWeightController.text =
          UnitConverter.roundUi(shown, fractionDigits: to == UnitSystem.imperial ? 2 : 0)
              .toStringAsFixed(to == UnitSystem.imperial ? 2 : 0);
    }
    final gpp = _parseNum(_gramsPerPieceController.text);
    if (gpp != null && gpp > 0) {
      final canonical = UnitConverter.fromDisplay(
        displayValue: gpp,
        canonicalUnit: 'g',
        system: from,
      );
      final shown = UnitConverter.toDisplay(
        canonicalValue: canonical,
        canonicalUnit: 'g',
        system: to,
      ).value;
      _gramsPerPieceController.text =
          UnitConverter.roundUi(shown, fractionDigits: to == UnitSystem.imperial ? 2 : 0)
              .toStringAsFixed(to == UnitSystem.imperial ? 2 : 0);
    }
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(
        text: p.getLocalizedName(widget.loc.currentLanguageCode));
    double? initialPrice;
    if (widget.establishmentId != null && widget.establishmentId!.isNotEmpty) {
      final ep =
          widget.store.getEstablishmentPrice(p.id, widget.establishmentId);
      initialPrice = ep?.$1;
    }
    _priceController =
        TextEditingController(text: initialPrice?.toString() ?? '');
    // Инициализация полей упаковки
    _priceByPackage = p.packagePrice != null || p.packageWeightGrams != null;
    _packagePriceController =
        TextEditingController(text: p.packagePrice?.toString() ?? '');
    _packageWeightController = TextEditingController(
        text: p.packageWeightGrams?.toStringAsFixed(0) ?? '');
    _gramsPerPieceController =
        TextEditingController(text: p.gramsPerPiece?.toStringAsFixed(0) ?? '');
    // Подставить адекватные калории при открытии карточки
    final saneCal =
        NutritionApiService.saneCaloriesForProduct(p.name, p.calories);
    final initialCal = saneCal ?? p.calories;
    _caloriesController =
        TextEditingController(text: initialCal?.toString() ?? '');
    _proteinController =
        TextEditingController(text: p.protein?.toString() ?? '');
    _fatController = TextEditingController(text: p.fat?.toString() ?? '');
    _carbsController = TextEditingController(text: p.carbs?.toString() ?? '');
    _wastePctController = TextEditingController(
        text: p.primaryWastePct?.toStringAsFixed(1) ?? '0');
    final unitMap = {'кг': 'kg', 'г': 'g', 'шт': 'pcs', 'л': 'l', 'мл': 'ml'};
    _unit = unitMap[p.unit] ?? p.unit ?? 'g';
    if (!CulinaryUnits.all.any((e) => e.id == _unit)) _unit = 'g';
    _currency = p.currency ?? 'VND';
    _containsGluten = p.containsGluten ?? false;
    _containsLactose = p.containsLactose ?? false;
    _kbjuManuallyConfirmed = p.kbjuManuallyConfirmed;
    if (widget.establishmentId != null && widget.establishmentId!.isNotEmpty) {
      widget.store.getPriceHistory(p.id, widget.establishmentId!).then((list) {
        if (mounted)
          setState(() {
            _priceHistory = list;
            _priceHistoryLoaded = true;
          });
      });
    } else {
      _priceHistoryLoaded = true;
    }
    final unitPrefs = context.read<UnitSystemPreferenceService>();
    if (unitPrefs.isImperial) {
      _reformatWeightControllersForSystem(
        from: UnitSystem.metric,
        to: UnitSystem.imperial,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _packagePriceController.dispose();
    _packageWeightController.dispose();
    _gramsPerPieceController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _wastePctController.dispose();
    super.dispose();
  }

  /// Расчётная цена за кг из упаковки
  double? get _computedPricePerKg {
    final pkgPrice = _parseNum(_packagePriceController.text);
    final unitPrefs = context.read<UnitSystemPreferenceService>();
    final pkgWeightRaw = _parseNum(_packageWeightController.text);
    final pkgWeight = pkgWeightRaw == null
        ? null
        : UnitConverter.fromDisplay(
            displayValue: pkgWeightRaw,
            canonicalUnit: 'g',
            system: unitPrefs.unitSystem,
          );
    if (pkgPrice != null && pkgWeight != null && pkgWeight > 0) {
      return pkgPrice / pkgWeight * 1000.0;
    }
    return null;
  }

  double? _parseNum(String v) {
    final s = v.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  bool get _currencyFollowsEstablishment =>
      widget.establishmentId != null && widget.establishmentId!.isNotEmpty;

  String _currencyCodeForSave(AccountManagerSupabase acc) {
    if (_currencyFollowsEstablishment) {
      return (acc.establishment?.defaultCurrency ?? _currency).toUpperCase();
    }
    return _currency.toUpperCase();
  }

  Future<void> _openEstablishmentCurrencyPicker() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    await showEstablishmentCurrencyPickerDialog(
      context: context,
      loc: widget.loc,
      currentCode: est.defaultCurrency,
      onApply: (code) async {
        final updated = est.copyWith(
          defaultCurrency: code,
          updatedAt: DateTime.now(),
        );
        try {
          await account.updateEstablishment(updated);
          await widget.store.syncEstablishmentNomenclatureCurrency(
            updated.productsEstablishmentId,
            updated.defaultCurrency,
          );
          if (mounted) setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(widget.loc.t('currency_saved'))),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  widget.loc.t(
                    'nomenclature_save_error',
                    args: {'error': '$e'},
                  ),
                ),
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildCurrencyControl(AccountManagerSupabase account) {
    if (_currencyFollowsEstablishment) {
      final code = account.establishment?.defaultCurrency ?? _currency;
      final preset = EstablishmentCurrencyOptions.presetForCode(code);
      return InkWell(
        onTap: _openEstablishmentCurrencyPicker,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.loc.t('currency'),
            border: const OutlineInputBorder(),
          ),
          child: Row(
            children: [
              Text(
                preset?['symbol'] ?? '',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset != null
                      ? '${preset['code']} — ${preset['name']}'
                      : code.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      );
    }
    final known = EstablishmentCurrencyOptions.isKnownPreset(_currency);
    final v = _currency.toUpperCase();
    return DropdownButtonFormField<String>(
      value: v,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: widget.loc.t('currency'),
        border: const OutlineInputBorder(),
      ),
      items: [
        ...EstablishmentCurrencyOptions.all.map(
          (c) => DropdownMenuItem(
            value: c['code']!,
            child: Row(
              children: [
                Text(c['symbol']!, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${c['code']} — ${c['name']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!known)
          DropdownMenuItem(
            value: v,
            child: Text(v),
          ),
      ],
      onChanged: (nv) => setState(() => _currency = nv ?? _currency),
    );
  }

  /// ИИ проверяет название на опечатки — подсказка только в тексте, название не меняем автоматически.
  Future<void> _checkNameWithAi() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _checkingName = true);
    try {
      final ai = context.read<AiService>();
      final result = await ai.recognizeProduct(name);
      if (!mounted) return;
      if (result != null && result.normalizedName != name) {
        final text = widget.loc
            .t('ai_name_suggestion_only')
            .replaceAll('%s', result.normalizedName);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
        if (result.suggestedUnit != null &&
            CulinaryUnits.all.any((e) => e.id == result.suggestedUnit)) {
          setState(() => _unit = result.suggestedUnit!);
        }
      } else if (result != null && result.normalizedName == name && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(widget.loc.t('ai_name_ok'))),
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _checkingName = false);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.loc.t('product_name_required'))));
      return;
    }
    double? calories = _parseNum(_caloriesController.text);
    double? protein = _parseNum(_proteinController.text);
    double? fat = _parseNum(_fatController.text);
    double? carbs = _parseNum(_carbsController.text);
    bool containsGluten = _containsGluten;
    bool containsLactose = _containsLactose;

    // КБЖУ подгружаются в фоне (NutritionBackfillService)
    final curLang = widget.loc.currentLanguageCode;
    final allLangs = LocalizationService.productLanguageCodes;
    final merged = Map<String, String>.from(widget.product.names ?? {});
    merged[curLang] = name;
    for (final c in allLangs) {
      merged.putIfAbsent(c, () => name);
    }
    // Цена за кг: если включён режим упаковки — рассчитываем из packagePrice/packageWeight
    final double? pricePerKg = _priceByPackage
        ? _computedPricePerKg
        : _parseNum(_priceController.text);
    final double? pkgPrice =
        _priceByPackage ? _parseNum(_packagePriceController.text) : null;
    final unitPrefs = context.read<UnitSystemPreferenceService>();
    final pkgWeightInput =
        _priceByPackage ? _parseNum(_packageWeightController.text) : null;
    final double? pkgWeight = pkgWeightInput == null
        ? null
        : UnitConverter.fromDisplay(
            displayValue: pkgWeightInput,
            canonicalUnit: 'g',
            system: unitPrefs.unitSystem,
          );

    final gppInput = CulinaryUnits.isCountable(_unit)
        ? _parseNum(_gramsPerPieceController.text)
        : null;
    final gpp = gppInput == null
        ? null
        : UnitConverter.fromDisplay(
            displayValue: gppInput,
            canonicalUnit: 'g',
            system: unitPrefs.unitSystem,
          );
    final acc = context.read<AccountManagerSupabase>();
    final currencyCode = _currencyCodeForSave(acc);
    final updated = widget.product.copyWith(
      name: name,
      names: merged,
      currency: currencyCode,
      packagePrice: pkgPrice,
      clearPackagePrice: !_priceByPackage,
      packageWeightGrams: pkgWeight,
      clearPackageWeight: !_priceByPackage,
      gramsPerPiece: gpp,
      clearGramsPerPiece: !CulinaryUnits.isCountable(_unit),
      unit: _unit,
      primaryWastePct: _parseNum(_wastePctController.text)?.clamp(0.0, 99.9),
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      kbjuManuallyConfirmed: _kbjuManuallyConfirmed,
      containsGluten: containsGluten,
      containsLactose: containsLactose,
    );
    try {
      if (widget.isCreate) {
        final savedUpdated = await widget.store.addProduct(updated);
        if (widget.establishmentId != null &&
            widget.establishmentId!.isNotEmpty) {
          await widget.store.addToNomenclature(
            widget.establishmentId!,
            savedUpdated.id,
            price: pricePerKg,
            currency: currencyCode,
          );
        }
      } else {
        await widget.store.updateProduct(updated);
        if (widget.establishmentId != null &&
            widget.establishmentId!.isNotEmpty) {
          if (pricePerKg != null) {
            await widget.store.setEstablishmentPrice(
              widget.establishmentId!,
              widget.product.id,
              pricePerKg,
              currencyCode,
            );
          }
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.loc
              .t(widget.isCreate ? 'product_added' : 'product_saved'))));
    } on DuplicateProductNameException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(widget.loc.t('product_name_duplicate'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(widget.loc
                .t('error_with_message')
                .replaceAll('%s', e.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountManagerSupabase>();
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final isImperial = unitPrefs.isImperial;
    final gLabel = UnitConverter.displayUnitLabel(
      'g',
      widget.loc.currentLanguageCode,
      unitPrefs.unitSystem,
    );
    final lang = widget.loc.currentLanguageCode;
    final priceDisplayCode = _currencyFollowsEstablishment
        ? (account.establishment?.defaultCurrency ?? _currency)
        : _currency;
    final priceDisplayPreset =
        EstablishmentCurrencyOptions.presetForCode(priceDisplayCode);
    final priceSuffix =
        priceDisplayPreset?['symbol'] ?? priceDisplayCode.toUpperCase();
    return AlertDialog(
      title: Text(
          widget.loc.t(widget.isCreate ? 'add_from_catalog' : 'edit_product')),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('product_name'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: _checkingName
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 20),
                    tooltip: widget.loc.t('ai_product_recognize'),
                    onPressed: _checkingName ? null : _checkNameWithAi,
                  ),
                ),
                onFieldSubmitted: (_) => _checkNameWithAi(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _unit,
                decoration: InputDecoration(
                  labelText: widget.loc.t('unit'),
                  border: const OutlineInputBorder(),
                ),
                items: CulinaryUnits.all
                    .map((e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(lang == 'ru' ? e.ru : e.en),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_unitSystemTitle(widget.loc, isImperial)),
                subtitle: Text(
                  widget.loc.currentLanguageCode == 'ru'
                      ? 'Весовые поля в этой форме: ${isImperial ? 'US Imperial' : 'Metric'}'
                      : 'Weight fields in this form: ${isImperial ? 'US Imperial' : 'Metric'}',
                ),
                value: isImperial,
                onChanged: _switchingUnitSystem
                    ? null
                    : (v) async {
                        final from = unitPrefs.unitSystem;
                        final to = v ? UnitSystem.imperial : UnitSystem.metric;
                        if (from == to) return;
                        setState(() => _switchingUnitSystem = true);
                        _reformatWeightControllersForSystem(from: from, to: to);
                        await unitPrefs.setUnitSystem(to);
                        if (mounted) setState(() => _switchingUnitSystem = false);
                      },
              ),
              if (CulinaryUnits.isCountable(_unit)) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gramsPerPieceController,
                  decoration: InputDecoration(
                    labelText: '${widget.loc.t('grams_per_piece_label')} ($gLabel)',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              const SizedBox(height: 16),
              // КБЖУ и подтягивание из Open Food Facts
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.loc.t('kbju_per_100g'),
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _caloriesController,
                                decoration: InputDecoration(
                                  labelText:
                                      widget.loc.t('ttk_calories'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _proteinController,
                                decoration: InputDecoration(
                                  labelText:
                                      widget.loc.t('ttk_protein'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _fatController,
                                decoration: InputDecoration(
                                  labelText: widget.loc.t('ttk_fat'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _carbsController,
                                decoration: InputDecoration(
                                  labelText:
                                      widget.loc.t('ttk_carbs'),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(widget.loc.t('product_kbju_confirmed')),
                value: _kbjuManuallyConfirmed,
                onChanged: (v) => setState(() => _kbjuManuallyConfirmed = v),
              ),
              const SizedBox(height: 16),
              // Переключатель: цена за кг/ед vs цена за упаковку
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(widget.loc.t('price_per_unit_label')),
                          icon: const Icon(Icons.scale_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(widget.loc.t('price_per_package_label')),
                          icon:
                              const Icon(Icons.inventory_2_outlined, size: 16),
                        ),
                      ],
                      selected: {_priceByPackage},
                      onSelectionChanged: (s) =>
                          setState(() => _priceByPackage = s.first),
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.compact),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_priceByPackage) ...[
                // Режим: цена за единицу (кг/шт)
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _priceController,
                        decoration: InputDecoration(
                          labelText: widget.loc.t('price'),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildCurrencyControl(account)),
                  ],
                ),
              ] else ...[
                // Режим: цена за упаковку (шт)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _packagePriceController,
                        decoration: InputDecoration(
                          labelText: widget.loc.t('package_price_label'),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _packageWeightController,
                        decoration: InputDecoration(
                          labelText: '${widget.loc.t('package_weight_label')} ($gLabel)',
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildCurrencyControl(account)),
                  ],
                ),
                // Показываем расчётную цену за кг
                if (_computedPricePerKg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${widget.loc.t('price_per_kg_computed')}: ${_computedPricePerKg!.toStringAsFixed(2)} $priceSuffix',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
              if (widget.establishmentId != null &&
                  widget.establishmentId!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(widget.loc.t('price_history'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (!_priceHistoryLoaded)
                  const SizedBox(
                      height: 24,
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_priceHistory.isEmpty)
                  Text(
                    widget.loc.t('price_history_empty'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                else
                  ..._priceHistory.take(10).map((e) {
                    final oldStr = e.oldPrice != null
                        ? e.oldPrice!.toStringAsFixed(0)
                        : '—';
                    final newStr = e.newPrice != null
                        ? e.newPrice!.toStringAsFixed(0)
                        : '—';
                    final dateStr = e.changedAt != null
                        ? '${e.changedAt!.day.toString().padLeft(2, '0')}.${e.changedAt!.month.toString().padLeft(2, '0')}.${e.changedAt!.year}'
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '$oldStr → $newStr ${Establishment.currencySymbolFor(e.currency ?? context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND')} ($dateStr)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.loc.t('cancel'))),
        FilledButton(onPressed: _save, child: Text(widget.loc.t('save'))),
      ],
    );
  }
}

class _NomenclatureSkeletonItem extends StatelessWidget {
  const _NomenclatureSkeletonItem();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Аватар с номером
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            // Текстовая часть
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Название
                  Container(
                    height: 16,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Подзаголовок
                  Container(
                    height: 14,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            // Кнопки действий
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Подтверждение очистки всей номенклатуры
  Future<void> _confirmClearAllNomenclature(
      BuildContext context, LocalizationService loc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('nomenclature_clear_all_dialog_title')),
        content: Text(loc.t('nomenclature_clear_all_dialog_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.t('delete_all_btn')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final store = context.read<ProductStoreSupabase>();
        final account = context.read<AccountManagerSupabase>();
        final estId = account.dataEstablishmentId;

        if (estId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('establishment_not_found'))),
          );
          return;
        }

        final count = store.getNomenclatureProducts(estId).length;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => LongOperationProgressDialog(
            message: loc.t('clear_nomenclature_progress'),
            hint: null,
            productCount: count > 0 ? count : null,
          ),
        );

        // Очищаем номенклатуру (с таймаутом, чтобы не зависать навсегда)
        await store.clearAllNomenclature(estId).timeout(
              const Duration(minutes: 2),
              onTimeout: () => throw TimeoutException(
                loc.t('clear_nomenclature_timeout'),
              ),
            );

        if (context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }

        // Показываем успех
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('clear_nomenclature_done')),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (context.mounted) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        }
        final message = e is TimeoutException
            ? (e.message ?? loc.t('clear_nomenclature_timeout'))
            : loc.t('nomenclature_clear_failed', args: {'error': '$e'});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Вкладка iiko-номенклатуры в экране номенклатуры.
class _IikoNomenclatureTab extends StatefulWidget {
  const _IikoNomenclatureTab({
    required this.store,
    required this.establishmentId,
    required this.onUpload,
  });

  final IikoProductStore store;
  final String establishmentId;
  final VoidCallback onUpload;

  @override
  State<_IikoNomenclatureTab> createState() => _IikoNomenclatureTabState();
}

class _IikoNomenclatureTabState extends State<_IikoNomenclatureTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _query = '';
  String? _selectedSheet; // null = первая вкладка / нет разделения

  /// Проверяет, является ли строка заголовком таблицы (шапкой), а не товаром.
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

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.establishmentId.isNotEmpty) {
        widget.store.loadProducts(widget.establishmentId);
        // Восстанавливаем sheetNames из localStorage/сервера чтобы вкладки появились
        widget.store
            .restoreBlankFromStorage(establishmentId: widget.establishmentId);
      }
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final loc = context.read<LocalizationService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('nomenclature_delete_all_iiko_title')),
        content: Text(loc.t('nomenclature_delete_all_iiko_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.store.deleteAll(widget.establishmentId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('nomenclature_iiko_products_deleted'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('product_upload_error_generic',
                args: {'error': '$e'})),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loc = context.watch<LocalizationService>();
    final products = widget.store.products;

    if (widget.store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(loc.t('nomenclature_iiko_empty_title'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text(loc.t('nomenclature_iiko_empty_subtitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[500])),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: Text(loc.t('nomenclature_upload_iiko_blank_button')),
              onPressed: widget.onUpload,
            ),
          ],
        ),
      );
    }

    // Сортируем по sort_order чтобы порядок совпадал с оригинальным файлом
    // Исключаем строки-заголовки и пустые имена (могут попасть из шапки Excel)
    final sorted = [...products]
      ..removeWhere((p) =>
          p.name.trim().isEmpty ||
          _IikoNomenclatureTabState._isIikoHeaderRow(p.name))
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Листы бланка
    final sheetNames = widget.store.sheetNames;
    final hasSheets = sheetNames.length > 1;

    // Если выбранный лист больше не существует — сбросим
    final activeSheet = (hasSheets && sheetNames.contains(_selectedSheet))
        ? _selectedSheet
        : (hasSheets ? sheetNames.first : null);

    // Фильтрация по листу и запросу
    // Продукты без sheetName (старые данные) показываем на первом листе
    var bySheet = (hasSheets && activeSheet != null)
        ? sorted.where((p) {
            final sn = p.sheetName;
            if (sn == null || sn.isEmpty)
              return activeSheet == sheetNames.first;
            return sn == activeSheet;
          }).toList()
        : sorted;
    final filtered = _query.isEmpty
        ? bySheet
        : bySheet
            .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Строим плоский список строк для ListView — чередуем группы и товары
    // Структура: _IikoBlankRow (строка бланка) с данными о том, первая ли строка группы
    final rows = <_IikoBlankRow>[];
    String? lastGroup;
    for (final p in filtered) {
      final g = p.groupName ?? '';
      final isFirstInGroup = g != lastGroup;
      lastGroup = g;
      rows.add(_IikoBlankRow(product: p, isFirstInGroup: isFirstInGroup));
    }

    // Считаем сколько товаров в каждой группе (для rowspan-эффекта)
    final groupCounts = <String, int>{};
    for (final p in filtered) {
      groupCounts[p.groupName ?? ''] =
          (groupCounts[p.groupName ?? ''] ?? 0) + 1;
    }

    return Column(
      children: [
        // ── Вкладки листов (если > 1 листа) ──
        if (hasSheets)
          _SheetTabBar(
            sheetNames: sheetNames,
            selected: activeSheet ?? sheetNames.first,
            onSelect: (s) => setState(() => _selectedSheet = s),
          ),

        // ── Тулбар ──
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: loc.t('nomenclature_search_by_name_hint'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: loc.t('nomenclature_upload_new_blank_tooltip'),
                onPressed: widget.onUpload,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: loc.t('refresh'),
                onPressed: () => widget.store
                    .loadProducts(widget.establishmentId, force: true),
              ),
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined, color: Colors.red[400]),
                tooltip: loc.t('nomenclature_delete_all_tooltip'),
                onPressed: () => _confirmDeleteAll(context),
              ),
            ],
          ),
        ),

        // ── Заголовок «N позиций» ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                loc.t(
                  'nomenclature_positions_count',
                  args: {'count': '${products.length}'},
                ),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ),
        ),

        // ── Шапка + таблица строк со скроллом по горизонтали ──
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _IikoBlankaHeader(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) {
                        final row = rows[i];
                        final groupCount =
                            groupCounts[row.product.groupName ?? ''] ?? 1;
                        return _IikoBlankaRowWidget(
                          row: row,
                          groupCount: groupCount,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Переключатель вкладок листов Excel (горизонтальный скролл)
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

/// Данные одной строки бланка
class _IikoBlankRow {
  final IikoProduct product;
  final bool isFirstInGroup; // нужно ли показывать ячейку группы
  const _IikoBlankRow({required this.product, required this.isFirstInGroup});
}

/// Шапка таблицы: Группа | Код | Наименование | Ед. изм. | Остаток фактический
// ── Константы ширин колонок (как в Excel бланке) ──────────────────────────────
// Группа=110, Код=60, Наименование=300, Ед.изм.=52, Остаток=90
// Итого минимальная ширина таблицы: 612px → горизонтальный скролл на узких экранах
const double _colGroup = 110;
const double _colCode = 60;
const double _colName = 300;
const double _colUnit = 52;
const double _colQty = 90;
const double _tableWidth = _colGroup + _colCode + _colName + _colUnit + _colQty;

class _IikoBlankaHeader extends StatelessWidget {
  const _IikoBlankaHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest;
    final border = BorderSide(color: theme.dividerColor);
    final style = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface);

    Widget cell(String text, double width) => Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            border: Border(right: border, bottom: border),
          ),
          child: Text(text, style: style, textAlign: TextAlign.center),
        );

    return Container(
      width: _tableWidth,
      decoration: BoxDecoration(
        border: Border(top: border, left: border),
        color: bg,
      ),
      child: Row(
        children: [
          cell('Группа', _colGroup),
          cell('Код', _colCode),
          cell('Наименование', _colName),
          cell('Ед.\nизм.', _colUnit),
          cell('Остаток\nфактический', _colQty),
        ],
      ),
    );
  }
}

/// Одна строка бланка — фиксированные ширины как в Excel
class _IikoBlankaRowWidget extends StatelessWidget {
  const _IikoBlankaRowWidget({required this.row, required this.groupCount});

  final _IikoBlankRow row;
  final int groupCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderSide(color: theme.dividerColor);

    Widget cell(Widget child, double width, {Color? bg}) => Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border(right: border, bottom: border),
          ),
          child: child,
        );

    final textColor = theme.colorScheme.onSurface;
    final subtleColor = theme.colorScheme.onSurface.withOpacity(0.55);
    final groupBg = theme.colorScheme.primaryContainer.withOpacity(0.18);

    return Container(
      width: _tableWidth,
      decoration: BoxDecoration(border: Border(left: border)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cell(
              row.isFirstInGroup
                  ? Text(row.product.groupName ?? '',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary))
                  : const SizedBox.shrink(),
              _colGroup,
              bg: groupBg,
            ),
            cell(
              Text(row.product.code ?? '',
                  style: TextStyle(fontSize: 11, color: subtleColor),
                  textAlign: TextAlign.center),
              _colCode,
            ),
            cell(
              Text(row.product.name,
                  style: TextStyle(fontSize: 12, color: textColor)),
              _colName,
            ),
            cell(
              Text(row.product.unit ?? '',
                  style: TextStyle(fontSize: 12, color: textColor),
                  textAlign: TextAlign.center),
              _colUnit,
            ),
            cell(const SizedBox.shrink(), _colQty),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Диалог ручного выбора столбца «Фактический остаток»
// Показывается только когда авто-определение не нашло нужный столбец.
// ════════════════════════════════════════════════════════════════════════════
class _QtyColumnPickerDialog extends StatefulWidget {
  final String sheetName;
  final List<String> headerRow;
  final List<List<String>> previewRows;
  final int maxCols;

  const _QtyColumnPickerDialog({
    required this.sheetName,
    required this.headerRow,
    required this.previewRows,
    required this.maxCols,
  });

  @override
  State<_QtyColumnPickerDialog> createState() => _QtyColumnPickerDialogState();
}

class _QtyColumnPickerDialogState extends State<_QtyColumnPickerDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final cols = widget.maxCols;

    // Буква столбца (A, B, C…)
    String colLetter(int i) {
      var n = i + 1;
      var s = '';
      while (n > 0) {
        n--;
        s = String.fromCharCode(65 + n % 26) + s;
        n ~/= 26;
      }
      return s;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок
              Row(children: [
                Icon(Icons.table_chart_outlined,
                    color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc.t('nomenclature_qty_column_title'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (widget.sheetName.isNotEmpty)
                        Text(
                            loc.t('nomenclature_sheet_label',
                                args: {'name': widget.sheetName}),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.55))),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                loc.t('nomenclature_qty_column_help'),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65)),
              ),
              const SizedBox(height: 14),

              // Превью таблицы
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Кнопки выбора столбца
                      Row(
                        children: List.generate(cols, (c) {
                          final isSelected = _selected == c;
                          return GestureDetector(
                            onTap: () => setState(() => _selected = c),
                            child: Container(
                              width: 80,
                              height: 32,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceVariant,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6)),
                                border: Border.all(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outline
                                          .withOpacity(0.3),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  colLetter(c),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? theme.colorScheme.onPrimary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      // Заголовок бланка
                      _buildPreviewRow(
                        context,
                        widget.headerRow,
                        cols,
                        isHeader: true,
                      ),
                      // Строки данных
                      ...widget.previewRows
                          .map((row) => _buildPreviewRow(context, row, cols)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Кнопки действий
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: Text(loc.t('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: Text(loc.t('confirm_btn')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewRow(
    BuildContext context,
    List<String> cells,
    int maxCols, {
    bool isHeader = false,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(maxCols, (c) {
        final isSelected = _selected == c;
        final text = c < cells.length ? cells[c] : '';
        return GestureDetector(
          onTap: () => setState(() => _selected = c),
          child: Container(
            width: 80,
            height: isHeader ? 36 : 28,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withOpacity(0.12)
                  : isHeader
                      ? theme.colorScheme.surfaceVariant.withOpacity(0.6)
                      : theme.colorScheme.surface,
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.5)
                    : theme.colorScheme.outline.withOpacity(0.2),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isHeader ? 10 : 11,
                  fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
