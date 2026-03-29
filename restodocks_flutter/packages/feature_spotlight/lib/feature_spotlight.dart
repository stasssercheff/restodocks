import 'package:flutter/material.dart';

/// Defines the shape of the spotlight highlight.
enum SpotlightShape {
  /// A circular highlight.
  circle,

  /// A rectangular highlight with rounded corners.
  rectangle,
}

/// A builder function for creating custom tooltips.
///
/// Provides [onNext], [onPrevious], and [onSkip] callbacks to control the tour flow.
typedef SpotlightTooltipBuilder = Widget Function(
  VoidCallback onNext,
  VoidCallback onPrevious,
  VoidCallback onSkip,
);

/// Represents a single step in a feature spotlight tour.
class SpotlightStep {
  /// Unique identifier for this step. Must match the ID used in [SpotlightTarget].
  final String id;

  /// The text to display in the default tooltip.
  ///
  /// Optional if [tooltipBuilder] is provided.
  final String? text;

  /// The shape of the spotlight highlight. Defaults to [SpotlightShape.rectangle].
  final SpotlightShape shape;

  /// How the tooltip content should be aligned relative to the spotlight.
  /// Currently internally used to determine placement.
  final Alignment contentAlignment;

  /// A custom builder for the tooltip widget.
  ///
  /// If provided, [text] is ignored.
  final SpotlightTooltipBuilder? tooltipBuilder;

  /// Additional padding around the highlighted widget.
  final EdgeInsets padding;

  /// When true, tooltip is positioned at a fixed location (bottom center)
  /// instead of near the target. Useful for scrollable content.
  final bool fixedTooltipPosition;

  /// When true and [tooltipBuilder] is used, the package's separate Skip button
  /// is hidden (tooltip should include its own skip).
  final bool skipButtonOnTooltip;

  /// When true, no dark overlay — only glow on the target button.
  final bool useGlowOnly;

  /// Цвет подсветки (glow) для тёмного фона (напр. красная панель).
  /// Если null — используется colorScheme.primary.
  final Color? glowColor;

  /// Creates a [SpotlightStep].
  ///
  /// Either [text] or [tooltipBuilder] must be provided.
  SpotlightStep({
    required this.id,
    this.text,
    this.shape = SpotlightShape.rectangle,
    this.contentAlignment = Alignment.center,
    this.tooltipBuilder,
    this.padding = EdgeInsets.zero,
    this.fixedTooltipPosition = false,
    this.skipButtonOnTooltip = false,
    this.useGlowOnly = false,
    this.glowColor,
  }) : assert(text != null || tooltipBuilder != null,
            'Either text or tooltipBuilder must be provided.');
}

/// A controller that manages the state and sequence of a feature spotlight tour.
///
/// Use this to define steps and control the navigation between them.
class SpotlightController extends ChangeNotifier {
  /// The list of steps in the tour.
  final List<SpotlightStep> steps;

  int _currentIndex = -1;
  final Map<String, GlobalKey> _targets = {};

  /// Callback triggered when the tour starts.
  final VoidCallback? onTourStarted;

  /// Callback triggered when the tour is completed (last step passed).
  final VoidCallback? onTourCompleted;

  /// Callback triggered if the user skips the tour.
  final VoidCallback? onTourSkipped;

  /// Creates a [SpotlightController] with the defined [steps].
  SpotlightController({
    required this.steps,
    this.onTourStarted,
    this.onTourCompleted,
    this.onTourSkipped,
  });

  /// The index of the currently active step. Returns -1 if no tour is active.
  int get currentIndex => _currentIndex;

  /// Whether a tour is currently active.
  bool get isTourActive => _currentIndex != -1;

  /// The currently active [SpotlightStep], or null if none.
  SpotlightStep? get currentStep => isTourActive ? steps[_currentIndex] : null;

  /// Registers a target widget with its ID and GlobalKey.
  /// Internal use only.
  void _registerTarget(String id, GlobalKey key) {
    _targets[id] = key;
  }

  /// Starts the feature tour from the first step.
  void start() {
    if (steps.isNotEmpty) {
      _currentIndex = 0;
      onTourStarted?.call();
      notifyListeners();
    }
  }

  /// Navigates to the next step in the tour.
  ///
  /// If the current step is the last one, the tour is completed.
  void next() {
    if (_currentIndex < steps.length - 1) {
      _currentIndex++;
      notifyListeners();
    } else {
      _complete();
    }
  }

  /// Navigates to the previous step in the tour.
  void previous() {
    if (_currentIndex > 0) {
      _currentIndex--;
      notifyListeners();
    }
  }

  /// Stops the tour immediately, triggering [onTourSkipped].
  void stop() {
    if (isTourActive) {
      _currentIndex = -1;
      onTourSkipped?.call();
      notifyListeners();
    }
  }

