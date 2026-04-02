import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

/// Полноэкранное сканирование QR / Data Matrix (маркировка). Возвращает строку кода через [Navigator.pop].
class PosMarkingScannerScreen extends StatefulWidget {
  const PosMarkingScannerScreen({super.key});

  @override
  State<PosMarkingScannerScreen> createState() => _PosMarkingScannerScreenState();
}

class _PosMarkingScannerScreenState extends State<PosMarkingScannerScreen> {
  late final MobileScannerController _controller;
  var _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue ?? b.displayValue;
      if (v != null && v.trim().isNotEmpty) {
        _handled = true;
        HapticFeedback.lightImpact();
        if (mounted) Navigator.of(context).pop<String>(v.trim());
        return;
      }
    }
  }

  Future<void> _manualEntry(BuildContext context, LocalizationService loc) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_marking_scan_manual')),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: loc.t('pos_marking_scan_manual_hint'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('save')),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && text.isNotEmpty) {
      if (!context.mounted) return;
      Navigator.of(context).pop<String>(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();

    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: Text(loc.t('pos_marking_scan_title')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.t('pos_marking_scan_unavailable_web'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _manualEntry(context, loc),
                child: Text(loc.t('pos_marking_scan_manual')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.t('pos_marking_scan_title')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: loc.t('pos_marking_scan_manual'),
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: () => _manualEntry(context, loc),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (ctx, err) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        size: 48, color: Theme.of(ctx).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      '${loc.t('error')}: ${err.errorDetails?.message ?? err.errorCode.name}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => _manualEntry(ctx, loc),
                      child: Text(loc.t('pos_marking_scan_manual')),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Material(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  loc.t('pos_order_line_marking_hint'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
