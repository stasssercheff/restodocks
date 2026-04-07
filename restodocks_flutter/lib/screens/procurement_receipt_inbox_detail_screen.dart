import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Просмотр приёмки поставки из входящих.
class ProcurementReceiptInboxDetailScreen extends StatefulWidget {
  const ProcurementReceiptInboxDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  State<ProcurementReceiptInboxDetailScreen> createState() =>
      _ProcurementReceiptInboxDetailScreenState();
}

class _ProcurementReceiptInboxDetailScreenState
    extends State<ProcurementReceiptInboxDetailScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final d = await ProcurementReceiptService.instance.getById(widget.documentId);
    if (!mounted) return;
    setState(() {
      _doc = d;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final currency =
        context.watch<AccountManagerSupabase>().establishment?.defaultCurrency ?? '—';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('procurement_receipt_title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_doc == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('procurement_receipt_title'))),
        body: Center(child: Text(loc.t('document_not_found'))),
      );
    }

    final payload = _doc!['payload'] as Map<String, dynamic>? ?? {};
    final header = payload['header'] as Map<String, dynamic>? ?? {};
    final items = payload['items'] as List<dynamic>? ?? [];
    final supplier = header['supplierName']?.toString() ?? '—';
    final ordered = header['orderedGrandTotal'];
    final received = header['receivedGrandTotal'];
    final created = _doc!['created_at'] != null
        ? DateTime.tryParse(_doc!['created_at'].toString())?.toLocal()
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('procurement_receipt_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${loc.t('inbox_header_supplier')}: $supplier'),
          if (created != null)
            Text('${loc.t('inbox_header_date')}: ${DateFormat('dd.MM.yyyy HH:mm').format(created)}'),
          if (ordered != null)
            Text('${loc.t('procurement_receipt_total_ordered')}: $ordered $currency'),
          if (received != null)
            Text('${loc.t('procurement_receipt_total_received')}: $received $currency'),
          const Divider(height: 24),
          ...items.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final m = Map<String, dynamic>.from(raw);
            final name = m['productName']?.toString() ?? '—';
            final rq = m['receivedQuantity'];
            final ap = m['actualPricePerUnit'];
            final lt = m['lineTotal'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('$name · ${loc.t('procurement_receipt_received_qty')}: $rq · '
                  '${loc.t('procurement_receipt_actual_price')}: $ap · '
                  '${loc.t('procurement_receipt_line_total')}: $lt'),
            );
          }),
        ],
      ),
    );
  }
}
