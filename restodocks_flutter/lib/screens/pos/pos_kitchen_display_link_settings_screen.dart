import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../widgets/app_bar_home_button.dart';
import 'kds_public_url.dart';

/// Создание и отзыв ссылки на гостевой KDS (ТВ / планшет без входа).
class PosKitchenDisplayLinkSettingsScreen extends StatefulWidget {
  const PosKitchenDisplayLinkSettingsScreen({super.key});

  @override
  State<PosKitchenDisplayLinkSettingsScreen> createState() =>
      _PosKitchenDisplayLinkSettingsScreenState();
}

class _PosKitchenDisplayLinkSettingsScreenState
    extends State<PosKitchenDisplayLinkSettingsScreen> {
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (!posCanConfigureOrdersDisplay(emp) || est == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await PosKitchenDisplayTokenService.instance
          .listActive(establishmentId: est.id);
      if (!mounted) return;
      setState(() {
        _rows = list;
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

  Future<void> _create(String department) async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final loc = context.read<LocalizationService>();
    if (est == null) return;
    try {
      await PosKitchenDisplayTokenService.instance.create(
        establishmentId: est.id,
        department: department,
        requireActiveShift: true,
      );
      if (!mounted) return;
      AppToastService.show(loc.t('pos_kds_link_created'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _revoke(String id) async {
    final loc = context.read<LocalizationService>();
    try {
      await PosKitchenDisplayTokenService.instance.revoke(id);
      if (!mounted) return;
      AppToastService.show(loc.t('pos_kds_link_revoked'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _copyLink(String token, String department) async {
    final loc = context.read<LocalizationService>();
    final full = kdsPublicDisplayFullUrl(department, token);
    final text = full ?? kdsPublicDisplayPath(department, token);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppToastService.show(loc.t('pos_kds_link_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;

    if (!posCanConfigureOrdersDisplay(emp)) {
      return Scaffold(
        appBar: AppBar(
          leading: shellReturnLeading(context) ?? appBarBackButton(context),
          title: Text(loc.t('pos_kds_link_settings_title')),
        ),
        body: Center(child: Text(loc.t('pos_kds_link_forbidden'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ?? appBarBackButton(context),
        title: Text(loc.t('pos_kds_link_settings_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      body: _body(context, loc),
    );
  }

  Widget _body(BuildContext context, LocalizationService loc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${loc.t('error')}: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(loc.t('retry')),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          loc.t('pos_kds_link_intro'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          loc.t('pos_kds_link_require_shift_note'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _create('kitchen'),
              icon: const Icon(Icons.restaurant_menu),
              label: Text(loc.t('pos_kds_link_new_kitchen')),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _create('bar'),
              icon: const Icon(Icons.local_bar),
              label: Text(loc.t('pos_kds_link_new_bar')),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          loc.t('pos_kds_link_active_list'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_rows.isEmpty)
          Text(loc.t('pos_kds_link_no_tokens'))
        else
          ..._rows.map((r) {
            final id = r['id']?.toString() ?? '';
            final token = r['token']?.toString() ?? '';
            final dept = r['department']?.toString() ?? 'kitchen';
            final deptLabel = dept == 'bar' ? loc.t('dept_bar') : loc.t('kitchen');
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$deptLabel · ${token.length > 8 ? '${token.substring(0, 6)}…' : token}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (kIsWeb)
                      SelectableText(
                        kdsPublicDisplayFullUrl(dept, token) ??
                            kdsPublicDisplayPath(dept, token),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: token.isEmpty
                                ? null
                                : () => _copyLink(token, dept),
                            icon: const Icon(Icons.link),
                            label: Text(loc.t('pos_kds_link_copy')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: id.isEmpty ? null : () => _revoke(id),
                          icon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          label: Text(
                            loc.t('pos_kds_link_revoke'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
