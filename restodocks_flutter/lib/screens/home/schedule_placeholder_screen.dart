import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/services.dart';

/// График: минимально по должностям (без имён). Позже — даты, смены, данные из БД.
class SchedulePlaceholderScreen extends StatelessWidget {
  const SchedulePlaceholderScreen({super.key});

  static const _roleCodes = [
    'sous_chef',
    'cook',
    'bartender',
    'waiter',
    'brigadier',
    'executive_chef',
  ];

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final locale = loc.currentLocale;
    final localeStr = '${locale.languageCode}_${locale.countryCode}';

    // Шапка таблицы: контрастный фон (не белый на белом)
    final headerBg = theme.colorScheme.primary;
    final headerFg = theme.colorScheme.onPrimary;

    final weekdays = List.generate(7, (i) {
      final d = DateTime.utc(2024, 1, 1).add(Duration(days: i));
      return DateFormat('EEE', localeStr).format(d);
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('schedule')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: loc.t('home'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.t('schedule_by_role'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              loc.t('schedule_week_hint'),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Редактирование графика — в разработке. Пока только просмотр.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: theme.dividerColor),
              columnWidths: const {
                0: FlexColumnWidth(1.8),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1),
                5: FlexColumnWidth(1),
                6: FlexColumnWidth(1),
                7: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: headerBg),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      child: Text(
                        loc.t('role'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: headerFg, fontSize: 14),
                      ),
                    ),
                    ...weekdays.map((d) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Text(d, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: headerFg)),
                        )),
                  ],
                ),
                ..._roleCodes.map((code) {
                  final key = 'role_$code';
                  final name = loc.translate(key);
                  final display = name == key ? code : name;
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        child: Text(display, style: const TextStyle(fontSize: 13)),
                      ),
                      ...List.generate(7, (_) => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Text('—', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                          )),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
