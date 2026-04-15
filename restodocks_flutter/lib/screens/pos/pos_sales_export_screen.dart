import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/inventory_download.dart';
import '../../services/pos_sales_excel_export_service.dart';
import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';
import '../../widgets/subscription_required_dialog.dart';

/// Выгрузка продаж POS в Excel (4 листа).
class PosSalesExportScreen extends StatefulWidget {
  const PosSalesExportScreen({super.key});

  @override
  State<PosSalesExportScreen> createState() => _PosSalesExportScreenState();
}

class _PosSalesExportScreenState extends State<PosSalesExportScreen> {
  bool _exporting = false;
  Object? _error;
  late DateTime _rangeStartLocal;
  late DateTime _rangeEndLocal;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStartLocal = DateTime(now.year, now.month, now.day);
    _rangeEndLocal = _rangeStartLocal;
  }

  (DateTime, DateTime) _fromToUtc() {
    final fromLocal = DateTime(
      _rangeStartLocal.year,
      _rangeStartLocal.month,
      _rangeStartLocal.day,
    );
    final endDay = DateTime(
      _rangeEndLocal.year,
      _rangeEndLocal.month,
      _rangeEndLocal.day,
    );
    final toExclusiveLocal = endDay.add(const Duration(days: 1));
    return (fromLocal.toUtc(), toExclusiveLocal.toUtc());
  }

  Future<void> _pickRange() async {
    final loc = context.read<LocalizationService>();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _rangeStartLocal,
        end: _rangeEndLocal,
      ),
      helpText: loc.t('pos_sales_export_period'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _rangeStartLocal =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      _rangeEndLocal =
          DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
  }

  Future<void> _export() async {
    final loc = context.read<LocalizationService>();
    final account = context.read<AccountManagerSupabase>();
    if (!account.hasProSubscription) {
      showSubscriptionRequiredDialog(context);
      return;
    }
    final est = account.establishment;
    if (est == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('error_no_establishment_or_employee'))),
      );
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final range = _fromToUtc();
      final bundles = await PosOrderService.instance.fetchClosedOrdersWithSalesLines(
        establishmentId: est.id,
        fromUtc: range.$1,
        toUtc: range.$2,
      );
      final allLines = <PosOrderLine>[];
      for (final b in bundles) {
        allLines.addAll(b.lines);
      }
      final tech = TechCardServiceSupabase();
      final cards = await tech.getTechCardsForEstablishment(est.id);
      final tcById = {for (final c in cards) c.id: c};
      final bytes = PosSalesExcelExportService.instance.build(
        loc: loc,
        allLines: allLines,
        tcById: tcById,
      );
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('pos_sales_export_failed'))),
          );
        }
        return;
      }
      final df = DateFormat('yyyy-MM-dd');
      final fn =
          'pos_sales_${df.format(_rangeStartLocal)}_${df.format(_rangeEndLocal)}.xlsx';
      if (account.isTrialOnlyWithoutPaid) {
        await account.trialIncrementDeviceSaveOrThrow(
          establishmentId: est.id,
          docKind: TrialDeviceSaveKinds.productSummary,
        );
      }
      await saveFileBytes(fn, bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('pos_sales_export_done'))),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final df = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final rangeText =
        '${df.format(_rangeStartLocal)} — ${df.format(_rangeEndLocal)}';

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_sales_export_title')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t('pos_sales_export_body'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(rangeText),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.table_chart_outlined),
              label: Text(loc.t('pos_sales_export_button')),
            ),
          ],
        ),
      ),
    );
  }
}
