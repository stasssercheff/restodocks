import '../services/localization_service.dart';

/// Описания кнопок тура — по документу «Начало работы».
abstract final class HomeTourConfig {
  static String _t(LocalizationService loc, String key, String fallback) {
    final v = loc.t(key);
    return v == key ? fallback : v;
  }

  /// Id и функция получения текста для владельца (полный список плиток).
  static List<({String id, String Function(LocalizationService loc) text})> ownerSteps(LocalizationService loc) => [
    (id: 'home-doc', text: (_) => _t(loc, 'tour_tile_doc', 'Создание и размещение общей документации и правил организации. Ограничение по подразделениям, цехам, сотрудникам.')),
    (id: 'home-haccp', text: (_) => _t(loc, 'tour_tile_haccp', '12 журналов по форме СанПин. Температура, бракераж, гигиена, дезинфекция и др. Данные нельзя изменить после заполнения.')),
    (id: 'home-messages', text: (_) => _t(loc, 'tour_tile_messages', 'Личное и групповое общение с сотрудниками с возможностью отправки фото.')),
    (id: 'home-inbox', text: (_) => _t(loc, 'tour_tile_inbox', 'Входящие: заказы продуктов, списания, чеклисты. Каждый заказ дублируется сюда с указанием стоимости.')),
    (id: 'home-employees', text: (_) => _t(loc, 'tour_tile_employees', 'Регистрация сотрудников по pin-коду, выдача доступа, система оплаты (почасовая/посменная) и ставка.')),
    (id: 'home-schedule-mgmt', text: (_) => _t(loc, 'tour_tile_schedule', 'График формируется руководителем. В карточке сотрудника можно выдать право формировать график самому.')),
    (id: 'home-schedule-kitchen', text: (_) => _t(loc, 'tour_tile_schedule_kitchen', 'График кухни. Смена, сотрудники подразделения.')),
    (id: 'home-menu-kitchen', text: (_) => _t(loc, 'tour_tile_menu_kitchen', 'Меню кухни: блюда подразделения.')),
    (id: 'home-ttk-kitchen', text: (_) => _t(loc, 'tour_tile_ttk', 'ТТК: создание из номенклатуры, расчёт себестоимости. Цех, категория, тип (ПФ/блюдо).')),
    (id: 'home-nomenclature-kitchen', text: (_) => _t(loc, 'tour_tile_nomenclature', 'Продукты с ценами. Вес упаковки, вес 1 шт. — для себестоимости ТТК и инвентаризации.')),
    (id: 'home-suppliers-kitchen', text: (_) => _t(loc, 'tour_tile_suppliers', 'Карточки поставщиков: название, контакты, продукты из номенклатуры.')),
    (id: 'home-order-kitchen', text: (_) => _t(loc, 'tour_tile_order', 'Заказ продуктов. Список по поставщику, сохранение для повтора. Отправка по почте или в буфер/файл.')),
    (id: 'home-writeoffs-kitchen', text: (_) => _t(loc, 'tour_tile_writeoffs', 'Списания: персонал, порча, бракераж, проработка, отказ гостя. Отправка во Входящие.')),
    (id: 'home-checklists-kitchen', text: (_) => _t(loc, 'tour_tile_checklists', 'Чеклисты «заготовки» (из ТТК) и «произвольный». Ограничение по цеху, сотруднику, дедлайну.')),
    (id: 'home-schedule-bar', text: (_) => _t(loc, 'tour_tile_schedule_bar', 'График бара. Смена, сотрудники подразделения.')),
    (id: 'home-menu-bar', text: (_) => _t(loc, 'tour_tile_menu_bar', 'Меню бара: блюда и напитки подразделения.')),
    (id: 'home-ttk-bar', text: (_) => _t(loc, 'tour_tile_ttk_bar', 'ТТК бара: создание из номенклатуры, расчёт себестоимости. Цех, категория, тип (ПФ/блюдо).')),
    (id: 'home-nomenclature-bar', text: (_) => _t(loc, 'tour_tile_nomenclature_bar', 'Продукты бара с ценами. Вес упаковки, вес 1 шт. — для себестоимости ТТК и инвентаризации.')),
    (id: 'home-suppliers-bar', text: (_) => _t(loc, 'tour_tile_suppliers_bar', 'Карточки поставщиков бара: название, контакты, продукты из номенклатуры.')),
    (id: 'home-order-bar', text: (_) => _t(loc, 'tour_tile_order_bar', 'Заказ продуктов для бара. Список по поставщику, сохранение для повтора. Отправка по почте или в буфер.')),
    (id: 'home-writeoffs-bar', text: (_) => _t(loc, 'tour_tile_writeoffs_bar', 'Списания бара: персонал, порча, бракераж, проработка, отказ гостя. Отправка во Входящие.')),
    (id: 'home-checklists-bar', text: (_) => _t(loc, 'tour_tile_checklists_bar', 'Чеклисты бара: «заготовки» (из ТТК) и «произвольный». Ограничение по цеху, сотруднику, дедлайну.')),
    (id: 'home-schedule-hall', text: (_) => _t(loc, 'tour_tile_schedule_hall', 'График зала. Смена, сотрудники подразделения.')),
    (id: 'home-menu-hall', text: (_) => _t(loc, 'tour_tile_menu_hall', 'Меню зала: блюда подразделения.')),
    (id: 'home-checklists-hall', text: (_) => _t(loc, 'tour_tile_checklists_hall', 'Чеклисты зала: «заготовки» (из ТТК) и «произвольный». Ограничение по цеху, сотруднику, дедлайну.')),
    (id: 'home-suppliers-hall', text: (_) => _t(loc, 'tour_tile_suppliers_hall', 'Карточки поставщиков зала: название, контакты, продукты из номенклатуры.')),
    (id: 'home-order-hall', text: (_) => _t(loc, 'tour_tile_order_hall', 'Заказ продуктов для зала. Список по поставщику, сохранение для повтора. Отправка по почте или в буфер.')),
    (id: 'home-writeoffs-hall', text: (_) => _t(loc, 'tour_tile_writeoffs_hall', 'Списания зала: персонал, порча, бракераж, проработка, отказ гостя. Отправка во Входящие.')),
    (id: 'home-expenses', text: (_) => _t(loc, 'tour_tile_expenses', 'Расходы: ФЗП (по графику и ставкам), заказы продуктов, списания. Выбор учёта для итоговой суммы.')),
  ];

