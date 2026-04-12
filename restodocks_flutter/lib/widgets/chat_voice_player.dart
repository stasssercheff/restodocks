import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Мини-плеер для голосового вложения в чате.
class ChatVoicePlayer extends StatefulWidget {
  const ChatVoicePlayer({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
  });

  final String audioUrl;
  final int durationSeconds;

  @override
  State<ChatVoicePlayer> createState() => _ChatVoicePlayerState();
}

class _ChatVoicePlayerState extends State<ChatVoicePlayer> {
  late final AudioPlayer _player;
  bool _loading = true;
  bool _playing = false;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.audioUrl);
      _player.positionStream.listen((d) {
        if (mounted) setState(() => _position = d);
      });
      _player.playerStateStream.listen((s) {
        if (mounted) {
          setState(() => _playing = s.playing);
          if (s.processingState == ProcessingState.completed) {
            _player.seek(Duration.zero);
            setState(() => _playing = false);
          }
        }
      });
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final m = s ~/ 60;
    final r = s % 60;
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.durationSeconds > 0
        ? Duration(seconds: widget.durationSeconds)
        : (_player.duration ?? Duration.zero);
    final label = _fmt(_position) + (total.inSeconds > 0 ? ' / ${_fmt(total)}' : '');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: _loading
              ? null
              : () async {
                  if (_playing) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                },
          icon: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 36),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
