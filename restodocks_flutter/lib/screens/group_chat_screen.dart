import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../widgets/app_bar_home_button.dart';

/// Групповой чат.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _inputFocusNode;
  ChatRoom? _room;
  List<ChatRoomMessage> _messages = [];
  Map<String, Employee> _employees = {};
  bool _loading = true;
  bool _sending = false;

  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          _send();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeRealtime();
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    _realtimeChannel = client.channel('group_chat_${widget.roomId}').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'chat_room_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'chat_room_id',
        value: widget.roomId,
      ),
      callback: (_) {
        if (mounted) _load(silent: true);
      },
    );
    _realtimeChannel!.subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    final est = acc.establishment;
    if (emp == null || est == null) return;
    if (!silent) setState(() => _loading = true);
    final groupSvc = context.read<GroupChatService>();
    try {
      final rooms = await groupSvc.getRoomsForEmployee(emp.id, est.id);
      _room = rooms.where((r) => r.id == widget.roomId).firstOrNull;
      if (_room == null) {
        if (mounted) {
          setState(() => _loading = false);
          context.pop();
        }
        return;
      }
      final emps = await acc.getEmployeesForEstablishment(est.id);
      _employees = {for (final e in emps) e.id: e};
      final list = await groupSvc.getMessages(widget.roomId);
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _loading = false);
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

  Future<void> _renameRoom() async {
    if (_room == null) return;
    final loc = context.read<LocalizationService>();
    final nameController = TextEditingController(text: _room!.displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('group_chat_rename') ?? 'Переименовать чат'),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: loc.t('group_chat_name') ?? 'Название',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.t('cancel') ?? 'Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: Text(loc.t('save') ?? 'Сохранить'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<GroupChatService>().renameRoom(widget.roomId, result);
      if (mounted) {
        setState(() {
          _room = ChatRoom(
            id: _room!.id,
            establishmentId: _room!.establishmentId,
            name: result.isEmpty ? null : result,
            createdAt: _room!.createdAt,
            createdByEmployeeId: _room!.createdByEmployeeId,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        AppToastService.show('${loc.t('error_short') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    }
  }

  Future<void> _sendPhoto() async {
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null || _sending) return;
    Uint8List? bytes;
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty) return;
      bytes = result.files.single.bytes;
    } else {
      final loc = context.read<LocalizationService>();
      final isGallery = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(loc.t('photo_from_gallery')),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(loc.t('photo_from_camera')),
                onTap: () => Navigator.pop(ctx, false),
              ),
            ],
          ),
        ),
      );
      if (isGallery == null || !mounted) return;
      final file = await ImagePicker().pickImage(
        source: isGallery ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      bytes = await file.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty || !mounted) return;
    setState(() => _sending = true);
    try {
      final sent = await context.read<GroupChatService>().sendPhoto(widget.roomId, emp.id, bytes);
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
        AppToastService.show('${context.read<LocalizationService>().t('photo_upload_error') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    if (emp == null) return;
    _controller.clear();
    setState(() => _sending = true);
    try {
      final sent = await context.read<GroupChatService>().sendMessage(widget.roomId, emp.id, text);
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
        AppToastService.show('${context.read<LocalizationService>().t('error_short') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    }
  }

  String _roomTitle() {
    if (_room == null) return '';
    if (_room!.displayName.isNotEmpty) return _room!.displayName;
    return context.read<LocalizationService>().t('group_chat_default_name') ?? 'Групповой чат';
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final myId = context.read<AccountManagerSupabase>().currentEmployee?.id;

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(_roomTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _loading ? null : _renameRoom,
            tooltip: loc.t('group_chat_rename') ?? 'Переименовать',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(),
            tooltip: loc.t('inbox_refresh') ?? 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _load,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
                                loc.t('chat_empty') ?? 'Нет сообщений. Напишите первым.',
                                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final msg = _messages[i];
                            final isMe = msg.senderEmployeeId == myId;
                            final senderName = _employees[msg.senderEmployeeId]?.fullName ?? msg.senderEmployeeId;
                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: _GroupMessageBubble(
                                message: msg,
                                isMe: isMe,
                                senderName: isMe ? null : senderName,
                                theme: theme,
                              ),
                            );
                          },
                        ),
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
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: _sending ? null : _sendPhoto,
                    tooltip: loc.t('photo_from_gallery') ?? 'Фото',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _inputFocusNode,
                      decoration: InputDecoration(
                        hintText: loc.t('chat_type_message') ?? 'Сообщение...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                      onSubmitted: (_) {},
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

String _formatMessageTime(DateTime dt) {
  return DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
}

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({
    required this.message,
    required this.isMe,
    required this.senderName,
    required this.theme,
  });

  final ChatRoomMessage message;
  final bool isMe;
  final String? senderName;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          if (senderName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  senderName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          if (message.hasImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => _showImageFullScreen(context, message.imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    message.imageUrl!,
                    fit: BoxFit.cover,
                    width: 200,
                    height: 200,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const SizedBox(width: 200, height: 200, child: Center(child: CircularProgressIndicator())),
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                  ),
                ),
              ),
            ),
          if (message.content.isNotEmpty)
            Text(
              message.content,
              style: theme.textTheme.bodyMedium,
            ),
          if (message.content.isNotEmpty) const SizedBox(height: 4),
          Text(
            _formatMessageTime(message.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showImageFullScreen(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
