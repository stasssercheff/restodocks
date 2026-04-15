import 'dart:async' show Timer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import '../utils/dev_log.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/subscription_entitlements.dart';
import '../models/models.dart';
import '../models/employee_direct_message.dart';
import '../models/employee_message_system_link.dart';
import '../services/services.dart';
import '../utils/chat_system_link_paths.dart';
import '../widgets/app_bar_home_button.dart';
import '../widgets/chat_system_link_picker_sheet.dart';
import '../widgets/chat_voice_player.dart';

/// Чат между двумя сотрудниками.
class EmployeeChatScreen extends StatefulWidget {
  const EmployeeChatScreen({super.key, required this.otherEmployeeId});

  final String otherEmployeeId;

  @override
  State<EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<EmployeeChatScreen> {
  static const int _maxVoiceSeconds = 120;

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _inputFocusNode;
  List<EmployeeDirectMessage> _messages = [];
  Employee? _otherEmployee;
  bool _loading = true;
  bool _sending = false;

  bool _recordingVoice = false;
  bool _voiceRecorderStopped = false;
  String? _voicePath;
  /// Путь к файлу или blob: URL после [voiceStopRecording] (важно для веба).
  String? _voiceResolvedPath;
  int _voiceElapsed = 0;
  Timer? _voiceTimer;

  /// Ссылки на экраны приложения (до отправки).
  List<EmployeeMessageSystemLink> _pendingLinks = [];

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
    _voiceTimer?.cancel();
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

  void _toastLiteChatTextOnly() {
    if (!mounted) return;
    AppToastService.show(context.read<LocalizationService>().t('lite_chat_text_only_hint'));
  }

  Future<void> _sendPhoto() async {
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (SubscriptionEntitlements.from(acc.establishment).isLiteTier) {
      _toastLiteChatTextOnly();
      return;
    }
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

  String _formatVoiceElapsed(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _startVoiceRecording() async {
    final acc = context.read<AccountManagerSupabase>();
    if (SubscriptionEntitlements.from(acc.establishment).isLiteTier) {
      _toastLiteChatTextOnly();
      return;
    }
    if (_sending || _recordingVoice) return;
    if (!await voiceRecordingSupported()) return;
    if (!await voiceHasMicPermission()) {
      if (!mounted) return;
      final l = context.read<LocalizationService>();
      AppToastService.show(l.t('chat_voice_mic_denied') ?? 'Нужен доступ к микрофону');
      return;
    }
    final path = await voiceStartRecordingToPath();
    if (path == null || !mounted) return;
    setState(() {
      _recordingVoice = true;
      _voiceRecorderStopped = false;
      _voicePath = path;
      _voiceResolvedPath = null;
      _voiceElapsed = 0;
    });
    _voiceTimer?.cancel();
    _voiceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _voiceElapsed++);
      if (_voiceElapsed >= _maxVoiceSeconds) {
        _voiceTimer?.cancel();
        _stopVoiceRecorderHardware();
        final l = context.read<LocalizationService>();
        AppToastService.show(l.t('chat_voice_max_duration') ?? 'Максимум 2 мин.');
      }
    });
  }

  Future<void> _stopVoiceRecorderHardware() async {
    if (_voiceRecorderStopped) return;
    final out = await voiceStopRecording();
    _voiceRecorderStopped = true;
    _voiceResolvedPath = out ?? _voicePath;
    if (mounted) setState(() {});
  }

