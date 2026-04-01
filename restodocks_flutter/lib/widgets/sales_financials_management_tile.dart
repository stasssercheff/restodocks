import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/feature_flags.dart';
import '../models/models.dart';
import '../services/account_manager_supabase.dart';
import '../services/localization_service.dart';
import '../services/sales_financial_visibility_service.dart';

/// Переключатель: видимость себестоимости и цен в «Продажах» для отдела управления.
class SalesFinancialsManagementTile extends StatefulWidget {
  const SalesFinancialsManagementTile({super.key, required this.employee});

  final Employee employee;

  @override
  State<SalesFinancialsManagementTile> createState() =>
      _SalesFinancialsManagementTileState();
}

class _SalesFinancialsManagementTileState
    extends State<SalesFinancialsManagementTile> {
  bool _loaded = false;
  bool _value = false;
  String? _establishmentId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final est =
        context.read<AccountManagerSupabase>().establishment?.dataEstablishmentId;
    if (est == null || est.isEmpty) return;
    _establishmentId = est;
    await SalesFinancialVisibilityService.instance.initializeForEstablishment(est);
    if (!mounted) return;
    setState(() {
      _value = SalesFinancialVisibilityService.instance
          .allowManagementFinancials(est);
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    if (!FeatureFlags.posModuleEnabled) return const SizedBox.shrink();
    if (!widget.employee.hasRole('owner') || widget.employee.isViewOnlyOwner) {
      return const SizedBox.shrink();
    }
    if (!_loaded) {
      return ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(loc.t('sales_financials_for_management') ?? ''),
        subtitle: const LinearProgressIndicator(),
      );
    }
    return SwitchListTile(
      secondary: const Icon(Icons.payments_outlined),
      title: Text(loc.t('sales_financials_for_management') ?? ''),
      subtitle: Text(
        loc.t('sales_financials_for_management_hint') ?? '',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: _value,
      onChanged: (v) async {
        final id = _establishmentId;
        if (id == null) return;
        setState(() => _value = v);
        await SalesFinancialVisibilityService.instance
            .setAllowManagementFinancials(id, v);
      },
    );
  }
}
