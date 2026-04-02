import 'package:intl/intl.dart';

import '../models/checklist_reminder_config.dart';
import '../services/localization_service.dart';

/// Строка под списком чеклистов / в заполнении.
String? formatChecklistReminderSubtitle(
  ChecklistReminderConfig? cfg,
  LocalizationService loc,
  String lang,
) {
  if (cfg == null || !cfg.enabled) return null;
  final localeTag = lang == 'ru' ? 'ru' : 'en';
  return cfg.buildSummary(
    reminderLabel: loc.t('checklist_reminder_short'),
    atShiftStart: loc.t('checklist_reminder_shift_start'),
    recurrenceNone: loc.t('checklist_recurrence_none'),
    recurrenceMulti: loc.t('checklist_recurrence_multi_daily'),
    recurrenceWeekdays: loc.t('checklist_recurrence_weekdays'),
    everyNWeeksLabel: loc.t('checklist_every_n_weeks_short'),
    formatWeekdayShort: (iso) => DateFormat.E(localeTag).format(DateTime(2024, 1, iso)),
  );
}
