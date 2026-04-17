import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/order_export_sheet.dart';
import '../widgets/supplier_contact_links.dart';

/// Экран создания заказа:
/// 1. Название заказа
/// 2. Выбор поставщика (из сохранённых)
/// 3. Список продуктов поставщика с вводом количеств
/// 4. Сохранить в «Списки заказов» или Отправить (почта/мессенджер + во входящие шефу и сушефу)
class OrderCreateScreen extends StatefulWidget {
  const OrderCreateScreen({super.key, this.department = 'kitchen'});

  final String department;

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _productSearchCtrl = TextEditingController();
  DateTime? _orderForDate;

  List<OrderList> _suppliers = [];
  bool _loadingSuppliers = true;
  OrderList? _selectedSupplier;

  // Позиции с количествами (копируются из выбранного поставщика при выборе)
  List<OrderListItem> _items = [];
  List<TextEditingController> _qtyControllers = [];
  final _commentCtrl = TextEditingController();

  bool _saving = false;

  static List<String> _unitIds(UnitSystem unitSystem) {
    final base = unitSystem == UnitSystem.imperial
        ? <String>['oz', 'lb', 'fl_oz', 'gal']
        : <String>['g', 'kg', 'ml', 'l'];
    return [...base, 'pcs', 'pack', 'can', 'box'];
  }

