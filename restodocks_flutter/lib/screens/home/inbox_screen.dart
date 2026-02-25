import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/services.dart';
import '../../models/models.dart';
import '../../models/inbox_document.dart';
import '../../services/inbox_service.dart';
import '../../widgets/app_bar_home_button.dart';

/// Входящие: Документы по отделам (Инвентаризация, Заказы продуктов, Подтверждения смен)
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late InboxService _inboxService;
  List<InboxDocument> _documents = [];
  bool _loading = true;
  String _selectedDepartment = 'all'; // all, kitchen, bar, hall, management

  @override
  void initState() {
    super.initState();
    // Инициализируем сервис позже, когда контекст будет доступен
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inboxService = InboxService(context.read<AccountManagerSupabase>().supabase);
      _loadDocuments();
    });
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
    return _inboxService.filterByDepartment(_documents, _selectedDepartment);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('inbox')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
            tooltip: 'Обновить',
          ),
          appBarHomeButton(context),
        ],
      ),
      body: Column(
        children: [
          // Фильтр по отделам
          _buildDepartmentFilter(loc),

          // Список документов
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDocuments.isEmpty
                    ? _buildEmptyState(loc)
                    : _buildDocumentsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentFilter(LocalizationService loc) {
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
      child: Row(
        children: [
          Text(
            '${loc.t('department') ?? 'Отдел'}:',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDepartmentChip('all', loc.t('all') ?? 'Все'),
                  _buildDepartmentChip('kitchen', loc.t('kitchen')),
                  _buildDepartmentChip('bar', loc.t('bar')),
                  _buildDepartmentChip('hall', loc.t('dining_room')),
                  _buildDepartmentChip('management', loc.t('management')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentChip(String department, String label) {
    final isSelected = _selectedDepartment == department;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _selectedDepartment = department);
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
            'Нет документов',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Документы появятся здесь после проведения инвентаризаций и получения заказов',
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
                docs.first.departmentName,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Документ "${document.title}" сохранен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
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
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');

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
        title: Text(document.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.description),
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
                } else {
                  onDownload(document);
                }
                break;
              case 'view':
                _viewDocument(context);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility),
                  SizedBox(width: 8),
                  Text('Просмотреть'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download),
                  SizedBox(width: 8),
                  Text('Сохранить'),
                ],
              ),
            ),
          ],
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(document.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Тип: ${document.typeName}'),
            Text('Отдел: ${document.departmentName}'),
            Text('Сотрудник: ${document.employeeName}'),
            Text('Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(document.createdAt)}'),
            const SizedBox(height: 8),
            Text(document.description),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
          if (document.fileUrl != null)
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onDownload(document);
              },
              child: const Text('Сохранить'),
            ),
        ],
      ),
    );
  }
}
