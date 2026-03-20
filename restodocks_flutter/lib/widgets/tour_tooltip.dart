import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';

/// Компактное окошко тура: маленькая карточка с текстом и кнопками.
Widget buildTourTooltip({
  required String text,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
  required VoidCallback onSkip,
  required bool isFirstStep,
  required bool isLastStep,
  required String nextLabel,
  required String skipLabel,
}) {
  return Align(
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                text,
                style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.35),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(skipLabel, style: const TextStyle(fontSize: 12)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isFirstStep)
                        TextButton(
                          onPressed: onPrevious,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, size: 14),
                        ),
                      FilledButton(
                        onPressed: onNext,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(nextLabel, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
