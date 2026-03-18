import 'package:flutter/material.dart';

/// Единый PrimaryScrollController для экранов приложения.
///
/// Нужен для паттерна "тап по заголовку AppBar = наверх" без ручного проброса
/// ScrollController в каждый экран.
class AppPrimaryScrollController extends StatefulWidget {
  const AppPrimaryScrollController({super.key, required this.child});

  final Widget child;

  @override
  State<AppPrimaryScrollController> createState() => _AppPrimaryScrollControllerState();
}

class _AppPrimaryScrollControllerState extends State<AppPrimaryScrollController> {
  late final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      child: widget.child,
    );
  }
}

