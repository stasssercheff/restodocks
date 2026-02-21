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
import '../services/ai_service.dart';
import '../services/ai_service_supabase.dart';
import '../services/order_list_storage_service.dart';
import '../services/excel_export_service.dart';
import '../services/domain_validation_service.dart';
import '../services/translation_service.dart';

/// Экран номенклатуры: продукты и ПФ заведения с ценами
class NomenclatureScreen extends StatefulWidget {
  const NomenclatureScreen({super.key});

  @override
  State<NomenclatureScreen> createState() => _NomenclatureScreenState();
}

enum _CatalogSort { nameAz, nameZa, priceAsc, priceDesc }
enum _NomenclatureFilter { all, products, semiFinished }

/// Единица измерения для отображения в номенклатуре.
String _unitDisplay(String? unit, String lang) {
  return CulinaryUnits.displayName((unit ?? 'g').trim().toLowerCase(), lang);
}

/// Единица для отображения цены: цена всегда за кг (для веса) или за шт (для штучных), не за грамм.
String _priceUnitDisplay(String? unit, String lang) {
  final u = (unit ?? 'g').trim().toLowerCase();
  if (u == 'pcs' || u == 'шт' || u == 'piece' || u == 'штука') {
    return lang == 'ru' ? 'шт' : 'pcs';
  }
  if (u == 'ml' || u == 'мл' || u == 'l' || u == 'л') {
    return lang == 'ru' ? 'л' : 'L';
  }
  return lang == 'ru' ? 'кг' : 'kg';
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
    final estId = account.establishment?.id;

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
          print('AI verification failed for "${item.name}": $aiError');
          verification = null;
        }

        // Используем проверенные ИИ данные или оригинальные
        final normalizedName = verification?.normalizedName ?? item.name;
        var names = <String, String>{for (final c in allLangs) c: normalizedName};

        // Для больших списков переводим только если ИИ дал нормализованное имя
        if (widget.items.length > 5 && verification?.normalizedName != null && verification!.normalizedName != item.name) {
          // Переводим на все языки
          for (final lang in allLangs) {
            if (lang == sourceLang) continue;
            final translated = await translationService.translate(
              entityType: TranslationEntityType.product,
              entityId: item.name,
              fieldName: 'name',
              text: normalizedName,
              from: sourceLang,
              to: lang,
            );
            if (translated != null && translated.trim().isNotEmpty) {
              names[lang] = translated.trim();
            }
          }
        }

        final product = Product(
          id: const Uuid().v4(),
          name: normalizedName,
          category: verification?.suggestedCategory ?? 'manual',
          names: names,
          calories: verification?.suggestedCalories,
          protein: null,
          fat: null,
          carbs: null,
          unit: verification?.suggestedUnit ?? 'g',
          basePrice: verification?.suggestedPrice ?? item.price,
          currency: (verification?.suggestedPrice ?? item.price) != null ? defCur : null,
        );

          try {
            await store.addProduct(product);
          } catch (e) {
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              // Продукт уже существует, просто добавляем в номенклатуру
              // Сначала попробуем найти продукт по имени
              try {
                final supabaseClient = Supabase.instance.client;
                final existingProducts = await supabaseClient
                    .from('products')
                    .select('id')
                    .eq('name', product.name)
                    .limit(1);

                if (existingProducts.isNotEmpty) {
                  final existingId = existingProducts[0]['id'] as String;
                  await store.addToNomenclature(estId, existingId, price: item.price);
                  setState(() => _skipped++);
                  continue;
                }
              } catch (findError) {
                print('Failed to find existing product "${product.name}": $findError');
              }
            }
            // Другая ошибка
            print('Failed to add product "${product.name}": $e');
            setState(() => _failed++);
            continue;
          }

          try {
            await store.addToNomenclature(estId, product.id, price: product.basePrice, currency: product.currency);
          } catch (e) {
            // Возможно продукт уже в номенклатуре - считаем это успехом
            if (e.toString().contains('duplicate key') ||
                e.toString().contains('already exists') ||
                e.toString().contains('unique constraint')) {
              setState(() => _skipped++);
              continue;
            }
            // Другая ошибка
            print('Failed to add to nomenclature "${product.name}": $e');
            setState(() => _failed++);
            continue;
          }

          setState(() => _added++);

          // Небольшая задержка чтобы не перегружать сервер
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          print('Unexpected error for "${item.name}": $e');
          setState(() => _failed++);
        }
    }

    setState(() => _isCompleted = true);

    // Автоматически закрываем диалог через 2 секунды
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pop();

        final msg = _failed == 0
            ? widget.loc.t('upload_added').replaceAll('%s', '${_added + _skipped}')
            : '${widget.loc.t('upload_added').replaceAll('%s', '${_added + _skipped}')}. ${widget.loc.t('upload_failed').replaceAll('%s', '$_failed')}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.items.isEmpty ? 1.0 : _processed / widget.items.length;

    return AlertDialog(
      title: Text('ИИ обрабатывает продукты'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Обработано $_processed из ${widget.items.length} продуктов'),
          const SizedBox(height: 8),
          Text('ИИ проверяет названия, категории и цены...', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
            Text('Добавлено: $_added${_skipped > 0 ? ', Пропущено: $_skipped' : ''}${_failed > 0 ? ', Ошибок: $_failed' : ''}'),
          if (_isCompleted) ...[
            const SizedBox(height: 16),
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            const Text('Все продукты успешно добавлены!'),
          ],
        ],
      ),
      actions: _isCompleted
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть'),
              ),
            ]
          : null,
    );
  }
}

class _NomenclatureScreenState extends State<NomenclatureScreen> {
  String _query = '';
  String? _category;
  // Фильтры номенклатуры
  _CatalogSort _nomSort = _CatalogSort.nameAz;
  _NomenclatureFilter _nomFilter = _NomenclatureFilter.all;