  Future<void> _cancelVoiceRecording() async {
    _voiceTimer?.cancel();
    if (!_voiceRecorderStopped) {
      await voiceAbortRecording();
      _voiceRecorderStopped = true;
    }
    await voiceDeleteTempFile(_voiceResolvedPath ?? _voicePath);
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _voicePath = null;
      _voiceResolvedPath = null;
      _voiceElapsed = 0;
      _voiceRecorderStopped = false;
    });
  }

  Future<void> _commitVoiceRecording() async {
    final loc = context.read<LocalizationService>();
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null || _voicePath == null) return;
    _voiceTimer?.cancel();
    setState(() => _sending = true);
    try {
      String? pathForRead = _voiceResolvedPath;
      if (!_voiceRecorderStopped) {
        pathForRead = await voiceStopRecording();
        _voiceRecorderStopped = true;
      }
      pathForRead ??= _voicePath;
      if (pathForRead == null) {
        if (mounted) {
          setState(() {
            _sending = false;
            _recordingVoice = false;
            _voicePath = null;
            _voiceResolvedPath = null;
            _voiceElapsed = 0;
            _voiceRecorderStopped = false;
          });
        }
        return;
      }
      final sec = _voiceElapsed.clamp(1, _maxVoiceSeconds);
      final bytes = await voiceReadFileBytes(pathForRead);
      await voiceDeleteTempFile(pathForRead);
      if (!mounted) return;
      setState(() {
        _recordingVoice = false;
        _voicePath = null;
        _voiceResolvedPath = null;
        _voiceElapsed = 0;
        _voiceRecorderStopped = false;
      });
      if (bytes == null || bytes.isEmpty) {
        setState(() => _sending = false);
        AppToastService.show(loc.t('chat_voice_error') ?? 'Ошибка записи');
        return;
      }
      if (bytes.length > EmployeeMessageService.maxChatVoiceUploadBytes) {
        setState(() => _sending = false);
        AppToastService.show(loc.t('chat_voice_file_too_large') ?? 'Файл слишком большой');
        return;
      }
      final msgSvc = context.read<EmployeeMessageService>();
      final sent = await msgSvc.sendVoiceBytes(emp.id, widget.otherEmployeeId, bytes, sec);
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _sending = false);
        AppToastService.show(loc.t('chat_voice_error') ?? 'Ошибка отправки');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _recordingVoice = false;
          _voicePath = null;
          _voiceResolvedPath = null;
          _voiceElapsed = 0;
          _voiceRecorderStopped = false;
        });
        AppToastService.show('${loc.t('chat_voice_error') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    }
  }

  Future<void> _pickSystemLink() async {
    final acc = context.read<AccountManagerSupabase>();
    final ent = SubscriptionEntitlements.from(acc.establishment);
    final loc = context.read<LocalizationService>();
    if (ent.isLiteTier) {
      _toastLiteChatTextOnly();
      return;
    }
    if (!ent.canUseChatSystemLinks) {
      AppToastService.show(
        loc.t('chat_system_links_ultra_only'),
      );
      return;
    }
    if (_sending) return;
    final link = await showChatSystemLinkPicker(context);
    if (link == null || !mounted) return;
    if (_pendingLinks.length >= kMaxSystemLinksPerMessage) return;
    if (_pendingLinks.any((e) => e.path == link.path)) return;
    setState(() => _pendingLinks = [..._pendingLinks, link]);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingLinks.isEmpty) return;
    final acc = context.read<AccountManagerSupabase>();
    final emp = acc.currentEmployee;
    if (emp == null) return;
    final loc = context.read<LocalizationService>();
    final linksCopy = List<EmployeeMessageSystemLink>.from(_pendingLinks);
    final ent = SubscriptionEntitlements.from(acc.establishment);
    final lite = ent.isLiteTier;
    var linksForSend = linksCopy;
    if (lite && linksCopy.isNotEmpty) {
      AppToastService.show(loc.t('lite_chat_text_only_hint'));
      linksForSend = [];
      if (text.isEmpty) return;
    }
    if (!ent.canUseChatSystemLinks && linksForSend.isNotEmpty) {
      AppToastService.show(loc.t('chat_system_links_ultra_only'));
      linksForSend = [];
      if (text.isEmpty) return;
    }
    if (text.isEmpty && linksForSend.isEmpty) return;
    _controller.clear();
    setState(() {
      _pendingLinks = [];
      _sending = true;
    });
    try {
      final msgSvc = context.read<EmployeeMessageService>();
      final sent = await msgSvc.send(
        emp.id,
        widget.otherEmployeeId,
        text,
        systemLinks: linksForSend.isEmpty ? null : linksForSend,
      );
      if (mounted && sent != null) {
        setState(() {
          _messages = [..._messages, sent];
          _sending = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() {
          _sending = false;
          _pendingLinks = linksCopy;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLinks = linksCopy;
        });
        AppToastService.show('${context.read<LocalizationService>().t('error_short') ?? 'Ошибка'}: $e', duration: const Duration(seconds: 4));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final theme = Theme.of(context);
    final acc = context.watch<AccountManagerSupabase>();
    final ent = SubscriptionEntitlements.from(acc.establishment);
    final liteChatTextOnly = ent.isLiteTier;
    final canUseChatSystemLinks = ent.canUseChatSystemLinks;
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
                              textOnlyViewer: liteChatTextOnly,
                              systemLinksOpenable: canUseChatSystemLinks,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_recordingVoice && _pendingLinks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _pendingLinks
                            .map(
                              (l) => InputChip(
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
                                  child: Text(l.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ),
                                onDeleted: _sending
                                    ? null
                                    : () => setState(() => _pendingLinks = _pendingLinks.where((x) => x.path != l.path).toList()),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_recordingVoice)
                  Row(
                      children: [
                        Icon(Icons.fiber_manual_record, color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${loc.t('chat_voice_recording') ?? 'Запись'} ${_formatVoiceElapsed(_voiceElapsed)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _sending ? null : _cancelVoiceRecording,
                          child: Text(loc.t('chat_voice_cancel') ?? 'Отмена'),
                        ),
                        FilledButton(
                          onPressed: _sending ? null : _commitVoiceRecording,
                          child: Text(loc.t('chat_voice_send') ?? 'Отправить'),
                        ),
                      ],
                    )
                  else
                  Row(
                      children: [
                        if (!liteChatTextOnly) ...[
                          IconButton(
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            onPressed: _sending ? null : _sendPhoto,
                            tooltip: loc.t('photo_from_gallery') ?? 'Фото',
                          ),
                          if (canUseChatSystemLinks)
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _sending ? null : _pickSystemLink,
                              tooltip: loc.t('chat_attach_link_title') ?? 'Ссылка',
                            ),
                          IconButton(
                            icon: const Icon(Icons.mic_none_outlined),
                            onPressed: _sending ? null : _startVoiceRecording,
                            tooltip: loc.t('chat_voice_tooltip') ?? 'Голосовое',
                          ),
                        ],
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

/// Определяет язык текста (грубая эвристика) среди поддерживаемых: ru/en/es/tr/vi.
String _detectLanguage(String text) {
  if (text.trim().isEmpty) return 'en';
  final runes = text.runes;

  // Кириллица.
  final hasCyrillic = runes.any((r) => r >= 0x0400 && r <= 0x04FF);
  if (hasCyrillic) return 'ru';

  // Вьетнамский: много латиницы с диакритикой + đặc biệt (đ/Đ).
  final hasVietSpecial = runes.any((r) => r == 0x0111 || r == 0x0110); // đ/Đ
  final hasLatinExtended = runes.any(
    (r) =>
        // Latin-1 Supplement + Latin Extended-A/B (часто встречается у vi/es/tr).
        (r >= 0x00C0 && r <= 0x024F) ||
        (r >= 0x1E00 && r <= 0x1EFF), // Latin Extended Additional
  );
  if (hasVietSpecial) return 'vi';

  // Турецкий: ı/İ/ş/Ş/ğ/Ğ/ç/Ç/ö/Ö/ü/Ü.
  final hasTurkishChars = runes.any((r) {
    switch (r) {
      case 0x0131: // ı
      case 0x0130: // İ
      case 0x015F: // ş
      case 0x015E: // Ş
      case 0x011F: // ğ
      case 0x011E: // Ğ
      case 0x00E7: // ç
      case 0x00C7: // Ç
      case 0x00F6: // ö
      case 0x00D6: // Ö
      case 0x00FC: // ü
      case 0x00DC: // Ü
        return true;
    }
    return false;
  });
  if (hasTurkishChars) return 'tr';

  // Испанский: ñ/Ñ, ¡, ¿, áéíóúü.
  final hasSpanishChars = runes.any((r) {
    switch (r) {
      case 0x00F1: // ñ
      case 0x00D1: // Ñ
      case 0x00A1: // ¡
      case 0x00BF: // ¿
      case 0x00E1: // á
      case 0x00C1: // Á
      case 0x00E9: // é
      case 0x00C9: // É
      case 0x00ED: // í
      case 0x00CD: // Í
      case 0x00F3: // ó
      case 0x00D3: // Ó
      case 0x00FA: // ú
      case 0x00DA: // Ú
      case 0x00FC: // ü
      case 0x00DC: // Ü
        return true;
    }
    return false;
  });
  if (hasSpanishChars) return 'es';

  // Если есть расширенная латиница, но не распознали — скорее vi (чаще всего).
  if (hasLatinExtended) return 'vi';

  return 'en';
}

/// Пузырёк сообщения с переводом по выбранному языку.
class _ChatMessageBubble extends StatefulWidget {
  const _ChatMessageBubble({
    required this.message,
    required this.isMe,
    required this.theme,
    this.textOnlyViewer = false,
    this.systemLinksOpenable = true,
  });

  final EmployeeDirectMessage message;
  final bool isMe;
  final ThemeData theme;

  /// Lite: не показывать фото, голос и системные ссылки (только текст).
  final bool textOnlyViewer;

  /// Ultra: системные ссылки открывают экран. Pro: подписи без перехода.
  final bool systemLinksOpenable;

  @override
  State<_ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<_ChatMessageBubble> {
  String? _translatedContent;
  String? _lastLang;

  @override
  void initState() {
    super.initState();
    _lastLang = context.read<LocalizationService>().currentLanguageCode;
    _translateIfNeeded();
  }

  Future<void> _translateIfNeeded() async {
    if (widget.message.content.trim().isEmpty) return;
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
      if (kDebugMode) devLog('[Chat] translate failed: $e');
    }
  }

  @override
  void didUpdateWidget(covariant _ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lang = context.read<LocalizationService>().currentLanguageCode;
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.content != widget.message.content ||
        _lastLang != lang) {
      _lastLang = lang;
      _translatedContent = null;
      _translateIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final content = _translatedContent ?? widget.message.content;
    final lite = widget.textOnlyViewer;
    final hasRich = widget.message.hasImage ||
        widget.message.hasAudio ||
        widget.message.hasSystemLinks;
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
          if (!lite && widget.message.hasImage)
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
          if (!lite && widget.message.hasAudio)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ChatVoicePlayer(
                  audioUrl: widget.message.audioUrl!,
                  durationSeconds: widget.message.audioDurationSeconds ?? 0,
                ),
              ),
            ),
          if (!lite && widget.message.hasSystemLinks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final link in widget.message.systemLinks)
                      widget.systemLinksOpenable
                          ? ActionChip(
                              avatar: const Icon(Icons.link, size: 18),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                                ),
                                child: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                              onPressed: () {
                                try {
                                  context.push(link.path);
                                } catch (_) {}
                              },
                            )
                          : Chip(
                              avatar: Icon(
                                Icons.link_off_outlined,
                                size: 18,
                                color: widget.theme.colorScheme.onSurfaceVariant,
                              ),
                              label: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                                ),
                                child: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                              side: BorderSide(
                                color: widget.theme.colorScheme.outlineVariant,
                              ),
                            ),
                  ],
                ),
              ),
            ),
          if (lite && hasRich && content.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  loc.t('lite_chat_rich_not_shown'),
                  style: widget.theme.textTheme.bodySmall?.copyWith(
                    color: widget.theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
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
