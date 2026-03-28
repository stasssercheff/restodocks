import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart' show appBarBackButton;

const _platformAdminEmails = <String>{'stasssercheff@gmail.com'};

bool _isPlatformAdminEmail(String email) =>
    _platformAdminEmails.contains(email.toLowerCase().trim());

/// Журнал записей из таблицы `system_errors` (склад, POS, клиент).
class SystemErrorsScreen extends StatefulWidget {
  const SystemErrorsScreen({super.key});

  @override
  State<SystemErrorsScreen> createState() => _SystemErrorsScreenState();
}

class _SystemErrorsScreenState extends State<SystemErrorsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _rows = [];
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await SystemErrorService.instance.listRecent(
        establishmentId: est.id,
      );
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final account = context.watch<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    final allowed = posCanRunWarehouseHealthCheck(emp) ||
        (emp != null && _isPlatformAdminEmail(emp.email));

    final title = loc.t('system_errors_screen_title');

    if (!allowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: appBarBackButton(context),
        ),
        body: Center(
          child: Text(loc.t('fiscal_access_denied')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: appBarBackButton(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.25,
                            ),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  loc.t('system_errors_empty'),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            final msg = r['message'] as String? ?? '';
                            final sev = r['severity'] as String? ?? 'error';
                            final at = r['created_at'] as String?;
                            final ctx = r['context'];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                title: Text(
                                  msg,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_fmtTime(at)} · $sev',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                children: [
                                  if (ctx != null)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        16,
                                      ),
                                      child: SelectableText(
                                        _prettyJson(ctx),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return iso;
      return dt.toLocal().toString().split('.').first;
    } catch (_) {
      return iso;
    }
  }

  String _prettyJson(dynamic ctx) {
    try {
      if (ctx is Map) {
        const encoder = JsonEncoder.withIndent('  ');
        return encoder.convert(ctx);
      }
      return ctx.toString();
    } catch (_) {
      return '$ctx';
    }
  }
}