  // Список элементов номенклатуры (продукты + ТТК ПФ)
  List<NomenclatureItem> _nomenclatureItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  Future<void> _ensureLoaded() async {
    print('📋 NomenclatureScreen: Starting _ensureLoaded...');
    final store = context.read<ProductStoreSupabase>();
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    print('📋 NomenclatureScreen: Establishment ID: $estId');

    if (estId == null) {
      print('📋 NomenclatureScreen: No establishment ID, returning');
      return;
    }

    final techCardService = context.read<TechCardServiceSupabase>();

    if (store.allProducts.isEmpty && !store.isLoading) {
      print('📋 NomenclatureScreen: Loading products...');
      await store.loadProducts();
      print('📋 NomenclatureScreen: Products loaded: ${store.allProducts.length}');
    }

    print('📋 NomenclatureScreen: Loading nomenclature...');
    await store.loadNomenclature(estId);

    // Загружаем элементы номенклатуры (продукты + ТТК ПФ)
    print('📋 NomenclatureScreen: Loading nomenclature items...');
    _nomenclatureItems = await store.getAllNomenclatureItems(estId, techCardService);
    print('📋 NomenclatureScreen: Nomenclature items loaded: ${_nomenclatureItems.length}');

    if (mounted) {
      setState(() => _isLoading = false);
      print('📋 NomenclatureScreen: UI updated, isLoading = false');
    }
  }

