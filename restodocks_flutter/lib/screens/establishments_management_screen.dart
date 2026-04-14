import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/establishment_delete_flow.dart';

/// Список заведений владельца: переключение, удаление, добавление (существующий маршрут).
class EstablishmentsManagementScreen extends StatefulWidget {
  const EstablishmentsManagementScreen({super.key});

  @override
  State<EstablishmentsManagementScreen> createState() =>
      _EstablishmentsManagementScreenState();
}

class _EstablishmentsManagementScreenState
    extends State<EstablishmentsManagementScreen> {
  List<Establishment> _list = [];
  int _maxEstablishmentsPerOwner = 5;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accountManager = context.read<AccountManagerSupabase>();
    if (accountManager.currentEmployee?.hasRole('owner') != true) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        accountManager.getEstablishmentsForOwner(),
        accountManager.getMaxEstablishmentsPerOwner(),
      ]);
      if (mounted) {
        setState(() {
          _list = results[0] as List<Establishment>;
          _maxEstablishmentsPerOwner = results[1] as int;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _additionalCount => (_list.length - 1).clamp(0, _maxEstablishmentsPerOwner);
  int get _totalCount => _list.isEmpty ? 0 : _list.length;
  int get _totalCap => _maxEstablishmentsPerOwner + 1;

  bool get _canAddMore => _additionalCount < _maxEstablishmentsPerOwner;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final establishment = accountManager.establishment;
    final viewOnly = accountManager.isViewOnlyOwner;

    if (accountManager.currentEmployee?.hasRole('owner') != true) {
      return Scaffold(
        appBar: AppBar(
          leading: shellReturnLeading(context) ?? appBarBackButton(context),
          title: Text(loc.t('establishments')),
        ),
        body: Center(child: Text(loc.t('error_no_establishment_or_employee'))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ??
            (GoRouter.of(context).canPop() ? appBarBackButton(context) : null),
        title: Text(loc.t('establishments')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!viewOnly) ...[
                    FilledButton.icon(
                      onPressed: _canAddMore
                          ? () async {
                              await context.push('/add-establishment');
                              if (mounted) await _load();
                            }
                          : null,
                      icon: const Icon(Icons.add_business),
                      label: Text(loc.t('add_establishment')),
                    ),
                    if (!_canAddMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          loc.t('establishments_max_reached'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_totalCount из $_totalCap',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (loc.t('establishments_counter'))
                                .replaceAll('{current}', '$_additionalCount')
                                .replaceAll('{max}', '$_maxEstablishmentsPerOwner'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                  Text(
                    loc.t('establishments_list_hint'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ..._list.map((est) {
                    String? parentName;
                    if (est.isBranch && est.parentEstablishmentId != null) {
                      for (final e in _list) {
                        if (e.id == est.parentEstablishmentId) {
                          parentName = e.name;
                          break;
                        }
                      }
                    }
                    final isCurrent = est.id == establishment?.id;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : (est.isBranch ? Icons.account_tree : Icons.store),
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(est.name),
                        subtitle: isCurrent
                            ? Text(loc.t('current'))
                            : (est.isBranch && parentName != null
                                ? Text(
                                    '${loc.t('branch_of')}: $parentName',
                                  )
                                : (est.isMain
                                    ? Text(loc.t('main_establishment'))
                                    : null)),
                        trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isCurrent)
                                    IconButton(
                                      tooltip: loc.t('establishments_switch'),
                                      icon: const Icon(Icons.swap_horiz),
                                      onPressed: () async {
                                        await accountManager.switchEstablishment(est);
                                        if (mounted) {
                                          context.go('/home',
                                              extra: {'back': true});
                                        }
                                      },
                                    ),
                                  if (!viewOnly)
                                    IconButton(
                                      tooltip: loc.t('delete_establishment'),
                                      icon: const Icon(Icons.delete_forever,
                                          color: Colors.red),
                                      onPressed: () async {
                                        await showDeleteEstablishmentFlow(
                                          context,
                                          establishment: est,
                                          loc: loc,
                                          accountManager: accountManager,
                                          onCompleted: (remaining) async {
                                            await handleEstablishmentDeletedNavigation(
                                              context,
                                              accountManager,
                                              remaining,
                                              loc,
                                            );
                                            if (mounted && remaining.isNotEmpty) {
                                              await _load();
                                            }
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                        onTap: isCurrent
                            ? null
                            : () async {
                                await accountManager.switchEstablishment(est);
                                if (mounted) {
                                  context.go('/home', extra: {'back': true});
                                }
                              },
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