  /// Internal method to complete the tour.
  void _complete() {
    if (isTourActive) {
      _currentIndex = -1;
      onTourCompleted?.call();
      notifyListeners();
    }
  }

  /// Returns the [GlobalKey] associated with the current step's target.
  GlobalKey? getKeyForCurrentStep() {
    if (currentStep == null) return null;
    return _targets[currentStep!.id];
  }
}

/// The main widget that provides the spotlight functionality.
///
/// Should typically wrap your [Scaffold] or your entire app to manage overlays.
class FeatureSpotlight extends StatefulWidget {
  /// The widget below this in the tree.
  final Widget child;

  /// Creates a [FeatureSpotlight].
  const FeatureSpotlight({super.key, required this.child});

  /// Returns the [FeatureSpotlightState] from the closest ancestor.
  static FeatureSpotlightState of(BuildContext context) {
    final state = context.findAncestorStateOfType<FeatureSpotlightState>();
    assert(state != null, 'Cannot find FeatureSpotlight in ancestor tree');
    return state!;
  }

  @override
  State<FeatureSpotlight> createState() => FeatureSpotlightState();
}

/// State for [FeatureSpotlight].
class FeatureSpotlightState extends State<FeatureSpotlight> {
  SpotlightController? _activeController;
  OverlayEntry? _overlayEntry;
  /// Starts a tour using the provided [controller].
  void startTour(SpotlightController controller) {
    setState(() {
      _activeController = controller;
      _activeController?.addListener(_onControllerUpdate);
      _activeController?.start();
    });
  }

  bool _updateScheduled = false;
  bool _updatePending = false;

  void _onControllerUpdate() {
    if (!mounted) return;
    if (_updateScheduled) {
      _updatePending = true;
      return;
    }
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (_updatePending) {
        _updatePending = false;
        _onControllerUpdate();
        return;
      }
      if (mounted) _updateOverlay();
    });
  }

  void _immediateNext() {
    final c = _activeController;
    if (c == null || !c.isTourActive) return;
    _applyTourNav((ctrl) => ctrl.next());
  }

  void _immediatePrevious() {
    final c = _activeController;
    if (c == null || !c.isTourActive) return;
    _applyTourNav((ctrl) => ctrl.previous());
  }

  /// Смена шага: listener не дублирует overlay; overlay — после кадра, где перестроились SpotlightTarget.
  void _applyTourNav(void Function(SpotlightController c) nav) {
    final c = _activeController;
    if (c == null || !mounted) return;
    c.removeListener(_onControllerUpdate);
    try {
      nav(c);
    } finally {
      c.addListener(_onControllerUpdate);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateOverlay();
    });
  }

  /// Stops the currently active tour.
  void _stopTour() {
    _activeController?.removeListener(_onControllerUpdate);
    _activeController?.stop();
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() {
      _activeController = null;
    });
  }

  /// Содержимое оверлея тура. Один и тот же [OverlayEntry] обновляется через [OverlayEntry.markNeedsBuild],
  /// иначе при смене шага remove+insert обрывает pointerDown/pointerUp — кнопки срабатывают со 2-го нажатия.
  Widget _buildActiveOverlayContent() {
    final key = _activeController!.getKeyForCurrentStep();
    if (key == null || key.currentContext == null) {
      final currentStep = _activeController!.currentStep!;
      return _SpotlightOverlay(
        targetRect: Rect.zero,
        shape: currentStep.shape,
        text: currentStep.text,
        tooltipBuilder: currentStep.tooltipBuilder,
        fixedTooltipPosition: true,
        skipButtonOnTooltip: currentStep.skipButtonOnTooltip,
        useGlowOnly: currentStep.useGlowOnly,
        onNext: _immediateNext,
        onPrevious: _immediatePrevious,
        onSkip: _stopTour,
      );
    }

    final renderBox = key.currentContext!.findRenderObject() as RenderBox;
    final targetSize = renderBox.size;
    final targetOffset = renderBox.localToGlobal(Offset.zero);
    final currentStep = _activeController!.currentStep!;

    final targetRect = Rect.fromLTWH(
      targetOffset.dx - currentStep.padding.left,
      targetOffset.dy - currentStep.padding.top,
      targetSize.width + currentStep.padding.horizontal,
      targetSize.height + currentStep.padding.vertical,
    );

    return _SpotlightOverlay(
      targetRect: targetRect,
      shape: currentStep.shape,
      text: currentStep.text,
      tooltipBuilder: currentStep.tooltipBuilder,
      fixedTooltipPosition: currentStep.fixedTooltipPosition,
      skipButtonOnTooltip: currentStep.skipButtonOnTooltip,
      useGlowOnly: currentStep.useGlowOnly,
      onNext: _immediateNext,
      onPrevious: _immediatePrevious,
      onSkip: _stopTour,
    );
  }

  void _updateOverlay() {
    if (!mounted) return;
    final active = _activeController?.isTourActive ?? false;
    if (!active) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {});
      return;
    }
    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) => _buildActiveOverlayContent(),
      );
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A widget that designates its child as a target for a spotlight step.
///
/// Ensure the [id] matches the one defined in your [SpotlightStep].
class SpotlightTarget extends StatefulWidget {
  /// The unique identifier for this target.
  final String id;

