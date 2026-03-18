import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/translation.dart';
import '../services/services.dart';

/// Один пункт документа: заголовок и список подпунктов (или вложенные пункты).
class _DocumentSection {
  const _DocumentSection(this.title, this.children);
  final String title;
  final List<_DocumentItem> children;
}

/// Элемент: либо подпункт (текст), либо вложенная секция (подзаголовок + подпункты).
class _DocumentItem {
  const _DocumentItem(this.text, [this.nested]);
  final String text;
  final List<_DocumentItem>? nested;
}

/// Контент «Начало работы с Restodocks» с раскрывающимися разделами.
class GettingStartedDocument extends StatefulWidget {
  const GettingStartedDocument({
    super.key,
    this.showTitle = true,
    this.scrollController,
    this.languageCodeOverride,
  });

  final bool showTitle;
  final ScrollController? scrollController;
  /// Позволяет принудительно показать документ на выбранном языке (для первого запуска).
  final String? languageCodeOverride;

  static const String _title = 'Начало работы с Restodocks';

  static final List<_DocumentSection> _sections = [
    _DocumentSection('1. Владелец заведения', [
      _DocumentItem('При регистрации владелец заведения может совмещать роль руководителя (шеф, су-шеф, бар-менеджер, менеджер зала)'),
      _DocumentItem('В настройках есть переключение роли: владелец / выбранная должность.'),
      _DocumentItem('Владелец может пригласить дополнительного совладельца.'),
      _DocumentItem('Владелец может создать до 5 заведений (филиалы либо обособленные).'),
      _DocumentItem('При создании филиала дублируются все ТТК и номенклатура.'),
      _DocumentItem('При создании более 1 заведения совладелец обладает только функцией просмотра (без возможности внесения данных) в роли владельца.'),
      _DocumentItem('Цены в филиалах индивидуальны, но номенклатура (список товаров) синхронизирована с основным заведением, т.к. она привязана к основному заведению.'),
      _DocumentItem('Филиал может вносить свои ТТК без возможности удалить ТТК основного заведения. В ТТК основного заведения доступен только просмотр.'),
    ]),
    _DocumentSection('2. Номенклатура', [
      _DocumentItem('Загрузите продукты в номенклатуру. (в настройках есть обучающее видео)'),
      _DocumentItem('Если есть возможность нужно загрузить продукты с ценами. Это даст возможность высчитывать себестоимость ТТК и блюд.'),
      _DocumentItem('В каждой карточке каждого продукта можно определить стоимость за кг, либо внести вес упаковки (для удобства заполнения инвентаризационного бланка в упаковках).'),
      _DocumentItem('В каждой карточке каждого продукта можно определить вес 1 шт (Например яйца) для корректного составления ТТК.'),
    ]),
    _DocumentSection('3. ТТК', [
      _DocumentItem('Загрузите / создайте ТТК.'),
      _DocumentItem('Создание ТТК может быть только из продуктов внесенных в номенклатуру.'),
      _DocumentItem('Если продукты в ТТК соответствуют продуктам в номенклатуре, стоимость будет рассчитываться автоматически.'),
      _DocumentItem('При загрузке ТТК (в подразделении "кухня") будут определены (частично автоматически) цех, категория (салат, заготовка, десерт), тип ТТК (ПФ, блюдо). Это влияет на отображение / скрытие у сотрудников того или иного цеха.'),
    ]),
    _DocumentSection('4. Регистрация сотрудников', [
      _DocumentItem('При регистрации заведению присваивается pin-код. Он необходим для регистрации сотрудников.'),
      _DocumentItem('После регистрации сотрудника его доступ ограничен доступом только к личному графику. У сотрудников управления (шеф, су-шеф, бар-менеджер, менеджер зала) во вкладке сотрудники есть кнопка — разрешить доступ. Это даёт доступ к данным сотрудника исходя из его должности (ТТК ПФ/блюда только своего цеха).'),
      _DocumentItem('В карточке сотрудника так же прописывается система оплаты (почасовая/посменная) и ставка (за час/смену).'),
    ]),
    _DocumentSection('5. График', [
      _DocumentItem('График формируется руководителем подразделения (шеф, су-шеф, бар-менеджер, менеджер зала).'),
      _DocumentItem('При необходимости в карточке сотрудника (раздел "Сотрудники") каждому можно выдать доступ формировать график самому.'),
    ]),
    _DocumentSection('6. Заказ продуктов', [
      _DocumentItem('В разделе поставщики формируется карточка поставщика. В ней внесены название, контактные данные и продукты внесенные в номенклатуру.'),
      _DocumentItem('Заказ продуктов формируется отдельно из каждого поставщика. Вносится продукт и количество. Каждый список можно сохранить для повторного использования.'),
      _DocumentItem('Отправить можно по почте (с выбранным языком отправки) либо сохранить на устройстве (текст в буфер обмена для отправки через мессенджер, либо сохранить файл в выбранном формате для дальнейшей отправки иным способом).'),
      _DocumentItem('Каждый отправленный заказ дублируется во "Входящие" (шеф, су-шеф, бар-менеджер, менеджер зала и владельцу заведения) с указанием стоимости (если внесена в номенклатуре) и так же в "Расходы". Во "Входящие" есть возможность сохранить заказ на устройстве.'),
    ]),
    _DocumentSection('7. Чеклисты', [
      _DocumentItem('Есть 2 вида чеклистов: "заготовки" и "произвольный". При выборе "заготовки" дается возможность выбрать ТТК с указанием необходимого количества готовой продукции (при просмотре/заполнении чеклиста на каждом пункте чеклиста ТТК ПФ есть ссылка, ведущая к конкретной карточке ТТК с уже вбитым количеством необходимого для приготовления продукта).'),
      _DocumentItem('При выборе "произвольный" текстом прописываются задачи для выполнения.'),
      _DocumentItem('Каждый чеклист можно ограничить цехом, сотрудником, дедлайном либо моментом к которому должна быть выполнена задача. При просрочке выполнения чеклиста сообщение об этом поступает во "Входящие" руководителю подразделения (шеф, су-шеф, бар-менеджер, менеджер зала).'),
    ]),
    _DocumentSection('8. Списания', [
      _DocumentItem('Список формируется сотрудником из учетной записи (его имя автоматически вшито в список заполнения). Заполняется из списка продуктов внесенных в номенклатуру, ТТК ПФ, ТТК блюда. Разделяется по типу (персонал, порча, бракераж, проработка, отказ гостя).'),
      _DocumentItem('Все списания могут быть сохранены на выбранном языке. И при заполнении отправляются во "Входящие" (шеф, су-шеф, бар-менеджер, менеджер зала).'),
    ]),
    _DocumentSection('9. Раздел расходы (только у владельца)', [
      _DocumentItem('В "ФЗП" рассчитывается итоговая и промежуточная сумма расходов на ЗП сотрудников. Расчёт ведётся исходя из составленного графика и ставки (за час/смену).'),
      _DocumentItem('В "Заказ продуктов" отображаются все сделанные заказы (с возможностью выбрать те, которые будут учтены для подсчёта итоговой суммы). Стоимость будет рассчитана в случае, если указана цена в карточке продукта в номенклатуре.'),
      _DocumentItem('В "Списания" отображаются все сделанные списания (с возможностью выбрать те, которые будут учтены для подсчёта итоговой суммы). Стоимость будет рассчитана в случае, если указана цена в карточке продукта в номенклатуре.'),
    ]),
    _DocumentSection('10. Сообщения', [
      _DocumentItem('Личное общение с сотрудником внутри платформы с возможностью отправки фото.'),
      _DocumentItem('Групповое общение с выбранными сотрудниками.'),
    ]),
    _DocumentSection('11. Документы', [
      _DocumentItem('В данном разделе владелец может создавать и выкладывать общую документацию и правила организации.'),
      _DocumentItem('Документы могут быть ограничены к просмотру по подразделениям, цехам, сотрудникам.'),
    ]),
    _DocumentSection('12. Перевод', [
      _DocumentItem('На данный момент на сайте 5 языков: русский, английский, испанский, турецкий, вьетнамский.'),
      _DocumentItem('Перевод осуществляется автоматически.'),
      _DocumentItem('Всё переводится в соответствии с выбранным языком интерфейса (в настройках). Если в настройках выбран какой-то язык, вне зависимости от данных: ННР (включая внесённой вручную при создании ТТК технологии процесса приготовления), сообщения, чеклисты, заказ продуктов (включая комментарии), инвентаризация.'),
      _DocumentItem('Исключения в переводе — продукты импортированные из списков, в именах которых присутствуют неоднозначные символы либо непонятные сокращения.'),
    ]),
    _DocumentSection('13. Журналы', [
      _DocumentItem(
        'На данный момент в системе 12 журналов. Все они созданы по форме "СанПин" в соответствии с законом:',
        [
          _DocumentItem('Гигиенический журнал (сотрудники)'),
          _DocumentItem('Журнал учета температурного режима холодильного оборудования'),
          _DocumentItem('Журнал учета температуры и влажности в складских помещениях'),
          _DocumentItem('Журнал бракеража готовой пищевой продукции'),
          _DocumentItem('Журнал бракеража скоропортящейся пищевой продукции'),
          _DocumentItem('Учёт фритюрных жиров'),
          _DocumentItem('Журнал учёта личных медицинских книжек'),
          _DocumentItem('Журнал учёта прохождения работниками обязательных предварительных и периодических медицинских осмотров'),
          _DocumentItem('Журнал учёта получения, расхода дезинфицирующих средств и проведения дезинфекционных работ на объекте'),
          _DocumentItem('Журнал мойки и дезинфекции оборудования'),
          _DocumentItem('Журнал-график проведения генеральных уборок'),
          _DocumentItem('Журнал результатов проверки и очистки сит (фильтров) и магнитоуловителей'),
        ],
      ),
      _DocumentItem('После заполнения данные невозможно изменить. Всё хранится на сервере в зашифрованном виде.'),
      _DocumentItem('В соответствии с этими данными и консультацией у компетентного специалиста, журналы допустимо вести в электронном виде при условии возможности их распечатать и хранить в течение 3 месяцев.'),
      _DocumentItem('Каждый сотрудник подписывает Соглашение о признании ПЭП (доступен для скачивания в настройках). По условиям соглашения, цифровая подпись (ПЭП) сотрудника из личной учетной записи приравнивается к подписи внутри компании.'),
      _DocumentItem('Все журналы скачиваются по форме установленного образца СанПин и подлежат выгрузке и заверению ответственным лицом.'),
    ]),
    _DocumentSection('14. Настройки', [
      _DocumentItem('Ввод данных, включая: имя, фамилию, дату рождения, адрес email, фото, должность (цех), подразделение.'),
      _DocumentItem(
        'Настройка профиля сотрудника',
        [
          _DocumentItem('Настройки домашнего экрана (порядок отображения кнопок, выбор функции центральной кнопки в нижней панели из предложенных).'),
          _DocumentItem('Уведомления (вкл/выкл).'),
          _DocumentItem('Цветовое оформление.'),
          _DocumentItem('Выбор языка интерфейса (автоматический перевод всей отображаемой информации на выбранный язык), включая сообщения и комментарии.'),
          _DocumentItem('Обучающие видео и текстовое описание (данная инструкция).'),
          _DocumentItem('Смена пароля.'),
        ],
      ),
      _DocumentItem(
        'Настройка профиля владельца',
        [
          _DocumentItem('Настройки домашнего экрана (порядок отображения кнопок, выбор функции центральной кнопки в нижней панели из предложенных).'),
          _DocumentItem('Уведомления (вкл/выкл).'),
          _DocumentItem('Цветовое оформление.'),
          _DocumentItem('Выбор языка интерфейса (автоматический перевод всей отображаемой информации на выбранный язык), включая сообщения и комментарии.'),
          _DocumentItem('Выбор валюты заведения.'),
          _DocumentItem('Выбор отображаемых журналов.'),
          _DocumentItem('Данные заведения.'),
          _DocumentItem('Добавление заведения.'),
          _DocumentItem('Выбор роли.'),
          _DocumentItem('Смена пароля.'),
        ],
      ),
    ]),
  ];

