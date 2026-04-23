import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/translation.dart';
import '../services/inventory_download.dart';
import '../services/services.dart';
import '../utils/employee_name_translation_utils.dart';
import '../utils/number_format_utils.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';

/// Полученные и отправленные заказы продуктов: просмотр и скачивание.
class ProductOrderReceivedScreen extends StatefulWidget {
  const ProductOrderReceivedScreen({super.key});

  @override
  State<ProductOrderReceivedScreen> createState() => _ProductOrderReceivedScreenState();
}

class _ProductOrderReceivedScreenState extends State<ProductOrderReceivedScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  final Map<String, String> _translatedEmployeeByDocId = {};
  final Map<String, String> _translatedSupplierByDocId = {};
  final Map<String, String> _translatedItemNames = {};
  String? _translatedForLang;

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
    try {
      final account = context.read<AccountManagerSupabase>();
      final establishmentId = account.establishment?.id;
      if (establishmentId == null) {
        setState(() {
          _loading = false;
          _error = 'Заведение не выбрано';
        });
        return;
      }

      final docs = await OrderDocumentService().listForEstablishment(establishmentId);

      if (mounted) {
        setState(() {
          _orders = docs;
          _loading = false;
        });
        _translateOrderData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (_translatedForLang != lang && _orders.isNotEmpty) {
      _translateOrderData();
    }
  }

  Future<void> _translateOrderData() async {
    if (!mounted || _orders.isEmpty) return;
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    final store = context.read<ProductStoreSupabase>();
    final ts = context.read<TranslationService>();

    if (store.allProducts.isEmpty) {
      await store.loadProducts();
    }

    final employees = <String, String>{};
    final suppliers = <String, String>{};
    final items = <String, String>{};

    for (final doc in _orders) {
      final docId = doc['id']?.toString() ?? '';
      if (docId.isEmpty) continue;
      final payload = doc['payload'] as Map<String, dynamic>? ?? {};
      final header = payload['header'] as Map<String, dynamic>? ?? {};
      final sourceLangRaw = (payload['sourceLang'] as String?)?.trim() ?? '';
      final sourceLang = sourceLangRaw.isNotEmpty ? sourceLangRaw : 'ru';

      final employeeName = (header['employeeName'] ?? '').toString().trim();
      if (employeeName.isNotEmpty && employeeName != '—') {
        employees[docId] =
            await translateAdHocPersonName(ts, employeeName, targetLang);
      }

      final supplierName = (header['supplierName'] ?? '').toString().trim();
      if (supplierName.isNotEmpty && supplierName != '—') {
        if (sourceLang == targetLang) {
          suppliers[docId] = supplierName;
        } else {
          try {
            final translated = await ts.translate(
              entityType: TranslationEntityType.ui,
              entityId: 'order_supplier_$docId',
              fieldName: 'supplier_name',
              text: supplierName,
              from: sourceLang,
              to: targetLang,
            );
            suppliers[docId] = (translated != null && translated.trim().isNotEmpty)
                ? translated.trim()
                : supplierName;
          } catch (_) {
            suppliers[docId] = supplierName;
          }
        }
      }

      final rows = payload['items'] as List<dynamic>? ??
          payload['rows'] as List<dynamic>? ??
          [];
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw as Map);
        final productId = (row['productId'] as String?)?.trim() ?? '';
        final productName = (row['productName'] as String?)?.trim() ?? '';
        if (productName.isEmpty) continue;
        final itemKey = '$docId::${productId.isNotEmpty ? productId : productName}';
        if (sourceLang == targetLang) {
          items[itemKey] = productName;
          continue;
        }
        if (productId.isNotEmpty) {
          final product = store.allProducts.where((p) => p.id == productId).firstOrNull;
          if (product != null) {
            final locName = product.getLocalizedName(targetLang);
            if (locName.trim().isNotEmpty) {
              items[itemKey] = locName;
              continue;
            }
          }
        }
        try {
          final translated = await ts.translate(
            entityType: TranslationEntityType.product,
            entityId: productId.isNotEmpty ? productId : productName,
            fieldName: 'name',
            text: productName,
            from: sourceLang,
            to: targetLang,
          );
          items[itemKey] = (translated != null && translated.trim().isNotEmpty)
              ? translated.trim()
              : productName;
        } catch (_) {
          items[itemKey] = productName;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _translatedForLang = targetLang;
      _translatedEmployeeByDocId
        ..clear()
        ..addAll(employees);
      _translatedSupplierByDocId
        ..clear()
        ..addAll(suppliers);
      _translatedItemNames
        ..clear()
        ..addAll(items);
    });
  }

  String _employeeNameForDoc(Map<String, dynamic> doc) {
    final docId = doc['id']?.toString() ?? '';
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final fallback = (header['employeeName'] ?? '—').toString();
    return _translatedEmployeeByDocId[docId] ?? fallback;
  }

  String _supplierNameForDoc(Map<String, dynamic> doc) {
    final docId = doc['id']?.toString() ?? '';
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final fallback = (header['supplierName'] ?? '—').toString();
    return _translatedSupplierByDocId[docId] ?? fallback;
  }

  String _itemNameForDocRow(Map<String, dynamic> doc, Map<String, dynamic> row) {
    final docId = doc['id']?.toString() ?? '';
    final productId = (row['productId'] as String?)?.trim() ?? '';
    final productName = (row['productName'] as String?)?.trim() ?? '';
    final key = '$docId::${productId.isNotEmpty ? productId : productName}';
    return _translatedItemNames[key] ?? productName;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final establishmentName = account.establishment?.name ?? '—';

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: ScrollToTopAppBarTitle(
          child: Text(loc.t('product_order')),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _buildBody(loc, establishmentName),
    );
  }

  Widget _buildBody(LocalizationService loc, String establishmentName) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Retry')),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('product_order_received_empty') ?? 'Sent orders will appear here',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text(loc.t('inbox_header_date') ?? 'Date', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_section') ?? 'Section', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_employee') ?? 'Employee', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(loc.t('inbox_header_supplier') ?? 'Supplier', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final order = _orders[i];
                return _OrderCard(
                  order: order,
                  establishmentName: establishmentName,
                  employeeName: _employeeNameForDoc(order),
                  supplierName: _supplierNameForDoc(order),
                  loc: loc,
                  onTap: () => _showOrderDetails(context, order, loc),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Map<String, dynamic> doc, LocalizationService loc) {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final rows = payload['items'] as List<dynamic>? ?? payload['rows'] as List<dynamic>? ?? [];
    final createdAt = DateTime.tryParse(doc['created_at']?.toString() ?? '') ?? DateTime.now();
    final employeeName = _employeeNameForDoc(doc);
    final establishmentName = header['establishmentName'] ?? '—';
    final supplierName = _supplierNameForDoc(doc);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(loc.t('order_details') ?? 'Order details', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              _detailRow(ctx, loc.t('inbox_header_date') ?? 'Date', DateFormat('dd.MM.yyyy HH:mm').format(createdAt)),
              _detailRow(ctx, loc.t('inbox_header_section') ?? 'Section', establishmentName),
              _detailRow(ctx, loc.t('inbox_header_employee') ?? 'Employee', employeeName),
              _detailRow(ctx, loc.t('inbox_header_supplier') ?? 'Supplier', supplierName),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: _buildOrderTable(ctx, loc, doc, rows),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.download),
                label: Text(loc.t('download') ?? 'Download'),
                onPressed: () => _downloadOrder(ctx, doc, loc),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildOrderTable(
      BuildContext context, LocalizationService loc, Map<String, dynamic> doc, List<dynamic> rows) {
    final theme = Theme.of(context);
    final hasPrices = rows.isNotEmpty && (rows.first as Map<String, dynamic>).containsKey('pricePerUnit');
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
    final lineTotalHeader = (loc.t('order_list_line_total_currency') ?? 'Amount %s').replaceFirst('%s', currency);
    if (hasPrices) {
      return Table(
        border: TableBorder.all(color: theme.dividerColor),
        columnWidths: const {0: FlexColumnWidth(2), 1: FixedColumnWidth(50), 2: FixedColumnWidth(70), 3: FixedColumnWidth(90), 4: FixedColumnWidth(90)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
            children: [
              _tableCell(theme, loc.t('inventory_item_name'), bold: true),
              _tableCell(theme, loc.t('order_list_unit'), bold: true),
              _tableCell(theme, loc.t('order_list_quantity'), bold: true),
              _tableCell(theme, loc.t('order_list_unit_price') ?? 'Price', bold: true),
              _tableCell(theme, lineTotalHeader, bold: true),
            ],
          ),
          ...rows.map((r) {
            final m = r as Map<String, dynamic>;
            return TableRow(
              children: [
                _tableCell(theme, _itemNameForDocRow(doc, m)),
                _tableCell(theme, (m['unit'] ?? '').toString()),
                _tableCell(theme, _fmtNum(m['quantity'])),
                _tableCell(theme, _fmtSum(m['pricePerUnit'], currency)),
                _tableCell(theme, _fmtSum(m['lineTotal'], currency)),
              ],
            );
          }),
        ],
      );
    }
    return Table(
      border: TableBorder.all(color: theme.dividerColor),
      columnWidths: const {0: FlexColumnWidth(2), 1: FixedColumnWidth(80), 2: FixedColumnWidth(100)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
          children: [
            _tableCell(theme, loc.t('inventory_item_name'), bold: true),
            _tableCell(theme, loc.t('order_list_unit'), bold: true),
            _tableCell(theme, loc.t('order_list_quantity'), bold: true),
          ],
        ),
        ...rows.map((r) {
          final m = r as Map<String, dynamic>;
          return TableRow(
            children: [
              _tableCell(theme, _itemNameForDocRow(doc, m)),
              _tableCell(theme, (m['unit'] ?? '').toString()),
              _tableCell(theme, _fmtNum(m['quantity'])),
            ],
          );
        }),
      ],
    );
  }

  Widget _tableCell(ThemeData theme, String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w600 : null)),
    );
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '—';
    if (v is num) return NumberFormatUtils.formatDecimal(v);
    return v.toString();
  }

  String _fmtSum(dynamic v, String currency) {
    if (v == null) return '—';
    if (v is num) return NumberFormatUtils.formatSum(v, currency);
    return v.toString();
  }

  Future<void> _downloadOrder(BuildContext context, Map<String, dynamic> doc, LocalizationService loc) async {
    final payload = doc['payload'] as Map<String, dynamic>? ?? {};
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
    try {
      final account = context.read<AccountManagerSupabase>();
      final est = account.establishment;
      if (est != null && account.isTrialOnlyWithoutPaid) {
        try {
          await account.trialIncrementDeviceSaveOrThrow(
            establishmentId: est.id,
            docKind: TrialDeviceSaveKinds.order,
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
      final bytes = await OrderListExportService.buildOrderExcelBytesFromPayload(
        payload: payload,
        t: (k) => loc.t(k) ?? k,
        currency: currency,
      );
      if (bytes.isNotEmpty) {
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(doc['created_at']?.toString() ?? '') ?? DateTime.now());
        await saveFileBytes('order_$dateStr.xlsx', bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('inventory_excel_downloaded') ?? 'Excel file saved')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('error_generic', args: {'error': '$e'})),
          ),
        );
      }
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.establishmentName,
    required this.employeeName,
    required this.supplierName,
    required this.loc,
    required this.onTap,
  });

  final Map<String, dynamic> order;
  final String establishmentName;
  final String employeeName;
  final String supplierName;
  final LocalizationService loc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payload = order['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();
    final dateStr = DateFormat('dd.MM.yyyy').format(createdAt);
    final supplier = supplierName;
    final estName = header['establishmentName'] ?? establishmentName;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 1, child: Text(dateStr, style: Theme.of(context).textTheme.bodyMedium)),
              Expanded(flex: 2, child: Text(estName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(employeeName, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(supplier, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis)),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
