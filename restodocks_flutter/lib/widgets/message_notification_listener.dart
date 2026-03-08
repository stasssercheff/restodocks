import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/router/app_router.dart';
import '../services/services.dart';

/// Слушает новые сообщения и показывает toast. По тапу — переход в диалог.
class MessageNotificationListener extends StatefulWidget {
  const MessageNotificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<MessageNotificationListener> createState() => _MessageNotificationListenerState();
}

class _MessageNotificationListenerState extends State<MessageNotificationListener> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;

    final client = Supabase.instance.client;
    _channel = client.channel('message_notification_${emp.id}').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'employee_direct_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_employee_id',
        value: emp.id,
      ),
      callback: (payload) {
        final newRow = payload.newRecord;
        final senderId = newRow['sender_employee_id']?.toString();
        final content = (newRow['content'] as String?)?.trim() ?? '';
        final hasImage = newRow['image_url'] != null && (newRow['image_url'] as String).isNotEmpty;
        if (senderId == null || senderId.isEmpty) return;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final location = GoRouterState.of(context).matchedLocation;
          if (location.contains('/inbox/chat/$senderId')) return;
          _showToast(senderId, content, hasImage);
        });
      },
    );
    _channel!.subscribe();
  }

  Future<void> _showToast(String senderId, String content, bool hasImage) async {
    final acc = context.read<AccountManagerSupabase>();
    final loc = context.read<LocalizationService>();
    final est = acc.establishment;
    if (est == null) return;
    final navigatorContext = AppRouter.rootNavigatorKey.currentContext;

    String displayText;
    try {
      final emps = await acc.getEmployeesForEstablishment(est.id);
      final sender = emps.where((e) => e.id == senderId).firstOrNull;
      final senderName = sender?.fullName ?? sender?.email ?? 'Сотрудник';
      displayText = hasImage
          ? '$senderName: [фото]'
          : (content.isNotEmpty ? '$senderName: ${content.length > 40 ? '${content.substring(0, 40)}…' : content}' : '$senderName: [сообщение]');
    } catch (_) {
      final newMsg = loc.t('new_message');
      displayText = hasImage ? '$newMsg: [фото]' : (content.isNotEmpty ? '$newMsg: ${content.length > 30 ? '${content.substring(0, 30)}…' : content}' : newMsg);
    }

    if (!mounted) return;
    AppToastService.show(
      displayText,
      onTap: () {
        if (navigatorContext != null && navigatorContext.mounted) {
          GoRouter.of(navigatorContext).go('/inbox/chat/$senderId');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
