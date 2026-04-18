import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../haccp/haccp_country_profile.dart';
import '../models/haccp_log_type.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';

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
        appBar: AppBar(
          leading: appBarBackButton(context),
          title: ScrollToTopAppBarTitle(
            child: Text(loc.t('haccp_journals')),
          ),
        ),
        body: Center(child: Text(loc.t('haccp_establishment_not_selected'))),
      );
    }

    List<HaccpLogType> journals;
    final selectedCountryCode = config.resolveCountryCodeForEstablishment(est);
    final selectedProfile = config.resolveCountryProfileForEstablishment(est);
    final explicitOverride = config.hasExplicitCountryOverride(est.id);
    try {
      journals = config.getEnabledJournalsOrdered(
        est.id,
        countryCode: selectedCountryCode,
      );
      journals = journals
          .where((t) => HaccpLogType.supportedInApp.contains(t))
          .toList();
    } catch (_) {
      journals = [];
    }
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
        title: ScrollToTopAppBarTitle(
          child: Text(loc.t('haccp_journals')),
        ),
      ),
      body: journals.isEmpty
          ? _EmptyState(
              onConfigure:
                  isOwnerOrManagement ? () => context.push('/settings') : null,
              loc: loc,
              profileLabel: HaccpCountryProfiles.templateCountryLabel(
                selectedProfile.countryCode,
                loc.currentLanguageCode,
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(HaccpCountryProfiles.templateCountryLabel(
                      selectedProfile.countryCode,
                      loc.currentLanguageCode,
                    )),
                    subtitle: Text(
                      '${HaccpCountryProfiles.legalFrameworkLabel(selectedProfile.countryCode, loc.currentLanguageCode)}\n'
                      '${HaccpCountryProfiles.profileSourceLabel(manual: explicitOverride, languageCode: loc.currentLanguageCode)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
                ...journals.map((t) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(_iconForType(t)),
                        title: Text(loc.t(t.displayNameKey)),
                        subtitle: Text(
                          _journalSubtitle(
                            loc,
                            t,
                            selectedCountryCode,
                          ),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/haccp-journals/${t.code}'),
                      ),
                    )),
              ],
            ),
    );
  }

  /// Подзаголовок (Приложение … / рекомендуемая форма) — только из [localizable.json].
  static String _journalSubtitle(
    LocalizationService loc,
    HaccpLogType t,
    String countryCode,
  ) {
    return HaccpCountryProfiles.journalLegalLineTr(countryCode, t, loc.t);
  }

  /// Иконки для поддерживаемых журналов (СанПиН 1–5 + фритюрные жиры).
  static IconData _iconForType(HaccpLogType t) {
    switch (t) {
      case HaccpLogType.healthHygiene:
        return Icons.health_and_safety;
      case HaccpLogType.fridgeTemperature:
      case HaccpLogType.warehouseTempHumidity:
        return Icons.thermostat;
      case HaccpLogType.finishedProductBrakerage:
      case HaccpLogType.incomingRawBrakerage:
        return Icons.fact_check;
      case HaccpLogType.fryingOil:
        return Icons.oil_barrel;
      case HaccpLogType.medBookRegistry:
        return Icons.medical_services;
      case HaccpLogType.medExaminations:
        return Icons.medical_information;
      case HaccpLogType.disinfectantAccounting:
        return Icons.cleaning_services;
      case HaccpLogType.equipmentWashing:
        return Icons.water_drop;
      case HaccpLogType.generalCleaningSchedule:
        return Icons.cleaning_services;
      case HaccpLogType.sieveFilterMagnet:
        return Icons.filter_alt;
      default:
        return Icons.assignment;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    this.onConfigure,
    required this.loc,
    required this.profileLabel,
  });

  final VoidCallback? onConfigure;
  final LocalizationService loc;
  final String profileLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('haccp_no_journals_hint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              loc.t('haccp_no_journals_subtitle'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              profileLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
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
