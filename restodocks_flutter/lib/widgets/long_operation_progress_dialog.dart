import 'dart:async';

import 'package:flutter/material.dart';

/// Диалог с индикатором и таймером для длительных операций.
/// Показывает прошедшее время (обновляется каждую секунду), чтобы было ясно, что процесс идёт.
class LongOperationProgressDialog extends StatefulWidget {
  const LongOperationProgressDialog({
    super.key,
    required this.message,
    this.hint,
    this.productCount,
  });

  final String message;
  final String? hint;
  /// Если задано — показываем "message (N)"
  final int? productCount;

  @override
  State<LongOperationProgressDialog> createState() => _LongOperationProgressDialogState();
}

class _LongOperationProgressDialogState extends State<LongOperationProgressDialog> {
  late final DateTime _startTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes} мин ${d.inSeconds % 60} сек';
    }
    return '${d.inSeconds} сек';
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startTime);
    final effectiveMessage = widget.productCount != null
        ? '${widget.message} (${widget.productCount})'
        : widget.message;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(effectiveMessage),
                    const SizedBox(height: 4),
                    Text(
                      _formatElapsed(elapsed),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.hint != null && widget.hint!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.hint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
