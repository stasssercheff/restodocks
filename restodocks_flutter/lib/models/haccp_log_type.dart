/// Целевая таблица для логирования (приложение выбирает автоматически).
enum HaccpLogTable { numeric, status, quality }

/// Типы журналов ХАССП. В UI и настройках используются только [sanpinOnly] (Приложения 1–5 СанПиН 2.3/2.4.3590-20).
/// Остальные значения оставлены для совместимости с БД при миграции.
enum HaccpLogType {
  healthHygiene('health_hygiene', 'Гигиенический журнал (сотрудники)', 'А', 'Приложение № 1 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.status),
  fridgeTemperature('fridge_temperature', 'Журнал учета температурного режима холодильного оборудования', 'Б', 'Приложение № 2 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.numeric),
  warehouseTempHumidity('warehouse_temp_humidity', 'Журнал учета температуры и влажности в складских помещениях', 'Б', 'Приложение № 3 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.numeric),
  finishedProductBrakerage('finished_product_brakerage', 'Журнал бракеража готовой пищевой продукции', 'В', 'Приложение № 4 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  incomingRawBrakerage('incoming_raw_brakerage', 'Журнал бракеража скоропортящейся пищевой продукции', 'В', 'Приложение № 5 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  uvLamps('uv_lamps', 'Учёт работы бак-ламп', 'А', 'Приложение 3 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.numeric),
  pediculosis('pediculosis', 'Осмотр на педикулёз', 'А', 'Форма учёта гигиенического контроля', HaccpLogTable.status),
  dishwasherControl('dishwasher_control', 'Контроль посудомоечных машин', 'Б', 'Приложение 6 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.status),
  greaseTrapCleaning('grease_trap_cleaning', 'Очистка жироуловителей и вентиляции', 'Б', 'График ТО и чистки фильтров', HaccpLogTable.status),
  fryingOil('frying_oil', 'Учёт фритюрных жиров', 'В', 'Приложение 8 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  medBookRegistry('med_book_registry', 'Журнал учёта личных медицинских книжек', 'А', 'Рекомендуемая форма учёта', HaccpLogTable.quality),
  foodWaste('food_waste', 'Учёт пищевых отходов', 'В', 'Вес, причина списания', HaccpLogTable.quality),
  glassCeramicsBreakage('glass_ceramics_breakage', 'Журнал боя стекла и керамики', 'Г', '«Стеклянная политика»', HaccpLogTable.status),
  emergencyIncidents('emergency_incidents', 'Регистрация аварийных ситуаций', 'Г', 'Вода, свет, канализация', HaccpLogTable.status),
  disinsectionDeratization('disinsection_deratization', 'Учёт дезинсекции и дератизации', 'Г', 'Приложение 9 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  generalCleaningSchedule('general_cleaning_schedule', 'Журнал-график проведения генеральных уборок', 'Г', 'Приложение 10 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  disinfectantConcentration('disinfectant_concentration', 'Учёт концентрации дезсредств', 'Г', 'Приложение 11 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.numeric),
  medExaminations('med_examinations', 'Журнал учёта прохождения работниками обязательных предварительных и периодических медицинских осмотров', 'А', 'Рекомендуемая форма учёта', HaccpLogTable.quality),
  disinfectantAccounting('disinfectant_accounting', 'Журнал учёта получения, расхода дезинфицирующих средств и проведения дезинфекционных работ на объекте', 'Г', 'Рекомендуемая форма учёта', HaccpLogTable.quality),
  equipmentWashing('equipment_washing', 'Журнал мойки и дезинфекции оборудования', 'Б', 'Рекомендуемая форма учёта', HaccpLogTable.quality),
  sieveFilterMagnet('sieve_filter_magnet', 'Журнал результатов проверки и очистки сит (фильтров) и магнитоуловителей', 'Б', 'Рекомендуемая форма учёта', HaccpLogTable.quality),
  ;

  const HaccpLogType(this.code, this.displayNameRu, this.group, this.sanpinRef, this.targetTable);
  final String code;
  final String displayNameRu;
  final String group;
  final String sanpinRef;
  final HaccpLogTable targetTable;

  /// Журналы по рекомендуемым образцам СанПиН 2.3/2.4.3590-20 (Приложения 1–5).
  static const List<HaccpLogType> sanpinOnly = [
    HaccpLogType.healthHygiene,
    HaccpLogType.fridgeTemperature,
    HaccpLogType.warehouseTempHumidity,
    HaccpLogType.finishedProductBrakerage,
    HaccpLogType.incomingRawBrakerage,
  ];

  /// СанПиН (1–5) + фритюр + медкнижки + медосмотры + дезсредства + мойка оборудования + генуборки + сита/фильтры.
  static List<HaccpLogType> get supportedInApp => [
    ...sanpinOnly,
    HaccpLogType.fryingOil,
    HaccpLogType.medBookRegistry,
    HaccpLogType.medExaminations,
    HaccpLogType.disinfectantAccounting,
    HaccpLogType.equipmentWashing,
    HaccpLogType.generalCleaningSchedule,
    HaccpLogType.sieveFilterMagnet,
  ];

  static HaccpLogType? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    return HaccpLogType.values.where((e) => e.code == code).firstOrNull;
  }

  static List<HaccpLogType> get groupA =>
      HaccpLogType.values.where((e) => e.group == 'А').toList();
  static List<HaccpLogType> get groupB =>
      HaccpLogType.values.where((e) => e.group == 'Б').toList();
  static List<HaccpLogType> get groupC =>
      HaccpLogType.values.where((e) => e.group == 'В').toList();
  static List<HaccpLogType> get groupD =>
      HaccpLogType.values.where((e) => e.group == 'Г').toList();
}
