import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../models/employee_direct_message.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Чат между двумя сотрудниками.
class EmployeeChatScreen extends StatefulWidget {
  const EmployeeChatScreen({super.key, required this.otherEmployeeId});

  final String otherEmployeeId;

  @override
  State<EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<EmployeeChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<EmployeeDirectMessage> _messages = [];
  Employee? _otherEmployee;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;
    setState(() => _loading = true);
    try {
      final emps = await acc.getEmployeesForEstablishment(est.id);
      _otherEmployee = emps.where((e) => e.id == widget.otherEmployeeId).firstOrNull;
      final msgSvc = context.read<EmployeeMessageService>();
      final list = await msgSvc.getMessagesWith(emp.id, widget.otherEmployeeId);
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      final msgSvc = context.read<EmployeeMessageService>();
      final sent = await msgSvc.send(emp.id, widget.otherEmployeeId, text);
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _sending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.read<LocalizationService>().t('error_short') ?? 'Ошибка'}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final otherName = _otherEmployee?.fullName ?? widget.otherEmployeeId;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(otherName),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          loc.t('chat_empty') ?? 'Нет сообщений. Напишите первым.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderEmployeeId == context.read<AccountManagerSupabase>().currentEmployee?.id;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? theme.colorScheme.primaryContainer
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    msg.content,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('HH:mm').format(msg.createdAt),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: loc.t('chat_type_message') ?? 'Сообщение...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    tooltip: loc.t('send') ?? 'Отправить',
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