  Future<void> _showDuplicates() async {
    final loc = context.read<LocalizationService>();
    final products = _nomenclatureItems
        .where((i) => i.isProduct)
        .map((i) => (id: i.id, name: i.getLocalizedName(loc.currentLanguageCode)))
        .toList();

    if (products.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('duplicates_need_more') ?? 'Нужно минимум 2 продукта для поиска дубликатов')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final ai = context.read<AiService>();
      final groups = await ai.findDuplicates(products);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (groups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('duplicates_none') ?? 'Похожих дубликатов не найдено')),
        );
        return;
      }

      final idToItem = {for (final i in _nomenclatureItems) i.id: i};
      final duplicateGroups = groups.map((ids) => ids.map((id) => idToItem[id]).whereType<NomenclatureItem>().toList()).where((g) => g.length >= 2).toList();

      if (duplicateGroups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('duplicates_none') ?? 'Похожих дубликатов не найдено')),
        );
        return;
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => _DuplicatesDialog(
          groups: duplicateGroups,
          loc: loc,
          onRemove: (idsToRemove) async {
            final store = context.read<ProductStoreSupabase>();
            final estId = context.read<AccountManagerSupabase>().establishment?.id;
            if (estId == null) return;
            for (final id in idsToRemove) {
              final item = idToItem[id];
              if (item?.isProduct == true) {
                await store.removeFromNomenclature(estId, id);
              }
            }
            await _ensureLoaded();
            if (mounted) setState(() {});
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('error') ?? 'Ошибка'}: $e')),
        );
      }
    }
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

  void _showEditProductForNomenclature(BuildContext context, Product p, ProductStoreSupabase store, LocalizationService loc, VoidCallback onRefresh, String estId) {
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

  Future<void> _confirmRemoveForNomenclature(BuildContext context, Product p, ProductStoreSupabase store, LocalizationService loc, VoidCallback onRefresh, String estId) async {
    // Проверяем, используется ли продукт в ТТК — блокируем удаление из номенклатуры
    try {
      final techCardService = context.read<TechCardServiceSupabase>();
      final allTechCards = await techCardService.getAllTechCards();
      for (final tc in allTechCards) {
        if (tc.ingredients.any((ing) => ing.productId == p.id)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Невозможно удалить: продукт используется в ТТК "${tc.dishName}"')),
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
          loc.t('remove_from_nomenclature_confirm').replaceAll('%s', p.getLocalizedName(loc.currentLanguageCode)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.t('cancel'))),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  String _buildProductSubtitle(BuildContext context, Product p, ProductStoreSupabase store, String estId, LocalizationService loc) {
    final loc = context.read<LocalizationService>();
    final establishmentPrice = store.getEstablishmentPrice(p.id, estId);
    final price = establishmentPrice?.$1 ?? p.basePrice;
    final currency = establishmentPrice?.$2 ?? 'RUB';

    final priceText = price != null ? '${price.toStringAsFixed(0)} ₽/${_priceUnitDisplay(p.unit, loc.currentLanguageCode)}' : 'Цена не установлена';

    // Проверяем подписку для отображения КБЖУ
    final account = context.read<AccountManagerSupabase>();
    final hasPro = account.currentEmployee?.hasProSubscription ?? false;

    if (!hasPro) {
      // Без PRO подписки показываем только категорию и цену
      return (p.category == 'misc' || p.category == 'manual')
          ? '$priceText'
          : '${_categoryLabel(p.category)} · $priceText';
    }

    // С PRO подпиской показываем КБЖУ
    return (p.category == 'misc' || p.category == 'manual')
        ? '${p.calories?.round() ?? 0} ккал · $priceText'
        : '${_categoryLabel(p.category)} · ${p.calories?.round() ?? 0} ккал · $priceText';
  }

  String _buildTechCardSubtitle(TechCard tc) {
    // Рассчитываем стоимость за кг для ТТК
    if (tc.ingredients.isEmpty) {
      return 'ПФ · Цена не рассчитана · Выход: ${tc.yield.toStringAsFixed(0)}г';
    }

    final totalCost = tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.cost);
    final totalOutput = tc.ingredients.fold<double>(0, (sum, ing) => sum + ing.outputWeight);
    final costPerKg = totalOutput > 0 ? (totalCost / totalOutput) * 1000 : 0;

    return 'ПФ · ${costPerKg.toStringAsFixed(0)} ₽/кг · Выход: ${tc.yield.toStringAsFixed(0)}г';
  }

  bool _needsKbju(NomenclatureItem item) {
    if (item.isTechCard) return false; // ТТК не нуждаются в КБЖУ
    final p = item.product!;
    return (p.calories == null || p.calories == 0) && p.protein == null && p.fat == null && p.carbs == null;
  }

  bool _canShowNutrition(BuildContext context) {
    final account = context.read<AccountManagerSupabase>();
    final employee = account.currentEmployee;
    return employee?.hasProSubscription ?? false;
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
      final vals = allLangs.map((c) => (n[c] ?? '').trim()).where((s) => s.isNotEmpty).toSet();
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
          _ensureLoaded().then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) _ensureLoaded().then((_) => setState(() {}));
  }

  Future<void> _loadTranslationsForAll(BuildContext context, List<Product> list) async {
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
          _ensureLoaded().then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) _ensureLoaded().then((_) => setState(() {}));
  }

  Future<void> _verifyWithAi(BuildContext context, List<Product> list) async {
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
        aiService: ai,
        loc: loc,
        onComplete: (r) {
          results = r;
          Navigator.of(ctx).pop();
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (!context.mounted) return;
    final withSuggestions = results.where((e) => e.hasAnySuggestion).toList();
    if (withSuggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('verify_no_suggestions'))));
      _ensureLoaded().then((_) => setState(() {}));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => _VerifyProductsResultsDialog(
        items: withSuggestions,
        store: store,
        loc: loc,
        onApplied: () {
          Navigator.of(ctx).pop();
          _ensureLoaded().then((_) => setState(() {}));
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('verify_applied'))));
          }
        },
      ),
    );
    if (context.mounted) _ensureLoaded().then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final store = context.watch<ProductStoreSupabase>();
    final account = context.watch<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    final canEdit = account.currentEmployee?.canEditChecklistsAndTechCards ?? false;

    // Фильтруем элементы номенклатуры
    var nomItems = _nomenclatureItems.where((item) {
      // Фильтр по типу (продукты/ПФ)
      if (_nomFilter == _NomenclatureFilter.products && item.isTechCard) return false;
      if (_nomFilter == _NomenclatureFilter.semiFinished && item.isProduct) return false;

      // Фильтр по категории (только для продуктов)
      if (_category != null && item.isProduct && item.product!.category != _category) return false;

      // Поисковый запрос
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return item.name.toLowerCase().contains(q) ||
            item.getLocalizedName(loc.currentLanguageCode).toLowerCase().contains(q);
      }
      return true;
    }).toList();

    // Сортируем
    nomItems = _sortNomenclatureItems(nomItems, _nomSort);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('nomenclature')),
        actions: [
          // Счетчик элементов
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${nomItems.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.warning),
            onPressed: () => _showDuplicates(),
            tooltip: 'Показать дубликаты',
          ),
          // Temporarily disabled - method has compilation issues
          // IconButton(
          //   icon: const Icon(Icons.clear_all),
          //   onPressed: () => _confirmClearAllNomenclature(context, loc),
          //   tooltip: 'Очистить всю номенклатуру',
          // ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Загрузить продукты',
            onPressed: () {
              print('=== Nomenclature upload button pressed ===');
              try {
                context.push('/products/upload');
                print('=== Navigation to /products/upload successful ===');
              } catch (e) {
                print('=== Navigation error: $e ===');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка навигации: $e')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.attach_money),
            onPressed: account.establishment != null ? () => _showCurrencyDialog(context, loc, account, store) : null,
            tooltip: loc.t('default_currency'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _ensureLoaded();
              if (mounted) setState(() {});
            },
            tooltip: loc.t('refresh'),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                hintText: loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
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
              onSortChanged: (s) => setState(() => _nomSort = s),
              onFilterTypeChanged: (f) => setState(() => _nomFilter = f),
              onRefresh: () => _ensureLoaded().then((_) => setState(() {})),
              onSwitchToCatalog: () {}, // Не используется
              onEditProduct: (ctx, p) => _showEditProductForNomenclature(ctx, p, store, loc, () => _ensureLoaded().then((_) => setState(() {})), estId ?? ''),
              onRemoveProduct: (ctx, p) => _confirmRemoveForNomenclature(ctx, p, store, loc, () => _ensureLoaded().then((_) => setState(() {})), estId ?? ''),
              onLoadKbju: (ctx, list) => _loadKbjuForAll(ctx, list),
              onLoadTranslations: (ctx, list) => _loadTranslationsForAll(ctx, list),
              onVerifyWithAi: (ctx, list) => _verifyWithAi(ctx, list),
              onNeedsKbju: (item) => _needsKbju(item),
              onNeedsTranslation: (item) => _needsTranslation(item),
              onCanShowNutrition: (context) => _canShowNutrition(context),
              onBuildProductSubtitle: (context, p, store, estId, loc) => _buildProductSubtitle(context, p, store, estId, loc),
              onBuildTechCardSubtitle: (tc) => _buildTechCardSubtitle(tc),
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _sortProducts(List<Product> list, _CatalogSort sort) {
    final copy = List<Product>.from(list);
    switch (sort) {
      case _CatalogSort.nameAz:
        copy.sort((a, b) => _sortKeyForName(a.getLocalizedName('ru')).toLowerCase().compareTo(_sortKeyForName(b.getLocalizedName('ru')).toLowerCase()));
        break;
      case _CatalogSort.nameZa:
        copy.sort((a, b) => _sortKeyForName(b.getLocalizedName('ru')).toLowerCase().compareTo(_sortKeyForName(a.getLocalizedName('ru')).toLowerCase()));
        break;
      case _CatalogSort.priceAsc:
        copy.sort((a, b) => (a.basePrice ?? 0).compareTo(b.basePrice ?? 0));
        break;
      case _CatalogSort.priceDesc:
        copy.sort((a, b) => (b.basePrice ?? 0).compareTo(a.basePrice ?? 0));
        break;
    }
    return copy;
  }

  /// Ключ сортировки: соус/специя и т.п. идут по букве слова-типа (С)
  static String _sortKeyForName(String name) {
    const words = ['соус', 'специя', 'смесь', 'приправа', 'маринад', 'подлива', 'паста', 'масло'];
    final lower = name.trim().toLowerCase();
    for (final w in words) {
      final idx = lower.indexOf(w);
      if (idx >= 0) {
        final before = idx > 0 ? lower.substring(0, idx).trim() : '';
        final after = idx + w.length < lower.length ? lower.substring(idx + w.length).trim() : '';
        final rest = [before, after].where((s) => s.isNotEmpty).join(' ');
        return '$w ${rest.isEmpty ? '' : rest}'.trim();
      }
    }
    return lower;
  }

  List<NomenclatureItem> _sortNomenclatureItems(List<NomenclatureItem> list, _CatalogSort sort) {
    final products = list.where((item) => item.isProduct).toList();
    final techCards = list.where((item) => item.isTechCard).toList();

    void sortGroup(List<NomenclatureItem> group) {
      switch (sort) {
        case _CatalogSort.nameAz:
          group.sort((a, b) => _sortKeyForName(a.getLocalizedName('ru')).toLowerCase().compareTo(_sortKeyForName(b.getLocalizedName('ru')).toLowerCase()));
          break;
        case _CatalogSort.nameZa:
          group.sort((a, b) => _sortKeyForName(b.getLocalizedName('ru')).toLowerCase().compareTo(_sortKeyForName(a.getLocalizedName('ru')).toLowerCase()));
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
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное', 'manual': 'Добавлено вручную',
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

  // Удалены дублированные функции загрузки продуктов:
  // _showUploadDialog, _showPasteDialog, _uploadFromTxt
  // Теперь используется единый экран загрузки продуктов
  // Fix for Vercel build issue

  static const _addProductCategories = ['manual', 'vegetables', 'fruits', 'meat', 'seafood', 'dairy', 'grains', 'bakery', 'pantry', 'spices', 'beverages', 'eggs', 'legumes', 'nuts', 'misc'];
  static const _addProductUnits = ['g', 'kg', 'pcs', 'шт', 'ml', 'L'];

  Future<void> _showAddProductDialog(LocalizationService loc) async {
    final account = context.read<AccountManagerSupabase>();
    final estId = account.establishment?.id;
    if (estId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('no_establishment'))));
      return;
    }
    final result = await showDialog<({String name, String category, String unit})>(
      context: context,
      builder: (ctx) => _AddProductDialog(
        loc: loc,
        categories: _addProductCategories,
        units: _addProductUnits,
      ),
    );
    if (result == null || result.name.trim().isEmpty || !mounted) return;
    final store = context.read<ProductStoreSupabase>();
    final defCur = account.establishment?.defaultCurrency ?? 'VND';
    final allLangs = LocalizationService.productLanguageCodes;
    final names = <String, String>{for (final c in allLangs) c: result.name.trim()};
    final product = Product(
      id: const Uuid().v4(),
      name: result.name.trim(),
      category: result.category,
      names: names,
      calories: null,
      protein: null,
      fat: null,
      carbs: null,
      unit: result.unit,
      basePrice: null,
      currency: null,
    );
    try {
      await store.addProduct(product);
      await store.addToNomenclature(estId, product.id);
      await store.loadProducts();
      await store.loadNomenclature(estId);
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('product_added'))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
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

  Future<void> _addProductsFromExcel(Uint8List bytes, LocalizationService loc) async {
    try {
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: не найдена таблица в файле')));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('file_empty'))));
        return;
      }
      await _addProductsFromText(text, loc);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка обработки Excel файла: $e')));
    }
  }

  Future<void> _addProductsFromText(String text, LocalizationService loc) async {
    final lines = text.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final items = lines.map(_parseLine).where((r) => r.name.isNotEmpty).toList();

    // Отладка
    if (!mounted) return;
    final sampleLines = lines.take(2).join('\n');
    final sampleItems = items.take(2).map((item) => '${item.name}: ${item.price}').join(', ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Найдено строк: ${lines.length}, валидных: ${items.length}\nСтроки: $sampleLines\nЭлементы: $sampleItems'),
      duration: const Duration(seconds: 8),
    ));

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('no_rows_to_add'))));
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('upload_txt_format'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(loc.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(loc.t('save'))),
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
    final estId = account.establishment?.id;
    if (estId != null) {
      await store.loadProducts();
      await store.loadNomenclature(estId);
    }
    if (mounted) setState(() {});
  }


  void _showCurrencyDialog(
    BuildContext context,
    LocalizationService loc,
    AccountManagerSupabase account,
    ProductStoreSupabase store,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CurrencySettingsDialog(
        establishment: account.establishment!,
        store: store,
        loc: loc,
        onSaved: (Establishment updated) async {
          await account.updateEstablishment(updated);
          if (context.mounted) setState(() {});
        },
        onApplyToAll: (currency) async {
          await store.bulkUpdateCurrency(currency);
          await store.loadProducts();
          if (context.mounted) setState(() {});
        },
      ),
    );
  }
}

