import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/services.dart';
import 'order_list_create_screen.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';
import '../utils/supplier_contact_validation.dart';
import '../widgets/supplier_contact_links.dart';

/// Высота области диалога «поставщик»: между safe area и клавиатурой (iOS / web mobile).
double _supplierSheetMaxHeight(BuildContext context) {
  final mq = MediaQuery.of(context);
  final keyboardInset = mq.viewInsets.bottom;
  final effectiveKeyboardInset = keyboardInset > 0 ? keyboardInset : 0.0;
  return math.max(
    320.0,
    mq.size.height -
        mq.padding.top -
        mq.padding.bottom -
        effectiveKeyboardInset -
        20,
  );
}

EdgeInsets _supplierDialogOuterInsets(BuildContext context) {
  final mq = MediaQuery.of(context);
  final keyboardInset = mq.viewInsets.bottom;
  return EdgeInsets.only(
    left: 16,
    right: 16,
    top: mq.padding.top + 8,
    bottom: 12 + (keyboardInset > 0 ? 8 : 0),
  );
}

EdgeInsets _supplierCenteredDialogInsets(BuildContext context) {
  final mq = MediaQuery.of(context);
  final vPad = math.max(16.0, math.max(mq.padding.top, mq.padding.bottom) + 12);
  return EdgeInsets.symmetric(horizontal: 16, vertical: vPad);
}

Alignment _supplierStep1DialogAlignment(BuildContext context) {
  final mq = MediaQuery.of(context);
  if (mq.viewInsets.bottom > 0) return Alignment.topCenter;
  if (mq.size.height < 700) return Alignment.topCenter;
  return Alignment.center;
}

