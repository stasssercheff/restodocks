import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/services.dart';
import '../../models/models.dart';
import '../../utils/number_format_utils.dart';
import '../../utils/translit_utils.dart';
import '../../models/inbox_document.dart';
import '../../services/inbox_service.dart';
import '../../widgets/app_bar_home_button.dart';

/// Входящие: документы (заказы, чеклисты, инвентаризации). Сообщения: диалоги с сотрудниками — отдельно.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.embedded = false, this.messagesOnly = false});

  final bool embedded;
  /// true — только диалоги (Сообщения), false — только документы (Входящие)
  final bool messagesOnly;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// Типы вкладок во входящих (для сотрудников)
enum _InboxTab { checklist, order, inventory, iikoInventory, messages }

/// Вкладки по подразделениям (для собственника)
enum _InboxDeptTab { kitchen, bar, hall }

/// Типы документов для 2-го яруса вкладок (собственник)
enum _InboxTypeTab { order, inventory, iikoInventory, messages }

class _InboxScreenState extends State<InboxScreen> {
  late InboxService _inboxService;
  List<InboxDocument> _documents = [];
  bool _loading = true;
  _InboxTab? _selectedTab;
  _InboxDeptTab? _selectedDeptTab;
  _InboxTypeTab? _selectedTypeTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inboxService = InboxService(context.read<AccountManagerSupabase>().supabase);
      _initDefaultTab();
      _loadDocuments();
    });
  }

  /// Выбираем первую доступную вкладку для текущего сотрудника
  void _initDefaultTab() {
    final employee = context.read<AccountManagerSupabase>().currentEmployee;
    if (employee == null) return;
    if (widget.messagesOnly) return;
    final tabs = _visibleTabs(employee);
    if (employee.hasRole('owner')) {
      setState(() {
        _selectedDeptTab = _InboxDeptTab.kitchen;
        _selectedTypeTab = _InboxTypeTab.order;
      });
    } else {
      if (tabs.isNotEmpty) {
        setState(() => _selectedTab = tabs.first);
      }
    }
  }

  /// Входящие: только документы (заказы, чеклисты, инвентаризации). Без диалогов.
  List<_InboxTab> _visibleTabs(Employee employee) {
    final isChef = employee.roles.contains('executive_chef');
    final isSousChef = employee.roles.contains('sous_chef');
    final isOwner = employee.roles.contains('owner');
    final hasDocs = employee.hasInboxDocuments;

    final tabs = <_InboxTab>[];
    if (hasDocs) {
      if (isChef || isSousChef) tabs.add(_InboxTab.checklist);
      if (isChef || isSousChef) tabs.add(_InboxTab.order);
      if (isChef || isOwner) tabs.add(_InboxTab.inventory);
      if ((isChef || isOwner) &&
          _documents.any((d) => d.type == DocumentType.iikoInventory)) {
        tabs.add(_InboxTab.iikoInventory);
      }
    }
    return tabs;
  }

  Future<void> _loadDocuments() async {
    final accountManager = context.read<AccountManagerSupabase>();
    final establishment = accountManager.establishment;

    if (establishment == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final currentEmployee = accountManager.currentEmployee;
      final documents = await _inboxService.getInboxDocuments(establishment.id, currentEmployee);
      if (mounted) {
        setState(() {
          _documents = documents;
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading inbox documents: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<InboxDocument> get _filteredDocuments {
    // Собственник: двухярусная фильтрация — подразделение + тип документа
    if (_selectedDeptTab != null && _selectedTypeTab != null) {
      if (_selectedTypeTab == _InboxTypeTab.messages) {
        return _documents.where((d) => d.type == DocumentType.checklistMissedDeadline).toList();
      }
      final dept = switch (_selectedDeptTab!) {
        _InboxDeptTab.kitchen => 'kitchen',
        _InboxDeptTab.bar => 'bar',
        _InboxDeptTab.hall => 'hall',
      };
      final docsByDept = _documents.where((d) => d.department == dept).toList();
      final docType = switch (_selectedTypeTab!) {
        _InboxTypeTab.order => DocumentType.productOrder,
        _InboxTypeTab.inventory => DocumentType.inventory,
        _InboxTypeTab.iikoInventory => DocumentType.iikoInventory,
        _InboxTypeTab.messages => DocumentType.checklistMissedDeadline,
      };
      return docsByDept.where((d) => d.type == docType).toList();
    }
    // Остальные: по типу документа
    switch (_selectedTab) {
      case _InboxTab.checklist:
        return _documents.where((d) => d.type == DocumentType.checklistSubmission).toList();
      case _InboxTab.order:
        return _documents.where((d) => d.type == DocumentType.productOrder).toList();
      case _InboxTab.inventory:
        return _documents.where((d) => d.type == DocumentType.inventory).toList();
      case _InboxTab.iikoInventory:
        return _documents.where((d) => d.type == DocumentType.iikoInventory).toList();
      case _InboxTab.messages:
        return _documents.where((d) => d.type == DocumentType.checklistMissedDeadline).toList();
      case null:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final isOwner = employee?.hasRole('owner') ?? false;
    final visibleTabs = employee != null ? _visibleTabs(employee) : <_InboxTab>[];

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: Text(widget.messagesOnly ? (loc.t('inbox_tab_messages') ?? 'Сообщения') : loc.t('inbox')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
            tooltip: loc.t('inbox_refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Фильтр документов (Кухня/Бар/Зал, Заказы/Инвентаризация) — только для Входящих, не для Сообщений
          if (!widget.messagesOnly) ...[
            if (isOwner) ...[
              _buildDeptFilter(loc),
              _buildTypeFilterForOwner(loc),
            ],
            if (!isOwner && visibleTabs.isNotEmpty) _buildTypeFilter(loc, visibleTabs),
          ],

          Expanded(
            child: widget.messagesOnly
                ? _buildMessagesContent(loc)
                : (_loading
                    ? const Center(child: CircularProgressIndicator())
                    : (isOwner ? (_selectedDeptTab == null || _selectedTypeTab == null) : _selectedTab == null)
                        ? _buildEmptyState(loc)
                        : _isMessagesTab(isOwner)
                            ? _buildMessagesContent(loc)
                            : _filteredDocuments.isEmpty
                                ? _buildEmptyState(loc)
                                : _buildDocumentsList()),
          ),
        ],
      ),
    );
  }

  Widget _buildDeptFilter(LocalizationService loc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildDeptChip(_InboxDeptTab.kitchen, loc.t('dept_kitchen') ?? 'Кухня', loc),
            const SizedBox(width: 8),
            _buildDeptChip(_InboxDeptTab.bar, loc.t('dept_bar') ?? 'Бар', loc),
            const SizedBox(width: 8),
            _buildDeptChip(_InboxDeptTab.hall, loc.t('dept_hall') ?? 'Зал', loc),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptChip(_InboxDeptTab tab, String label, LocalizationService loc) {
    final isSelected = _selectedDeptTab == tab;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedDeptTab = tab;
          if (tab == _InboxDeptTab.bar || tab == _InboxDeptTab.hall) {
            if (_selectedTypeTab == _InboxTypeTab.iikoInventory) {
              _selectedTypeTab = _InboxTypeTab.inventory;
            }
          }
        });
      },
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }

  Widget _buildTypeFilterForOwner(LocalizationService loc) {
    final isBarOrHall = _selectedDeptTab == _InboxDeptTab.bar || _selectedDeptTab == _InboxDeptTab.hall;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTypeChip(_InboxTypeTab.order, loc.t('inbox_tab_order') ?? 'Заказ продуктов', loc),
            const SizedBox(width: 8),
            _buildTypeChip(_InboxTypeTab.inventory, loc.t('inbox_tab_inventory') ?? 'Инвентаризация', loc),
            if (!isBarOrHall) ...[
              const SizedBox(width: 8),
              _buildTypeChip(_InboxTypeTab.iikoInventory, loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko', loc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(_InboxTypeTab tab, String label, LocalizationService loc) {
    final isSelected = _selectedTypeTab == tab;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _selectedTypeTab = tab);
      },
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }

  String _tabLabel(_InboxTab tab, LocalizationService loc) {
    switch (tab) {
      case _InboxTab.checklist:
        return loc.t('inbox_tab_checklist');
      case _InboxTab.order:
        return loc.t('inbox_tab_order');
      case _InboxTab.inventory:
        return loc.t('inbox_tab_inventory');
      case _InboxTab.iikoInventory:
        return loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko';
      case _InboxTab.messages:
        return loc.t('inbox_tab_messages') ?? 'Сообщения';
    }
  }

  Widget _buildTypeFilter(LocalizationService loc, List<_InboxTab> visibleTabs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: visibleTabs.map((tab) => _buildTabChip(tab, loc)).toList(),
        ),
      ),
    );
  }

  Widget _buildTabChip(_InboxTab tab, LocalizationService loc) {
    final isSelected = _selectedTab == tab;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(_tabLabel(tab, loc)),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedTab = tab);
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
        checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildEmptyState(LocalizationService loc) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            loc.t('inbox_empty_title'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            loc.t('inbox_empty_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  bool _isMessagesTab(bool isOwner) {
    if (isOwner) return _selectedTypeTab == _InboxTypeTab.messages;
    return _selectedTab == _InboxTab.messages;
  }

  Widget _buildMessagesContent(LocalizationService loc) {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    final missedDocs = _filteredDocuments;
    return _MessagesContent(
      currentEmployee: emp,
      establishmentId: est?.id ?? '',
      missedDocuments: missedDocs,
      onDownload: _downloadDocument,
      onRefresh: _loadDocuments,
    );
  }

  Widget _buildDocumentsList() {
    // Группируем документы по отделам
    final groupedDocuments = <String, List<InboxDocument>>{};
    for (final doc in _filteredDocuments) {
      final department = doc.department;
      groupedDocuments.putIfAbsent(department, () => []).add(doc);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedDocuments.length,
      itemBuilder: (context, index) {
        final department = groupedDocuments.keys.elementAt(index);
        final docs = groupedDocuments[department]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок отдела
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                docs.first.getDepartmentName(context.read<LocalizationService>()),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

            // Документы отдела
            ...docs.map((doc) => _DocumentTile(document: doc, onDownload: _downloadDocument)),

            if (index < groupedDocuments.length - 1) const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Future<void> _downloadDocument(InboxDocument document) async {
    try {
      await _inboxService.downloadDocument(document);
      if (mounted) {
          final loc = context.read<LocalizationService>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('inbox_doc_saved').replaceFirst('%s', document.title))),
          );
        }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('inbox_doc_save_error').replaceFirst('%s', '$e'))),
        );
      }
    }
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.onDownload,
  });

  final InboxDocument document;
  final Future<void> Function(InboxDocument) onDownload;

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');
    final grandTotal = document.type == DocumentType.productOrder
        ? (document.metadata?['grandTotal'] as num?)?.toDouble()
        : null;
    final currency = context.read<AccountManagerSupabase>().establishment?.defaultCurrency ?? 'VND';
    final totalStr = grandTotal != null ? NumberFormatUtils.formatSum(grandTotal!, currency) : null;
    final totalLabel = loc.t('order_list_grand_total') ?? 'Итого';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            document.icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(document.getLocalizedTitle(loc)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.description),
            if (totalStr != null) ...[
              const SizedBox(height: 2),
              Text(
                '$totalLabel: $totalStr',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '${document.employeeName} • ${dateFormat.format(document.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'download':
                if (document.type == DocumentType.inventory) {
                  context.push('/inbox/inventory/${document.id}');
                } else if (document.type == DocumentType.productOrder) {
                  context.push('/inbox/order/${document.id}');
                } else if (document.type == DocumentType.checklistSubmission) {
                  context.push('/inbox/checklist/${document.id}');
                } else if (document.type == DocumentType.iikoInventory) {
                  context.push('/inbox/iiko/${document.id}');
                } else if (document.type == DocumentType.checklistMissedDeadline) {
                  context.push('/checklists/${document.id}?view=1');
                } else {
                  onDownload(document);
                }
                break;
              case 'view':
                _viewDocument(context);
                break;
            }
          },
          itemBuilder: (context) {
            final loc = context.read<LocalizationService>();
            return [
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    const Icon(Icons.visibility),
                    const SizedBox(width: 8),
                    Text(loc.t('inbox_view')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    const Icon(Icons.download),
                    const SizedBox(width: 8),
                    Text(loc.t('inbox_save')),
                  ],
                ),
              ),
            ];
          },
        ),
        onTap: () => _viewDocument(context),
      ),
    );
  }

  void _viewDocument(BuildContext context) {
    if (document.type == DocumentType.inventory) {
      context.push('/inbox/inventory/${document.id}');
      return;
    }
    if (document.type == DocumentType.productOrder) {
      context.push('/inbox/order/${document.id}');
      return;
    }
    if (document.type == DocumentType.checklistSubmission) {
      context.push('/inbox/checklist/${document.id}');
      return;
    }
    if (document.type == DocumentType.iikoInventory) {
      context.push('/inbox/iiko/${document.id}');
      return;
    }
    if (document.type == DocumentType.checklistMissedDeadline) {
      context.push('/checklists/${document.id}?view=1');
      return;
    }
    final loc = context.read<LocalizationService>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(document.getLocalizedTitle(loc)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${loc.t('inbox_doc_type')}: ${document.getTypeName(loc)}'),
            Text('${loc.t('inbox_doc_dept')}: ${document.getDepartmentName(loc)}'),
            Text('${loc.t('inbox_doc_employee')}: ${document.employeeName}'),
            Text('${loc.t('inbox_doc_date')}: ${DateFormat('dd.MM.yyyy HH:mm').format(document.createdAt)}'),
            const SizedBox(height: 8),
            Text(document.description),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(loc.t('close')),
          ),
          if (document.fileUrl != null)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDownload(document);
              },
              child: Text(loc.t('inbox_save')),
            ),
        ],
      ),
    );
  }
}

