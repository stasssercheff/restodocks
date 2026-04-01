import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/scroll_to_top_app_bar_title.dart';
import '../utils/supplier_contact_validation.dart';
import '../widgets/supplier_contact_links.dart';

/// Экран «Поставщики» — только карточки поставщиков со списком продуктов, без заказов.
/// Для каждого подразделения (кухня, бар, зал) свои поставщики.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.department});

  final String department;

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

  /// Загрузка списка к поставщику — тариф Pro / Premium или промокод ([hasPaidProAccess]), не окно 72ч trial.
  bool _canUploadSupplierProductList(AccountManagerSupabase acc) =>
      acc.hasPaidProSubscription;

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

    final messenger = ScaffoldMessenger.of(context);

    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    OrderList buildDraft() {
      final name = nameCtrl.text.trim();
      return OrderList(
        id: const Uuid().v4(),
        name: name,
        supplierName: name,
        contactPerson: contactCtrl.text.trim().isEmpty
            ? null
            : contactCtrl.text.trim(),
        email: normalizedSupplierEmailOrNull(emailCtrl.text),
        phone: normalizedSupplierPhoneOrNull(phoneCtrl.text),
        department: widget.department,
      );
    }

    Future<void> saveDraftAndGo({
      required BuildContext dialogContext,
      required bool uploadFlow,
    }) async {
      if (uploadFlow && !_canUploadSupplierProductList(acc)) {
        messenger.showSnackBar(
          SnackBar(content: Text(loc.t('supplier_upload_requires_pro'))),
        );
        return;
      }
      final name = nameCtrl.text.trim();
      if (name.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(loc.t('order_list_supplier_name'))),
        );
        return;
      }
      if (!_validateSupplierContacts(loc, messenger, emailCtrl, phoneCtrl)) {
        return;
      }
      final draft = buildDraft();
      final lists =
          await loadOrderLists(estId, department: widget.department);
      await saveOrderLists(estId, [...lists, draft],
          department: widget.department);
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
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
                        loc.t('supplier_create_title'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loc.t('supplier_external_subtitle'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 20),
                      FilledButton.tonalIcon(
                        onPressed: () => saveDraftAndGo(
                          dialogContext: dialogContext,
                          uploadFlow: false,
                        ),
                        icon: const Icon(Icons.playlist_add_check_outlined),
                        label: Text(loc.t('supplier_products_from_nomenclature')),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => saveDraftAndGo(
                          dialogContext: dialogContext,
                          uploadFlow: true,
                        ),
                        icon: const Icon(Icons.upload_file),
                        label: Text(loc.t('upload_products')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(loc.t('cancel')),
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
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: ScrollToTopAppBarTitle(
          child: Text('${loc.t('order_tab_suppliers') ?? 'Поставщики'} — ${_departmentLabel(loc)}'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      floatingActionButton: !_loading && _error == null
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
              FilledButton.icon(
                icon: const Icon(Icons.shopping_cart),
                label: Text(loc.t('product_order') ?? 'Заказ продуктов'),
                onPressed: () => context.go('/product-order?department=${widget.department}'),
              ),
              const SizedBox(height: 12),
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
                                    CulinaryUnits.displayName(item.unit, loc.currentLanguageCode),
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