class _DuplicatesDialog extends StatefulWidget {
  const _DuplicatesDialog({
    required this.groups,
    required this.loc,
    required this.onRemove,
  });

  final List<List<NomenclatureItem>> groups;
  final LocalizationService loc;
  final Future<void> Function(List<String> idsToRemove) onRemove;

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
    await widget.onRemove(_selectedToRemove.toList());
    if (mounted) Navigator.of(context).pop();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.loc.t('duplicates_title') ?? 'Поиск дубликатов'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.loc.t('duplicates_hint') ?? 'ИИ нашёл похожие названия. Выберите, какие удалить (останется один эталон).',
              style: theme.textTheme.bodySmall,
            ),
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
                            widget.loc.t('duplicates_group') ?? 'Группа ${gi + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
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
                                    fontWeight: group.indexOf(item) == 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: item.price != null ? Text('${item.price} ${item.currency ?? ''}') : null,
                                controlAffinity: ListTileControlAffinity.leading,
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
          child: Text(widget.loc.t('cancel') ?? 'Закрыть'),
        ),
        TextButton(
          onPressed: _saving ? null : _selectAllExceptFirst,
          child: Text(widget.loc.t('duplicates_remove_all') ?? 'Удалить все кроме первого'),
        ),
        FilledButton(
          onPressed: _saving || _selectedToRemove.isEmpty ? null : _applyRemoval,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.loc.t('duplicates_apply') ?? 'Применить'),
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
  });

  final LocalizationService loc;
  final List<String> categories;
  final List<String> units;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  late TextEditingController _nameController;
  late String _category;
  late String _unit;
  bool _recognizing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _category = 'manual';
    _unit = 'g';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _recognize() async {
    final name = _nameController.text.trim();
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
        _nameController.text = result.normalizedName;
        if (result.suggestedCategory != null && widget.categories.contains(result.suggestedCategory)) {
          _category = result.suggestedCategory!;
        }
        if (result.suggestedUnit != null && widget.units.contains(result.suggestedUnit)) {
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
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.loc.t('product_name'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _recognize(),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _recognizing ? null : _recognize,
              icon: _recognizing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 20),
              label: Text(widget.loc.t('ai_product_recognize')),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(labelText: widget.loc.t('column_category'), border: const OutlineInputBorder()),
              items: widget.categories.map((c) => DropdownMenuItem(value: c, child: Text(c == 'manual' ? widget.loc.t('category_manual') : c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? 'manual'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _unit,
              decoration: InputDecoration(labelText: widget.loc.t('unit'), border: const OutlineInputBorder()),
              items: widget.units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
              onChanged: (v) => setState(() => _unit = v ?? 'g'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text(widget.loc.t('cancel'))),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, category: _category, unit: _unit));
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
    required this.onSortChanged,
    required this.onFilterTypeChanged,
    required this.onRefresh,
    required this.onSwitchToCatalog,
    required this.onEditProduct,
    required this.onRemoveProduct,
    required this.onLoadKbju,
    required this.onLoadTranslations,
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
  final void Function(_CatalogSort) onSortChanged;
  final void Function(_NomenclatureFilter) onFilterTypeChanged;
  final VoidCallback onRefresh;
  final VoidCallback onSwitchToCatalog;
  final void Function(BuildContext, Product) onEditProduct;
  final void Function(BuildContext, Product) onRemoveProduct;
  final void Function(BuildContext, List<Product>) onLoadKbju;
  final void Function(BuildContext, List<Product>) onLoadTranslations;
  final void Function(BuildContext, List<Product>) onVerifyWithAi;
  final bool Function(NomenclatureItem) onNeedsKbju;
  final bool Function(NomenclatureItem) onNeedsTranslation;
  final bool Function(BuildContext) onCanShowNutrition;
  final String Function(BuildContext, Product, ProductStoreSupabase, String, LocalizationService) onBuildProductSubtitle;
  final String Function(TechCard) onBuildTechCardSubtitle;

  static String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное',
    };
    return map[c] ?? c;
  }


  @override
  State<_NomenclatureTab> createState() => _NomenclatureTabState();
}

