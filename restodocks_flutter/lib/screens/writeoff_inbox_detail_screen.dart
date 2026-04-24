import 'dart:async';

import 'package:excel/excel.dart' hide TextSpan;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../services/inventory_download.dart';
import '../utils/employee_display_utils.dart';
import '../utils/employee_name_translation_utils.dart';
import '../utils/translit_utils.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр списания из входящих.
class WriteoffInboxDetailScreen extends StatefulWidget {
  const WriteoffInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<WriteoffInboxDetailScreen> createState() =>
      _WriteoffInboxDetailScreenState();
}

class _WriteoffInboxDetailScreenState extends State<WriteoffInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  Employee? _authorEmployee;
  bool _loading = true;
  String? _error;
  List<TechCard> _techCards = [];
  final Map<String, String> _localizedRowNames = {};
  String? _translatedComment;
  /// Строка «сотрудник» после перевода ФИО (без «транслита вместо перевода»).
  String? _authorHeaderResolved;
  String? _rawAuthorHeaderResolved;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProductStoreSupabase>().loadProducts(force: true);
    });
  }

  String _localizedRowProductNameSync(
    Map<String, dynamic> r,
    String lang,
    ProductStoreSupabase store,
    List<TechCard> techCards,
  ) {
    final pid = r['productId']?.toString() ?? '';
    final fallback = r['productName']?.toString() ?? '';
    if (pid.isEmpty) return fallback;
    if (pid.startsWith('pf_')) {
      final tcId = pid.length > 3 ? pid.substring(3) : '';
      if (tcId.isEmpty) return fallback;
      for (final tc in techCards) {
        if (tc.id == tcId) return tc.getDisplayNameInLists(lang);
      }
      return fallback;
    }
    for (final p in store.allProducts) {
      if (p.id == pid) return p.getLocalizedName(lang);
    }
    return fallback;
  }

  String _rowDisplayName(
    Map<String, dynamic> r,
    String lang,
    ProductStoreSupabase store,
  ) {
    final pid = (r['productId']?.toString() ?? '').trim();
    final pname = (r['productName']?.toString() ?? '').trim();
    if (pid.isNotEmpty && _localizedRowNames.containsKey(pid)) {
      return _localizedRowNames[pid]!;
    }
    if (pname.isNotEmpty && _localizedRowNames.containsKey(pname)) {
      return _localizedRowNames[pname]!;
    }
    return _localizedRowProductNameSync(r, lang, store, _techCards);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final acc = context.read<AccountManagerSupabase>();
    final doc = await InventoryDocumentService().getById(widget.documentId);
    Employee? author;
    if (doc != null && mounted) {
      final empId = doc['created_by_employee_id']?.toString();
      final estId = doc['establishment_id']?.toString();
      if (empId != null && estId != null) {
        try {
          final emps = await acc.getEmployeesForEstablishment(estId);
          for (final e in emps) {
            if (e.id == empId) {
              author = e;
              break;
            }
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _authorEmployee = author;
      _loading = false;
      if (doc == null)
        _error = context.read<LocalizationService>().t('document_not_found');
    });
    if (doc != null) {
      final estId = context.read<AccountManagerSupabase>().establishment?.id;
      context.read<InboxViewedService>().addViewed(estId, widget.documentId);
      unawaited(_afterDocLoaded(doc));
    }
  }

  Future<void> _afterDocLoaded(Map<String, dynamic> doc) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final dataEstId = est?.dataEstablishmentId ?? est?.id;
    var cards = <TechCard>[];
    if (dataEstId != null) {
      try {
        cards = await TechCardServiceSupabase()
            .getTechCardsForEstablishment(dataEstId);
      } catch (_) {}
    }
    if (mounted) setState(() => _techCards = cards);
    await _resolveAuthorHeader();
    await _loadRowLocalizedNames(doc, cards);
    await _translateWriteoffComment(doc);
  }

  Future<void> _resolveAuthorHeader() async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final ts = context.read<TranslationService>();
    final acc = context.read<AccountManagerSupabase>();
    final lang = loc.currentLanguageCode;
    final payload = _doc?['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rawEmp = header['employeeName']?.toString() ?? '—';

    if (_authorEmployee != null) {
      final name = await translatePersonName(ts, _authorEmployee!, lang);
      final pos = employeePositionLine(
        _authorEmployee!,
        loc,
        establishment: acc.establishment,
      );
      final line = pos == '—' ? name : '$name · $pos';
      if (mounted) setState(() => _authorHeaderResolved = line);
      return;
    }
    if (rawEmp.isNotEmpty && rawEmp != '—') {
      final t = await translateAdHocPersonName(ts, rawEmp, lang);
      if (mounted) setState(() => _rawAuthorHeaderResolved = t);
    }
  }

  Future<void> _translateWriteoffComment(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final comment = (payload['comment'] as String?)?.trim() ?? '';
    if (comment.isEmpty) return;
    final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
    final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : 'ru';
    if (sourceLang == targetLang) return;
    try {
      final translationSvc = context.read<TranslationService>();
      final commentHash = comment.hashCode.toRadixString(16);
      final translated = await translationSvc.translate(
        entityType: TranslationEntityType.ui,
        entityId:
            'writeoff_comment_${doc['id'] ?? commentHash}_$commentHash',
        fieldName: 'comment',
        text: comment,
        from: sourceLang,
        to: targetLang,
      );
      if (translated != null &&
          translated.trim().isNotEmpty &&
          translated != comment &&
          mounted) {
        setState(() => _translatedComment = translated);
      }
    } catch (_) {}
  }

  Future<void> _loadRowLocalizedNames(
    Map<String, dynamic> doc,
    List<TechCard> techCards,
  ) async {
    if (!mounted) return;
    final lang = context.read<LocalizationService>().currentLanguageCode;
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
    final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : 'ru';
    final rows = payload['rows'] as List<dynamic>? ?? [];
    if (rows.isEmpty) return;

    final store = context.read<ProductStoreSupabase>();
    if (store.allProducts.isEmpty) await store.loadProducts();

    final updated = <String, String>{};
    final needDeepL = <Map<String, dynamic>>[];

    for (final raw in rows) {
      final item = raw as Map<String, dynamic>;
      final productId = item['productId']?.toString() ?? '';
      final productName = (item['productName'] as String?)?.trim() ?? '';
      if (productName.isEmpty) continue;

      if (sourceLang == lang) continue;

      if (productId.startsWith('pf_')) {
        final tcId = productId.length > 3 ? productId.substring(3) : '';
        TechCard? tc;
        for (final x in techCards) {
          if (x.id == tcId) {
            tc = x;
            break;
          }
        }
        if (tc != null) {
          final locName = tc.getDisplayNameInLists(lang);
          if (locName != productName) updated[productId] = locName;
        } else {
          needDeepL.add(item);
        }
        continue;
      }

      if (productId.isNotEmpty) {
        Product? product;
        for (final p in store.allProducts) {
          if (p.id == productId) {
            product = p;
            break;
          }
        }
        if (product != null) {
          final locName = product.getLocalizedName(lang);
          if (locName != productName) {
            updated[productId] = locName;
          } else {
            final updatedNames = await store.translateProductAwait(productId);
            final translated = updatedNames?[lang];
            if (translated != null && translated != productName) {
              updated[productId] = translated;
            }
          }
          continue;
        }
      }
      needDeepL.add(item);
    }

    if (mounted && updated.isNotEmpty) {
      setState(() => _localizedRowNames.addAll(updated));
    }

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
        if (translated != null &&
            translated != productName &&
            mounted) {
          final key = productId.isNotEmpty ? productId : productName;
          setState(() => _localizedRowNames[key] = translated);
        }
      }
    } catch (_) {}
  }

  String _categoryName(LocalizationService loc, String? code) {
    switch (code) {
      case 'staff':
        return loc.t('writeoff_category_staff');
      case 'workingThrough':
        return loc.t('writeoff_category_working');
      case 'spoilage':
        return loc.t('writeoff_category_spoilage');
      case 'breakage':
        return loc.t('writeoff_category_breakage');
      case 'guestRefusal':
        return loc.t('writeoff_category_guest_refusal');
      case 'generic':
        return loc.t('writeoff_category_simple');
      default:
        return code ?? '—';
    }
  }

  Future<void> _showSaveLanguageAndExport() async {
    final loc = context.read<LocalizationService>();
    final payload = _doc?['payload'] as Map<String, dynamic>? ?? {};
    String selectedLang = loc.currentLanguageCode;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setState) => AlertDialog(
          title: Text(loc.t('writeoff_save_lang_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('inventory_export_lang'),
                style: Theme.of(ctx2).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: LocalizationService.productLanguageCodes.map((code) {
                  return ChoiceChip(
                    label: Text(loc.getLanguageName(code)),
                    selected: selectedLang == code,
                    onSelected: (_) => setState(() => selectedLang = code),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(MaterialLocalizations.of(ctx2).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selectedLang),
              child: Text(loc.t('inventory_export_excel')),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;

    try {
      final account = context.read<AccountManagerSupabase>();
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        try {
          await account.trialIncrementDeviceSaveOrThrow(
            establishmentId: est.id,
            docKind: TrialDeviceSaveKinds.writeoff,
          );
        } catch (e) {
          if (e.toString().contains('TRIAL_DEVICE_SAVE_CAP')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'В первые 72 часа можно сохранить не более 3 документов этого типа.'),
                ),
              );
            }
            return;
          }
          rethrow;
        }
      }
      final bytes = _buildExcelBytes(payload, result);
      if (bytes != null && bytes.isNotEmpty) {
        final header = payload['header'] as Map<String, dynamic>? ?? {};
        final date =
            header['date'] ?? DateTime.now().toIso8601String().split('T').first;
        final cat = payload['category']?.toString() ?? 'writeoff';
        await saveFileBytes('writeoff_${cat}_$date.xlsx', bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    loc.t('inventory_excel_downloaded'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${loc.t('error')}: $e')));
      }
    }
  }

  List<int>? _buildExcelBytes(Map<String, dynamic> payload, String saveLang) {
    try {
      final loc = context.read<LocalizationService>();
      final excel = Excel.createExcel();
      final sheet = excel['Списание'];
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      var rows = payload['rows'] as List<dynamic>? ?? [];
      sheet.appendRow([
        TextCellValue(loc.t('inventory_excel_number')),
        TextCellValue(loc.t('inventory_item_name')),
        TextCellValue(loc.t('inventory_unit')),
        TextCellValue(loc.t('inventory_excel_total')),
      ]);
      rows = rows.map((e) => e as Map<String, dynamic>).toList();
      final store = context.read<ProductStoreSupabase>();
      rows.sort((a, b) => _localizedRowProductNameSync(a, saveLang, store, _techCards)
          .toLowerCase()
          .compareTo(
              _localizedRowProductNameSync(b, saveLang, store, _techCards).toLowerCase()));
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final unitRaw = (r['unit']?.toString() ?? 'g').trim().toLowerCase();
        sheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(_localizedRowProductNameSync(r, saveLang, store, _techCards)),
          TextCellValue(LocalizationService().unitLabelForLanguage(unitRaw, saveLang)),
          DoubleCellValue((r['total'] as num?)?.toDouble() ?? 0),
        ]);
      }
      final comment = payload['comment']?.toString();
      if (comment != null && comment.isNotEmpty) {
        sheet.appendRow([]);
        sheet.appendRow([
          TextCellValue(loc.t('writeoff_comment')),
          TextCellValue(comment)
        ]);
      }
      excel.setDefaultSheet('Списание');
      return excel.encode();
    } catch (_) {
      return null;
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
              Text(_error ?? loc.t('document_not_found'),
                  style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => context.pop(),
                  child: Text(loc.t('back'))),
            ],
          ),
        ),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    var rows = (payload['rows'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final store = context.watch<ProductStoreSupabase>();
    final acc = context.watch<AccountManagerSupabase>();
    final layoutPrefs = context.watch<ScreenLayoutPreferenceService>();
    final useTranslit =
        loc.currentLanguageCode != 'ru' || layoutPrefs.showNameTranslit;
    final lang = loc.currentLanguageCode;
    rows.sort((a, b) => _rowDisplayName(a, lang, store)
        .toLowerCase()
        .compareTo(_rowDisplayName(b, lang, store).toLowerCase()));
    final comment = payload['comment']?.toString();
    final rawEmp = header['employeeName']?.toString() ?? '—';
    final String empHeader;
    if (_authorHeaderResolved != null) {
      empHeader = _authorHeaderResolved!;
    } else if (_rawAuthorHeaderResolved != null && rawEmp != '—') {
      empHeader = _rawAuthorHeaderResolved!;
    } else if (_authorEmployee != null) {
      empHeader = employeeNameWithPositionLine(
        _authorEmployee!,
        loc,
        establishment: acc.establishment,
        translit: useTranslit,
      );
    } else if (rawEmp == '—') {
      empHeader = rawEmp;
    } else {
      empHeader = useTranslit ? cyrillicToLatin(rawEmp) : rawEmp;
    }

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('writeoffs')),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: loc.t('download'),
            onPressed: _showSaveLanguageAndExport,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerRow(loc.t('inventory_establishment'),
                header['establishmentName'] ?? '—'),
            _headerRow(loc.t('inventory_employee'), empHeader),
            _headerRow(loc.t('inventory_date'), header['date'] ?? '—'),
            _headerRow(loc.t('writeoffs'),
                _categoryName(loc, payload['category']?.toString())),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                loc.t('writeoff_comment'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(comment, style: theme.textTheme.bodyMedium),
              if (_translatedComment != null &&
                  _translatedComment!.trim().isNotEmpty &&
                  _translatedComment != comment) ...[
                const SizedBox(height: 6),
                Text(
                  _translatedComment!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            Text(
              loc.t('inventory_item_name'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Table(
              border: TableBorder.all(color: theme.dividerColor),
              columnWidths: const {
                0: FlexColumnWidth(0.4),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(0.5),
                3: FlexColumnWidth(0.6),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest),
                  children: [
                    _cell(theme, '#', bold: true),
                    _cell(theme, loc.t('inventory_item_name'), bold: true),
                    _cell(theme, loc.t('inventory_unit'), bold: true),
                    _cell(theme, loc.t('inventory_excel_total'), bold: true),
                  ],
                ),
                ...rows.asMap().entries.map((e) {
                  final r = e.value;
                  final unitRaw =
                      (r['unit']?.toString() ?? 'g').trim().toLowerCase();
                  return TableRow(
                    children: [
                      _cell(theme, '${e.key + 1}'),
                      _cell(theme, _rowDisplayName(r, lang, store)),
                      _cell(theme, LocalizationService().unitLabelForLanguage(unitRaw, lang)),
                      _cell(theme, _fmt(r['total'])),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _cell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium
            ?.copyWith(fontWeight: bold ? FontWeight.w600 : null),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is num)
      return v == v.truncateToDouble()
          ? v.toInt().toString()
          : v.toStringAsFixed(1);
    return v.toString();
  }
}