  /// The controller managing the tour this target belongs to.
  final SpotlightController controller;

  /// The widget to be highlighted.
  final Widget child;

  /// Creates a [SpotlightTarget].
  const SpotlightTarget({
    super.key,
    required this.id,
    required this.controller,
    required this.child,
  });

  @override
  State<SpotlightTarget> createState() => _SpotlightTargetState();
}

class _SpotlightTargetState extends State<SpotlightTarget> {
  final GlobalKey _key = GlobalKey();
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    widget.controller._registerTarget(widget.id, _key);
    _wasActive = widget.controller.isTourActive &&
        widget.controller.currentStep?.id == widget.id;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SpotlightTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final isActive = widget.controller.isTourActive &&
        widget.controller.currentStep?.id == widget.id;
    if (_wasActive != isActive) {
      _wasActive = isActive;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.controller.isTourActive &&
        widget.controller.currentStep?.id == widget.id;
    final useGlow = isActive &&
        (widget.controller.currentStep?.useGlowOnly ?? false);
    final glowColor = widget.controller.currentStep?.glowColor ??
        Theme.of(context).colorScheme.primary;

    return Container(
      key: _key,
      padding: useGlow ? const EdgeInsets.all(2) : null,
      decoration: useGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 0,
                ),
              ],
              border: Border.all(
                color: glowColor.withValues(alpha: 0.7),
                width: 2,
              ),
            )
          : null,
      child: widget.child,
    );
  }
}

/// The internal widget that draws the spotlight masking and tooltip.
class _SpotlightOverlay extends StatelessWidget {
  final Rect targetRect;
  final SpotlightShape shape;
  final String? text;
  final SpotlightTooltipBuilder? tooltipBuilder;
  final bool fixedTooltipPosition;
  final bool skipButtonOnTooltip;
  final bool useGlowOnly;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;

  const _SpotlightOverlay({
    required this.targetRect,
    required this.shape,
    this.text,
    this.tooltipBuilder,
    this.fixedTooltipPosition = false,
    this.skipButtonOnTooltip = false,
    this.useGlowOnly = false,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // Tooltip position: fixed at bottom center, or near target
    // При fixedTooltipPosition — выше нижней навигации (56px) и safe area
    Widget tooltipContent;
    if (fixedTooltipPosition) {
      final bottomNavHeight = 56.0;
      final bottomOffset = 24.0 + bottomNavHeight + MediaQuery.of(context).padding.bottom;
      tooltipContent = Positioned(
        left: 20,
        right: 20,
        bottom: bottomOffset,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: tooltipBuilder != null
                ? tooltipBuilder!(onNext, onPrevious, onSkip)
                : _buildDefaultTooltipContent(),
          ),
        ),
      );
    } else {
      final bool isTooltipBelow = targetRect.center.dy < screenSize.height / 2;
      tooltipContent = Positioned(
        top: isTooltipBelow ? targetRect.bottom + 16 : null,
        bottom:
            isTooltipBelow ? null : screenSize.height - targetRect.top + 16,
        left: 20,
        right: 20,
        child: tooltipBuilder != null
            ? tooltipBuilder!(onNext, onPrevious, onSkip)
            : _buildDefaultTooltipContent(),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background: при useGlowOnly — полностью прозрачный барьер (тап = Далее), иначе тёмный с вырезом
          GestureDetector(
            onTap: onNext,
            behavior: HitTestBehavior.opaque,
            child: useGlowOnly
                ? const SizedBox.expand()
                : ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Color.fromARGB(153, 0, 0, 0),
                      BlendMode.srcOut,
                    ),
                    child: Stack(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            backgroundBlendMode: BlendMode.dstOut,
                          ),
                        ),
                        Positioned(
                          top: targetRect.top,
                          left: targetRect.left,
                          child: _buildHighlight(targetRect.size),
                        ),
                      ],
                    ),
                  ),
          ),
          tooltipContent,
          // Skip button (hidden when skipButtonOnTooltip is true)
          if (!skipButtonOnTooltip)
            Positioned(
              top: 40,
              right: 20,
              child: TextButton(
                onPressed: onSkip,
                child: const Text('Skip', style: TextStyle(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighlight(Size size) {
    switch (shape) {
      case SpotlightShape.circle:
        final radius =
            size.width > size.height ? size.width / 2 : size.height / 2;
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        );
      case SpotlightShape.rectangle:
        return Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    }
  }

  Widget _buildDefaultTooltipContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.1 * 255).toInt()),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text ?? '',
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onPrevious,
                child: const Text('Previous'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onNext,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
