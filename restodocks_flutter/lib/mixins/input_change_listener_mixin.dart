import 'package:flutter/material.dart';

/// Mixin для отслеживания изменений в полях ввода
mixin InputChangeListenerMixin<T extends StatefulWidget> on State<T> {
  /// Callback, который вызывается при изменении любого поля ввода
  VoidCallback? onInputChanged;

  /// Установить callback для отслеживания изменений
  void setOnInputChanged(VoidCallback callback) {
    onInputChanged = callback;
  }

  /// Создать TextEditingController с отслеживанием изменений
  TextEditingController createTrackedController({
    String initialValue = '',
    void Function(String)? onChanged,
  }) {
    final controller = TextEditingController(text: initialValue);

    controller.addListener(() {
      onChanged?.call(controller.text);
      onInputChanged?.call();
    });

    return controller;
  }

  /// Создать FocusNode с отслеживанием изменений
  FocusNode createTrackedFocusNode() {
    final focusNode = FocusNode();

    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        // Поле потеряло фокус - вызвать callback
        onInputChanged?.call();
      }
    });

    return focusNode;
  }

  /// Отследить изменения в ValueNotifier
  void trackValueNotifier<T>(ValueNotifier<T> notifier) {
    notifier.addListener(() {
      onInputChanged?.call();
    });
  }

  /// Отследить изменения в списке
  void trackListChanges<T>(List<T> list) {
    // Для списков нужно переопределить методы изменения списка
    // Этот метод должен вызываться после каждого изменения списка
  }

  /// Вызвать callback изменения вручную
  void notifyInputChanged() {
    onInputChanged?.call();
  }
}