class _NomenclatureTabState extends State<_NomenclatureTab> {
  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return _NomenclatureEmpty(
        loc: widget.loc,
        onSwitchToCatalog: widget.onSwitchToCatalog,
      );
    }

    final needsKbju = widget.items.where((item) => item.isProduct && item.product!.category == 'manual' && widget.onNeedsKbju(item)).toList();
    final needsTranslation = widget.items.where((item) => widget.onNeedsTranslation(item)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              Tooltip(
                message: widget.loc.t('verify_with_ai_tooltip'),
                child: FilledButton.tonalIcon(
                  onPressed: () => widget.onVerifyWithAi(context, widget.items.where((item) => item.isProduct).map((item) => item.product!).toList()),
                  icon: const Icon(Icons.auto_awesome, size: 20),
                  label: Text(widget.loc.t('verify_with_ai').replaceAll('%s', '${widget.items.length}')),
                ),
              ),
              PopupMenuButton<_CatalogSort>(
                icon: const Icon(Icons.sort),
                tooltip: widget.loc.t('sort_name_az').split(' ').take(2).join(' '),
                onSelected: widget.onSortChanged,
                itemBuilder: (_) => [
                  PopupMenuItem(value: _CatalogSort.nameAz, child: Text(widget.loc.t('sort_name_az'))),
                  PopupMenuItem(value: _CatalogSort.nameZa, child: Text(widget.loc.t('sort_name_za'))),
                  PopupMenuItem(value: _CatalogSort.priceAsc, child: Text(widget.loc.t('sort_price_asc'))),
                  PopupMenuItem(value: _CatalogSort.priceDesc, child: Text(widget.loc.t('sort_price_desc'))),
                ],
              ),
              FilterChip(
                label: Text('Продукты', style: const TextStyle(fontSize: 11)),
                selected: widget.filterType == _NomenclatureFilter.products,
                onSelected: (_) => widget.onFilterTypeChanged(_NomenclatureFilter.products),
              ),
              FilterChip(
                label: Text('ПФ', style: const TextStyle(fontSize: 11)),
                selected: widget.filterType == _NomenclatureFilter.semiFinished,
                onSelected: (_) => widget.onFilterTypeChanged(_NomenclatureFilter.semiFinished),
              ),
              FilterChip(
                label: Text('Все', style: const TextStyle(fontSize: 11)),
                selected: widget.filterType == _NomenclatureFilter.all,
                onSelected: (_) => widget.onFilterTypeChanged(_NomenclatureFilter.all),
              ),
              if (needsKbju.isNotEmpty && widget.onCanShowNutrition(context))
                FilledButton.tonalIcon(
                  onPressed: () => widget.onLoadKbju(context, needsKbju.where((item) => item.isProduct).map((item) => item.product!).toList()),
                  icon: const Icon(Icons.cloud_download, size: 20),
                  label: Text(widget.loc.t('load_kbju_for_all').replaceAll('%s', '${needsKbju.length}')),
                ),
              if (needsTranslation.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () => widget.onLoadTranslations(context, needsTranslation.where((item) => item.isProduct).map((item) => item.product!).toList()),
                  icon: const Icon(Icons.translate, size: 20),
                  label: Text(widget.loc.t('translate_names_for_all').replaceAll('%s', '${needsTranslation.length}')),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: widget.items.length,
            itemBuilder: (_, i) {
              final item = widget.items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  onTap: item.isProduct
                      ? () => widget.onEditProduct(context, item.product!)
                      : null,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (i + 1).toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(item.getLocalizedName(widget.loc.currentLanguageCode)),
                  subtitle: Text(
                    item.isProduct
                        ? widget.onBuildProductSubtitle(context, item.product!, widget.store, widget.estId, widget.loc)
                        : widget.onBuildTechCardSubtitle(item.techCard!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.isProduct) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onEditProduct(context, item.product!),
                          child: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: widget.loc.t('edit_product'),
                            onPressed: () => widget.onEditProduct(context, item.product!),
                          ),
                        ),
                        if (widget.canRemove)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            tooltip: widget.loc.t('remove_from_nomenclature'),
                            onPressed: () => widget.onRemoveProduct(context, item.product!),
                          ),
                      ],
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

}

class _NomenclatureEmpty extends StatelessWidget {
  const _NomenclatureEmpty({
    required this.loc,
    required this.onSwitchToCatalog,
  });

  final LocalizationService loc;
  final VoidCallback onSwitchToCatalog;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '${loc.t('nomenclature')}: пусто',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('add_from_catalog'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onSwitchToCatalog,
                icon: const Icon(Icons.add),
                label: Text(loc.t('add_from_catalog')),
              ),
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
          price: ep?.$1 ?? p.basePrice,
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
      title: Text(widget.loc.t('add_all_to_nomenclature').replaceAll('%s', '$total')),
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
                'Ошибка: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
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
  State<_LoadKbjuProgressDialog> createState() => _LoadKbjuProgressDialogState();
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
        final result = await NutritionApiService.fetchNutrition(p.getLocalizedName(widget.loc.currentLanguageCode));
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
          Text('$_done / $total', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
      (result!.normalizedName != null ||
          result!.suggestedPrice != null ||
          result!.suggestedCalories != null ||
          result!.suggestedProtein != null ||
          result!.suggestedFat != null ||
          result!.suggestedCarbs != null);
}

class _VerifyProductsProgressDialog extends StatefulWidget {
  const _VerifyProductsProgressDialog({
    required this.list,
    required this.store,
    required this.aiService,
    required this.loc,
    required this.onComplete,
    required this.onError,
  });

