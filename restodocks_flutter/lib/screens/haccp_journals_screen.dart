import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Экран «Журналы и ХАССП» — список включённых журналов.
class HaccpJournalsScreen extends StatefulWidget {
  const HaccpJournalsScreen({super.key});

  @override
  State<HaccpJournalsScreen> createState() => _HaccpJournalsScreenState();
}

class _HaccpJournalsScreenState extends State<HaccpJournalsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acc = context.read<AccountManagerSupabase>();
      final est = acc.establishment;
      if (est != null) context.read<HaccpConfigService>().load(est.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final acc = context.watch<AccountManagerSupabase>();
    final config = context.watch<HaccpConfigService>();
    final est = acc.establishment;
    if (est == null) {
      return Scaffold(
        appBar: AppBar(leading: appBarBackButton(context), title: Text(loc.t('haccp_journals') ?? 'Журналы и ХАССП')),
        body: Center(child: Text(loc.t('haccp_establishment_not_selected') ?? 'Заведение не выбрано')),
      );
    }

    final journals = config.getEnabledJournalsOrdered(est.id);
    final isOwnerOrManagement = acc.currentEmployee?.hasRole('owner') == true ||
        acc.currentEmployee?.department == 'management' ||
        acc.currentEmployee?.hasRole('executive_chef') == true ||
        acc.currentEmployee?.hasRole('sous_chef') == true ||
        acc.currentEmployee?.hasRole('bar_manager') == true ||
        acc.currentEmployee?.hasRole('floor_manager') == true ||
        acc.currentEmployee?.hasRole('general_manager') == true;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('haccp_journals') ?? 'Журналы и ХАССП'),
      ),
      body: journals.isEmpty
          ? _EmptyState(
              onConfigure: isOwnerOrManagement ? () => context.push('/settings') : null,
              loc: loc,
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: journals.length,
              itemBuilder: (_, i) {
                final t = journals[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(_iconForType(t)),
                    title: Text(t.displayNameRu),
                    subtitle: Text(t.sanpinRef, style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/haccp-journals/${t.code}'),
                  ),
                );
              },
            ),
    );
  }

  static IconData _iconForType(HaccpLogType t) {
    switch (t) {
      case HaccpLogType.healthHygiene:
      case HaccpLogType.pediculosis:
        return Icons.health_and_safety;
      case HaccpLogType.uvLamps:
        return Icons.lightbulb_outline;
      case HaccpLogType.fridgeTemperature:
      case HaccpLogType.warehouseTempHumidity:
        return Icons.thermostat;
      case HaccpLogType.dishwasherControl:
      case HaccpLogType.greaseTrapCleaning:
        return Icons.kitchen;
      case HaccpLogType.finishedProductBrakerage:
      case HaccpLogType.incomingRawBrakerage:
        return Icons.fact_check;
      case HaccpLogType.fryingOil:
      case HaccpLogType.foodWaste:
        return Icons.restaurant;
      case HaccpLogType.glassCeramicsBreakage:
        return Icons.broken_image;
      case HaccpLogType.emergencyIncidents:
        return Icons.warning_amber;
      case HaccpLogType.disinsectionDeratization:
      case HaccpLogType.generalCleaningSchedule:
      case HaccpLogType.disinfectantConcentration:
        return Icons.cleaning_services;
      default:
        return Icons.assignment;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onConfigure, required this.loc});

  final VoidCallback? onConfigure;
  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('haccp_no_journals_hint') ?? 'Журналы ХАССП не настроены',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('haccp_no_journals_subtitle') ?? loc.t('haccp_configure_in_settings') ?? 'Собственник и сотрудники управления выбирают журналы в Настройках',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (onConfigure != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onConfigure,
                icon: const Icon(Icons.settings),
                label: Text(loc.t('settings')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
