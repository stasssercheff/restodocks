import 'package:equatable/equatable.dart';

/// Режим повторения напоминаний чеклиста (шаблон).
enum ChecklistRecurrenceKind {
  /// Одно правило времени/начала смены без отдельного расписания повторов.
  none('none'),

  /// Несколько фиксированных времён в течение дня.
  multiDaily('multi_daily'),

  /// Выбранные дни недели; [everyNWeeks] — каждые 1–8 недель.
  weekdays('weekdays');

  const ChecklistRecurrenceKind(this.jsonValue);
  final String jsonValue;

  static ChecklistRecurrenceKind fromJson(String? v) {
    for (final k in ChecklistRecurrenceKind.values) {
      if (k.jsonValue == v) return k;
    }
    return ChecklistRecurrenceKind.none;
  }
}

/// Настройки уведомления и повторения (хранятся в `checklists.reminder_config`).
class ChecklistReminderConfig extends Equatable {
  static const defaultShiftHour = 9;
  static const defaultShiftMinute = 0;

  /// Включено ли системное уведомление (notification time / начало смены).
  final bool enabled;

  /// Включено ли повторение (расписание повторов чеклиста).
  final bool recurrenceEnabled;

  /// Дата завершения повторения (если null — повторение бессрочно).
  /// Храним как дату (без времени); в JSON — ISO `YYYY-MM-DD`.
  final DateTime? recurrenceEndDate;

  /// Если true — использовать [hour]/[minute]; иначе «начало смены» ([defaultShiftHour]:[defaultShiftMinute] до появления графика в продукте).
  final bool useSpecificTime;
  final int hour;
  final int minute;

  final ChecklistRecurrenceKind recurrenceKind;

  /// Для [ChecklistRecurrenceKind.multiDaily] — списки «HH:mm».
  final List<String> dailyTimes;

  /// ISO weekday 1=Пн … 7=Вс
  final List<int> weekdays;

  /// 1–8, для [ChecklistRecurrenceKind.weekdays].
  final int everyNWeeks;

  const ChecklistReminderConfig({
    this.enabled = false,
    this.recurrenceEnabled = false,
    this.recurrenceEndDate,
    this.useSpecificTime = false,
    this.hour = defaultShiftHour,
    this.minute = defaultShiftMinute,
    this.recurrenceKind = ChecklistRecurrenceKind.none,
    this.dailyTimes = const [],
    this.weekdays = const [],
    this.everyNWeeks = 1,
  });

  bool get hasAny => enabled || recurrenceEnabled;
  bool get isEmpty => !hasAny;