  final List<Product> list;
  final ProductStoreSupabase store;
  final AiService aiService;
  final LocalizationService loc;
  final void Function(List<_VerifyProductItem>) onComplete;
  final void Function(Object) onError;

  @override
  State<_VerifyProductsProgressDialog> createState() => _VerifyProductsProgressDialogState();
}

class _VerifyProductsProgressDialogState extends State<_VerifyProductsProgressDialog> {
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
        final nutrition = (p.calories != null || p.protein != null || p.fat != null || p.carbs != null)
            ? NutritionResult(
                calories: p.calories,
                protein: p.protein,
                fat: p.fat,
                carbs: p.carbs,
              )
            : null;
        final result = await widget.aiService.verifyProduct(
          p.getLocalizedName(widget.loc.currentLanguageCode),
          currentPrice: p.basePrice,
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
    required this.loc,
    required this.onApplied,
  });

  final List<_VerifyProductItem> items;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final VoidCallback onApplied;

  Future<void> _applyOne(BuildContext context, _VerifyProductItem item) async {
    final p = item.product;
    final r = item.result!;
    Product updated = p;
    if (r.normalizedName != null && r.normalizedName!.trim().isNotEmpty) {
      updated = updated.copyWith(name: r.normalizedName!.trim());
    }
    if (r.suggestedPrice != null) {
      updated = updated.copyWith(basePrice: r.suggestedPrice);
    }
    if (r.suggestedCalories != null || r.suggestedProtein != null || r.suggestedFat != null || r.suggestedCarbs != null) {
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
      if (r.normalizedName != null && r.normalizedName!.trim().isNotEmpty) {
        updated = updated.copyWith(name: r.normalizedName!.trim());
      }
      if (r.suggestedPrice != null) updated = updated.copyWith(basePrice: r.suggestedPrice);
      if (r.suggestedCalories != null || r.suggestedProtein != null || r.suggestedFat != null || r.suggestedCarbs != null) {
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
                          if (r.normalizedName != null && r.normalizedName != p.name) ...[
                            const SizedBox(height: 4),
                            Text('${loc.t('name')}: ${p.name} → ${r.normalizedName}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                          if (r.suggestedPrice != null && r.suggestedPrice != p.basePrice) ...[
                            const SizedBox(height: 2),
                            Text('${loc.t('price')}: ${p.basePrice?.toStringAsFixed(2) ?? '—'} → ${r.suggestedPrice!.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                          if (r.suggestedCalories != null || r.suggestedProtein != null || r.suggestedFat != null || r.suggestedCarbs != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'КБЖУ: ${p.calories?.round() ?? 0}/${p.protein?.round() ?? 0}/${p.fat?.round() ?? 0}/${p.carbs?.round() ?? 0} → ${(NutritionApiService.saneCaloriesForProduct(p.getLocalizedName(loc.currentLanguageCode), r.suggestedCalories) ?? r.suggestedCalories)?.round() ?? 0}/${r.suggestedProtein?.round() ?? 0}/${r.suggestedFat?.round() ?? 0}/${r.suggestedCarbs?.round() ?? 0}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(loc.t('close'))),
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
  State<_LoadTranslationsProgressDialog> createState() => _LoadTranslationsProgressDialogState();
}

class _LoadTranslationsProgressDialogState extends State<_LoadTranslationsProgressDialog> {
  int _done = 0;
  int _updated = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final translationService = TranslationService(
      aiService: context.read<AiServiceSupabase>(),
      supabase: context.read<SupabaseService>(),
    );
    final allLangs = LocalizationService.productLanguageCodes;
    for (final p in widget.list) {
      try {
        final source = p.names?['ru'] ?? p.names?['en'] ?? p.name;
        if (source.trim().isEmpty) {
          setState(() => _done++);
          continue;
        }
        final missing = allLangs.where((c) => (p.names?[c] ?? '').trim().isEmpty).toList();
        if (missing.isEmpty) {
          setState(() => _done++);
          continue;
        }
        final sourceLang = p.names?['ru'] != null && (p.names!['ru'] ?? '').trim().isNotEmpty
            ? 'ru'
            : (p.names?['en'] != null && (p.names!['en'] ?? '').trim().isNotEmpty ? 'en' : 'ru');
        final merged = Map<String, String>.from(p.names ?? {});
        for (final target in missing) {
          if (target == sourceLang) continue;
          final tr = await translationService.translate(
            entityType: TranslationEntityType.product,
            entityId: p.id ?? p.name,
            fieldName: 'name',
            text: source,
            from: sourceLang,
            to: target,
          );
          if (tr != null && tr.trim().isNotEmpty) merged[target] = tr;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (merged.length > (p.names?.length ?? 0)) {
          final updated = p.copyWith(names: merged);
          await widget.store.updateProduct(updated);
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
      widget.onError(Exception('Ни один перевод не получен. Проверьте интернет или попробуйте позже.'));
    }
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.list.length;
    final progress = total > 0 ? (_done / total).clamp(0.0, 1.0) : 1.0;
    return AlertDialog(
      title: Text(widget.loc.t('translate_names_for_all').replaceAll('%s', '$total')),
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
          Text('$_done / $total', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          Text(
            '${widget.loc.t('kbju_updated')}: $_updated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': 'Разное', 'manual': 'Добавлено вручную',
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
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('kbju_load_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  Future<void> _addAllToNomenclature(BuildContext context, List<Product> list) async {
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
              SnackBar(content: Text(loc.t('add_all_done').replaceAll('%s', '${list.length}'))),
            );
          }
        },
        onError: (e) {
          Navigator.of(ctx).pop();
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
  }

  bool _needsKbju(Product p) =>
      (p.calories == null || p.calories == 0) && p.protein == null && p.fat == null && p.carbs == null;

  bool _needsTranslation(Product p) {
    final allLangs = LocalizationService.productLanguageCodes;
    final n = p.names;
    if (n == null || n.isEmpty) return true;
    if (allLangs.any((c) => (n[c] ?? '').trim().isEmpty)) return true;
    // Ручные продукты с одинаковым текстом во всех языках — не переведены
    if (p.category == 'manual') {
      final vals = allLangs.map((c) => (n[c] ?? '').trim()).where((s) => s.isNotEmpty).toSet();
      if (vals.length <= 1) return true;
    }
    return false;
  }

  Future<void> _loadTranslationsForAll(BuildContext context, List<Product> list) async {
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
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('translate_done'))));
          }
        },
        onError: (e) {
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
          }
        },
      ),
    );
    if (context.mounted) onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final notInNom = products.where((p) => !store.isInNomenclature(p.id)).toList();
    final needsKbju = store.allProducts.where((p) => p.category == 'manual' && _needsKbju(p)).toList();
    final needsTranslation = store.allProducts.where(_needsTranslation).toList();
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
                tooltip: 'Сортировка',
                onSelected: onSortChanged,
                itemBuilder: (_) => [
                  PopupMenuItem(value: _CatalogSort.nameAz, child: Text(loc.t('sort_name_az'))),
                  PopupMenuItem(value: _CatalogSort.nameZa, child: Text(loc.t('sort_name_za'))),
                  PopupMenuItem(value: _CatalogSort.priceAsc, child: Text(loc.t('sort_price_asc'))),
                  PopupMenuItem(value: _CatalogSort.priceDesc, child: Text(loc.t('sort_price_desc'))),
                ],
              ),
              FilterChip(
                label: Text(loc.t('filter_gluten_free'), style: const TextStyle(fontSize: 11)),
                selected: filterGlutenFree,
                onSelected: onFilterGlutenChanged,
              ),
              FilterChip(
                label: Text(loc.t('filter_lactose_free'), style: const TextStyle(fontSize: 11)),
                selected: filterLactoseFree,
                onSelected: onFilterLactoseChanged,
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
              label: Text(loc.t('add_all_to_nomenclature').replaceAll('%s', '${notInNom.length}')),
            ),
          ),
        if (needsKbju.isNotEmpty || needsTranslation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (needsKbju.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadKbjuForAll(context, needsKbju),
                    icon: const Icon(Icons.cloud_download, size: 20),
                    label: Text(loc.t('load_kbju_for_all').replaceAll('%s', '${needsKbju.length}')),
                  ),
                if (needsTranslation.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => _loadTranslationsForAll(context, needsTranslation),
                    icon: const Icon(Icons.translate, size: 20),
                    label: Text(loc.t('translate_names_for_all').replaceAll('%s', '${needsTranslation.length}')),
                  ),
              ],
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
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Справочник пуст',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Загрузите список или вставьте текст (название + таб + цена).',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
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
                                  : Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(
                                inNom ? Icons.check : Icons.add,
                                color: inNom ? Colors.green : Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(p.getLocalizedName(loc.currentLanguageCode)),
                            subtitle: Text(
                              p.category == 'misc'
                                  ? '${p.calories?.round() ?? 0} ккал · ${_unitDisplay(p.unit, loc.currentLanguageCode)}'
                                  : '${_categoryLabel(p.category)} · ${p.calories?.round() ?? 0} ккал · ${_unitDisplay(p.unit, loc.currentLanguageCode)}',
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
                                if ((p.calories == null || p.calories == 0) &&
                                    (p.protein == null && p.fat == null && p.carbs == null))
                                  IconButton(
                                    icon: const Icon(Icons.cloud_download),
                                    tooltip: loc.t('load_kbju_from_web'),
                                    onPressed: () => _fetchKbju(context, p),
                                  ),
                                if (inNom)
                                  Chip(
                                    label: Text(loc.t('nomenclature'), style: const TextStyle(fontSize: 11)),
                                  )
                                else
                                  FilledButton.tonal(
                                    onPressed: () => _addToNomenclature(context, p),
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
      final price = establishmentPrice?.$1 ?? p.basePrice;
      await store.addToNomenclature(estId, p.id, price: price, currency: establishmentPrice?.$2 ?? p.currency);
      if (context.mounted) onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  Future<void> _fetchKbju(BuildContext context, Product p) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(SnackBar(content: Text(loc.t('kbju_searching'))));
    final result = await NutritionApiService.fetchNutrition(p.getLocalizedName(loc.currentLanguageCode));
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
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text(loc.t('error_with_message').replaceAll('%s', e.toString()))));
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

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

/// Карточка продукта — редактирование единицы измерения, КБЖУ, стоимости
class _ProductEditDialog extends StatefulWidget {
  const _ProductEditDialog({
    required this.product,
    required this.store,
    required this.loc,
    this.establishmentId,
    required this.onSaved,
  });

  final Product product;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final String? establishmentId;
  final VoidCallback onSaved;

  static const _currencies = ['RUB', 'USD', 'EUR', 'VND'];

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbsController;
  late final TextEditingController _wastePctController;
  late String _unit;
  late String _currency;
  late bool _containsGluten;
  late bool _containsLactose;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p.name);
    double? initialPrice = p.basePrice;
    if (widget.establishmentId != null && widget.establishmentId!.isNotEmpty) {
      final ep = widget.store.getEstablishmentPrice(p.id, widget.establishmentId);
      if (ep?.$1 != null) initialPrice = ep!.$1;
    }
    _priceController = TextEditingController(text: initialPrice?.toString() ?? '');
    // Подставить адекватные калории при открытии карточки (грудка 0 → 165, авокадо 655 → 160)
    final saneCal = NutritionApiService.saneCaloriesForProduct(p.name, p.calories);
    final initialCal = saneCal ?? p.calories;
    _caloriesController = TextEditingController(text: initialCal?.toString() ?? '');
    _proteinController = TextEditingController(text: p.protein?.toString() ?? '');
    _fatController = TextEditingController(text: p.fat?.toString() ?? '');
    _carbsController = TextEditingController(text: p.carbs?.toString() ?? '');
    _wastePctController = TextEditingController(text: p.primaryWastePct?.toStringAsFixed(1) ?? '0');
    final unitMap = {'кг': 'kg', 'г': 'g', 'шт': 'pcs', 'л': 'l', 'мл': 'ml'};
    _unit = unitMap[p.unit] ?? p.unit ?? 'g';
    if (!CulinaryUnits.all.any((e) => e.id == _unit)) _unit = 'g';
    _currency = p.currency ?? 'VND';
    _containsGluten = p.containsGluten ?? false;
    _containsLactose = p.containsLactose ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbsController.dispose();
    _wastePctController.dispose();
    super.dispose();
  }

