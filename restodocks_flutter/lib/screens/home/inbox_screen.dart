import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/services.dart';
import '../../models/models.dart';
import '../../models/inbox_document.dart';
import '../../services/inbox_service.dart';
import '../../widgets/app_bar_home_button.dart';

/// Входящие: Документы по типам (Чеклисты, Заказы, Инвентаризация)
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// Типы вкладок во входящих
enum _InboxTab { checklist, order, inventory }

class _InboxScreenState extends State<InboxScreen> {
  late InboxService _inboxService;
  List<InboxDocument> _documents = [];
  bool _loading = true;
  _InboxTab? _selectedTab;

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
    final tabs = _visibleTabs(employee);
    if (tabs.isNotEmpty) {
      setState(() => _selectedTab = tabs.first);
    }
  }

  /// Список вкладок, доступных данному сотруднику
  List<_InboxTab> _visibleTabs(Employee employee) {
    final isChef = employee.roles.contains('executive_chef');
    final isSousChef = employee.roles.contains('sous_chef');
    final isOwner = employee.roles.contains('owner');

    final tabs = <_InboxTab>[];
    // Чеклист — шеф и су-шеф
    if (isChef || isSousChef) tabs.add(_InboxTab.checklist);
    // Заказы — шеф и су-шеф
    if (isChef || isSousChef) tabs.add(_InboxTab.order);
    // Инвентаризация — шеф и собственник
    if (isChef || isOwner) tabs.add(_InboxTab.inventory);
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
    switch (_selectedTab) {
      case _InboxTab.checklist:
        return _documents.where((d) => d.type == DocumentType.checklistSubmission).toList();
      case _InboxTab.order:
        return _documents.where((d) => d.type == DocumentType.productOrder).toList();
      case _InboxTab.inventory:
        return _documents.where((d) => d.type == DocumentType.inventory).toList();
      case null:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final visibleTabs = employee != null ? _visibleTabs(employee) : <_InboxTab>[];

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: Text(loc.t('inbox')),
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
          // Фильтр по типу документа
          if (visibleTabs.isNotEmpty) _buildTypeFilter(loc, visibleTabs),

          // Список документов
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _selectedTab == null
                    ? _buildEmptyState(loc)
                    : _filteredDocuments.isEmpty
                        ? _buildEmptyState(loc)
                        : _buildDocumentsList(),
          ),
        ],
      ),
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
    final totalStr = grandTotal != null ? NumberFormat('#,##0.00', 'ru').format(grandTotal) : null;
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