  /// Id и текст для менеджмента (шеф, барменеджер, менеджер зала).
  static List<({String id, String Function(LocalizationService loc) text})> managementSteps(LocalizationService loc) => [
    (id: 'home-schedule', text: (_) => _t(loc, 'tour_tile_schedule', 'График формируется руководителем.')),
    (id: 'home-doc', text: (_) => _t(loc, 'tour_tile_doc', 'Документация и правила организации.')),
    (id: 'home-haccp', text: (_) => _t(loc, 'tour_tile_haccp', 'Журналы по СанПин.')),
    (id: 'home-messages', text: (_) => _t(loc, 'tour_tile_messages', 'Личное и групповое общение.')),
    (id: 'home-inbox', text: (_) => _t(loc, 'tour_tile_inbox', 'Входящие: заказы, списания, чеклисты.')),
    (id: 'home-employees', text: (_) => _t(loc, 'tour_tile_employees', 'Сотрудники, выдача доступа.')),
    (id: 'home-checklists', text: (_) => _t(loc, 'tour_tile_checklists', 'Чеклисты.')),
    (id: 'home-menu', text: (_) => _t(loc, 'tour_tile_menu', 'Меню.')),
    (id: 'home-ttk', text: (_) => _t(loc, 'tour_tile_ttk', 'ТТК подразделения.')),
    (id: 'home-nomenclature', text: (_) => _t(loc, 'tour_tile_nomenclature', 'Номенклатура.')),
    (id: 'home-suppliers', text: (_) => _t(loc, 'tour_tile_suppliers', 'Поставщики.')),
    (id: 'home-order', text: (_) => _t(loc, 'tour_tile_order', 'Заказ продуктов.')),
    (id: 'home-inventory', text: (_) => _t(loc, 'tour_tile_inventory', 'Инвентаризация.')),
    (id: 'home-writeoffs', text: (_) => _t(loc, 'tour_tile_writeoffs', 'Списания.')),
  ];

  /// Id и текст для сотрудника (кухня/бар/зал) — порядок из layout.
  static String tileIdForStaff(String homeTileKey) => 'home-$homeTileKey';
}
