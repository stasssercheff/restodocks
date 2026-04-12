import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checklist.dart';
import '../models/employee_message_system_link.dart';
import '../models/inbox_document.dart';
import '../models/order_list.dart';
import '../services/account_manager_supabase.dart';
import '../services/checklist_service_supabase.dart';
import '../services/inbox_service.dart';
import '../services/localization_service.dart';
import '../services/order_list_storage_service.dart';
import '../services/supabase_service.dart';
import '../utils/chat_system_link_paths.dart';

/// Модальное окно выбора ссылки на экран приложения. Возвращает одну ссылку за раз.
Future<EmployeeMessageSystemLink?> showChatSystemLinkPicker(BuildContext context) {
  return showModalBottomSheet<EmployeeMessageSystemLink>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => const _ChatSystemLinkPickerBody(),
  );
}

class _ChatSystemLinkPickerBody extends StatefulWidget {
  const _ChatSystemLinkPickerBody();

  @override
  State<_ChatSystemLinkPickerBody> createState() => _ChatSystemLinkPickerBodyState();
}

class _ChatSystemLinkPickerBodyState extends State<_ChatSystemLinkPickerBody> {
  late String _dept;
  final _ttkSearch = TextEditingController();
  List<InboxDocument>? _inboxDocs;
  bool _inboxLoading = true;
  String? _inboxError;
  List<Checklist>? _checklists;
  bool _checklistsLoading = false;
  List<OrderList>? _orderLists;
  bool _orderListsLoading = false;
  List<Map<String, dynamic>>? _ttkRows;
  bool _ttkLoading = false;

