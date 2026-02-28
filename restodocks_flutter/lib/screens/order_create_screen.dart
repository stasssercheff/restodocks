import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/order_export_sheet.dart';

/// Экран создания заказа:
/// 1. Название заказа
/// 2. Выбор поставщика (из сохранённых)
/// 3. Список продуктов поставщика с вводом количеств
/// 4. Сохранить в «Списки заказов» или Отправить (почта/мессенджер + во входящие шефу и сушефу)
class OrderCreateScreen extends StatefulWidget {
  const OrderCreateScreen({super.key});

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _nameCtrl = TextEditingController();
  DateTime? _orderForDate;

  List<OrderList> _suppliers = [];
  bool _loadingSuppliers = true;
  OrderList? _selectedSupplier;

  // Позиции с количествами (копируются из выбранного поставщика при выборе)
  List<OrderListItem> _items = [];
  List<TextEditingController> _qtyControllers = [];
  final _commentCtrl = TextEditingController();

  bool _saving = false;

  static const _unitIds = ['g', 'kg', 'ml', 'l', 'pcs', 'шт', 'pack', 'can', 'box'];

  static String _unitLabel(String unitId, String lang) =>
      CulinaryUnits.displayName(unitId, lang);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuppliers());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
      final lists = await loadOrderLists(estId);
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
          ? (double.tryParse(_qtyControllers[e.key].text.replaceFirst(',', '.')) ?? 0)
          : e.value.quantity;
      return e.value.copyWith(quantity: q);
    }).toList();
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
      final saved = OrderList(
        id: const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        supplierName: _selectedSupplier!.supplierName,
        email: _selectedSupplier!.email,
        phone: _selectedSupplier!.phone,
        telegram: _selectedSupplier!.telegram,
        zalo: _selectedSupplier!.zalo,
        whatsapp: _selectedSupplier!.whatsapp,
        items: itemsWithQty,
        comment: _commentCtrl.text,
        savedAt: now,
        orderForDate: _orderForDate,
      );

      final lists = await loadOrderLists(estId);
      await saveOrderLists(estId, [...lists, saved]);

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
      };
      final itemsPayload = itemsWithQty.map((item) => {
        'productId': item.productId,
        'productName': item.productName,
        'unit': item.unit,
        'quantity': item.quantity,
      }).toList();
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.t('order_save_inbox_warning') ?? '${loc.t('order_list_save_with_quantities')} ✓ (входящие: ошибка — нет получателей)'),
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _saving = false);
          if (context.canPop()) context.pop();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.t('order_list_save_with_quantities')} ✓')),
        );
        // pop вместо go, чтобы разрешить await в OrderListsScreen и сразу показать новый заказ
        if (context.canPop()) context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocalizationService>().t('error_short')}: $e')),
        );
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
    final itemsPayload = itemsWithQty.map((item) => {
      'productId': item.productId,
      'productName': item.productName,
      'unit': item.unit,
      'quantity': item.quantity,
    }).toList();
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
            Row(
              children: [
                Expanded(
                  child: _LangButton(
                    flag: '🇷🇺',
                    label: loc.t('order_export_language_ru'),
                    onTap: () => Navigator.of(ctx).pop('ru'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LangButton(
                    flag: '🇬🇧',
                    label: loc.t('order_export_language_en'),
                    onTap: () => Navigator.of(ctx).pop('en'),
                  ),
                ),
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => OrderExportSheet(
        list: tempList,
        itemsWithQuantities: itemsWithQty,
        companyName: companyName,
        loc: loc,
        exportLang: exportLang,
        commentSourceLang: loc.currentLanguageCode,
        onSaved: (msg) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          }
        },
        onExportToInbox: () async {
          final ok = await _saveOrderToInbox();
          if (mounted && !ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${loc.t('error_short')}: ${loc.t('order_save_inbox_error')}',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final lang = loc.currentLanguageCode;

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
                    Row(
                      children: [
                        Expanded(child: Text(loc.t('order_export_order_for') ?? 'На дату')),
                        TextButton(
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
                          child: Text(
                            _orderForDate != null
                                ? DateFormat('dd.MM.yyyy').format(_orderForDate!)
                                : '...',
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Список продуктов
                  if (_selectedSupplier != null && _items.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      loc.t('order_list_add_products') ?? 'Продукты',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Table(
                      border: TableBorder.all(color: Theme.of(context).dividerColor),
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
                        ..._items.asMap().entries.map((e) {
                          final i = e.key;
                          final item = e.value;
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(item.productName,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                child: DropdownButton<String>(
                                  value: item.unit,
                                  isDense: true,
                                  isExpanded: true,
                                  items: _unitIds
                                      .map((id) => DropdownMenuItem(
                                            value: id,
                                            child: Text(
                                              _unitLabel(id, lang),
                                              style: const TextStyle(
                                                  fontSize: 12),
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
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                                decimal: true),
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

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Нижние кнопки
          if (_canSave)
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
        border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.3)),
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

    final contacts = [
      selected!.email,
      selected!.phone,
      selected!.telegram,
    ].where((v) => v != null && v.isNotEmpty).join(' · ');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.store_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(selected!.supplierName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: contacts.isNotEmpty ? Text(contacts) : null,
        trailing: TextButton(
          onPressed: () => _showPicker(context),
          child: Text(loc.t('change') ?? 'Изменить'),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<OrderList>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                loc.t('order_select_supplier') ?? 'Выберите поставщика',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...suppliers.map((s) => ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: Text(s.supplierName),
                  subtitle: s.email != null || s.phone != null
                      ? Text(s.email ?? s.phone ?? '')
                      : null,
                  selected: selected?.id == s.id,
                  onTap: () => Navigator.of(ctx).pop(s),
                )),
            const SizedBox(height: 8),
          ],
        ),
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
