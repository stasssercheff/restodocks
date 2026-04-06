import 'package:flutter/material.dart';
import '../../utils/dev_log.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/services.dart';
import '../../models/models.dart';
import '../../utils/number_format_utils.dart';
import '../../utils/employee_display_utils.dart';
import '../../models/inbox_document.dart';
import '../../models/chat_room.dart';
import '../../services/inbox_service.dart';
import '../../services/group_chat_service.dart';
import '../../widgets/app_bar_home_button.dart';
import '../../widgets/scroll_to_top_app_bar_title.dart';

/// Входящие: документы (заказы, чеклисты, инвентаризации). Сообщения: диалоги с сотрудниками — отдельно.
class InboxScreen extends StatefulWidget {
  const InboxScreen(
      {super.key, this.embedded = false, this.messagesOnly = false});

  final bool embedded;

  /// true — только диалоги (Сообщения), false — только документы (Входящие)
  final bool messagesOnly;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

/// Типы вкладок во входящих (для сотрудников)
enum _InboxTab {
  checklist,
  order,
  inventory,
  iikoInventory,
  writeoff,
  messages,
  notifications
}

/// Вкладки по подразделениям (для собственника)
enum _InboxDeptTab { kitchen, bar, hall }

/// Типы документов для 2-го яруса вкладок (собственник)
enum _InboxTypeTab {
  checklist,
  order,
  inventory,
  iikoInventory,
  writeoff,
  messages,
  notifications
}

class _InboxScreenState extends State<InboxScreen> {
  late InboxService _inboxService;
  List<InboxDocument> _documents = [];
  List<EmployeeDeletionNotification> _deletionNotifications = [];
  List<EmployeeBirthdayChangeNotification> _birthdayChangeNotifications = [];
  List<({Employee emp, DateTime birthdayDate, int daysUntil})>
      _upcomingBirthdays = [];
  int _unreadMessagesCount = 0;
  bool _loading = true;
  _InboxTab? _selectedTab;
  _InboxDeptTab? _selectedDeptTab;
  _InboxTypeTab? _selectedTypeTab;
  final GlobalKey<_MessagesContentState> _messagesContentKey = GlobalKey();
  GoRouter? _goRouter;
  VoidCallback? _routeListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inboxService =
          InboxService(context.read<AccountManagerSupabase>().supabase);
      _initDefaultTab();
      _loadDocuments();
      final router = context.read<GoRouter>();
      _goRouter = router;
      void onRouteChange() {
        if (!mounted) return;
        final path = router.routerDelegate.currentConfiguration.fullPath;
        if (path == '/inbox' || path == '/notifications') _loadDocuments();
      }