  double? _parseNum(String v) {
    final s = v.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('product_name_required'))));
      return;
    }
    final curLang = widget.loc.currentLanguageCode;
    final allLangs = LocalizationService.productLanguageCodes;
    final merged = Map<String, String>.from(widget.product.names ?? {});
    merged[curLang] = name;
    for (final c in allLangs) {
      merged.putIfAbsent(c, () => name);
    }
    final updated = widget.product.copyWith(
      name: name,
      names: merged,
      basePrice: _parseNum(_priceController.text),
      currency: _currency,
      unit: _unit,
      primaryWastePct: _parseNum(_wastePctController.text)?.clamp(0.0, 99.9),
      calories: _parseNum(_caloriesController.text),
      protein: _parseNum(_proteinController.text),
      fat: _parseNum(_fatController.text),
      carbs: _parseNum(_carbsController.text),
      containsGluten: _containsGluten,
      containsLactose: _containsLactose,
    );
    try {
      await widget.store.updateProduct(updated);
      if (widget.establishmentId != null && widget.establishmentId!.isNotEmpty) {
        final price = _parseNum(_priceController.text);
        if (price != null) {
          await widget.store.setEstablishmentPrice(
            widget.establishmentId!,
            widget.product.id,
            price,
            _currency,
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('product_saved'))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('error_with_message').replaceAll('%s', e.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.loc.currentLanguageCode;
    return AlertDialog(
      title: Text(widget.loc.t('edit_product')),
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
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _unit,
                decoration: InputDecoration(
                  labelText: widget.loc.t('unit'),
                  border: const OutlineInputBorder(),
                ),
                items: CulinaryUnits.all.map((e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(lang == 'ru' ? e.ru : e.en),
                )).toList(),
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _wastePctController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('waste_pct'),
                  hintText: '0',
                  border: const OutlineInputBorder(),
                  helperText: widget.loc.t('waste_pct_product_hint'),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: InputDecoration(
                        labelText: widget.loc.t('currency'),
                        border: const OutlineInputBorder(),
                      ),
                      items: _ProductEditDialog._currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _currency = v ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(widget.loc.t('kbju_per_100g'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _caloriesController,
                      decoration: InputDecoration(labelText: widget.loc.t('kcal'), border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _proteinController,
                      decoration: InputDecoration(labelText: widget.loc.t('protein_short'), border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _fatController,
                      decoration: InputDecoration(labelText: widget.loc.t('fat_short'), border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _carbsController,
                      decoration: InputDecoration(labelText: widget.loc.t('carbs_short'), border: const OutlineInputBorder(), isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: !_containsGluten,
                onChanged: (v) => setState(() => _containsGluten = !(v ?? true)),
                title: Text(widget.loc.t('filter_gluten_free'), style: const TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: !_containsLactose,
                onChanged: (v) => setState(() => _containsLactose = !(v ?? true)),
                title: Text(widget.loc.t('filter_lactose_free'), style: const TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.loc.t('cancel'))),
        FilledButton(onPressed: _save, child: Text(widget.loc.t('save'))),
      ],
    );
  }
}

/// Диалог настройки валюты заведения
class _CurrencySettingsDialog extends StatefulWidget {
  const _CurrencySettingsDialog({
    required this.establishment,
    required this.store,
    required this.loc,
    required this.onSaved,
    required this.onApplyToAll,
  });

  final Establishment establishment;
  final ProductStoreSupabase store;
  final LocalizationService loc;
  final Future<void> Function(Establishment) onSaved;
  final Future<void> Function(String) onApplyToAll;

  static const _presetCurrencies = ['RUB', 'USD', 'EUR', 'VND', 'GBP'];

  @override
  State<_CurrencySettingsDialog> createState() => _CurrencySettingsDialogState();
}

class _CurrencySettingsDialogState extends State<_CurrencySettingsDialog> {
  late String _currency;
  bool _useCustom = false;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currency = widget.establishment.defaultCurrency;
    _useCustom = !_CurrencySettingsDialog._presetCurrencies.contains(_currency);
    if (_useCustom) _customController.text = _currency;
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  String get _effectiveCurrency => _useCustom
      ? _customController.text.trim().toUpperCase().isEmpty ? 'RUB' : _customController.text.trim().toUpperCase()
      : _currency;

  Future<void> _saveAsDefault() async {
    final c = _effectiveCurrency;
    final updated = widget.establishment.copyWith(
      defaultCurrency: c,
      updatedAt: DateTime.now(),
    );
    await widget.onSaved(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.loc.t('currency_saved'))));
  }

  Future<void> _applyToAll() async {
    final c = _effectiveCurrency;
    await widget.onApplyToAll(c);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.loc.t('currency_applied_to_all').replaceAll('%s', widget.store.allProducts.length.toString()))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.loc.t('default_currency')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: _useCustom,
            onChanged: (v) => setState(() => _useCustom = v ?? false),
            title: Text(widget.loc.t('custom_currency'), style: const TextStyle(fontSize: 14)),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_useCustom)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                controller: _customController,
                decoration: InputDecoration(
                  labelText: widget.loc.t('currency_code'),
                  hintText: widget.loc.t('currency_hint'),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) => setState(() {}),
              ),
            )
          else
            DropdownButtonFormField<String>(
              value: _CurrencySettingsDialog._presetCurrencies.contains(_currency) ? _currency : _CurrencySettingsDialog._presetCurrencies.first,
              decoration: InputDecoration(labelText: widget.loc.t('currency'), border: const OutlineInputBorder()),
              items: _CurrencySettingsDialog._presetCurrencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
          const SizedBox(height: 16),
          Text(
            widget.loc.t('currency_apply_hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.loc.t('cancel'))),
        FilledButton.tonal(
          onPressed: _applyToAll,
          child: Text(widget.loc.t('apply_currency_to_all')),
        ),
        FilledButton(onPressed: _saveAsDefault, child: Text(widget.loc.t('save'))),
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
  Future<void> _confirmClearAllNomenclature(BuildContext context, LocalizationService loc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить всю номенклатуру?'),
        content: const Text(
          'Это действие удалит ВСЕ продукты из номенклатуры заведения.\n\n'
          'Продукты можно будет добавить заново через загрузку.\n\n'
          'Это действие нельзя отменить!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить всё'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final store = context.read<ProductStoreSupabase>();
        final account = context.read<AccountManagerSupabase>();
        final estId = account.establishment?.id;

        if (estId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не найдено заведение')),
          );
          return;
        }

        // Показываем индикатор загрузки
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Очищаем номенклатуру...'),
              ],
            ),
          ),
        );

        // Очищаем номенклатуру
        await store.clearAllNomenclature(estId);

        // Закрываем диалог загрузки
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        // Данные будут перезагружены автоматически при следующем взаимодействии

        // Показываем успех
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вся номенклатура очищена'),
            backgroundColor: Colors.green,
          ),
        );

      } catch (e) {
        // Закрываем диалог загрузки
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка очистки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
