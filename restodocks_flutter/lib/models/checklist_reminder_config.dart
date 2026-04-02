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

  final bool enabled;
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
    this.useSpecificTime = false,
    this.hour = defaultShiftHour,
    this.minute = defaultShiftMinute,
    this.recurrenceKind = ChecklistRecurrenceKind.none,
    this.dailyTimes = const [],
    this.weekdays = const [],
    this.everyNWeeks = 1,
  });

  bool get isEmpty => !enabled;

  factory ChecklistReminderConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const ChecklistReminderConfig();
    final enabled = json['enabled'] == true;
    if (!enabled) return const ChecklistReminderConfig();
    final useSpecificTime = json['use_specific_time'] == true;
    final hour = (json['hour'] as num?)?.clamp(0, 23).toInt() ?? defaultShiftHour;
    final minute = (json['minute'] as num?)?.clamp(0, 59).toInt() ?? defaultShiftMinute;
    final kind = ChecklistRecurrenceKind.fromJson(json['recurrence_kind'] as String?);
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
    return ChecklistReminderConfig(
      enabled: true,
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
    if (!enabled) {
      return {'enabled': false};
    }
    return {
      'enabled': true,
      'use_specific_time': useSpecificTime,
      'hour': hour,
      'minute': minute,
      'recurrence_kind': recurrenceKind.jsonValue,
      'daily_times': recurrenceKind == ChecklistRecurrenceKind.multiDaily ? dailyTimes : <String>[],
      'weekdays': recurrenceKind == ChecklistRecurrenceKind.weekdays ? weekdays : <int>[],
      'every_n_weeks': recurrenceKind == ChecklistRecurrenceKind.weekdays ? everyNWeeks.clamp(1, 8) : 1,
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
    if (recurrenceKind == ChecklistRecurrenceKind.multiDaily && dailyTimes.isNotEmpty) {
      buf.write(': ${dailyTimes.join(', ')}');
    } else if (useSpecificTime) {
      buf.write(': ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    } else {
      buf.write(': $atShiftStart');
    }
    switch (recurrenceKind) {
      case ChecklistRecurrenceKind.none:
        buf.write(' · $recurrenceNone');
        break;
      case ChecklistRecurrenceKind.multiDaily:
        buf.write(' · $recurrenceMulti');
        break;
      case ChecklistRecurrenceKind.weekdays:
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
        break;
    }
    return buf.toString();
  }

  ChecklistReminderConfig copyWith({
    bool? enabled,
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
        useSpecificTime,
        hour,
        minute,
        recurrenceKind,
        dailyTimes,
        weekdays,
        everyNWeeks,
      ];
}
