import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../models/models.dart';
import '../services/app_toast_service.dart';
import '../services/services.dart';

const _keyBirthdayNotifyLastShown = 'restodocks_birthday_notify_last_shown';

/// Слушает новые данные во Входящих и Сообщениях. Показывает уведомление (плашка/модал) по настройкам.
/// Также по выбранному времени показывает уведомление о ближайших днях рождения (если пользователь в приложении).
class InboxNotificationListener extends StatefulWidget {
  const InboxNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<InboxNotificationListener> createState() => _InboxNotificationListenerState();
}

class _InboxNotificationListenerState extends State<InboxNotificationListener> {
  final List<RealtimeChannel> _channels = [];
  Timer? _birthdayNotifyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _subscribe();
    });
  }

  @override
  void dispose() {
    _birthdayNotifyTimer?.cancel();
    _birthdayNotifyTimer = null;
    for (final ch in _channels) {
      ch.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _subscribe() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;

    final prefs = context.read<NotificationPreferencesService>();
    await prefs.load(emp.id);
    if (!mounted) return;
    final client = Supabase.instance.client;

    // 1. Сообщения
    if (prefs.shouldNotifyFor('messages')) {
      final ch = client.channel('inbox_notif_messages_${emp.id}').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'employee_direct_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_employee_id',
          value: emp.id,
        ),
        callback: (payload) => _onNewMessage(payload, emp.id),
      );
      ch.subscribe();
      _channels.add(ch);
    }

    // 2. Заказы продуктов
    if (prefs.shouldNotifyFor('orders') && _hasInboxOrders(emp)) {
      final ch = client.channel('inbox_notif_orders_${emp.id}').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'order_documents',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'establishment_id',
          value: est.id,
        ),
        callback: (p) => _onNewOrderDocument(p),
      );
      ch.subscribe();
      _channels.add(ch);
    }

    // 3. Инвентаризация
    if (prefs.shouldNotifyFor('inventory') && _hasInboxInventory(emp)) {
      final ch = client.channel('inbox_notif_inv_${emp.id}').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'inventory_documents',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'establishment_id',
          value: est.id,
        ),
        callback: (p) => _onNewInventoryDocument(p),
      );
      ch.subscribe();
      _channels.add(ch);
    }

    // 4. Чеклисты
    if (_hasInboxChecklists(emp)) {
      final ch = client.channel('inbox_notif_checklists_${emp.id}').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'checklist_submissions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'establishment_id',
          value: est.id,
        ),
        callback: (p) => _onNewChecklistSubmission(p, emp, prefs),
      );
      ch.subscribe();
      _channels.add(ch);
    }

    // 5. Уведомления об удалении (для руководителей)
    if (prefs.shouldNotifyFor('notifications') && _canSeeDeletionNotifications(emp)) {
      final ch = client.channel('inbox_notif_deletion_${emp.id}').onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'employee_deletion_notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'establishment_id',
          value: est.id,
        ),
        callback: (p) => _onNewDeletionNotification(p),
      );
      ch.subscribe();
      _channels.add(ch);
    }

    // 6. Уведомление о днях рождения в выбранное время (если пользователь в приложении)
    if (_canSeeDeletionNotifications(emp)) {
      _scheduleBirthdayNotification(est.id);
    }
  }

  void _scheduleBirthdayNotification(String estId) {
    _birthdayNotifyTimer?.cancel();
    _birthdayNotifyTimer = null;
    final screenPref = ScreenLayoutPreferenceService();
    if (screenPref.birthdayNotifyDays < 1) return;
    final timeStr = screenPref.birthdayNotifyTime;
    final parts = timeStr.split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (now.isAfter(next) || now.isAtSameMomentAs(next)) {
      next = next.add(const Duration(days: 1));
    }
    var duration = next.difference(now);
    if (duration.isNegative) duration = duration + const Duration(days: 1);
    _birthdayNotifyTimer = Timer(duration, () => _onBirthdayNotifyFired(estId));
  }

  Future<void> _onBirthdayNotifyFired(String estId) async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _todayKey();
    if (prefs.getString(_keyBirthdayNotifyLastShown) == todayStr) return;
    final screenPref = ScreenLayoutPreferenceService();
    if (screenPref.birthdayNotifyDays < 1) return;
    final days = screenPref.birthdayNotifyDays;
    final acc = AccountManagerSupabase();
    List<Employee> employees;
    try {
      employees = await acc.getEmployeesForEstablishment(estId);
    } catch (_) {
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = <({Employee emp, int daysUntil})>[];
    for (final emp in employees) {
      final b = emp.birthday;
      if (b == null) continue;
      final thisYear = DateTime(now.year, b.month, b.day);
      if (thisYear == today) {
        upcoming.add((emp: emp, daysUntil: 0));
        continue;
      }
      for (var d = 1; d <= days; d++) {
        final target = today.add(Duration(days: d));
        if (thisYear.year == target.year && thisYear.month == target.month && thisYear.day == target.day) {
          upcoming.add((emp: emp, daysUntil: d));
          break;
        }
      }
    }
    if (upcoming.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleBirthdayNotification(estId);
      });
      return;
    }
    final parts = upcoming.map((e) {
      if (e.daysUntil == 0) return '${e.emp.fullName} (сегодня)';
      return '${e.emp.fullName} (через ${e.daysUntil} дн.)';
    }).toList();
    final message = 'День рождения: ${parts.join(', ')}';
    AppToastService.showBanner(message, onTap: AppToastService.goToInboxNotifications);
    await prefs.setString(_keyBirthdayNotifyLastShown, todayStr);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleBirthdayNotification(estId);
    });
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  bool _hasInboxOrders(dynamic emp) =>
      emp.hasRole('owner') ||
      emp.hasRole('executive_chef') ||
      emp.hasRole('sous_chef') ||
      emp.department == 'management';

  bool _hasInboxInventory(dynamic emp) =>
      emp.hasRole('owner') ||
      emp.hasRole('executive_chef') ||
      emp.hasRole('sous_chef') ||
      emp.hasRole('bar_manager') ||
      emp.hasRole('floor_manager') ||
      emp.department == 'management';

  bool _hasInboxChecklists(dynamic emp) =>
      emp.hasRole('owner') ||
      emp.hasRole('executive_chef') ||
      emp.hasRole('sous_chef') ||
      emp.department == 'management';

  bool _canSeeDeletionNotifications(dynamic emp) =>
      emp.hasRole('owner') ||
      emp.hasRole('executive_chef') ||
      emp.hasRole('sous_chef') ||
      emp.hasRole('bar_manager') ||
      emp.hasRole('floor_manager');

  void _onNewMessage(dynamic payload, String myId) {
    final newRow = payload.newRecord;
    final senderId = newRow['sender_employee_id']?.toString();
    final content = (newRow['content'] as String?)?.trim() ?? '';
    final hasImage = newRow['image_url'] != null && (newRow['image_url'] as String).isNotEmpty;
    if (senderId == null || senderId.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = GoRouterState.of(context).matchedLocation;
      if (location.contains('/inbox/chat/$senderId')) return;
      _showNotification(
        category: 'messages',
        title: '',
        body: hasImage ? '[фото]' : (content.isNotEmpty ? (content.length > 40 ? '${content.substring(0, 40)}…' : content) : ''),
        onTap: () => _go('/inbox/chat/$senderId'),
        extra: senderId,
      );
    });
  }

  void _onNewOrderDocument(dynamic payload) {
    final newRow = payload.newRecord;
    final id = newRow['id']?.toString();
    if (id == null) return;
    final pl = newRow['payload'];
    final header = pl is Map ? pl['header'] : null;
    final supplier = (header is Map ? header['supplierName'] : null)?.toString() ?? '—';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showNotification(
        category: 'orders',
        title: 'Заказ $supplier',
        body: '',
        onTap: () => _go('/inbox/order/$id'),
      );
    });
  }

  void _onNewInventoryDocument(dynamic payload) {
    final newRow = payload.newRecord;
    final id = newRow['id']?.toString();
    if (id == null) return;
    final p = newRow['payload'];
    final pMap = p is Map ? p as Map<String, dynamic> : null;
    final isIiko = pMap?['type'] == 'iiko_inventory';
    final prefs = context.read<NotificationPreferencesService>();
    if (isIiko && !prefs.shouldNotifyFor('iikoInventory')) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = isIiko ? '/inbox/iiko/$id' : '/inbox/inventory/$id';
      _showNotification(
        category: isIiko ? 'iikoInventory' : 'inventory',
        title: isIiko ? 'Инвентаризация iiko' : 'Инвентаризация',
        body: '',
        onTap: () => _go(route),
      );
    });
  }

  void _onNewChecklistSubmission(dynamic payload, dynamic emp, NotificationPreferencesService prefs) {
    if (!_hasInboxChecklists(emp)) return;
    final newRow = payload.newRecord;
    final id = newRow['id']?.toString();
    if (id == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showNotification(
        category: 'notifications',
        title: 'Чеклист заполнен',
        body: '',
        onTap: () => _go('/inbox/checklist/$id'),
      );
    });
  }

  void _onNewDeletionNotification(dynamic payload) {
    final newRow = payload.newRecord;
    final name = newRow['deleted_employee_name']?.toString() ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showNotification(
        category: 'notifications',
        title: 'Удаление сотрудника',
        body: name,
        onTap: () => _go('/inbox?tab=notifications'),
      );
    });
  }

  Future<void> _showNotification({
    required String category,
    required String title,
    required String body,
    required VoidCallback onTap,
    String? extra,
  }) async {
    final prefs = context.read<NotificationPreferencesService>();
    if (prefs.displayType == NotificationDisplayType.disabled) return;
    if (!prefs.shouldNotifyFor(category)) return;

    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();

    String displayText = title;
    if (category == 'messages' && extra != null) {
      try {
        final emps = await acc.getEmployeesForEstablishment(acc.establishment!.id);
        final sender = emps.where((e) => e.id == extra).firstOrNull;
        displayText = '${sender?.fullName ?? sender?.email ?? 'Сотрудник'}: ${body.isEmpty ? (loc.t('new_message') ?? 'новое сообщение') : body}';
      } catch (_) {
        displayText = '${loc.t('new_message') ?? 'Новое сообщение'}: ${body.isEmpty ? '' : body}';
      }
    } else if (body.isNotEmpty) {
      displayText = title.isEmpty ? body : '$title — $body';
    }

    if (!mounted) return;

    if (prefs.displayType == NotificationDisplayType.banner) {
      AppToastService.showBanner(displayText, onTap: () {
        onTap();
        AppToastService.hide();
      });
    } else {
      AppToastService.show(displayText, onTap: () {
        onTap();
        AppToastService.hide();
      });
    }
  }

  void _go(String route) {
    final nav = AppRouter.rootNavigatorKey.currentContext;
    if (nav != null && nav.mounted) {
      GoRouter.of(nav).go(route);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
