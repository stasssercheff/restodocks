import 'package:flutter/material.dart';

import '../services/services.dart';

/// Индикатор безопасности данных — строка из [LocalizationService] (тот же синглтон, что и в Provider).
///
/// [labelKey] по умолчанию [data_safety_protected]; на инвентаризации лучше [inventory_data_protected].
class DataSafetyIndicator extends StatelessWidget {
  final bool isVisible;
  final String labelKey;

  const DataSafetyIndicator({
    super.key,
    this.isVisible = true,
    this.labelKey = 'data_safety_protected',
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: LocalizationService(),
      builder: (context, _) {
        final label = LocalizationService().t(labelKey);
        return Positioned(
          top: 8, // В пустой области между датой и строкой поиска
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.security,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}