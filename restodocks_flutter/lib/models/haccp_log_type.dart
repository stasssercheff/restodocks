/// Целевая таблица для логирования (приложение выбирает автоматически).
enum HaccpLogTable { numeric, status, quality }

/// Типы журналов ХАССП (совпадают с enum в БД).
/// targetTable — в какую таблицу писать: numeric / status / quality
enum HaccpLogType {
  // Группа А: Санитария и Персонал
  healthHygiene('health_hygiene', 'Гигиенический журнал (Здоровье)', 'А', 'Приложение 1 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.status),
  uvLamps('uv_lamps', 'Учёт работы бак-ламп (Кварцевание)', 'А', '31.rospotrebnadzor.ru', HaccpLogTable.numeric),
  pediculosis('pediculosis', 'Осмотр на педикулёз', 'А', 'Форма учёта гигиенического контроля', HaccpLogTable.status),

  // Группа Б: Оборудование и Склад
  fridgeTemperature('fridge_temperature', 'Температурный режим холодильников', 'Б', 'Приложение 2 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.numeric),
  warehouseTempHumidity('warehouse_temp_humidity', 'Температура и влажность склада', 'Б', '74.rospotrebnadzor.ru (Психрометр)', HaccpLogTable.numeric),
  dishwasherControl('dishwasher_control', 'Контроль посудомоечных машин', 'Б', '66.rospotrebnadzor.ru', HaccpLogTable.status),
  greaseTrapCleaning('grease_trap_cleaning', 'Очистка жироуловителей и вентиляции', 'Б', 'График ТО и чистки фильтров', HaccpLogTable.status),

  // Группа В: Качество и Бракераж
  finishedProductBrakerage('finished_product_brakerage', 'Бракераж готовой продукции', 'В', 'Приложение 4 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  incomingRawBrakerage('incoming_raw_brakerage', 'Входной контроль сырья (Бракераж скоропорта)', 'В', '74.rospotrebnadzor.ru', HaccpLogTable.quality),
  fryingOil('frying_oil', 'Учёт фритюрных жиров (Замена масла)', 'В', 'Приложение 8 к СанПиН 2.3/2.4.3590-20', HaccpLogTable.quality),
  foodWaste('food_waste', 'Учёт пищевых отходов (Утилизация)', 'В', 'Вес, причина списания', HaccpLogTable.quality),

  // Группа Г: HACCP PRO
  glassCeramicsBreakage('glass_ceramics_breakage', 'Журнал боя стекла и керамики', 'Г', '«Стеклянная политика»', HaccpLogTable.status),
  emergencyIncidents('emergency_incidents', 'Регистрация аварийных ситуаций', 'Г', 'Вода, свет, канализация', HaccpLogTable.status),
  disinsectionDeratization('disinsection_deratization', 'Учёт дезинсекции и дератизации', 'Г', '74.rospotrebnadzor.ru', HaccpLogTable.quality),
  generalCleaningSchedule('general_cleaning_schedule', 'График генеральных уборок', 'Г', '74.rospotrebnadzor.ru', HaccpLogTable.status),
  disinfectantConcentration('disinfectant_concentration', 'Учёт концентрации дезсредств', 'Г', '74.rospotrebnadzor.ru', HaccpLogTable.numeric),
  ;

  const HaccpLogType(this.code, this.displayNameRu, this.group, this.sanpinRef, this.targetTable);
  final String code;
  final String displayNameRu;
  final String group;
  final String sanpinRef;
  final HaccpLogTable targetTable;

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
