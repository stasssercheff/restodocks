import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  late final FocusNode _inputFocusNode;
  List<EmployeeDirectMessage> _messages = [];
  Employee? _otherEmployee;
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
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    final myId = emp.id;
    final otherId = widget.otherEmployeeId;
    final supabase = Supabase.instance.client;
    _realtimeChannel = supabase.channel('employee_chat_$otherId').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'employee_direct_messages',
      callback: (payload) {
        final newRow = payload.newRecord;
        final sender = newRow['sender_employee_id']?.toString();
        final recipient = newRow['recipient_employee_id']?.toString();
        if (sender == null || recipient == null) return;
        final isForThisChat = (sender == myId && recipient == otherId) ||
            (sender == otherId && recipient == myId);
        if (isForThisChat && mounted) {
          _load(silent: true);
        }
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
    final msgSvc = context.read<EmployeeMessageService>();
    try {
      await msgSvc.markAsRead(emp.id, widget.otherEmployeeId);
      final emps = await acc.getEmployeesForEstablishment(est.id);
      _otherEmployee = emps.where((e) => e.id == widget.otherEmployeeId).firstOrNull;
      final list = await msgSvc.getMessagesWith(emp.id, widget.otherEmployeeId);
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

  Future<void> _sendPhoto() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
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
      final msgSvc = context.read<EmployeeMessageService>();
      final sent = await msgSvc.sendPhoto(emp.id, widget.otherEmployeeId, bytes);
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
        AppToastService.show('${context.read<LocalizationService>().t('error_short') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
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
        actions: [
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
                          final isMe = msg.senderEmployeeId == context.read<AccountManagerSupabase>().currentEmployee?.id;
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: _ChatMessageBubble(
                              message: msg,
                              isMe: isMe,
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

/// Форматирует время сообщения: полная дата + время (dd.MM.yyyy HH:mm).
String _formatMessageTime(DateTime dt) {
  return DateFormat('dd.MM.yyyy HH:mm').format(dt.toLocal());
}

/// Определяет язык текста: ru если есть кириллица, иначе en.
String _detectLanguage(String text) {
  if (text.isEmpty) return 'ru';
  final hasCyrillic = text.runes.any((r) => r >= 0x0400 && r <= 0x04FF);
  return hasCyrillic ? 'ru' : 'en';
}

/// Пузырёк сообщения с переводом по выбранному языку.
class _ChatMessageBubble extends StatefulWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  final EmployeeDirectMessage message;
  final bool isMe;
  final ThemeData theme;

  @override
  State<_ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<_ChatMessageBubble> {
  String? _translatedContent;

  @override
  void initState() {
    super.initState();
    _translateIfNeeded();
  }

  Future<void> _translateIfNeeded() async {
    final loc = context.read<LocalizationService>();
    final targetLang = loc.currentLanguageCode;
    final sourceLang = _detectLanguage(widget.message.content);
    if (sourceLang == targetLang) return;
    try {
      final translationManager = context.read<TranslationManager>();
      final translated = await translationManager.getLocalizedText(
        entityType: TranslationEntityType.ui,
        entityId: 'chat_${widget.message.id}',
        fieldName: 'content',
        sourceText: widget.message.content,
        sourceLanguage: sourceLang,
        targetLanguage: targetLang,
      );
      if (mounted && translated != widget.message.content) {
        setState(() => _translatedContent = translated);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] translate failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _translatedContent ?? widget.message.content;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      decoration: BoxDecoration(
        color: widget.isMe
            ? widget.theme.colorScheme.primaryContainer
            : widget.theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.message.hasImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => _showImageFullScreen(context, widget.message.imageUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    widget.message.imageUrl!,
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
          if (content.isNotEmpty)
            Text(
              content,
              style: widget.theme.textTheme.bodyMedium,
            ),
          if (content.isNotEmpty) const SizedBox(height: 4),
          Text(
            _formatMessageTime(widget.message.createdAt),
            style: widget.theme.textTheme.labelSmall?.copyWith(
              color: widget.theme.colorScheme.onSurfaceVariant,
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