  @override
  void initState() {
    super.initState();
    final acc = context.read<AccountManagerSupabase>();
    final d = acc.currentEmployee?.department ?? 'kitchen';
    _dept = ['kitchen', 'bar', 'hall'].contains(d) ? d : 'kitchen';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInbox());
  }

  @override
  void dispose() {
    _ttkSearch.dispose();
    super.dispose();
  }

  Future<void> _loadInbox() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    final emp = acc.currentEmployee;
    if (est == null || emp == null) {
      setState(() {
        _inboxLoading = false;
        _inboxError = null;
        _inboxDocs = [];
      });
      return;
    }
    setState(() {
      _inboxLoading = true;
      _inboxError = null;
    });
    try {
      final svc = InboxService(SupabaseService());
      final docs = await svc.getInboxDocuments(est.id, emp);
      if (mounted) {
        setState(() {
          _inboxDocs = docs;
          _inboxLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inboxError = '$e';
          _inboxLoading = false;
        });
      }
    }
  }

  Future<void> _loadChecklists() async {
    if (_checklists != null) return;
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment?.id;
    if (est == null) return;
    setState(() => _checklistsLoading = true);
    try {
      final list = await ChecklistServiceSupabase().getChecklistsForEstablishment(
        est,
        department: _dept,
        currentEmployeeId: acc.currentEmployee?.id,
        applyAssignmentFilter: false,
      );
      if (mounted) {
        setState(() {
          _checklists = list;
          _checklistsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checklistsLoading = false);
    }
  }

  Future<void> _loadOrderLists() async {
    if (_orderLists != null) return;
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    setState(() => _orderListsLoading = true);
    try {
      final list = await loadOrderLists(est, department: _dept);
      if (mounted) setState(() {
        _orderLists = list;
        _orderListsLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _orderListsLoading = false);
      }
    }
  }

  Future<void> _loadTtk(String q) async {
    final est = context.read<AccountManagerSupabase>().establishment?.id;
    if (est == null) return;
    setState(() => _ttkLoading = true);
    try {
      final dynamic rows;
      if (q.trim().isEmpty) {
        rows = await Supabase.instance.client
            .from('tech_cards')
            .select('id, dish_name, department')
            .eq('establishment_id', est)
            .order('dish_name')
            .limit(40);
      } else {
        rows = await Supabase.instance.client
            .from('tech_cards')
            .select('id, dish_name, department')
            .eq('establishment_id', est)
            .ilike('dish_name', '%${q.trim()}%')
            .order('dish_name')
            .limit(50);
      }
      if (mounted) {
        setState(() {
          _ttkRows = List<Map<String, dynamic>>.from(rows as List);
          _ttkLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ttkLoading = false);
    }
  }

  void _pick(EmployeeMessageSystemLink link) {
    Navigator.of(context).pop(link);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final h = MediaQuery.sizeOf(context).height * 0.88;

    return SizedBox(
      height: h,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              loc.t('chat_attach_link_title') ?? 'Прикрепить ссылку',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(loc.departmentDisplayName('kitchen')),
                  selected: _dept == 'kitchen',
                  onSelected: (_) => setState(() {
                    _dept = 'kitchen';
                    _orderLists = null;
                    _checklists = null;
                  }),
                ),
                ChoiceChip(
                  label: Text(loc.departmentDisplayName('bar')),
                  selected: _dept == 'bar',
                  onSelected: (_) => setState(() {
                    _dept = 'bar';
                    _orderLists = null;
                    _checklists = null;
                  }),
                ),
                ChoiceChip(
                  label: Text(loc.departmentDisplayName('hall')),
                  selected: _dept == 'hall',
                  onSelected: (_) => setState(() {
                    _dept = 'hall';
                    _orderLists = null;
                    _checklists = null;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _sectionTitle(loc.t('chat_attach_shortcuts') ?? 'Быстрые ссылки'),
                ListTile(
                  leading: const Icon(Icons.restaurant_menu_outlined),
                  title: Text('${loc.t('menu') ?? 'Меню'} · ${loc.departmentDisplayName(_dept)}'),
                  onTap: () => _pick(EmployeeMessageSystemLink(
                    kind: 'menu',
                    path: '/menu/$_dept',
                    label: '${loc.t('menu') ?? 'Меню'} · ${loc.departmentDisplayName(_dept)}',
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text('${loc.t('schedule') ?? 'График'} · ${loc.departmentDisplayName(_dept)}'),
                  onTap: () => _pick(EmployeeMessageSystemLink(
                    kind: 'schedule',
                    path: '/schedule/$_dept',
                    label: '${loc.t('schedule') ?? 'График'} · ${loc.departmentDisplayName(_dept)}',
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(loc.t('chat_attach_schedule_all') ?? 'График · все подразделения'),
                  onTap: () => _pick(EmployeeMessageSystemLink(
                    kind: 'schedule_all',
                    path: '/schedule/all',
                    label: loc.t('chat_attach_schedule_all') ?? 'График · все',
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: Text(loc.t('order_tab_orders') ?? 'Заказы продуктов'),
                  subtitle: Text(loc.departmentDisplayName(_dept)),
                  onTap: () => _pick(EmployeeMessageSystemLink(
                    kind: 'product_order_hub',
                    path: '/product-order?department=$_dept',
                    label: '${loc.t('order_tab_orders') ?? 'Заказы'} · ${loc.departmentDisplayName(_dept)}',
                  )),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(loc.t('chat_attach_procurement') ?? 'Приёмка товара'),
                  subtitle: Text(loc.departmentDisplayName(_dept)),
                  onTap: () => _pick(EmployeeMessageSystemLink(
                    kind: 'procurement',
                    path: '/procurement-receipt?department=$_dept',
                    label: '${loc.t('chat_attach_procurement') ?? 'Приёмка'} · ${loc.departmentDisplayName(_dept)}',
                  )),
                ),
                _sectionTitle(loc.t('chat_attach_inbox') ?? 'Входящие'),
                if (_inboxLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_inboxError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_inboxError!, style: theme.textTheme.bodySmall),
                  )
                else if (_inboxDocs == null || _inboxDocs!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      loc.t('chat_attach_empty_inbox') ?? 'Нет документов',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  ..._inboxDocs!.take(40).map((d) {
                    final link = chatLinkFromInboxDocument(d, loc);
                    if (link == null) return const SizedBox.shrink();
                    return ListTile(
                      leading: Icon(d.icon, size: 22),
                      title: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _pick(link),
                    );
                  }),
                _sectionTitle(loc.t('chat_attach_ttk') ?? 'Техкарты'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _ttkSearch,
                    decoration: InputDecoration(
                      hintText: loc.t('search') ?? 'Поиск',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _loadTtk(_ttkSearch.text),
                      ),
                    ),
                    onSubmitted: _loadTtk,
                  ),
                ),
                const SizedBox(height: 8),
                if (_ttkLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_ttkRows == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextButton(
                      onPressed: () => _loadTtk(''),
                      child: Text(loc.t('chat_attach_load_ttk') ?? 'Показать техкарты'),
                    ),
                  )
                else if (_ttkRows!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(loc.t('chat_attach_empty') ?? 'Ничего не найдено'),
                  )
                else
                  ..._ttkRows!.map((row) {
                    final id = row['id']?.toString() ?? '';
                    final name = row['dish_name']?.toString() ?? '—';
                    return ListTile(
                      leading: const Icon(Icons.book_outlined),
                      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _pick(EmployeeMessageSystemLink(
                        kind: 'ttk',
                        path: '/tech-cards/$id',
                        label: name,
                      )),
                    );
                  }),
                _sectionTitle(loc.t('chat_attach_checklists') ?? 'Чеклисты'),
                if (!_checklistsLoading && _checklists == null)
                  TextButton(
                    onPressed: _loadChecklists,
                    child: Text(loc.t('chat_attach_load_lists') ?? 'Загрузить список'),
                  ),
                if (_checklistsLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_checklists != null)
                  ..._checklists!.take(50).map((c) {
                    return ListTile(
                      leading: const Icon(Icons.checklist_outlined),
                      title: Text(c.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _pick(EmployeeMessageSystemLink(
                        kind: 'checklist_tpl',
                        path: '/checklists/${c.id}?department=${Uri.encodeComponent(c.assignedDepartment)}',
                        label: c.name,
                      )),
                    );
                  }),
                _sectionTitle(loc.t('chat_attach_order_lists') ?? 'Списки заказов'),
                if (!_orderListsLoading && _orderLists == null)
                  TextButton(
                    onPressed: _loadOrderLists,
                    child: Text(loc.t('chat_attach_load_lists') ?? 'Загрузить списки'),
                  ),
                if (_orderListsLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_orderLists != null)
                  ..._orderLists!.take(50).map((l) {
                    return ListTile(
                      leading: const Icon(Icons.list_alt_outlined),
                      title: Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(l.supplierName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _pick(EmployeeMessageSystemLink(
                        kind: 'order_list',
                        path: '/product-order/${l.id}?department=${Uri.encodeComponent(l.department)}',
                        label: l.name,
                      )),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