class _MessagesContent extends StatefulWidget {
  const _MessagesContent({
    required this.currentEmployee,
    required this.establishmentId,
    required this.missedDocuments,
    required this.onDownload,
    required this.onRefresh,
  });

  final Employee? currentEmployee;
  final String establishmentId;
  final List<InboxDocument> missedDocuments;
  final Future<void> Function(InboxDocument) onDownload;
  final VoidCallback onRefresh;

  @override
  State<_MessagesContent> createState() => _MessagesContentState();
}

class _MessagesContentState extends State<_MessagesContent> {
  List<Employee> _employees = [];
  List<String> _chatPartnerIds = [];
  bool _loadingEmployees = true;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final emp = widget.currentEmployee;
    final estId = widget.establishmentId;
    if (emp == null || estId.isEmpty) {
      setState(() => _loadingEmployees = false);
      return;
    }
    try {
      final acc = context.read<AccountManagerSupabase>();
      final emps = await acc.getEmployeesForEstablishment(estId);
      final msgSvc = context.read<EmployeeMessageService>();
      final partnerIds = await msgSvc.getConversationPartnerIds(emp.id, estId);
      if (mounted) {
        setState(() {
          _employees = emps.where((e) => e.id != emp.id).toList();
          _chatPartnerIds = partnerIds;
          _loadingEmployees = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await _loadEmployees();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.t('chat_with_employees') ?? 'Диалоги с сотрудниками',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          if (_loadingEmployees)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else
            ..._employees.map((e) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        (e.fullName.isNotEmpty ? e.fullName[0] : '?').toUpperCase(),
                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                    ),
                    title: Text(
                      context.read<ScreenLayoutPreferenceService>().showNameTranslit
                          ? cyrillicToLatin(e.fullName)
                          : e.fullName,
                    ),
                    subtitle: Text(
                      e.roles.isNotEmpty
                          ? e.roles.map((r) => loc.roleDisplayName(r)).where((s) => s.isNotEmpty).join(', ')
                          : (e.department.isNotEmpty ? loc.departmentDisplayName(e.department) : ''),
                    ),
                    trailing: _chatPartnerIds.contains(e.id)
                        ? Icon(Icons.chat_bubble, size: 18, color: Theme.of(context).colorScheme.primary)
                        : const Icon(Icons.chat_bubble_outline, size: 18),
                    onTap: () => context.push('/inbox/chat/${e.id}'),
                  ),
                )),
          if (widget.missedDocuments.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                loc.t('inbox_msg_checklist_not_done') ?? 'Чеклист не выполнен',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...widget.missedDocuments.map((doc) => _DocumentTile(document: doc, onDownload: widget.onDownload)),
          ],
        ],
      ),
    );
  }
}
