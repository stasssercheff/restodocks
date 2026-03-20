import 'package:feature_spotlight/feature_spotlight.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import 'tour_tooltip.dart';

/// Обёртка для страницы с одностъёпным туром.
/// Показывает тур при первом посещении или по запросу из настроек.
class PageTourWrapper extends StatefulWidget {
  const PageTourWrapper({
    super.key,
    required this.pageKey,
    required this.tourText,
    required this.child,
  });

  final String pageKey;
  final String tourText;
  final Widget child;

  @override
  State<PageTourWrapper> createState() => _PageTourWrapperState();
}

class _PageTourWrapperState extends State<PageTourWrapper> {
  bool _tourCheckDone = false;
  SpotlightController? _tourController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowTour());
  }

  Future<void> _maybeShowTour() async {
    if (_tourCheckDone) return;
    final accountManager = context.read<AccountManagerSupabase>();
    final employee = accountManager.currentEmployee;
    if (employee == null) return;
    _tourCheckDone = true;

    final tourService = context.read<PageTourService>();
    final forceReplay = tourService.consumeReplayRequest(widget.pageKey);
    if (!forceReplay && await tourService.isPageTourSeen(employee.id, widget.pageKey)) return;
    if (!mounted) return;

    final loc = context.read<LocalizationService>();
    final controller = SpotlightController(
      steps: [
        SpotlightStep(
          id: widget.pageKey,
          text: widget.tourText,
          shape: SpotlightShape.rectangle,
          padding: const EdgeInsets.all(4),
          fixedTooltipPosition: true,
          skipButtonOnTooltip: true,
          useGlowOnly: true,
          tooltipBuilder: (onNext, onPrev, onSkip) => buildTourTooltip(
            text: widget.tourText,
            onNext: onNext,
            onPrevious: onPrev,
            onSkip: onSkip,
            isFirstStep: true,
            isLastStep: true,
            nextLabel: PageTourService.getTourDone(loc),
            skipLabel: PageTourService.getTourSkip(loc),
          ),
        ),
      ],
      onTourCompleted: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employee.id, widget.pageKey);
        if (mounted) setState(() => _tourController = null);
      },
      onTourSkipped: () async {
        if (!forceReplay) await tourService.markPageTourSeen(employee.id, widget.pageKey);
        if (mounted) setState(() => _tourController = null);
      },
    );

    if (!mounted) return;
    setState(() => _tourController = controller);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      try {
        FeatureSpotlight.of(context).startTour(controller);
      } catch (e) {
        debugPrint('[Tour] ${widget.pageKey} startTour error: $e');
        if (mounted) setState(() => _tourController = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _tourController;
    if (ctrl == null) return widget.child;
    return SpotlightTarget(
      id: widget.pageKey,
      controller: ctrl,
      child: widget.child,
    );
  }
}
