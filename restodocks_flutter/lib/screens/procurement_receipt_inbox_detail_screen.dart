import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
  bool _confirming = false;

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

  bool _canConfirmManagement(Employee? e) {
    if (e == null) return false;
    return e.hasRole('owner') ||
        e.hasRole('executive_chef') ||
        e.hasRole('sous_chef') ||
        e.hasRole('bar_manager') ||
        e.hasRole('floor_manager') ||
        e.hasRole('general_manager');
  }

  Future<void> _confirmManagement() async {
    final doc = _doc;
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (doc == null || emp == null) return;
    final payload = Map<String, dynamic>.from(doc['payload'] as Map? ?? {});
    final header = Map<String, dynamic>.from(payload['header'] as Map? ?? {});
    setState(() => _confirming = true);
    try {
      header['pendingManagementApproval'] = false;
      header['managementApprovedAt'] = DateTime.now().toUtc().toIso8601String();
      header['managementApprovedByEmployeeId'] = emp.id;
      payload['header'] = header;
      final ok = await ProcurementReceiptService.instance
          .updatePayload(widget.documentId, payload);
      if (!mounted) return;
      if (ok) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('procurement_receipt_saved'))),
        );
        await _load();
      } else {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.t('procurement_receipt_save_error')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final currency =
        context.watch<AccountManagerSupabase>().establishment?.defaultCurrency ?? '—';
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;

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
    final extRaw = header['externalReceiptDate']?.toString();
    DateTime? extDate;
    if (extRaw != null && extRaw.isNotEmpty) {
      extDate = DateTime.tryParse(extRaw);
    }
    final pendingMgmt = header['pendingManagementApproval'] == true;
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
          if (extDate != null)
            Text(
              '${loc.t('procurement_external_receipt_date')}: ${DateFormat('dd.MM.yyyy').format(extDate.toLocal())}',
            ),
          if (ordered != null)
            Text('${loc.t('procurement_receipt_total_ordered')}: $ordered $currency'),
          if (received != null)
            Text('${loc.t('procurement_receipt_total_received')}: $received $currency'),
          if (pendingMgmt && _canConfirmManagement(emp)) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _confirming ? null : _confirmManagement,
              child: _confirming
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(loc.t('procurement_confirm_goods_receipt')),
            ),
          ],
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