  @override
  State<GettingStartedDocument> createState() => _GettingStartedDocumentState();
}

class _GettingStartedDocumentState extends State<GettingStartedDocument> {
  final Map<String, String> _cache = {};
  bool _loading = false;

  static const String _entityId = 'getting_started';
  static const String _sourceLang = 'ru';

  String _key(String fieldName, String targetLang) => '$_entityId|$fieldName|$targetLang';

  String _t(String fieldName, String original, String targetLang) {
    if (targetLang == _sourceLang) return original;
    return _cache[_key(fieldName, targetLang)] ?? original;
  }

  Future<void> _ensureTranslations(String targetLang) async {
    if (!mounted) return;
    if (targetLang == _sourceLang) return;
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final translationSvc = context.read<TranslationService>();

      Future<void> translateAndStore(String fieldName, String text) async {
        final clean = text.trim();
        if (clean.isEmpty) return;
        final k = _key(fieldName, targetLang);
        if (_cache.containsKey(k)) return;
        final translated = await translationSvc.translate(
          entityType: TranslationEntityType.ui,
          entityId: _entityId,
          fieldName: fieldName,
          text: clean,
          from: _sourceLang,
          to: targetLang,
        );
        if (!mounted) return;
        setState(() {
          _cache[k] = (translated != null && translated.trim().isNotEmpty) ? translated : clean;
        });
      }

      await translateAndStore('title', GettingStartedDocument._title);

      for (var si = 0; si < GettingStartedDocument._sections.length; si++) {
        final s = GettingStartedDocument._sections[si];
        await translateAndStore('section_${si}_title', s.title);
        for (var ii = 0; ii < s.children.length; ii++) {
          final item = s.children[ii];
          await translateAndStore('section_${si}_item_${ii}', item.text);
          final nested = item.nested;
          if (nested != null && nested.isNotEmpty) {
            for (var ni = 0; ni < nested.length; ni++) {
              await translateAndStore('section_${si}_item_${ii}_nested_${ni}', nested[ni].text);
            }
          }
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final targetLang = widget.languageCodeOverride ?? loc.currentLanguageCode;
    // Ленивая подгрузка: при смене языка переведём контент в фоне.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTranslations(targetLang));

    final theme = Theme.of(context);
    final hasTitle = widget.showTitle;
    final sectionCount = GettingStartedDocument._sections.length;
    return ListView.builder(
      controller: widget.scrollController,
      shrinkWrap: false,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: (hasTitle ? 1 : 0) + sectionCount,
      itemBuilder: (context, index) {
        if (hasTitle && index == 0) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  _t('title', GettingStartedDocument._title, targetLang),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
          );
        }
        final sectionIndex = hasTitle ? index - 1 : index;
        final section = GettingStartedDocument._sections[sectionIndex];
        return _SectionExpansion(
          title: _t('section_${sectionIndex}_title', section.title, targetLang),
          sectionIndex: sectionIndex,
          children: section.children,
          translate: (fieldName, original) => _t(fieldName, original, targetLang),
        );
      },
    );
  }
}

