import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';
import '../../widgets/app_bar_home_button.dart';

/// Настройки таймера и размера подписей в списках заказов POS.
class PosOrdersDisplaySettingsScreen extends StatelessWidget {
  const PosOrdersDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final disp = context.watch<PosOrdersDisplaySettingsService>();

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_orders_display_settings_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            loc.t('pos_orders_display_settings_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Text(
            loc.t('pos_orders_display_timer_label'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            loc.t('pos_orders_display_timer_hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              for (final s in PosOrdersDisplaySettingsService.allowedTimerSeconds)
                ButtonSegment(
                  value: s,
                  label: Text(loc.t('pos_orders_display_timer_sec', args: {'n': '$s'})),
                ),
            ],
            selected: {disp.timerIntervalSeconds},
            onSelectionChanged: (set) {
              final v = set.first;
              disp.setTimerIntervalSeconds(v);
            },
          ),
          const SizedBox(height: 32),
          Text(
            loc.t('pos_orders_display_text_label'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            loc.t('pos_orders_display_text_hint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 1,
                label: Text(loc.t('pos_orders_display_text_compact')),
              ),
              ButtonSegment(
                value: 2,
                label: Text(loc.t('pos_orders_display_text_normal')),
              ),
              ButtonSegment(
                value: 3,
                label: Text(loc.t('pos_orders_display_text_large')),
              ),
            ],
            selected: {disp.subtitlePreset},
            onSelectionChanged: (set) {
              disp.setSubtitlePreset(set.first);
            },
          ),
        ],
      ),
    );
  }
}
