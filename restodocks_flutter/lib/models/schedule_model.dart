/// Модель графика: цеха (блоки), слоты (должности/имена) по цехам, назначения по датам.
/// Создаётся один раз, дальше только правки. Прокрутка по неделям не ограничена.

/// Цех — блок в графике (горячий цех, холодный цех, кондитерский и т.д.).
class ScheduleSection {
  final String id;
  /// Ключ локализации названия, например section_hot_kitchen.
  final String nameKey;

  const ScheduleSection({required this.id, required this.nameKey});

  Map<String, dynamic> toJson() => {'id': id, 'nameKey': nameKey};

  factory ScheduleSection.fromJson(Map<String, dynamic> json) {
    return ScheduleSection(
      id: json['id'] as String? ?? '',
      nameKey: json['nameKey'] as String? ?? json['id'] as String? ?? '',
    );
  }
}

/// Слот — строка в графике (должность/имя), привязана к цеху.
class ScheduleSlot {
  final String id;
  final String name;
  final String sectionId;

  const ScheduleSlot({required this.id, required this.name, this.sectionId = ''});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'sectionId': sectionId};

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) {
    return ScheduleSlot(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sectionId: json['sectionId'] as String? ?? '',
    );
  }

  ScheduleSlot copyWith({String? id, String? name, String? sectionId}) {
    return ScheduleSlot(
      id: id ?? this.id,
      name: name ?? this.name,
      sectionId: sectionId ?? this.sectionId,
    );
  }
}

class ScheduleModel {
  /// Цеха в порядке отображения (горячий, холодный, кондитерский и т.д.).
  final List<ScheduleSection> sections;
  /// Слоты (строки графика): Повар 1, Кондитер и т.д. — привязаны к цеху по sectionId.
  final List<ScheduleSlot> slots;
  /// Понедельник первой отображаемой недели.
  final DateTime startDate;
  /// Количество недель (для отображения и прокрутки).
  final int numWeeks;
  /// Назначения: ключ "slotId_date" (date = yyyy-MM-dd), значение — имя или должность.
  final Map<String, String> assignments;

  const ScheduleModel({
    this.sections = const [],
    this.slots = const [],
    required this.startDate,
    this.numWeeks = 12,
    this.assignments = const {},
  });

  /// Цеха по умолчанию (если в сохранённых данных нет).
  static List<ScheduleSection> get defaultSections => const [
    ScheduleSection(id: 'hot_kitchen', nameKey: 'section_hot_kitchen'),
    ScheduleSection(id: 'cold_kitchen', nameKey: 'section_cold_kitchen'),
    ScheduleSection(id: 'grill', nameKey: 'section_grill'),
    ScheduleSection(id: 'pastry', nameKey: 'section_pastry'),
    ScheduleSection(id: 'prep', nameKey: 'section_prep'),
    ScheduleSection(id: 'cleaning', nameKey: 'section_cleaning'),
  ];

  static String _dateKey(DateTime d) {
    final y = d.year;
    final m = d.month;
    final day = d.day;
    return '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  String assignmentKey(String slotId, DateTime date) =>
      '${slotId}_${_dateKey(date)}';

  String? getAssignment(String slotId, DateTime date) {
    return assignments[assignmentKey(slotId, date)];
  }

  ScheduleModel setAssignment(String slotId, DateTime date, String? value) {
    final key = assignmentKey(slotId, date);
    final next = Map<String, String>.from(assignments);
    if (value == null || value.trim().isEmpty) {
      next.remove(key);
    } else {
      next[key] = value.trim();
    }
    return copyWith(assignments: next);
  }

  ScheduleModel copyWith({
    List<ScheduleSection>? sections,
    List<ScheduleSlot>? slots,
    DateTime? startDate,
    int? numWeeks,
    Map<String, String>? assignments,
  }) {
    return ScheduleModel(
      sections: sections ?? this.sections,
      slots: slots ?? this.slots,
      startDate: startDate ?? this.startDate,
      numWeeks: numWeeks ?? this.numWeeks,
      assignments: assignments ?? this.assignments,
    );
  }

  /// Слоты, сгруппированные по sectionId в порядке sections. Слоты без sectionId попадают в первый цех.
  Map<String, List<ScheduleSlot>> get slotsBySection {
    final map = <String, List<ScheduleSlot>>{};
    final orphanSlots = slots.where((slot) => slot.sectionId.isEmpty).toList();
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final list = slots.where((slot) => slot.sectionId == s.id).toList();
      if (i == 0 && orphanSlots.isNotEmpty) {
        map[s.id] = [...orphanSlots, ...list];
      } else {
        map[s.id] = list;
      }
    }
    return map;
  }

  /// Список дат от startDate на numWeeks*7 дней (только понедельник первой недели выровнен).
  List<DateTime> get dates {
    final out = <DateTime>[];
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    for (var i = 0; i < numWeeks * 7; i++) {
      out.add(start.add(Duration(days: i)));
    }
    return out;
  }

  Map<String, dynamic> toJson() {
    return {
      'sections': sections.map((s) => s.toJson()).toList(),
      'slots': slots.map((s) => s.toJson()).toList(),
      'startDate': _dateKey(startDate),
      'numWeeks': numWeeks,
      'assignments': assignments,
    };
  }

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    final startStr = json['startDate'] as String? ?? '';
    DateTime start = DateTime.now();
    if (startStr.length >= 10) {
      final parts = startStr.split('-');
      if (parts.length == 3) {
        start = DateTime(
          int.tryParse(parts[0]) ?? start.year,
          int.tryParse(parts[1]) ?? start.month,
          int.tryParse(parts[2]) ?? start.day,
        );
      }
    }
    // Понедельник недели
    final weekday = start.weekday;
    if (weekday != 1) {
      start = start.subtract(Duration(days: weekday - 1));
    }
    final sectionsList = json['sections'] as List<dynamic>?;
    final sections = sectionsList != null && sectionsList.isNotEmpty
        ? sectionsList.map((e) => ScheduleSection.fromJson(e as Map<String, dynamic>)).toList()
        : ScheduleModel.defaultSections;
    final slotsList = json['slots'] as List<dynamic>?;
    final slots = slotsList != null
        ? slotsList.map((e) => ScheduleSlot.fromJson(e as Map<String, dynamic>)).toList()
        : <ScheduleSlot>[];
    final assignRaw = json['assignments'] as Map<String, dynamic>?;
    final assign = assignRaw != null
        ? assignRaw.map((k, v) => MapEntry(k as String, v as String))
        : <String, String>{};
    return ScheduleModel(
      sections: sections,
      slots: slots,
      startDate: start,
      numWeeks: json['numWeeks'] as int? ?? 12,
      assignments: assign,
    );
  }
}