      _routeListener = onRouteChange;
      router.routerDelegate.addListener(_routeListener!);
    });
  }

  @override
  void dispose() {
    if (_goRouter != null && _routeListener != null) {
      _goRouter!.routerDelegate.removeListener(_routeListener!);
    }
    super.dispose();
  }

  /// Выбираем первую доступную вкладку для текущего сотрудника
  void _initDefaultTab() {
    final employee = context.read<AccountManagerSupabase>().currentEmployee;
    if (employee == null) return;
    if (widget.messagesOnly) return;
    final tabs = _visibleTabs(employee);
    final isOwner = employee.hasRole('owner');
    final isManagement = employee.hasRole('executive_chef') ||
        employee.hasRole('sous_chef') ||
        employee.hasRole('bar_manager') ||
        employee.hasRole('floor_manager') ||
        employee.department == 'management';
    if (isOwner || isManagement) {
      final dept =
          (employee.department == 'bar' || employee.hasRole('bar_manager'))
              ? _InboxDeptTab.bar
              : (employee.department == 'dining_room' ||
                      employee.hasRole('floor_manager'))
                  ? _InboxDeptTab.hall
                  : _InboxDeptTab.kitchen;
      setState(() {
        _selectedDeptTab = dept;
        _selectedTypeTab = _InboxTypeTab.order; // Заказы по умолчанию
      });
    } else {
      if (tabs.isNotEmpty) {
        setState(() => _selectedTab = tabs.first);
      }
    }
  }

  bool _canSeeNotifications(Employee employee) {
    return employee.roles.any((r) =>
            r == 'owner' ||
            r == 'executive_chef' ||
            r == 'sous_chef' ||
            r == 'bar_manager' ||
            r == 'floor_manager' ||
            r == 'general_manager') ||
        employee.department == 'management';
  }

  /// Входящие по ролям: Заказы, Инвентаризация, iiko, Уведомления, Чеклисты. Сообщения — отдельная кнопка на главной.
  List<_InboxTab> _visibleTabs(Employee employee) {
    final isOwner = employee.hasRole('owner');
    final isManagement = employee.hasRole('executive_chef') ||
        employee.hasRole('sous_chef') ||
        employee.hasRole('bar_manager') ||
        employee.hasRole('floor_manager') ||
        employee.department == 'management';
    final hasDocs = employee.hasInboxDocuments;

    final tabs = <_InboxTab>[];
    if (hasDocs) {
      tabs.add(_InboxTab.order);
      if (isOwner || isManagement) {
        tabs.add(_InboxTab.inventory);
        tabs.add(_InboxTab.writeoff);
        if (employee.hasRole('executive_chef') ||
            employee.hasRole('owner') ||
            employee.hasRole('bar_manager')) {
          tabs.add(_InboxTab.iikoInventory);
        }
      }
    }
    if (_canSeeNotifications(employee)) tabs.add(_InboxTab.notifications);
    if (hasDocs &&
        (employee.hasRole('executive_chef') ||
            employee.hasRole('sous_chef') ||
            isOwner ||
            isManagement)) {
      tabs.add(_InboxTab.checklist); // Чеклисты — после остальных
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
      final loc = context.read<LocalizationService>();
      final layoutPrefs = context.read<ScreenLayoutPreferenceService>();
      final documents = await _inboxService.getInboxDocuments(
          establishment.id, currentEmployee);
      final useTranslit = loc.currentLanguageCode != 'ru' ||
          layoutPrefs.showNameTranslit;
      var enrichedDocs = documents;
      if (currentEmployee != null) {
        final emps = await accountManager
            .getEmployeesForEstablishment(establishment.id);
        final byId = {for (final e in emps) e.id: e};
        enrichedDocs = documents.map((d) {
          if (d.type != DocumentType.writeoff) return d;
          final e = byId[d.employeeId];
          if (e != null) {
            final line = employeeNameWithPositionLine(
              e,
              loc,
              establishment: accountManager.establishment,
              translit: useTranslit,
            );
            return d.copyWith(employeeName: line, description: line);
          }
          final raw = d.employeeName;
          if (raw.isEmpty || raw == '—') return d;
          final shown = loc.currentLanguageCode != 'ru'
              ? loc.displayPersonNameForLanguage(raw, loc.currentLanguageCode)
              : raw;
          return d.copyWith(employeeName: shown, description: shown);
        }).toList();
      }
      List<EmployeeDeletionNotification> notifications = [];
      List<EmployeeBirthdayChangeNotification> birthdayChanges = [];
      List<({Employee emp, DateTime birthdayDate, int daysUntil})> upcoming =
          [];
      if (currentEmployee != null && _canSeeNotifications(currentEmployee)) {
        notifications =
            await _inboxService.getDeletionNotifications(establishment.id);
        birthdayChanges = await _inboxService
            .getBirthdayChangeNotifications(establishment.id);
        final screenPref = context.read<ScreenLayoutPreferenceService>();
        final days = screenPref.birthdayNotifyDays;
        if (days > 0) {
          final employees = await accountManager
              .getEmployeesForEstablishment(establishment.id);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          for (final emp in employees) {
            final b = emp.birthday;
            if (b == null) continue;
            final thisYear = DateTime(now.year, b.month, b.day);
            if (thisYear == today) {
              upcoming.add((emp: emp, birthdayDate: thisYear, daysUntil: 0));
              continue;
            }
            for (var d = 1; d <= days; d++) {
              final target = today.add(Duration(days: d));
              if (thisYear.year == target.year &&
                  thisYear.month == target.month &&
                  thisYear.day == target.day) {
                upcoming.add((emp: emp, birthdayDate: thisYear, daysUntil: d));
                break;
              }
            }
          }
        }
      }
      int unreadMessages = 0;
      if (currentEmployee != null) {
        final unreadMap = await context
            .read<EmployeeMessageService>()
            .getUnreadCountPerPartner(currentEmployee.id, establishment.id);
        unreadMessages = unreadMap.values.fold(0, (a, b) => a + b);
      }
      await context.read<InboxViewedService>().getViewedIds(establishment.id);
      if (mounted) {
        setState(() {
          _documents = enrichedDocs;
          _deletionNotifications = notifications;
          _birthdayChangeNotifications = birthdayChanges;
          _upcomingBirthdays = upcoming;
          _unreadMessagesCount = unreadMessages;
          _loading = false;
        });
      }
    } catch (e) {
      devLog('Error loading inbox documents: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// ID непросмотренных документов/уведомлений текущей вкладки (для «Прочитать все»).
  List<String> _getUnviewedIdsForCurrentTab(bool isOwner) {
    final viewed = _viewedIds;
    if (isOwner) {
      if (_selectedTypeTab == _InboxTypeTab.messages)
        return []; // Чат — отдельная логика
      if (_selectedTypeTab == _InboxTypeTab.notifications) {
        final overdue = _overdueChecklistsForNotifications
            .where((d) => !viewed.contains(d.id))
            .map((d) => d.id)
            .toList();
        final del = _deletionNotifications
            .where((n) => !viewed.contains('del_${n.id}'))
            .map((n) => 'del_${n.id}')
            .toList();
        final bday = _birthdayChangeNotifications
            .where((n) => !viewed.contains('bday_${n.id}'))
            .map((n) => 'bday_${n.id}')
            .toList();
        return [...overdue, ...del, ...bday];
      }
      return _filteredDocuments
          .where((d) => !viewed.contains(d.id))
          .map((d) => d.id)
          .toList();
    }
    if (_selectedTab == _InboxTab.messages) return []; // Чат — отдельная логика
    if (_selectedTab == _InboxTab.notifications) {
      final overdue = _overdueChecklistsForNotifications
          .where((d) => !viewed.contains(d.id))
          .map((d) => d.id)
          .toList();
      final del = _deletionNotifications
          .where((n) => !viewed.contains('del_${n.id}'))
          .map((n) => 'del_${n.id}')
          .toList();
      final bday = _birthdayChangeNotifications
          .where((n) => !viewed.contains('bday_${n.id}'))
          .map((n) => 'bday_${n.id}')
          .toList();
      return [...overdue, ...del, ...bday];
    }
    return _filteredDocuments
        .where((d) => !viewed.contains(d.id))
        .map((d) => d.id)
        .toList();
  }

  Future<void> _markAllInCurrentTabAsViewed() async {
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    final isOwner = context
            .read<AccountManagerSupabase>()
            .currentEmployee
            ?.hasRole('owner') ??
        false;
    final ids = _getUnviewedIdsForCurrentTab(isOwner);
    if (ids.isEmpty) return;
    await context.read<InboxViewedService>().addViewedBatch(estId, ids);
  }

  /// Кнопка объединения на вкладках инвентаризации и списаний.
  bool _isInventoryMergeTabSelected(bool isOwner) {
    if (isOwner) {
      return _selectedTypeTab == _InboxTypeTab.inventory ||
          _selectedTypeTab == _InboxTypeTab.iikoInventory ||
          _selectedTypeTab == _InboxTypeTab.writeoff;
    }
    return _selectedTab == _InboxTab.inventory ||
        _selectedTab == _InboxTab.iikoInventory ||
        _selectedTab == _InboxTab.writeoff;
  }

  /// Бланки для объединения: только того типа, что выбрана на вкладке (инвентаризация стандарт или iiko).
  List<InboxDocument> get _mergeableDocumentsForCurrentTab {
    if (_isInventoryMergeTabSelected(context
            .read<AccountManagerSupabase>()
            .currentEmployee
            ?.hasRole('owner') ??
        false)) {
      return _filteredDocuments;
    }
    return [];
  }

  List<InboxDocument> get _filteredDocuments {
    // Собственник: двухярусная фильтрация — подразделение + тип документа
    if (_selectedDeptTab != null && _selectedTypeTab != null) {
      if (_selectedTypeTab == _InboxTypeTab.messages) {
        return _documents
            .where((d) => d.type == DocumentType.checklistMissedDeadline)
            .toList();
      }
      final dept = switch (_selectedDeptTab!) {
        _InboxDeptTab.kitchen => 'kitchen',
        _InboxDeptTab.bar => 'bar',
        _InboxDeptTab.hall => 'hall',
      };
      final docsByDept = _documents.where((d) => d.department == dept).toList();
      if (_selectedTypeTab == _InboxTypeTab.checklist) {
        return docsByDept
            .where((d) =>
                d.type == DocumentType.checklistSubmission ||
                d.type == DocumentType.checklistMissedDeadline)
            .toList();
      }
      if (_selectedTypeTab == _InboxTypeTab.notifications) {
        return []; // Notifications shown separately
      }
      final docType = switch (_selectedTypeTab!) {
        _InboxTypeTab.order => DocumentType.productOrder,
        _InboxTypeTab.inventory => DocumentType.inventory,
        _InboxTypeTab.iikoInventory => DocumentType.iikoInventory,
        _InboxTypeTab.writeoff => DocumentType.writeoff,
        _InboxTypeTab.messages => DocumentType.checklistMissedDeadline,
        _InboxTypeTab.checklist =>
          DocumentType.checklistSubmission, // unreachable, handled above
        _InboxTypeTab.notifications =>
          DocumentType.checklistMissedDeadline, // unreachable, handled above
      };
      return docsByDept.where((d) => d.type == docType).toList();
    }
    // Остальные: по типу документа
    switch (_selectedTab) {
      case _InboxTab.checklist:
        return _documents
            .where((d) =>
                d.type == DocumentType.checklistSubmission ||
                d.type == DocumentType.checklistMissedDeadline)
            .toList();
      case _InboxTab.order:
        return _documents
            .where((d) => d.type == DocumentType.productOrder)
            .toList();
      case _InboxTab.inventory:
        return _documents
            .where((d) => d.type == DocumentType.inventory)
            .toList();
      case _InboxTab.iikoInventory:
        return _documents
            .where((d) => d.type == DocumentType.iikoInventory)
            .toList();
      case _InboxTab.writeoff:
        return _documents
            .where((d) => d.type == DocumentType.writeoff)
            .toList();
      case _InboxTab.messages:
        return _documents
            .where((d) => d.type == DocumentType.checklistMissedDeadline)
            .toList();
      case _InboxTab.notifications:
        return []; // Notifications shown via _deletionNotifications
      case null:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<InboxViewedService>();
    final loc = context.watch<LocalizationService>();
    final accountManager = context.watch<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    final isOwner = employee?.hasRole('owner') ?? false;
    final isManagement = employee != null &&
        (employee.hasRole('executive_chef') ||
            employee.hasRole('sous_chef') ||
            employee.hasRole('bar_manager') ||
            employee.hasRole('floor_manager') ||
            employee.department == 'management');
    final visibleTabs =
        employee != null ? _visibleTabs(employee) : <_InboxTab>[];

    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : appBarBackButton(context),
        title: ScrollToTopAppBarTitle(
          child: Text(widget.messagesOnly
              ? (loc.t('inbox_tab_messages') ?? 'Сообщения')
              : loc.t('inbox')),
        ),
        actions: [
          if (!widget.messagesOnly) ...[
            if (!_isNotificationsTab(isOwner) &&
                _getUnviewedIdsForCurrentTab(isOwner).isNotEmpty)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 1.2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  await _markAllInCurrentTabAsViewed();
                },
                icon: const Icon(Icons.done_all, size: 20, color: Colors.white),
                label:
                    Text(loc.t('inbox_mark_all_viewed') ?? 'Просмотреть все'),
              ),
            if (_isInventoryMergeTabSelected(isOwner) &&
                _mergeableDocumentsForCurrentTab.isNotEmpty &&
                (employee?.hasRole('executive_chef') == true ||
                    employee?.hasRole('sous_chef') == true ||
                    employee?.hasRole('owner') == true ||
                    employee?.hasRole('bar_manager') == true ||
                    employee?.hasRole('floor_manager') == true))
              IconButton(
                icon: const Icon(Icons.merge),
                tooltip: loc.t('inventory_merge_title') ?? 'Объединить бланки',
                onPressed: () async {
                  final result = await context.push<bool>(
                    '/inbox/merge',
                    extra: _mergeableDocumentsForCurrentTab,
                  );
                  if (result == true && mounted) await _loadDocuments();
                },
              ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadDocuments();
              if (widget.messagesOnly)
                _messagesContentKey.currentState?.refresh();
            },
            tooltip: loc.t('inbox_refresh'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Фильтр документов (Кухня/Бар/Зал, Заказы/Инвентаризация) — только для Входящих, не для Сообщений
          if (!widget.messagesOnly) ...[
            if (isOwner || isManagement) ...[
              _buildDeptFilter(loc),
              _buildTypeFilterForOwner(loc),
            ],
            if (!isOwner && !isManagement && visibleTabs.isNotEmpty)
              _buildTypeFilter(loc, visibleTabs),
          ],

          Expanded(
            child: widget.messagesOnly
                ? _buildMessagesContent(loc)
                : (_loading
                    ? const Center(child: CircularProgressIndicator())
                    : _isNotificationsTab(isOwner)
                        ? _buildDeletionNotificationsList(loc)
                        : (isOwner
                                ? (_selectedDeptTab == null ||
                                    _selectedTypeTab == null)
                                : _selectedTab == null)
                            ? _buildEmptyState(loc)
                            : _isMessagesTab(isOwner)
                                ? _buildMessagesContent(loc)
                                : _filteredDocuments.isEmpty
                                    ? _buildEmptyState(loc)
                                    : _isChecklistsTab(isOwner)
                                        ? _buildChecklistsGroupedList(loc)
                                        : _isWriteoffTab(isOwner)
                                            ? _buildWriteoffsGroupedList(loc)
                                            : _buildDocumentsList()),
          ),
        ],
      ),
    );
  }

  Widget _buildDeptFilter(LocalizationService loc) {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final isOwner = emp?.hasRole('owner') == true;
    final allowed = <_InboxDeptTab>[];
    if (!isOwner) {
      final dept = emp?.department ?? 'kitchen';
      if (dept == 'bar' || emp?.hasRole('bar_manager') == true) {
        allowed.add(_InboxDeptTab.bar);
      } else if (dept == 'dining_room' ||
          dept == 'hall' ||
          emp?.hasRole('floor_manager') == true) {
        allowed.add(_InboxDeptTab.hall);
      } else {
        allowed.add(_InboxDeptTab.kitchen);
      }
    } else {
      allowed.addAll(
          [_InboxDeptTab.kitchen, _InboxDeptTab.bar, _InboxDeptTab.hall]);
    }

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
            for (var i = 0; i < allowed.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _buildDeptChip(
                allowed[i],
                switch (allowed[i]) {
                  _InboxDeptTab.kitchen => loc.t('dept_kitchen') ?? 'Кухня',
                  _InboxDeptTab.bar => loc.t('dept_bar') ?? 'Бар',
                  _InboxDeptTab.hall => loc.t('dept_hall') ?? 'Зал',
                },
                loc,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Set<String> get _viewedIds {
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    return context.read<InboxViewedService>().getViewedIdsSync(estId);
  }

  int _getCountForDeptTab(_InboxDeptTab dept) {
    final viewed = _viewedIds;
    final deptStr = switch (dept) {
      _InboxDeptTab.kitchen => 'kitchen',
      _InboxDeptTab.bar => 'bar',
      _InboxDeptTab.hall => 'hall',
    };
    return _documents
        .where((d) => d.department == deptStr && !viewed.contains(d.id))
        .length;
  }

  int _getCountForOwnerTypeTab(_InboxTypeTab tab) {
    if (_selectedDeptTab == null) return 0;
    final viewed = _viewedIds;
    final deptStr = switch (_selectedDeptTab!) {
      _InboxDeptTab.kitchen => 'kitchen',
      _InboxDeptTab.bar => 'bar',
      _InboxDeptTab.hall => 'hall',
    };
    final docsByDept = _documents
        .where((d) => d.department == deptStr && !viewed.contains(d.id));
    switch (tab) {
      case _InboxTypeTab.messages:
        return _unreadMessagesCount;
      case _InboxTypeTab.order:
        return docsByDept
            .where((d) => d.type == DocumentType.productOrder)
            .length;
      case _InboxTypeTab.inventory:
        return docsByDept.where((d) => d.type == DocumentType.inventory).length;
      case _InboxTypeTab.iikoInventory:
        return docsByDept
            .where((d) => d.type == DocumentType.iikoInventory)
            .length;
      case _InboxTypeTab.writeoff:
        return docsByDept.where((d) => d.type == DocumentType.writeoff).length;
      case _InboxTypeTab.notifications:
        final delUnviewed = _deletionNotifications
            .where((n) => !viewed.contains('del_${n.id}'))
            .length;
        return docsByDept
                .where((d) => d.type == DocumentType.checklistMissedDeadline)
                .length +
            delUnviewed;
      case _InboxTypeTab.checklist:
        return docsByDept
            .where((d) =>
                d.type == DocumentType.checklistSubmission ||
                d.type == DocumentType.checklistMissedDeadline)
            .length;
    }
  }

  int _getCountForTab(_InboxTab tab) {
    final viewed = _viewedIds;
    final docsUnviewed = _documents.where((d) => !viewed.contains(d.id));
    switch (tab) {
      case _InboxTab.messages:
        return _unreadMessagesCount;
      case _InboxTab.order:
        return docsUnviewed
            .where((d) => d.type == DocumentType.productOrder)
            .length;
      case _InboxTab.inventory:
        return docsUnviewed
            .where((d) => d.type == DocumentType.inventory)
            .length;
      case _InboxTab.iikoInventory:
        return docsUnviewed
            .where((d) => d.type == DocumentType.iikoInventory)
            .length;
      case _InboxTab.writeoff:
        return docsUnviewed
            .where((d) => d.type == DocumentType.writeoff)
            .length;
      case _InboxTab.notifications:
        final delUnviewed = _deletionNotifications
            .where((n) => !viewed.contains('del_${n.id}'))
            .length;
        final bdayUnviewed = _birthdayChangeNotifications
            .where((n) => !viewed.contains('bday_${n.id}'))
            .length;
        return docsUnviewed
                .where((d) => d.type == DocumentType.checklistMissedDeadline)
                .length +
            delUnviewed +
            bdayUnviewed;
      case _InboxTab.checklist:
        return docsUnviewed
            .where((d) =>
                d.type == DocumentType.checklistSubmission ||
                d.type == DocumentType.checklistMissedDeadline)
            .length;
    }
  }

  Widget _buildCountBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    final n = count > 99 ? '99+' : '$count';
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.onError.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      alignment: Alignment.center,
      child: Text(
        n,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Подписи вкладок входящих: брендовый красный; выбранная — onPrimaryContainer; «всё просмотрено» — приглушённый primary.
  Color _inboxChipLabelColor(
    BuildContext context, {
    required bool isSelected,
    required bool allViewed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (isSelected) return scheme.onPrimaryContainer;
    if (allViewed) return scheme.primary.withValues(alpha: 0.5);
    return scheme.primary;
  }

  Widget _buildDeptChip(
      _InboxDeptTab tab, String label, LocalizationService loc) {
    final isSelected = _selectedDeptTab == tab;
    final count = _getCountForDeptTab(tab);
    final allViewed = count == 0;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _inboxChipLabelColor(context,
                  isSelected: isSelected, allViewed: allViewed),
            ),
          ),
          _buildCountBadge(count),
        ],
      ),
      selected: isSelected,
      showCheckmark: false,
      backgroundColor: allViewed && !isSelected
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Theme.of(context).colorScheme.surface,
      onSelected: (_) {
        setState(() {
          _selectedDeptTab = tab;
          // Инвентаризация iiko есть только у кухни и бара; при переходе в зал сбрасываем на обычную инвентаризацию
          if (tab == _InboxDeptTab.hall &&
              _selectedTypeTab == _InboxTypeTab.iikoInventory) {
            _selectedTypeTab = _InboxTypeTab.inventory;
          }
        });
      },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
    );
  }

  /// Типы вкладок для собственника: Заказы, Инвентаризация, iiko (кухня и бар), Уведомления, Чеклисты.
  Widget _buildTypeFilterForOwner(LocalizationService loc) {
    final isHall = _selectedDeptTab == _InboxDeptTab.hall;
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
            _buildTypeChip(
                _InboxTypeTab.order, loc.t('inbox_tab_order') ?? 'Заказы', loc),
            const SizedBox(width: 8),
            _buildTypeChip(_InboxTypeTab.inventory,
                loc.t('inbox_tab_inventory') ?? 'Инвентаризация', loc),
            _buildTypeChip(
                _InboxTypeTab.writeoff, loc.t('writeoffs') ?? 'Списания', loc),
            if (!isHall) ...[
              const SizedBox(width: 8),
              _buildTypeChip(_InboxTypeTab.iikoInventory,
                  loc.t('iiko_inventory_title') ?? 'Инвентаризация iiko', loc),
            ],
            const SizedBox(width: 8),
            _buildTypeChip(_InboxTypeTab.notifications,
                loc.t('inbox_tab_notifications') ?? 'Уведомления', loc),
            const SizedBox(width: 8),
            _buildTypeChip(_InboxTypeTab.checklist,
                loc.t('inbox_tab_checklist') ?? 'Чеклисты', loc),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(
      _InboxTypeTab tab, String label, LocalizationService loc) {
    final isSelected = _selectedTypeTab == tab;
    final count = _getCountForOwnerTypeTab(tab);
    final allViewed = count == 0;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: _inboxChipLabelColor(context,
                  isSelected: isSelected, allViewed: allViewed),
            ),
          ),
          _buildCountBadge(count),
        ],
      ),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) {
        setState(() => _selectedTypeTab = tab);
      },
      backgroundColor: allViewed && !isSelected
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : Theme.of(context).colorScheme.surface,
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
      case _InboxTab.writeoff:
        return loc.t('writeoffs') ?? 'Списания';
      case _InboxTab.messages:
        return loc.t('inbox_tab_messages') ?? 'Сообщения';
      case _InboxTab.notifications:
        return loc.t('inbox_tab_notifications') ?? 'Уведомления';
    }
  }

  Widget _buildTypeFilter(
      LocalizationService loc, List<_InboxTab> visibleTabs) {
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
    final count = _getCountForTab(tab);
    final allViewed = count == 0;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tabLabel(tab, loc),
              style: TextStyle(
                color: _inboxChipLabelColor(context,
                    isSelected: isSelected, allViewed: allViewed),
              ),
            ),
            _buildCountBadge(count),
          ],
        ),
        selected: isSelected,
        showCheckmark: false,
        onSelected: (selected) {
          setState(() => _selectedTab = tab);
        },
        backgroundColor: allViewed && !isSelected
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : Theme.of(context).colorScheme.surface,
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

  bool _isNotificationsTab(bool isOwner) {
    if (isOwner) return _selectedTypeTab == _InboxTypeTab.notifications;
    return _selectedTab == _InboxTab.notifications;
  }

  List<InboxDocument> get _overdueChecklistsForNotifications {
    if (context
                .read<AccountManagerSupabase>()
                .currentEmployee
                ?.hasRole('owner') ==
            true &&
        _selectedDeptTab != null) {
      final deptStr = switch (_selectedDeptTab!) {
        _InboxDeptTab.kitchen => 'kitchen',
        _InboxDeptTab.bar => 'bar',
        _InboxDeptTab.hall => 'hall',
      };
      return _documents
          .where((d) =>
              d.type == DocumentType.checklistMissedDeadline &&
              d.department == deptStr)
          .toList();
    }
    return _documents
        .where((d) => d.type == DocumentType.checklistMissedDeadline)
        .toList();
  }

  Widget _buildDeletionNotificationsList(LocalizationService loc) {
    final overdueChecklists = _overdueChecklistsForNotifications;
    final hasDeletions = _deletionNotifications.isNotEmpty;
    final hasBirthdayChanges = _birthdayChangeNotifications.isNotEmpty;
    final hasUpcoming = _upcomingBirthdays.isNotEmpty;
    final hasOverdue = overdueChecklists.isNotEmpty;

    if (!hasDeletions && !hasOverdue && !hasBirthdayChanges && !hasUpcoming) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              loc.t('inbox_notifications_empty') ?? 'Нет уведомлений',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasOverdue) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.t('checklist_overdue') ?? 'Просроченные чеклисты',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
          ...overdueChecklists.map((doc) => _DocumentTile(
                document: doc,
                onDownload: _downloadDocument,
              )),
          const SizedBox(height: 16),
        ],
        if (hasUpcoming) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.t('birthday_upcoming') ?? 'Ближайшие дни рождения',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ..._upcomingBirthdays.map((e) {
            final dateStr = DateFormat('dd.MM').format(e.birthdayDate);
            final daysText = e.daysUntil == 0
                ? (loc.t('birthday_today') ?? 'Сегодня')
                : (loc.t('birthday_in_days') ?? 'Через %s дн.')
                    .replaceAll('%s', '${e.daysUntil}');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.cake,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(
                  '${e.emp.fullName} — $dateStr',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(daysText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        if (hasBirthdayChanges) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              loc.t('birthday_changed') ?? 'Изменение дня рождения',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          ..._birthdayChangeNotifications.map((n) {
            final estId =
                context.read<AccountManagerSupabase>().establishment?.id;
            if (estId != null)
              context
                  .read<InboxViewedService>()
                  .addViewed(estId, 'bday_${n.id}');
            final dateStr = DateFormat('dd.MM.yyyy').format(n.newBirthday);
            final prevStr = n.previousBirthday != null
                ? DateFormat('dd.MM.yyyy').format(n.previousBirthday!)
                : (loc.t('not_specified') ?? 'не указано');
            final createdStr =
                DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal());
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(Icons.edit_calendar,
                      color:
                          Theme.of(context).colorScheme.onSecondaryContainer),
                ),
                title: Text(
                  '${n.employeeName}: $dateStr',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '${loc.t('birthday_was') ?? 'Было'}: $prevStr • $createdStr',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        if (hasDeletions) ...[
          ..._deletionNotifications.map((n) {
            final estId =
                context.read<AccountManagerSupabase>().establishment?.id;
            context.read<InboxViewedService>().addViewed(estId, 'del_${n.id}');
            final dateStr =
                DateFormat('dd.MM.yyyy HH:mm').format(n.createdAt.toLocal());
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(Icons.person_remove,
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                title: Text(
                  n.isSelfDeletion
                      ? loc.t('employee_deleted_self_inbox').replaceAll('%s', n.deletedEmployeeName)
                      : '${n.deletedEmployeeName} ${loc.t('employee_deleted_by')} ${n.deletedByName})',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  (n.deletedEmployeeEmail != null
                          ? '${n.deletedEmployeeEmail} • '
                          : '') +
                      dateStr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  bool _isChecklistsTab(bool isOwner) {
    if (isOwner) return _selectedTypeTab == _InboxTypeTab.checklist;
    return _selectedTab == _InboxTab.checklist;
  }

  bool _isWriteoffTab(bool isOwner) {
    if (isOwner) return _selectedTypeTab == _InboxTypeTab.writeoff;
    return _selectedTab == _InboxTab.writeoff;
  }

  /// Списания с группировкой по датам
  Widget _buildWriteoffsGroupedList(LocalizationService loc) {
    return _buildWriteoffsGroupedListContent(loc);
  }

  Widget _buildWriteoffsGroupedListContent(LocalizationService loc) {
    final docs = _filteredDocuments;
    final fmtDate = (DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final grouped = <String, List<InboxDocument>>{};
    for (final doc in docs) {
      final dateKey = fmtDate(doc.createdAt);
      grouped.putIfAbsent(dateKey, () => []).add(doc);
    }
    final dateKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: dateKeys.expand((dateKey) {
        final dateDocs = List<InboxDocument>.from(grouped[dateKey]!)
          ..sort((a, b) => (a.employeeName)
              .toLowerCase()
              .compareTo((b.employeeName).toLowerCase()));
        return [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              dateKey,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...dateDocs.map((doc) =>
              _DocumentTile(document: doc, onDownload: _downloadDocument)),
        ];
      }).toList(),
    );
  }

  /// Чеклисты с группировкой: Просроченные, затем по цеху → дате → сотруднику
  Widget _buildChecklistsGroupedList(LocalizationService loc) {
    return _buildChecklistsGroupedListContent(loc);
  }

  Widget _buildChecklistsGroupedListContent(LocalizationService loc) {
    final docs = _filteredDocuments;
    final overdue = docs
        .where((d) => d.type == DocumentType.checklistMissedDeadline)
        .toList();
    final submitted =
        docs.where((d) => d.type == DocumentType.checklistSubmission).toList();

    final lang = loc.currentLanguageCode;
    final noSection = loc.t('checklist_no_section') ?? 'Без цеха';
    final overdueLabel = loc.t('checklist_overdue') ?? 'Просроченные';
    final fmtDate = (DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    // Группировка submitted: section -> date -> employee
    final grouped = <String, Map<String, Map<String, List<InboxDocument>>>>{};
    for (final doc in submitted) {
      final sectionCode =
          doc.metadata?['submission']?['section']?.toString().trim() ?? '';
      final sectionLabel = sectionCode.isEmpty
          ? noSection
          : (KitchenSection.fromCode(sectionCode)?.getLocalizedName(lang) ??
              doc.getDepartmentName(loc));
      final dateKey = fmtDate(doc.createdAt);
      final empName = doc.employeeName.isNotEmpty
          ? doc.employeeName
          : (loc.t('checklist_all_employees') ?? 'Всем');

      grouped.putIfAbsent(sectionLabel, () => {});
      grouped[sectionLabel]!.putIfAbsent(dateKey, () => {});
      grouped[sectionLabel]![dateKey]!.putIfAbsent(empName, () => []);
      grouped[sectionLabel]![dateKey]![empName]!.add(doc);
    }

    final sectionOrder = grouped.keys.toList()
      ..sort((a, b) {
        if (a == noSection) return 1;
        if (b == noSection) return -1;
        return a.compareTo(b);
      });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (overdue.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              overdueLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
          ...overdue.map((doc) =>
              _DocumentTile(document: doc, onDownload: _downloadDocument)),
          const SizedBox(height: 24),
        ],
        ...sectionOrder.expand((sec) {
          final dates = grouped[sec]!.keys.toList()
            ..sort((a, b) => b.compareTo(a));
          return [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                sec,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...dates.expand((dateKey) {
              final emps = grouped[sec]![dateKey]!.keys.toList();
              return emps.expand((emp) {
                final list = grouped[sec]![dateKey]![emp]!;
                return [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      '$dateKey • $emp',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  ...list.map((doc) => _DocumentTile(
                      document: doc, onDownload: _downloadDocument)),
                ];
              });
            }),
            const SizedBox(height: 16),
          ];
        }),
      ],
    );
  }

  Widget _buildMessagesContent(LocalizationService loc) {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    final missedDocs = _filteredDocuments;
    final restrictToChefOnly =
        emp != null && !emp.hasRole('owner') && !emp.effectiveDataAccess;
    return _MessagesContent(
      key: _messagesContentKey,
      currentEmployee: emp,
      establishmentId: est?.id ?? '',
      restrictToChefOnly: restrictToChefOnly,
      missedDocuments: missedDocs,
      onDownload: _downloadDocument,
      onRefresh: () async {
        await _loadDocuments();
        _messagesContentKey.currentState?.refresh();
      },
    );
  }

  Widget _buildDocumentsList() {
    final loc = context.read<LocalizationService>();
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
                docs.first.getDepartmentName(loc),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),

            // Документы отдела
            ...docs.map((doc) =>
                _DocumentTile(document: doc, onDownload: _downloadDocument)),

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
        AppToastService.show(
            loc.t('inbox_doc_saved').replaceFirst('%s', document.title),
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        final loc = context.read<LocalizationService>();
        AppToastService.show(
            loc.t('inbox_doc_save_error').replaceFirst('%s', '$e'),
            duration: const Duration(seconds: 4));
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
    context.watch<InboxViewedService>();
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    final isViewed = context
        .read<InboxViewedService>()
        .getViewedIdsSync(estId)
        .contains(document.id);
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'ru');
    final grandTotal = document.type == DocumentType.productOrder
        ? (document.metadata?['grandTotal'] as num?)?.toDouble()
        : null;
    final currency =
        context.read<AccountManagerSupabase>().establishment?.defaultCurrency ??
            'VND';
    final totalStr = grandTotal != null
        ? NumberFormatUtils.formatSum(grandTotal!, currency)
        : null;
    final totalLabel = loc.t('order_list_grand_total') ?? 'Итого';
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isViewed
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isViewed
              ? theme.colorScheme.outlineVariant
              : theme.colorScheme.primary,
          width: isViewed ? 1 : 2,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isViewed
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          child: Icon(
            document.icon,
            color: isViewed
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          document.getLocalizedTitle(loc),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: isViewed ? FontWeight.normal : FontWeight.w600,
          ),
        ),
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
                _markDocumentViewed(context);
                if (document.type == DocumentType.inventory) {
                  context.push('/inbox/inventory/${document.id}');
                } else if (document.type == DocumentType.writeoff) {
                  context.push('/inbox/writeoff/${document.id}');
                } else if (document.type == DocumentType.productOrder) {
                  context.push('/inbox/order/${document.id}');
                } else if (document.type == DocumentType.checklistSubmission) {
                  context.push('/inbox/checklist/${document.id}');
                } else if (document.type == DocumentType.iikoInventory) {
                  context.push('/inbox/iiko/${document.id}');
                } else if (document.type ==
                    DocumentType.checklistMissedDeadline) {
                  context.push('/checklists/${document.id}?view=1');
                } else if (document.type ==
                    DocumentType.techCardChangeRequest) {
                  context.push('/inbox/ttk-change/${document.id}');
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

  void _markDocumentViewed(BuildContext context) {
    final estId = context.read<AccountManagerSupabase>().establishment?.id;
    context.read<InboxViewedService>().addViewed(estId, document.id);
  }

  void _viewDocument(BuildContext context) {
    _markDocumentViewed(context);
    if (document.type == DocumentType.inventory) {
      context.push('/inbox/inventory/${document.id}');
      return;
    }
    if (document.type == DocumentType.writeoff) {
      context.push('/inbox/writeoff/${document.id}');
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
    if (document.type == DocumentType.techCardChangeRequest) {
      context.push('/inbox/ttk-change/${document.id}');
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
            Text(
                '${loc.t('inbox_doc_dept')}: ${document.getDepartmentName(loc)}'),
            Text('${loc.t('inbox_doc_employee')}: ${document.employeeName}'),
            Text(
                '${loc.t('inbox_doc_date')}: ${DateFormat('dd.MM.yyyy HH:mm').format(document.createdAt)}'),
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
    super.key,
    required this.currentEmployee,
    required this.establishmentId,
    required this.restrictToChefOnly,
    required this.missedDocuments,
    required this.onDownload,
    required this.onRefresh,
  });

  final Employee? currentEmployee;
  final String establishmentId;

  /// true — показывать только диалоги с шефом/су-шефом (для сотрудников без доступа к данным)
  final bool restrictToChefOnly;
  final List<InboxDocument> missedDocuments;
  final Future<void> Function(InboxDocument) onDownload;
  final Future<void> Function() onRefresh;

  @override
  State<_MessagesContent> createState() => _MessagesContentState();
}

class _MessagesContentState extends State<_MessagesContent> {
  List<Employee> _employees = [];
  List<String> _chatPartnerIds = [];
  Map<String, int> _unreadCounts = {};
  List<ChatRoom> _groupRooms = [];
  bool _loadingEmployees = true;
  RealtimeChannel? _realtimeChannel;
  RealtimeChannel? _groupRealtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _subscribeRealtime();
  }

  /// Обновить список диалогов (вызывается по кнопке «Обновить» в AppBar).
  Future<void> refresh() => _loadEmployees();

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _groupRealtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    final emp = widget.currentEmployee;
    if (emp == null) return;
    final myId = emp.id;
    final client = Supabase.instance.client;
    _realtimeChannel = client
        .channel('inbox_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'employee_direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_employee_id',
            value: myId,
          ),
          callback: (_) {
            if (mounted) _loadEmployees();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'employee_direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_employee_id',
            value: myId,
          ),
          callback: (_) {
            if (mounted) _loadEmployees();
          },
        );
    _realtimeChannel!.subscribe();
    _groupRealtimeChannel =
        client.channel('inbox_group_messages').onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_room_messages',
              callback: (_) {
                if (mounted) _loadEmployees();
              },
            );
    _groupRealtimeChannel!.subscribe();
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
      final msgSvc = context.read<EmployeeMessageService>();
      final groupSvc = context.read<GroupChatService>();
      var emps = await acc.getEmployeesForEstablishment(estId);
      emps = emps.where((e) => e.id != emp.id).toList();
      if (widget.restrictToChefOnly) {
        emps = emps
            .where((e) =>
                e.roles.contains('executive_chef') ||
                e.roles.contains('sous_chef'))
            .toList();
      }
      var partnerIds = await msgSvc.getConversationPartnerIds(emp.id, estId);
      if (widget.restrictToChefOnly && emps.isNotEmpty) {
        final chefIds = emps.map((e) => e.id).toSet();
        partnerIds = partnerIds.where((id) => chefIds.contains(id)).toList();
      }
      final unread = await msgSvc.getUnreadCountPerPartner(emp.id, estId);
      final rooms = await groupSvc.getRoomsForEmployee(emp.id, estId);
      if (mounted) {
        setState(() {
          _employees = emps;
          _chatPartnerIds = partnerIds;
          _unreadCounts = unread;
          _groupRooms = rooms;
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
    final showTranslit =
        context.watch<ScreenLayoutPreferenceService>().showNameTranslit;
    final establishment = context.watch<AccountManagerSupabase>().establishment;

    return RefreshIndicator(
      onRefresh: () async {
        await widget.onRefresh();
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
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()))
          else
            ..._employees.map((e) {
              final raw = employeeFullNameRaw(e);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      (raw.isNotEmpty ? raw[0] : '?').toUpperCase(),
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                  title: Text(
                    employeeDisplayName(e,
                        translit: showTranslit ||
                            loc.currentLanguageCode != 'ru'),
                  ),
                  subtitle: Text(
                    [
                      employeePositionLine(e, loc,
                          establishment: establishment),
                      if (e.department.isNotEmpty)
                        loc.departmentDisplayName(e.department),
                    ].where((s) => s.isNotEmpty && s != '—').join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((_unreadCounts[e.id] ?? 0) > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_unreadCounts[e.id]}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onError,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      _chatPartnerIds.contains(e.id)
                          ? Icon(Icons.chat_bubble,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.chat_bubble_outline, size: 18),
                    ],
                  ),
                  onTap: () => context.push('/inbox/chat/${e.id}'),
                ),
              );
            }),
          if (!_loadingEmployees) ...[
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.t('group_chat_title') ?? 'Групповые чаты',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push('/inbox/group/new'),
                    icon: const Icon(Icons.group_add, size: 20),
                    label:
                        Text(loc.t('group_chat_new') ?? 'Новый групповой чат'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            ..._groupRooms.map((room) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(Icons.group,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                    ),
                    title: Text(
                      room.displayName.isEmpty
                          ? (loc.t('group_chat_default_name') ??
                              'Групповой чат')
                          : room.displayName,
                    ),
                    trailing: const Icon(Icons.chat_bubble, size: 18),
                    onTap: () => context.push('/inbox/group/${room.id}'),
                  ),
                )),
          ],
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
            ...widget.missedDocuments.map((doc) =>
                _DocumentTile(document: doc, onDownload: widget.onDownload)),
          ],
        ],
      ),
    );
  }
}