  factory ChecklistReminderConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ChecklistReminderConfig();
    final enabled = json['notify_enabled'] == true || json['enabled'] == true;
    final useSpecificTime = json['use_specific_time'] == true;
    final hour =
        (json['hour'] as num?)?.clamp(0, 23).toInt() ?? defaultShiftHour;
    final minute =
        (json['minute'] as num?)?.clamp(0, 59).toInt() ?? defaultShiftMinute;
    final kind =
        ChecklistRecurrenceKind.fromJson(json['recurrence_kind'] as String?);
    final timesRaw = json['daily_times'];
    final dailyTimes = <String>[];
    if (timesRaw is List) {
      for (final e in timesRaw) {
        final s = e?.toString().trim() ?? '';
        if (_isValidHm(s)) dailyTimes.add(s);
      }
    }
    final wdRaw = json['weekdays'];
    final weekdays = <int>[];
    if (wdRaw is List) {
      for (final e in wdRaw) {
        final n = (e as num?)?.toInt();
        if (n != null && n >= 1 && n <= 7) weekdays.add(n);
      }
      weekdays.sort();
    }
    final every = (json['every_n_weeks'] as num?)?.clamp(1, 8).toInt() ?? 1;
    final recurrenceEnabled = json.containsKey('recurrence_enabled')
        ? json['recurrence_enabled'] == true
        : kind != ChecklistRecurrenceKind.none;
    DateTime? endDate;
    final endRaw = json['recurrence_end_date'];
    if (endRaw is String && endRaw.trim().isNotEmpty) {
      // ISO date: YYYY-MM-DD (или полноценный ISO datetime — берём дату).
      final p = DateTime.tryParse(endRaw.trim());
      if (p != null) endDate = DateTime(p.year, p.month, p.day);
    }
    if (!enabled && !recurrenceEnabled) return const ChecklistReminderConfig();
    return ChecklistReminderConfig(
      enabled: enabled,
      recurrenceEnabled: recurrenceEnabled,
      recurrenceEndDate: endDate,
      useSpecificTime: useSpecificTime,
      hour: hour,
      minute: minute,
      recurrenceKind: kind,
      dailyTimes: dailyTimes,
      weekdays: weekdays,
      everyNWeeks: every,
    );
  }

  Map<String, dynamic> toJson() {
    if (!hasAny) {
      return {'enabled': false};
    }
    return {
      // legacy key used by existing SQL/functions
      'enabled': enabled,
      'notify_enabled': enabled,
      'recurrence_enabled': recurrenceEnabled,
      'use_specific_time': enabled ? useSpecificTime : false,
      'hour': enabled ? hour : defaultShiftHour,
      'minute': enabled ? minute : defaultShiftMinute,
      'recurrence_kind': recurrenceEnabled
          ? recurrenceKind.jsonValue
          : ChecklistRecurrenceKind.none.jsonValue,
      // Одновременно поддерживаем дни недели + несколько времен в день.
      'daily_times': recurrenceEnabled ? dailyTimes : <String>[],
      'weekdays': recurrenceEnabled ? weekdays : <int>[],
      'every_n_weeks': recurrenceEnabled ? everyNWeeks.clamp(1, 8) : 1,
      'recurrence_end_date': recurrenceEnabled && recurrenceEndDate != null
          ? '${recurrenceEndDate!.year.toString().padLeft(4, '0')}-${recurrenceEndDate!.month.toString().padLeft(2, '0')}-${recurrenceEndDate!.day.toString().padLeft(2, '0')}'
          : null,
    };
  }

  static bool _isValidHm(String s) {
    final p = s.split(':');
    if (p.length != 2) return false;
    final h = int.tryParse(p[0].trim());
    final m = int.tryParse(p[1].trim());
    if (h == null || m == null) return false;
    return h >= 0 && h <= 23 && m >= 0 && m <= 59;
  }

  /// Краткая строка для списка чеклистов.
  String buildSummary({
    required String reminderLabel,
    required String atShiftStart,
    required String recurrenceNone,
    required String recurrenceMulti,
    required String recurrenceWeekdays,
    required String everyNWeeksLabel,
    required String Function(int isoWeekday) formatWeekdayShort,
  }) {
    if (!enabled) return '';
    final buf = StringBuffer(reminderLabel);
    if (dailyTimes.isNotEmpty) {
      buf.write(': ${dailyTimes.join(', ')}');
    } else if (useSpecificTime) {
      buf.write(
          ': ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    } else {
      buf.write(': $atShiftStart');
    }
    if (!recurrenceEnabled || recurrenceKind == ChecklistRecurrenceKind.none) {
      buf.write(' · $recurrenceNone');
      return buf.toString();
    }
    if (weekdays.isEmpty) {
      buf.write(' · $recurrenceWeekdays');
    } else {
      final wd = weekdays.map(formatWeekdayShort).join(', ');
      final n = everyNWeeks.clamp(1, 8);
      buf.write(' · $recurrenceWeekdays: $wd');
      if (n > 1) {
        buf.write(' ($everyNWeeksLabel: $n)');
      }
    }
    if (dailyTimes.isNotEmpty) {
      buf.write(' · $recurrenceMulti: ${dailyTimes.join(', ')}');
    }
    return buf.toString();
  }

  /// Краткая строка, когда повторение включено, а уведомление — нет.
  String buildRecurrenceOnlySummary({
    required String recurrenceLabel,
    required String recurrenceNone,
    required String recurrenceMulti,
    required String recurrenceWeekdays,
    required String everyNWeeksLabel,
    required String Function(int isoWeekday) formatWeekdayShort,
  }) {
    if (!recurrenceEnabled) return '';
    final buf = StringBuffer(recurrenceLabel);
    if (recurrenceKind == ChecklistRecurrenceKind.none) {
      buf.write(': $recurrenceNone');
      return buf.toString();
    }
    if (weekdays.isEmpty) {
      buf.write(': $recurrenceWeekdays');
    } else {
      final wd = weekdays.map(formatWeekdayShort).join(', ');
      final n = everyNWeeks.clamp(1, 8);
      buf.write(': $recurrenceWeekdays: $wd');
      buf.write(' · $everyNWeeksLabel: $n');
    }
    if (dailyTimes.isNotEmpty) {
      buf.write(' · $recurrenceMulti (${dailyTimes.join(', ')})');
    }
    return buf.toString();
  }

  ChecklistReminderConfig copyWith({
    bool? enabled,
    bool? recurrenceEnabled,
    DateTime? recurrenceEndDate,
    bool? useSpecificTime,
    int? hour,
    int? minute,
    ChecklistRecurrenceKind? recurrenceKind,
    List<String>? dailyTimes,
    List<int>? weekdays,
    int? everyNWeeks,
  }) {
    return ChecklistReminderConfig(
      enabled: enabled ?? this.enabled,
      recurrenceEnabled: recurrenceEnabled ?? this.recurrenceEnabled,
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      useSpecificTime: useSpecificTime ?? this.useSpecificTime,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      recurrenceKind: recurrenceKind ?? this.recurrenceKind,
      dailyTimes: dailyTimes ?? this.dailyTimes,
      weekdays: weekdays ?? this.weekdays,
      everyNWeeks: everyNWeeks ?? this.everyNWeeks,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        recurrenceEnabled,
        recurrenceEndDate?.year,
        recurrenceEndDate?.month,
        recurrenceEndDate?.day,
        useSpecificTime,
        hour,
        minute,
        recurrenceKind,
        dailyTimes,
        weekdays,
        everyNWeeks,
      ];
}
