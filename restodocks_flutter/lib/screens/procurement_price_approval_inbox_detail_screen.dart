import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Согласование цен номенклатуры по факту приёмки (шеф во входящих).
class ProcurementPriceApprovalInboxDetailScreen extends StatefulWidget {
  const ProcurementPriceApprovalInboxDetailScreen({
    super.key,
    required this.approvalId,
  });

  final String approvalId;

  @override
  State<ProcurementPriceApprovalInboxDetailScreen> createState() =>
      _ProcurementPriceApprovalInboxDetailScreenState();
}

class _ProcurementPriceApprovalInboxDetailScreenState
    extends State<ProcurementPriceApprovalInboxDetailScreen> {
  Map<String, dynamic>? _row;
  bool _loading = true;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final r = await ProcurementPriceApprovalService.instance
        .getById(widget.approvalId);
    if (!mounted) return;
    final lines = r?['lines'];
    if (lines is List) {
      for (final x in lines) {
        if (x is Map && x['productId'] != null) {
          _selected.add(x['productId'].toString());
        }
      }
    }
    setState(() {
      _row = r;
      _loading = false;
    });
  }

  Future<void> _apply() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null || _row == null) return;
    final loc = context.read<LocalizationService>();
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.t('procurement_price_approval_select_one')),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final store = context.read<ProductStoreSupabase>();
      await ProcurementPriceApprovalService.instance.applySelected(
        row: _row!,
        productIds: _selected.toList(),
        resolverEmployeeId: emp.id,
        store: store,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('procurement_price_approval_applied'))),
      );
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _cancel() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    final loc = context.read<LocalizationService>();
    setState(() => _loading = true);
    try {
      await ProcurementPriceApprovalService.instance.cancel(
        approvalId: widget.approvalId,
        resolverEmployeeId: emp.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('procurement_price_approval_cancelled'))),
      );
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final currency =
        context.watch<AccountManagerSupabase>().establishment?.defaultCurrency ??
            '—';
    final nf = NumberFormat.decimalPattern('ru');

    if (_loading && _row == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('procurement_price_approval_title')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_row == null) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('procurement_price_approval_title')),
        ),
        body: Center(child: Text(loc.t('document_not_found'))),
      );
    }

    final status = _row!['status']?.toString() ?? '';
    final linesRaw = _row!['lines'];
    final lines = linesRaw is List ? linesRaw : <dynamic>[];
    final pending = status == 'pending';

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('procurement_price_approval_title')),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                loc.t('procurement_price_approval_hint'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!pending) ...[
                const SizedBox(height: 8),
                Text(
                  status == 'applied'
                      ? loc.t('procurement_price_approval_status_applied')
                      : loc.t('procurement_price_approval_status_cancelled'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
              const SizedBox(height: 16),
              ...lines.map((raw) {
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw);
                final pid = m['productId']?.toString() ?? '';
                final name = m['productName']?.toString() ?? '—';
                final unit = m['unit']?.toString() ?? '';
                final oldP = m['oldPricePerUnit'];
                final newP = m['newPricePerUnit'];
                final oldStr = oldP == null
                    ? '—'
                    : nf.format((oldP as num).toDouble());
                final newStr = newP == null
                    ? '—'
                    : nf.format((newP as num).toDouble());
                return CheckboxListTile(
                  value: _selected.contains(pid),
                  onChanged: pending
                      ? (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(pid);
                            } else {
                              _selected.remove(pid);
                            }
                          });
                        }
                      : null,
                  title: Text(name),
                  subtitle: Text(
                    '$unit · ${loc.t('procurement_price_approval_old')}: $oldStr → '
                    '${loc.t('procurement_price_approval_new')}: $newStr $currency',
                  ),
                );
              }),
            ],
          ),
          if (_loading && _row != null)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: pending
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: _loading ? null : _apply,
                      child: Text(loc.t('procurement_price_approval_apply')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading ? null : _cancel,
                      child: Text(loc.t('procurement_price_approval_cancel')),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