/// Вложенный раскрывающийся блок (например, список 12 журналов внутри п. 13).
class _NestedExpandableItem extends StatefulWidget {
  const _NestedExpandableItem({
    required this.index,
    required this.introText,
    required this.nestedItems,
    required this.theme,
    required this.translate,
    required this.sectionIndex,
    required this.itemIndex,
  });

  final int index;
  final String introText;
  final List<_DocumentItem> nestedItems;
  final ThemeData theme;
  final String Function(String fieldName, String original) translate;
  final int sectionIndex;
  final int itemIndex;

  @override
  State<_NestedExpandableItem> createState() => _NestedExpandableItemState();
}

class _NestedExpandableItemState extends State<_NestedExpandableItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.index}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.introText,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            ...widget.nestedItems.asMap().entries.map((e) {
              final j = e.key + 1;
              final sub = e.value;
              return Padding(
                padding: const EdgeInsets.fromLTRB(44, 4, 16, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$j.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.translate(
                          'section_${widget.sectionIndex}_item_${widget.itemIndex}_nested_${e.key}',
                          sub.text,
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _SectionExpansion extends StatefulWidget {
  const _SectionExpansion({
    required this.title,
    required this.children,
    required this.translate,
    required this.sectionIndex,
  });

  final String title;
  final int sectionIndex;
  final List<_DocumentItem> children;
  final String Function(String fieldName, String original) translate;

  @override
  State<_SectionExpansion> createState() => _SectionExpansionState();
}

class _SectionExpansionState extends State<_SectionExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...widget.children.asMap().entries.map((e) {
              final i = e.key + 1;
              final item = e.value;
              if (item.nested == null || item.nested!.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$i.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.translate('section_${widget.sectionIndex}_item_${e.key}', item.text),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _NestedExpandableItem(
                index: i,
                introText: widget.translate('section_${widget.sectionIndex}_item_${e.key}', item.text),
                nestedItems: item.nested!,
                theme: theme,
                translate: widget.translate,
                sectionIndex: widget.sectionIndex,
                itemIndex: e.key,
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