  static String _unitLabel(String unitId, String lang) =>
      LocalizationService().unitLabelForLanguage(unitId, lang);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuppliers());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _productSearchCtrl.dispose();
    _commentCtrl.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final acc = context.read<AccountManagerSupabase>();
    final estId = acc.establishment?.id;
    if (estId == null) {
      setState(() => _loadingSuppliers = false);
      return;
    }
    try {
      // Загружаем продукты для отображения локализованных имён в таблице
      final store = context.read<ProductStoreSupabase>();
      if (store.allProducts.isEmpty) await store.loadProducts();

      final lists = await loadOrderLists(estId, department: widget.department);
      if (mounted) {
        setState(() {
          _suppliers = lists.where((l) => !l.isSavedWithQuantities).toList();
          _loadingSuppliers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSuppliers = false);
    }
  }

  void _selectSupplier(OrderList supplier) {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    setState(() {
      _selectedSupplier = supplier;
      _items = supplier.items.map((e) => e.copyWith(quantity: 0)).toList();
      _qtyControllers = _items.map((_) => TextEditingController()).toList();
    });
  }

  List<OrderListItem> _getItemsWithQuantities() {
    return _items.asMap().entries.map((e) {
      final q = e.key < _qtyControllers.length
          ? (double.tryParse(
                  _qtyControllers[e.key].text.replaceFirst(',', '.')) ??
              0)
          : e.value.quantity;
      return e.value.copyWith(quantity: q);
    }).toList();
  }

  List<MapEntry<int, OrderListItem>> _filteredItemEntries(String lang) {
    final q = _productSearchCtrl.text.trim().toLowerCase();
    final entries = _items.asMap().entries.toList();
    if (q.isEmpty) return entries;
    return entries.where((e) {
      final name = _getItemDisplayName(e.value, lang).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  /// Локализованное имя продукта для отображения в UI.
  String _getItemDisplayName(OrderListItem item, String lang) {
    final productId = item.productId;
    if (productId != null && productId.isNotEmpty) {
      final store = context.read<ProductStoreSupabase>();
      final product =
          store.allProducts.where((p) => p.id == productId).firstOrNull;
      if (product != null) return product.getLocalizedName(lang);
    }
    return item.productName;
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty &&
      _selectedSupplier != null &&
      _items.isNotEmpty;

  Future<void> _saveOrder() async {
    if (!_canSave) return;
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final estId = acc.establishment?.id;
    final employee = acc.currentEmployee;
    final establishment = acc.establishment;
    if (estId == null || employee == null || establishment == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final itemsWithQty = _getItemsWithQuantities();
      final dept = widget.department;
      final saved = OrderList(
        id: const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        supplierName: _selectedSupplier!.supplierName,
        contactPerson: _selectedSupplier!.contactPerson,
        email: _selectedSupplier!.email,
        phone: _selectedSupplier!.phone,
        telegram: _selectedSupplier!.telegram,
        zalo: _selectedSupplier!.zalo,
        whatsapp: _selectedSupplier!.whatsapp,
        items: itemsWithQty,
        comment: _commentCtrl.text,
        savedAt: now,
        orderForDate: _orderForDate,
        department: dept,
      );

      final lists = await loadOrderLists(estId, department: dept);
      await saveOrderLists(estId, [...lists, saved], department: dept);

      // Сохраняем во входящие шефу и собственнику
      final orderForDateStr = _orderForDate != null
          ? DateFormat('yyyy-MM-dd').format(_orderForDate!)
          : null;
      final header = {
        'supplierName': saved.supplierName,
        'employeeName': employee.fullName,
        'establishmentName': establishment.name,
        'createdAt': now.toIso8601String(),
        'orderForDate': orderForDateStr,
        'department': dept,
      };
      final itemsPayload = itemsWithQty
          .map((item) => {
                'productId': item.productId,
                'productName': item.productName,
                'unit': item.unit,
                'quantity': item.quantity,
              })
          .toList();
      final orderDoc = await OrderDocumentService().saveWithServerPrices(
        establishmentId: estId,
        createdByEmployeeId: employee.id,
        header: header,
        items: itemsPayload,
        comment: saved.comment,
        sourceLang: loc.currentLanguageCode,
      );

      if (mounted) {
        if (orderDoc == null) {
          // Заказ сохранён локально, но входящие не созданы — показываем предупреждение, но не блокируем
          AppToastService.show(
            loc.t('order_save_inbox_warning') ??
                '${loc.t('order_list_save_with_quantities')} ✓ (входящие: ошибка — нет получателей)',
            duration: const Duration(seconds: 5),
          );
          setState(() => _saving = false);
          if (context.canPop()) context.pop();
          return;
        }
        AppToastService.show('${loc.t('order_list_save_with_quantities')} ✓',
            duration: const Duration(seconds: 3));
        // pop вместо go, чтобы разрешить await в OrderListsScreen и сразу показать новый заказ
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppToastService.show(
            '${context.read<LocalizationService>().t('error_short')}: $e',
            duration: const Duration(seconds: 4));
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _saveOrderToInbox() async {
    if (_selectedSupplier == null) return false;
    final acc = context.read<AccountManagerSupabase>();
    final employee = acc.currentEmployee;
    final establishment = acc.establishment;
    if (employee == null || establishment == null) return false;
    final itemsWithQty = _getItemsWithQuantities();
    final now = DateTime.now();
    final orderForDateStr = _orderForDate != null
        ? DateFormat('yyyy-MM-dd').format(_orderForDate!)
        : null;
    final header = {
      'supplierName': _selectedSupplier!.supplierName,
      'employeeName': employee.fullName,
      'establishmentName': establishment.name,
      'createdAt': now.toIso8601String(),
      'orderForDate': orderForDateStr,
    };
    final itemsPayload = itemsWithQty
        .map((item) => {
              'productId': item.productId,
              'productName': item.productName,
              'unit': item.unit,
              'quantity': item.quantity,
            })
        .toList();
    final orderDoc = await OrderDocumentService().saveWithServerPrices(
      establishmentId: establishment.id,
      createdByEmployeeId: employee.id,
      header: header,
      items: itemsPayload,
      comment: _commentCtrl.text,
      sourceLang: context.read<LocalizationService>().currentLanguageCode,
    );
    return orderDoc != null;
  }

  Future<void> _showSendSheet() async {
    if (_selectedSupplier == null) return;
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final companyName = acc.establishment?.name ?? '—';

    final exportLang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('order_export_language_title')),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.t('order_export_language_subtitle')),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LangButton(
                    flag: '🇷🇺',
                    label: loc.t('order_export_language_ru'),
                    onTap: () => Navigator.of(ctx).pop('ru')),
                _LangButton(
                    flag: '🇺🇸',
                    label: loc.t('order_export_language_en'),
                    onTap: () => Navigator.of(ctx).pop('en')),
                _LangButton(
                    flag: '🇪🇸',
                    label: loc.t('order_export_language_es'),
                    onTap: () => Navigator.of(ctx).pop('es')),
                _LangButton(
                    flag: '🇮🇹',
                    label: loc.t('order_export_language_it') ?? 'Italiano',
                    onTap: () => Navigator.of(ctx).pop('it')),
                _LangButton(
                    flag: '🇹🇷',
                    label: loc.t('order_export_language_tr') ?? 'Türkçe',
                    onTap: () => Navigator.of(ctx).pop('tr')),
                _LangButton(
                    flag: '🇰🇿',
                    label: loc.t('order_export_language_kk') ?? 'Қазақша',
                    onTap: () => Navigator.of(ctx).pop('kk')),
              ],
            ),
          ],
        ),
      ),
    );
    if (exportLang == null || !mounted) return;

    // Строим временный OrderList с текущими данными для экспорта
    final itemsWithQty = _getItemsWithQuantities();
    final tempList = OrderList(
      id: const Uuid().v4(),
      name: _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : _selectedSupplier!.supplierName,
      supplierName: _selectedSupplier!.supplierName,
      contactPerson: _selectedSupplier!.contactPerson,
      email: _selectedSupplier!.email,
      phone: _selectedSupplier!.phone,
      telegram: _selectedSupplier!.telegram,
      zalo: _selectedSupplier!.zalo,
      whatsapp: _selectedSupplier!.whatsapp,
      items: itemsWithQty,
      comment: _commentCtrl.text,
      orderForDate: _orderForDate,
    );

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => OrderExportSheet(
        list: tempList,
        itemsWithQuantities: itemsWithQty,
        companyName: companyName,
        loc: loc,
        exportLang: exportLang,
        commentSourceLang: loc.currentLanguageCode,
        itemsSourceLang: loc.currentLanguageCode,
        onSaved: (msg) {
          if (mounted) {
            AppToastService.show(msg, duration: const Duration(seconds: 3));
          }
        },
        onExportToInbox: () async {
          final ok = await _saveOrderToInbox();
          if (mounted && !ok) {
            AppToastService.show(
                '${loc.t('error_short')}: ${loc.t('order_save_inbox_error')}',
                duration: const Duration(seconds: 4));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final unitPrefs = context.watch<UnitSystemPreferenceService>();
    final lang = loc.currentLanguageCode;
    final mq = MediaQuery.of(context);
    final narrowPhone = mq.size.shortestSide < 600;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('order_list_create') ?? 'Создать заказ'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Название заказа
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: loc.t('order_list_name') ?? 'Название заказа',
                      border: const OutlineInputBorder(),
                      filled: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Выбор поставщика
                  _loadingSuppliers
                      ? const Center(child: CircularProgressIndicator())
                      : _suppliers.isEmpty
                          ? _NoSuppliersHint(loc: loc)
                          : _SupplierSelector(
                              suppliers: _suppliers,
                              selected: _selectedSupplier,
                              onSelect: _selectSupplier,
                              loc: loc,
                            ),

                  // Дата поставки
                  if (_selectedSupplier != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _orderForDate ??
                              DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _orderForDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        _orderForDate != null
                            ? '${loc.t('order_export_order_for') ?? 'На когда заказ'}: ${DateFormat('dd.MM.yyyy').format(_orderForDate!)}'
                            : (loc.t('order_export_order_for') ??
                                'На когда заказ'),
                      ),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ],

                  // Список продуктов
                  if (_selectedSupplier != null && _items.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _productSearchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: loc.t('search') ?? 'Поиск',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Table(
                      border: TableBorder.all(
                          color: Theme.of(context).dividerColor),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FixedColumnWidth(100),
                        2: FixedColumnWidth(100),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              child: Text(
                                loc.t('inventory_item_name') ?? 'Наименование',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              child: Text(
                                loc.t('order_list_unit') ?? 'Ед.',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              child: Text(
                                loc.t('order_list_quantity') ?? 'Кол-во',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        ..._filteredItemEntries(lang).map((e) {
                          final i = e.key;
                          final item = e.value;
                          final allowedUnits = _unitIds(unitPrefs.unitSystem);
                          final selectedUnit = allowedUnits.contains(item.unit)
                              ? item.unit
                              : allowedUnits.first;
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(_getItemDisplayName(item, lang),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                child: DropdownButton<String>(
                                  value: selectedUnit,
                                  isDense: true,
                                  isExpanded: true,
                                  items: allowedUnits
                                      .map((id) => DropdownMenuItem(
                                            value: id,
                                            child: Text(
                                              _unitLabel(id, lang),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      final newItems =
                                          List<OrderListItem>.from(_items);
                                      newItems[i] = item.copyWith(unit: v);
                                      _items = newItems;
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                child: i < _qtyControllers.length
                                    ? TextField(
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                        ),
                                        style: const TextStyle(fontSize: 12),
                                        controller: _qtyControllers[i],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],

                  // Пустое состояние — поставщик выбран, но продуктов нет
                  if (_selectedSupplier != null && _items.isEmpty) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        loc.t('no_products') ?? 'У поставщика нет продуктов',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],

                  // Комментарий
                  if (_selectedSupplier != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      loc.t('order_list_comment') ?? 'Комментарий',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: loc.t('order_comment_hint'),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                  ],

                  const SizedBox(height: 24),
                  if (_canSave && narrowPhone) ...[
                    OutlinedButton(
                      onPressed: _saving ? null : _saveOrder,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              loc.t('order_list_save_with_quantities') ??
                                  'Сохранить',
                            ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _saving ? null : _showSendSheet,
                      icon: const Icon(Icons.send),
                      label: Text(loc.t('order_list_send') ?? 'Отправить'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Нижние кнопки
          if (_canSave && !narrowPhone)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _saveOrder,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                loc.t('order_list_save_with_quantities') ??
                                    'Сохранить',
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _showSendSheet,
                        icon: const Icon(Icons.send),
                        label: Text(loc.t('order_list_send') ?? 'Отправить'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Виджет: нет поставщиков
// ─────────────────────────────────────────────

class _NoSuppliersHint extends StatelessWidget {
  const _NoSuppliersHint({required this.loc});

  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).colorScheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              loc.t('order_no_suppliers_hint') ??
                  'Сначала создайте поставщика во вкладке «Поставщики»',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Виджет: выбор поставщика
// ─────────────────────────────────────────────

class _SupplierSelector extends StatelessWidget {
  const _SupplierSelector({
    required this.suppliers,
    required this.selected,
    required this.onSelect,
    required this.loc,
  });

  final List<OrderList> suppliers;
  final OrderList? selected;
  final void Function(OrderList) onSelect;
  final LocalizationService loc;

  @override
  Widget build(BuildContext context) {
    if (selected == null) {
      return OutlinedButton.icon(
        onPressed: () => _showPicker(context),
        icon: const Icon(Icons.store_outlined),
        label: Text(
          loc.t('order_select_supplier') ?? 'Выберите поставщика',
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size(double.infinity, 0),
        ),
      );
    }

    final hasEmail = (selected!.email ?? '').trim().isNotEmpty;
    final hasPhone = (selected!.phone ?? '').trim().isNotEmpty;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.store_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(selected!.supplierName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: (hasEmail || hasPhone)
            ? SupplierContactLinks(
                email: hasEmail ? selected!.email : null,
                phone: hasPhone ? selected!.phone : null,
                linkColor: Theme.of(context).colorScheme.primary,
                inline: true,
              )
            : null,
        trailing: TextButton(
          onPressed: () => _showPicker(context),
          child: Text(loc.t('change') ?? 'Изменить'),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<OrderList>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.t('order_select_supplier') ?? 'Выберите поставщика'),
        children: [
          ...suppliers.map((s) => SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(s),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
                    child: Icon(Icons.store_outlined,
                        color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                        size: 20),
                  ),
                  title: Text(s.supplierName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: (s.email ?? s.phone) != null
                      ? Text(s.email ?? s.phone ?? '',
                          overflow: TextOverflow.ellipsis)
                      : null,
                  selected: selected?.id == s.id,
                ),
              )),
          const SizedBox(height: 4),
        ],
      ),
    ).then((s) {
      if (s != null) onSelect(s);
    });
  }
}

// ─────────────────────────────────────────────
// Кнопка выбора языка документа
// ─────────────────────────────────────────────

class _LangButton extends StatelessWidget {
  const _LangButton({
    required this.flag,
    required this.label,
    required this.onTap,
  });

  final String flag;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