/// Экран «Поставщики» — только карточки поставщиков со списком продуктов, без заказов.
/// Для каждого подразделения (кухня, бар, зал) свои поставщики.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({
    super.key,
    required this.department,
    this.embedded = false,
  });

  final String department;

  /// Вкладка внутри закупки: без верхней панели, полоса обновления в теле.
  final bool embedded;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<OrderList> _suppliers = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchController = TextEditingController();
  bool _sortAsc = true; // supplier name A→Z / Z→A

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<OrderList> get _filteredSuppliers {
    var list = List<OrderList>.from(_suppliers);
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) {
        if (s.supplierName.toLowerCase().contains(q)) return true;
        return s.items.any((i) => i.productName.toLowerCase().contains(q));
      }).toList();
    }
    list.sort((a, b) {
      final cmp = a.supplierName.toLowerCase().compareTo(b.supplierName.toLowerCase());
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  String _departmentLabel(LocalizationService loc) {
    switch (widget.department) {
      case 'kitchen':
        return loc.t('dept_kitchen') ?? 'Кухня';
      case 'bar':
        return loc.t('dept_bar') ?? 'Бар';
      case 'hall':
        return loc.t('dept_hall') ?? 'Зал';
      default:
        return widget.department;
    }
  }

  /// Загрузка списка к поставщику — Pro / промо или первые 72 ч триала ([hasProSubscription]).
  bool _canUploadSupplierProductList(AccountManagerSupabase acc) =>
      acc.hasProSubscription;

  OrderList _draftFromSupplierFields(
    OrderList s,
    TextEditingController nameCtrl,
    TextEditingController contactCtrl,
    TextEditingController emailCtrl,
    TextEditingController phoneCtrl,
  ) {
    final supplierName = nameCtrl.text.trim();
    return (supplierName.isEmpty
            ? s
            : s.copyWith(name: supplierName, supplierName: supplierName))
        .copyWith(
      contactPerson: contactCtrl.text.trim().isEmpty
          ? null
          : contactCtrl.text.trim(),
      email: normalizedSupplierEmailOrNull(emailCtrl.text),
      phone: normalizedSupplierPhoneOrNull(phoneCtrl.text),
    );
  }

  bool _validateSupplierContacts(
    LocalizationService loc,
    ScaffoldMessengerState messenger,
    TextEditingController emailCtrl,
    TextEditingController phoneCtrl,
  ) {
    if (!isValidSupplierEmail(emailCtrl.text)) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('supplier_invalid_email'))),
      );
      return false;
    }
    if (!isValidSupplierPhone(phoneCtrl.text)) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('supplier_invalid_phone'))),
      );
      return false;
    }
    return true;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() {
        _loading = false;
        _error = 'Нет заведения';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await loadOrderLists(est.id, department: widget.department);
      if (mounted) {
        setState(() {
          _suppliers = list.where((l) => !l.isSavedWithQuantities).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openExternalSupplierSheet() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final estId = acc.establishment?.id;
    if (estId == null) return;

    final draft = await Navigator.of(context).push<OrderList>(
      MaterialPageRoute(
        builder: (_) => OrderListCreateScreen(
          department: widget.department,
          returnDraftOnly: true,
        ),
      ),
    );
    if (draft == null || !mounted) return;
    await _persistNewSupplierAndNavigate(
      establishmentId: estId,
      draft: draft,
      uploadFlow: false,
      loc: loc,
      acc: acc,
    );
  }

  Future<void> _persistNewSupplierAndNavigate({
    required String establishmentId,
    required OrderList draft,
    required bool uploadFlow,
    required LocalizationService loc,
    required AccountManagerSupabase acc,
  }) async {
    if (uploadFlow && !_canUploadSupplierProductList(acc)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('supplier_upload_requires_pro'))),
      );
      return;
    }
    final lists =
        await loadOrderLists(establishmentId, department: widget.department);
    await saveOrderLists(establishmentId, [...lists, draft],
        department: widget.department);
    if (!mounted) return;
    if (uploadFlow) {
      final encName = Uri.encodeComponent(draft.supplierName);
      await context.push(
        '/products/upload?supplierListId=${draft.id}&department=${widget.department}&supplierName=$encName',
      );
    } else {
      await context.push('/product-order/new/products?pop=1', extra: draft);
    }
    if (mounted) _load();
  }

  Future<void> _saveSupplierEdits(OrderList updated) async {
    final acc = context.read<AccountManagerSupabase>();
    final estId = acc.establishment?.id;
    if (estId == null) return;
    final dept = updated.department;
    final lists = await loadOrderLists(estId, department: dept);
    final idx = lists.indexWhere((l) => l.id == updated.id);
    final merged = List<OrderList>.from(lists);
    if (idx >= 0) {
      merged[idx] = updated;
    } else {
      merged.add(updated);
    }
    await saveOrderLists(estId, merged, department: dept);
  }

  Future<void> _deleteSupplier(OrderList s) async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final messenger = ScaffoldMessenger.of(context);
    final estId = acc.establishment?.id;
    if (estId == null) return;
    try {
      final lists =
          await loadOrderLists(estId, department: widget.department);
      final next = lists.where((l) => l.id != s.id).toList();
      await saveOrderLists(estId, next, department: widget.department);
      if (!mounted) return;
      setState(() {
        _suppliers.removeWhere((x) => x.id == s.id);
      });
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('supplier_deleted'))),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${loc.t('error_short')}: $e')),
      );
    }
  }

  Future<void> _editSupplier(OrderList s) async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController(text: s.supplierName);
    final contactCtrl = TextEditingController(text: s.contactPerson ?? '');
    final emailCtrl = TextEditingController(text: s.email ?? '');
    final phoneCtrl = TextEditingController(
      text: supplierPhoneDigitsOnly(s.phone ?? ''),
    );

    OrderList? result;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.t('order_tab_suppliers'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: loc.t('order_list_supplier_name'),
                          border: const OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: contactCtrl,
                        decoration: InputDecoration(
                          labelText: loc.t('supplier_contact_person'),
                          border: const OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: emailCtrl,
                        decoration: InputDecoration(
                          labelText: loc.t('order_list_contact_email'),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: phoneCtrl,
                        decoration: InputDecoration(
                          labelText: loc.t('order_list_contact_phone'),
                          border: const OutlineInputBorder(),
                          counterText: '',
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 15,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: dialogContext,
                              builder: (ctx) => AlertDialog(
                                title: Text(loc.t('supplier_delete_title')),
                                content: Text(
                                  loc.t(
                                    'supplier_delete_confirm',
                                    args: {'name': s.supplierName},
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: Text(loc.t('cancel')),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(ctx).colorScheme.error,
                                      foregroundColor:
                                          Theme.of(ctx).colorScheme.onError,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(loc.t('supplier_delete')),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true || !dialogContext.mounted) {
                              return;
                            }
                            Navigator.of(dialogContext).pop();
                            await _deleteSupplier(s);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          child: Text(loc.t('supplier_delete')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: Text(loc.t('cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final supplierName = nameCtrl.text.trim();
                                if (supplierName.isEmpty) return;
                                if (!_validateSupplierContacts(
                                  loc,
                                  messenger,
                                  emailCtrl,
                                  phoneCtrl,
                                )) {
                                  return;
                                }
                                result = s.copyWith(
                                  name: supplierName,
                                  supplierName: supplierName,
                                  contactPerson: contactCtrl.text.trim().isEmpty
                                      ? null
                                      : contactCtrl.text.trim(),
                                  email: normalizedSupplierEmailOrNull(
                                    emailCtrl.text,
                                  ),
                                  phone: normalizedSupplierPhoneOrNull(
                                    phoneCtrl.text,
                                  ),
                                );
                                Navigator.of(dialogContext).pop();
                              },
                              child: Text(loc.t('save')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          loc.t('order_list_add_products'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          if (!_validateSupplierContacts(
                            loc,
                            messenger,
                            emailCtrl,
                            phoneCtrl,
                          )) {
                            return;
                          }
                          final draft = _draftFromSupplierFields(
                            s,
                            nameCtrl,
                            contactCtrl,
                            emailCtrl,
                            phoneCtrl,
                          );
                          result = draft;
                          Navigator.of(dialogContext).pop();
                          context.push('/product-order/new/products?pop=1',
                              extra: draft);
                        },
                        icon: const Icon(Icons.playlist_add_check_outlined),
                        label: Text(loc.t('supplier_products_from_nomenclature')),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () {
                          if (!_canUploadSupplierProductList(acc)) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                    loc.t('supplier_upload_requires_pro')),
                              ),
                            );
                            return;
                          }
                          if (!_validateSupplierContacts(
                            loc,
                            messenger,
                            emailCtrl,
                            phoneCtrl,
                          )) {
                            return;
                          }
                          final draft = _draftFromSupplierFields(
                            s,
                            nameCtrl,
                            contactCtrl,
                            emailCtrl,
                            phoneCtrl,
                          );
                          result = draft;
                          Navigator.of(dialogContext).pop();
                          final encName =
                              Uri.encodeComponent(draft.supplierName);
                          context.push(
                            '/products/upload?supplierListId=${draft.id}&department=${widget.department}&supplierName=$encName',
                          );
                        },
                        icon: const Icon(Icons.upload_file),
                        label: Text(loc.t('upload_products')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      nameCtrl.dispose();
      contactCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
    }

    if (result == null) return;
    final updated = result!;
    try {
      await _saveSupplierEdits(updated);
      if (!mounted) return;
      setState(() {
        final idx = _suppliers.indexWhere((x) => x.id == updated.id);
        if (idx >= 0) _suppliers[idx] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text('${loc.t('error_short')}: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _productLineLabel(OrderListItem item, LocalizationService loc, ProductStoreSupabase store) {
    final lang = loc.currentLanguageCode;
    final id = item.productId?.trim() ?? '';
    if (id.isNotEmpty) {
      final p = store.findProductById(id);
      if (p != null) return p.getLocalizedName(lang);
    }
    return item.productName;
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final productStore = context.watch<ProductStoreSupabase>();

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              leading: appBarBackButton(context),
              title: ScrollToTopAppBarTitle(
                child: Text(
                    '${loc.t('order_tab_suppliers') ?? 'Поставщики'} — ${_departmentLabel(loc)}'),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load,
                  tooltip: loc.t('refresh'),
                ),
              ],
            ),
      // Одна кнопка «Создать» в пустом состоянии; FAB — только когда список не пуст
      floatingActionButton: !_loading && _error == null && _suppliers.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _openExternalSupplierSheet,
              icon: const Icon(Icons.add_business_outlined),
              label: Text(loc.t('supplier_create_title')),
            )
          : null,
      body: _suppliers.isEmpty && !_loading && _error == null
          ? _buildBody(loc, productStore)
          : Column(
              children: [
                if (widget.embedded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loading ? null : _load,
                        tooltip: loc.t('refresh'),
                      ),
                    ),
                  ),
                if (_suppliers.isNotEmpty) _buildSearchAndSortPanel(loc),
                Expanded(child: _buildBody(loc, productStore)),
              ],
            ),
    );
  }

  Widget _buildSearchAndSortPanel(LocalizationService loc) {
    final sortHint = loc.t(_sortAsc ? 'order_sort_az' : 'order_sort_za');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: loc.t('order_search_supplier_or_product'),
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _searchController.clear()),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: '${loc.t('order_sort')} $sortHint',
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LocalizationService loc, ProductStoreSupabase productStore) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('retry') ?? 'Повторить')),
            ],
          ),
        ),
      );
    }
    if (_suppliers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store_outlined, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(
                loc.t('order_suppliers_empty') ?? 'Нет поставщиков',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                loc.t('order_suppliers_empty_hint') ??
                    'Создайте поставщика в разделе "Поставщики".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _openExternalSupplierSheet,
                icon: const Icon(Icons.add_business_outlined),
                label: Text(loc.t('supplier_create_title')),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredSuppliers;
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            loc.t('order_no_results') ?? 'Ничего не найдено',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final s = filtered[i];
          final hasEmail = (s.email ?? '').trim().isNotEmpty;
          final hasPhone = (s.phone ?? '').trim().isNotEmpty;
          final hasContactPerson = (s.contactPerson ?? '').trim().isNotEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.store_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: loc.t('edit') ?? 'Редактировать',
                onPressed: () => _editSupplier(s),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.supplierName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasContactPerson)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${loc.t('supplier_contact_person') ?? 'Контакт'}: ${s.contactPerson}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  if (hasEmail || hasPhone)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: SupplierContactLinks(
                        email: hasEmail ? s.email! : null,
                        phone: hasPhone ? s.phone! : null,
                        linkColor: Theme.of(context).colorScheme.primary,
                        inline: true,
                      ),
                    ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${loc.t('order_products_count') ?? 'Продуктов'}: ${s.items.length}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      if (s.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...s.items.take(20).map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.circle, size: 6, color: Theme.of(context).colorScheme.outline),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _productLineLabel(item, loc, productStore),
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                  Text(
                                    loc.unitLabel(item.unit),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            )),
                        if (s.items.length > 20)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              (loc.t('order_products_and_more') ?? '... и ещё {n}').replaceAll('{n}', '${s.items.length - 20}'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Шаг 1 мастера «Создать поставщика» — только реквизиты; продукты на следующих шагах.
class _SupplierStep1Result {
  const _SupplierStep1Result({
    required this.name,
    this.contactPerson,
    this.email,
    this.phone,
  });

  final String name;
  final String? contactPerson;
  final String? email;
  final String? phone;
}

class _SupplierStep1Dialog extends StatefulWidget {
  const _SupplierStep1Dialog({required this.loc});

  final LocalizationService loc;

  @override
  State<_SupplierStep1Dialog> createState() => _SupplierStep1DialogState();
}

class _SupplierStep1DialogState extends State<_SupplierStep1Dialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  bool _includeEmail = false;
  bool _includePhone = false;
  String? _nameError;
  String? _emailError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _contactCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl.addListener(_onEmailChanged);
    _phoneCtrl.addListener(_onPhoneChanged);
  }

  void _onEmailChanged() {
    if (_emailCtrl.text.isNotEmpty && !_includeEmail) {
      setState(() => _includeEmail = true);
    }
  }

  void _onPhoneChanged() {
    if (_phoneCtrl.text.isNotEmpty && !_includePhone) {
      setState(() => _includePhone = true);
    }
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onEmailChanged);
    _phoneCtrl.removeListener(_onPhoneChanged);
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final loc = widget.loc;
    setState(() {
      _nameError = null;
      _emailError = null;
      _phoneError = null;
    });

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _nameError = loc.t('supplier_name_required');
      });
      return;
    }

    if (_includeEmail &&
        _emailCtrl.text.trim().isNotEmpty &&
        !isValidSupplierEmail(_emailCtrl.text)) {
      setState(() {
        _emailError = loc.t('supplier_invalid_email');
      });
      return;
    }
    if (_includePhone &&
        _phoneCtrl.text.trim().isNotEmpty &&
        !isValidSupplierPhone(_phoneCtrl.text)) {
      setState(() {
        _phoneError = loc.t('supplier_invalid_phone');
      });
      return;
    }

    final email =
        _includeEmail ? normalizedSupplierEmailOrNull(_emailCtrl.text) : null;
    final phone =
        _includePhone ? normalizedSupplierPhoneOrNull(_phoneCtrl.text) : null;
    final contact = _contactCtrl.text.trim().isEmpty
        ? null
        : _contactCtrl.text.trim();

    Navigator.of(context).pop(
      _SupplierStep1Result(
        name: name,
        contactPerson: contact,
        email: email,
        phone: phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = _supplierSheetMaxHeight(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Dialog(
      alignment: _supplierStep1DialogAlignment(context),
      insetPadding: _supplierDialogOuterInsets(context),
      backgroundColor: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: maxH,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.t('supplier_create_title'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  loc.t('supplier_create_step1_hint'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: loc.t('order_list_supplier_name'),
                    border: const OutlineInputBorder(),
                    errorText: _nameError,
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contactCtrl,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: loc.t('supplier_contact_person'),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _includeEmail,
                  onChanged: (v) {
                    setState(() {
                      _includeEmail = v ?? false;
                      _emailError = null;
                      if (!_includeEmail) {
                        _emailCtrl.clear();
                      }
                    });
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.t('supplier_include_email')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                TextField(
                  controller: _emailCtrl,
                  enabled: _includeEmail,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: loc.t('order_list_contact_email'),
                    border: const OutlineInputBorder(),
                    errorText: _emailError,
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _includePhone,
                  onChanged: (v) {
                    setState(() {
                      _includePhone = v ?? false;
                      _phoneError = null;
                      if (!_includePhone) {
                        _phoneCtrl.clear();
                      }
                    });
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.t('supplier_include_phone')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                TextField(
                  controller: _phoneCtrl,
                  enabled: _includePhone,
                  textInputAction: TextInputAction.done,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: loc.t('order_list_contact_phone'),
                    border: const OutlineInputBorder(),
                    counterText: '',
                    errorText: _phoneError,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  maxLength: 15,
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _submit,
                  child: Text(loc.t('order_list_next')),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(loc.t('cancel')),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

