import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../utils/number_format_utils.dart';
import '../services/inventory_download.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр заказа продуктов из входящих: данные с ценами и итогом, сохранение PDF/Excel.
class OrderInboxDetailScreen extends StatefulWidget {
  const OrderInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<OrderInboxDetailScreen> createState() => _OrderInboxDetailScreenState();
}

class _OrderInboxDetailScreenState extends State<OrderInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  String? _error;
  // Локализованные имена продуктов: productId -> localizedName
  final Map<String, String> _localizedNames = {};
  // Переведённый комментарий (DeepL)
  String? _translatedComment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final doc = await OrderDocumentService().getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _loading = false;
      if (doc == null) _error = 'Документ не найден';
    });
    // После загрузки документа — подгружаем локализованные имена и переводим комментарий
    if (doc != null) {
      _loadLocalizedNames(doc);
      _translateComment(doc);
    }
  }

  Future<void> _translateComment(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final comment = (payload['comment'] as String?)?.trim() ?? '';
    if (comment.isEmpty) return;

    // sourceLang — язык написания комментария, сохранённый при отправке заказа.
    // Если старый документ без sourceLang — считаем что комментарий на русском
    // (исторически все заказы создавались с русским интерфейсом).
    final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
    final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : 'ru';

    if (sourceLang == targetLang) return;

    try {
      final translationSvc = context.read<TranslationService>();
      // Включаем хеш текста в entityId — при изменении комментария кеш не применяется
      final commentHash = comment.hashCode.toRadixString(16);
      final translated = await translationSvc.translate(
        entityType: TranslationEntityType.ui,
        entityId: 'order_comment_${doc['id'] ?? commentHash}_$commentHash',
        fieldName: 'comment',
        text: comment,
        from: sourceLang,
        to: targetLang,
      );
      // Показываем перевод только если он содержательно отличается от оригинала
      if (translated != null && translated.trim().isNotEmpty && translated != comment && mounted) {
        setState(() => _translatedComment = translated);
      }
    } catch (_) {}
  }

  Future<void> _loadLocalizedNames(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final lang = loc.currentLanguageCode;

    final acc = context.read<AccountManagerSupabase>();
    final estId = acc.establishment?.id;

    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];

    // sourceLang — язык, на котором записаны productName в payload
    final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
    final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : (lang == 'ru' ? 'en' : 'ru');

    if (items.isEmpty) return;

    // 1. Пробуем через productStore (быстро, без сети — продукты в номенклатуре уже имеют names)
    final store = context.read<ProductStoreSupabase>();
    if (store.allProducts.isEmpty) await store.loadProducts();

    final updated = <String, String>{};
    final needDeepL = <Map<String, dynamic>>[];

    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final productId = item['productId'] as String?;
      final productName = (item['productName'] as String?)?.trim() ?? '';
      if (productName.isEmpty) continue;

      // Если язык совпадает — перевод не нужен
      if (sourceLang == lang) continue;

      // Ищем в store по productId — продукты в номенклатуре уже имеют переводы в names
      if (productId != null && productId.isNotEmpty) {
        final product = store.allProducts.where((p) => p.id == productId).firstOrNull;
        if (product != null) {
          final locName = product.getLocalizedName(lang);
          if (locName != productName) {
            // Перевод уже есть в names[]
            updated[productId] = locName;
          } else {
            // Перевод отсутствует — ждём синхронно чтобы сразу показать корректно
            final updatedNames = await store.translateProductAwait(productId);
            final translated = updatedNames?[lang];
            if (translated != null && translated != productName) {
              updated[productId] = translated;
            } else {
              updated[productId] = locName;
            }
          }
          continue;
        }
      }
      // Продукт не найден в store — запросим DeepL
      needDeepL.add(item);
    }

    if (mounted && updated.isNotEmpty) {
      setState(() => _localizedNames.addAll(updated));
    }

    // 2. Переводим через DeepL имена которых нет в store
    if (needDeepL.isEmpty || sourceLang == lang) return;
    if (!mounted) return;

    try {
      final translationSvc = context.read<TranslationService>();
      final seen = <String>{};
      for (final item in needDeepL) {
        final productName = (item['productName'] as String?)?.trim() ?? '';
        final productId = (item['productId'] as String?)?.trim() ?? '';
        if (productName.isEmpty || seen.contains(productName)) continue;
        seen.add(productName);
        final entityId = productId.isNotEmpty ? productId : productName;
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.product,
          entityId: entityId,
          fieldName: 'name',
          text: productName,
          from: sourceLang,
          to: lang,
        );
        if (translated != null && translated != productName && mounted) {
          // Используем productId как ключ если есть, иначе — имя
          final key = productId.isNotEmpty ? productId : productName;
          setState(() => _localizedNames[key] = translated);
        }
      }
    } catch (_) {}
  }

  String _getItemName(Map<String, dynamic> item) {
    final productId = (item['productId'] as String?)?.trim() ?? '';
    final productName = (item['productName'] as String?)?.trim() ?? '';
    // Сначала ищем по productId, затем по имени (для продуктов без id)
    if (productId.isNotEmpty && _localizedNames.containsKey(productId)) {
      return _localizedNames[productId]!;
    }
    if (productName.isNotEmpty && _localizedNames.containsKey(productName)) {
      return _localizedNames[productName]!;
    }
    return productName;
  }

  Future<String?> _getTranslatedCommentForExport(Map<String, dynamic> doc, String targetLang) async {
    if (!mounted) return null;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final comment = (payload['comment'] as String?)?.trim() ?? '';
    if (comment.isEmpty) return null;
    final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
    final loc = context.read<LocalizationService>();
    // Fallback: если sourceLang не сохранён — считаем русский (исторически заказы на русском)
    final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : 'ru';
    if (sourceLang == targetLang) return null;
    // Если уже переведено на нужный язык — используем кешированный результат
    if (targetLang == loc.currentLanguageCode && _translatedComment != null) {
      return _translatedComment;
    }
    try {
      final translationSvc = context.read<TranslationService>();
      final commentHash = comment.hashCode.toRadixString(16);
      final translated = await translationSvc.translate(
        entityType: TranslationEntityType.ui,
        entityId: 'order_comment_${doc['id'] ?? commentHash}_$commentHash',
        fieldName: 'comment',
        text: comment,
        from: sourceLang,
        to: targetLang,
      );
      return (translated != null && translated != comment) ? translated : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _showSaveFormatDialog() async {
    final doc = _doc;
    final loc = context.read<LocalizationService>();
    if (doc == null) return;

    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final dateStr = header['createdAt'] != null
        ? DateFormat('yyyy-MM-dd').format((DateTime.tryParse(header['createdAt'].toString()) ?? DateTime.now()).toLocal())
        : DateFormat('yyyy-MM-dd').format(DateTime.now());
    final supplier = (header['supplierName'] ?? 'order').toString().replaceAll(RegExp(r'[^\w\-.\s]'), '_');

    // Шаг 1: выбор языка документа
    final exportLang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_export_language_title') ?? 'Язык документа'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('order_export_language_subtitle') ?? 'Выберите язык для файла'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop('ru'),
                  child: Text('🇷🇺  ${loc.t('order_export_language_ru')}'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop('en'),
                  child: Text('🇺🇸  ${loc.t('order_export_language_en')}'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop('es'),
                  child: Text('🇪🇸  ${loc.t('order_export_language_es')}'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop('tr'),
                  child: Text('🇹🇷  ${loc.t('order_export_language_tr') ?? 'Türkçe'}'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );

    if (exportLang == null || !mounted) return;

    // Шаг 2: выбор формата
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('download') ?? 'Сохранить'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF'),
              onTap: () => Navigator.of(ctx).pop('pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel'),
              onTap: () => Navigator.of(ctx).pop('excel'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
        ],
      ),
    );

    if (format == null || !mounted) return;

    final tLang = (String key) => loc.tForLanguage(exportLang, key);

    // Собираем переведённые имена для выбранного языка экспорта
    // Если exportLang совпадает с текущим языком UI — используем уже загруженные _localizedNames
    // Если отличается — переводим через DeepL
    final exportTranslatedNames = <String, String>{};
    final exportTranslatedComment = await _getTranslatedCommentForExport(doc, exportLang);
    if (exportLang == loc.currentLanguageCode) {
      exportTranslatedNames.addAll(_localizedNames);
    } else {
      // Нужен перевод на другой язык — запрашиваем
      final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
      final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : loc.currentLanguageCode;
      if (sourceLang != exportLang) {
        final items2 = payload['items'] as List<dynamic>? ?? [];
        try {
          final translationSvc = context.read<TranslationService>();
          final seen = <String>{};
          for (final raw in items2) {
            final item = raw as Map<String, dynamic>;
            final productName = (item['productName'] as String?)?.trim() ?? '';
            final productId = (item['productId'] as String?)?.trim() ?? '';
            if (productName.isEmpty || seen.contains(productName)) continue;
            seen.add(productName);
            final entityId = productId.isNotEmpty ? productId : productName;
            final translated = await translationSvc.translate(
              entityType: TranslationEntityType.product,
              entityId: entityId,
              fieldName: 'name',
              text: productName,
              from: sourceLang,
              to: exportLang,
            );
            if (translated != null && translated != productName) {
              final key = productId.isNotEmpty ? productId : productName;
              exportTranslatedNames[key] = translated;
            }
          }
        } catch (_) {}
      }
    }

    try {
      final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
      if (format == 'pdf') {
        final bytes = await OrderListExportService.buildOrderPdfBytesFromPayload(
          payload: payload,
          t: tLang,
          translatedNames: exportTranslatedNames.isNotEmpty ? exportTranslatedNames : null,
          translatedComment: exportTranslatedComment,
          currency: currency,
        );
        await saveFileBytes('order_${supplier}_$dateStr.pdf', bytes);
      } else {
        final bytes = await OrderListExportService.buildOrderExcelBytesFromPayload(
          payload: payload,
          t: tLang,
          translatedNames: exportTranslatedNames.isNotEmpty ? exportTranslatedNames : null,
          translatedComment: exportTranslatedComment,
          currency: currency,
        );
        await saveFileBytes('order_${supplier}_$dateStr.xlsx', bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Файл сохранён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error ?? 'Документ не найден', style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.pop(), child: Text(loc.t('back') ?? 'Назад')),
            ],
          ),
        ),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    final grandTotal = (payload['grandTotal'] as num?)?.toDouble() ?? 0;
    final rawComment = (payload['comment'] as String?)?.trim() ?? '';
    final comment = (_translatedComment?.isNotEmpty == true) ? _translatedComment! : rawComment;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('product_order')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download') ?? 'Сохранить',
            onPressed: _showSaveFormatDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(loc, header),
            const SizedBox(height: 24),
            Text(
              loc.t('order_export_list') ?? 'Список',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildTable(theme, loc, items, grandTotal),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${loc.t('order_list_comment')}: $comment',
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(LocalizationService loc, Map<String, dynamic> header) {
    final createdAt = header['createdAt'] != null ? DateTime.tryParse(header['createdAt'].toString())?.toLocal() : null;
    final orderFor = header['orderForDate'] != null ? DateTime.tryParse(header['orderForDate'].toString())?.toLocal() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(loc.t('inbox_header_employee') ?? 'Кто отправил', header['employeeName'] ?? '—'),
        _row(loc.t('order_export_date_time') ?? 'Дата отправки', createdAt != null ? DateFormat('dd.MM.yyyy HH:mm').format(createdAt) : '—'),
        _row(loc.t('order_export_to') ?? 'Поставщик', header['supplierName'] ?? '—'),
        _row(loc.t('order_export_from') ?? 'Заведение', header['establishmentName'] ?? '—'),
        _row(loc.t('order_export_order_for') ?? 'На дату', orderFor != null ? DateFormat('dd.MM.yyyy').format(orderFor) : '—'),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildTable(ThemeData theme, LocalizationService loc, List<dynamic> items, double grandTotal) {
    // Минимальные ширины колонок (px): #, наименование, ед., кол-во, цена, сумма
    const colWidths = [28.0, 160.0, 48.0, 52.0, 68.0, 68.0];
    final totalMinWidth = colWidths.fold(0.0, (a, b) => a + b);

    return LayoutBuilder(
      builder: (_, constraints) {
        // Если экрана достаточно — растягиваем, иначе горизонтальный скролл
        final availableWidth = constraints.maxWidth;
        final useScroll = availableWidth < totalMinWidth;
        final tableWidth = useScroll ? totalMinWidth : availableWidth;

        Widget buildTable() => SizedBox(
          width: tableWidth,
          child: Table(
            border: TableBorder.all(color: theme.dividerColor),
            columnWidths: {
              0: FixedColumnWidth(colWidths[0]),
              1: useScroll
                  ? FixedColumnWidth(colWidths[1])
                  : FlexColumnWidth(colWidths[1]),
              2: FixedColumnWidth(colWidths[2]),
              3: FixedColumnWidth(colWidths[3]),
              4: FixedColumnWidth(colWidths[4]),
              5: FixedColumnWidth(colWidths[5]),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
                children: [
                  _cell(theme, loc.t('order_export_no') ?? '#', bold: true),
                  _cell(theme, loc.t('inventory_item_name'), bold: true),
                  _cell(theme, loc.t('order_list_unit'), bold: true),
                  _cell(theme, loc.t('order_list_quantity'), bold: true),
                  _cell(theme, loc.t('order_list_unit_price') ?? 'Цена', bold: true),
                  _cell(theme, _lineTotalHeader(loc), bold: true),
                ],
              ),
              ...items.asMap().entries.map((e) {
                final item = e.value as Map<String, dynamic>;
                return TableRow(
                  children: [
                    _cell(theme, '${e.key + 1}'),
                    _cell(theme, _getItemName(item)),
                    _cell(theme, CulinaryUnits.displayName((item['unit'] ?? '').toString(), loc.currentLanguageCode)),
                    _cell(theme, _fmtNum(item['quantity'])),
                    _cell(theme, _fmtSum(item['pricePerUnit'])),
                    _cell(theme, _fmtSum(item['lineTotal'])),
                  ],
                );
              }),
              TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
                children: [
                  _cell(theme, '', bold: true),
                  _cell(theme, loc.t('order_list_grand_total') ?? 'Итого:', bold: true),
                  _cell(theme, '', bold: true),
                  _cell(theme, '', bold: true),
                  _cell(theme, '', bold: true),
                  _cell(theme, _fmtSum(grandTotal), bold: true),
                ],
              ),
            ],
          ),
        );

        if (useScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: buildTable(),
          );
        }
        return buildTable();
      },
    );
  }

  Widget _cell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: theme.colorScheme.onSurface,
          height: 1.3,
        ),
        softWrap: true,
      ),
    );
  }

  String _lineTotalHeader(LocalizationService loc) {
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
    final t = loc.t('order_list_line_total_currency') ?? 'Сумма %s';
    return t.replaceFirst('%s', currency);
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '—';
    if (v is num) return NumberFormatUtils.formatDecimal(v);
    return v.toString();
  }

  String _fmtSum(dynamic v) {
    if (v == null) return '—';
    if (v is num) {
      final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
      return NumberFormatUtils.formatSum(v, currency);
    }
    return v.toString();
  }
}
