import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart';

/// Очередь `fiscal_outbox`: просмотр и снятие ошибочных записей до подключения ККТ.
class FiscalOutboxScreen extends StatefulWidget {
  const FiscalOutboxScreen({super.key});

  @override
  State<FiscalOutboxScreen> createState() => _FiscalOutboxScreenState();
}

class _FiscalOutboxScreenState extends State<FiscalOutboxScreen> {
  bool _loading = true;
  Object? _error;
  List<FiscalOutboxEntry> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await FiscalOutboxService.instance.fetchRecent(est.id);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _statusLabel(LocalizationService loc, String s) {
    switch (s) {
      case 'pending':
        return loc.t('fiscal_outbox_status_pending');
      case 'synced':
        return loc.t('fiscal_outbox_status_synced');
      case 'failed':
        return loc.t('fiscal_outbox_status_failed');
      case 'skipped':
        return loc.t('fiscal_outbox_status_skipped');
      default:
        return s;
    }
  }

  Future<void> _skip(FiscalOutboxEntry e) async {
    final loc = context.read<LocalizationService>();
    try {
      await FiscalOutboxService.instance.markSkipped(e.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('fiscal_outbox_skipped_done'))),
      );
      await _load();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${loc.t('error')}: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final allowed = posCanManageFiscalTaxSettings(emp);

    if (!allowed) {
      return Scaffold(
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: Text(loc.t('fiscal_outbox_title')),
        ),
        body: Center(child: Text(loc.t('fiscal_access_denied'))),
      );
    }

    final fmt = DateFormat.yMMMd().add_Hm();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('fiscal_outbox_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('$_error', textAlign: TextAlign.center),
                  ),
                )
              : _items.isEmpty
                  ? Center(child: Text(loc.t('fiscal_outbox_empty')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          final payloadShort = jsonEncode(e.payload);
                          final sub = payloadShort.length > 120
                              ? '${payloadShort.substring(0, 120)}…'
                              : payloadShort;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          fmt.format(e.createdAt.toLocal()),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          _statusLabel(loc, e.status),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (e.posOrderId != null)
                                    Text(
                                      '${loc.t('fiscal_outbox_order')}: ${e.posOrderId}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  if (e.errorMessage != null &&
                                      e.errorMessage!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${loc.t('fiscal_outbox_error')}: ${e.errorMessage}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      sub,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontFamily: 'monospace',
                                          ),
                                    ),
                                  ),
                                  if (e.status == 'failed')
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => _skip(e),
                                        child: Text(
                                          loc.t('fiscal_outbox_mark_skipped'),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
