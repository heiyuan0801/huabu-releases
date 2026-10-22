import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';

class DesktopLaunchOverlay extends StatefulWidget {
  const DesktopLaunchOverlay({required this.child, super.key});
  final Widget child;
  @override
  State<DesktopLaunchOverlay> createState() => _DesktopLaunchOverlayState();
}

class _DesktopLaunchOverlayState extends State<DesktopLaunchOverlay> {
  final _contentFocus = FocusScopeNode();
  final _launchFocus = FocusNode();
  bool _finished = false, _played = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_finished) _launchFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_finished) return;
    final desktop = !kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.windows);
    if (!desktop || MediaQuery.disableAnimationsOf(context)) {
      _finished = true;
      if (_played) _restoreFocus();
    } else {
      _played = true;
    }
  }

  void _restoreFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _contentFocus.nextFocus();
  });

  void _finish() {
    if (!mounted || _finished) return;
    setState(() => _finished = true);
    _restoreFocus();
  }

  @override
  void dispose() { _launchFocus.dispose(); _contentFocus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    // Keep the router mounted while the launch layer comes and goes.
    FocusScope(node: _contentFocus, child: ExcludeFocus(excluding: !_finished,
      child: ExcludeSemantics(excluding: !_finished, child: IgnorePointer(ignoring: !_finished, child: widget.child)),
    )),
    if (!_finished) Positioned.fill(child: Semantics(label: '未来画布开屏动画', scopesRoute: true, explicitChildNodes: true,
      child: CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.escape): _finish},
        child: Focus(focusNode: _launchFocus, child: Animate(
          onComplete: (_) => _finish(),
          effects: [
            CustomEffect(duration: AppMotion.launch, builder: (_, value, _) => _LaunchScene(progress: value, onSkip: _finish)),
            const FadeEffect(begin: 1, end: 0, delay: AppMotion.launchExitAt, duration: AppMotion.page, curve: AppMotion.curve),
          ],
          child: const SizedBox.expand(),
        )),
      ),
    )),
  ]);
}

class _LaunchScene extends StatelessWidget {
  const _LaunchScene({required this.progress, required this.onSkip});
  final double progress;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme, colors = theme.colors;
    final mark = AppMotion.launchMark.transform(progress), copy = AppMotion.launchCopy.transform(progress);
    return AnimatedContainer(duration: AppMotion.normal, color: colors.background, child: Stack(fit: StackFit.expand, children: [
      ExcludeSemantics(child: RepaintBoundary(child: CustomPaint(painter: _LaunchOrbitPainter(progress, Theme.brightnessOf(context) == Brightness.dark)))),
      SafeArea(child: Padding(padding: const EdgeInsets.all(AppSpace.xxl), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('HUABU', style: theme.typography.body.xs.copyWith(letterSpacing: 5, color: colors.mutedForeground)),
          FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min,
            onPress: onSkip, semanticsLabel: '跳过开屏动画', child: Row(mainAxisSize: MainAxisSize.min, spacing: AppSpace.sm, children: [
              const Text('跳过'),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(border: Border.all(color: colors.border), borderRadius: BorderRadius.circular(AppRadius.sm / 2)),
                child: Text('Esc', style: theme.typography.body.xs.copyWith(color: colors.mutedForeground))),
            ])),
        ]),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final size = math.min(AppTheme.launchMarkSize, constraints.maxHeight * .45);
          return Center(child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(opacity: mark, child: Transform.translate(offset: Offset(0, 12 * (1 - mark)), child: Transform.scale(scale: .88 + .12 * mark,
              child: RepaintBoundary(child: Image.asset('assets/branding/desktop-launch-mark.png', width: size, height: size, cacheWidth: 384, excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Icon(FLucideIcons.sparkles, size: size * .6, color: colors.primary))),
            ))),
            const SizedBox(height: AppSpace.xl),
            Opacity(opacity: copy, child: Transform.translate(offset: Offset(0, 8 * (1 - copy)), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('未来画布', style: theme.typography.display.xl2.copyWith(fontSize: AppTheme.launchTitleSize, fontWeight: FontWeight.w500, letterSpacing: 8)),
              const SizedBox(height: AppSpace.md),
              Text('让想象发生', style: theme.typography.body.sm.copyWith(letterSpacing: 5, color: colors.mutedForeground)),
            ]))),
          ])));
        })),
        Text('AI 创作工作室', style: theme.typography.body.xs.copyWith(letterSpacing: 4, color: colors.mutedForeground)),
      ]))),
    ]));
  }
}

class _LaunchOrbitPainter extends CustomPainter {
  const _LaunchOrbitPainter(this.progress, this.dark);
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final intensity = dark ? 1.0 : .55;
    canvas.drawRect(bounds, Paint()..shader = RadialGradient(center: const Alignment(0, -.1), radius: .75,
      colors: [AppTheme.blue.withValues(alpha: .12 * intensity), AppTheme.accent.withValues(alpha: .035 * intensity), AppTheme.accent.withValues(alpha: 0)],
    ).createShader(bounds));
    final width = math.min(size.width * .8, 1040.0) * (.94 + .06 * progress);
    final orbit = Rect.fromCenter(center: Offset.zero, width: width, height: math.min(size.height * .58, width * .46));
    canvas.save();
    canvas.translate(size.width / 2, size.height * .48);
    canvas.rotate(-.1 + .035 * progress);
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = .7
      ..shader = SweepGradient(colors: [AppTheme.blue.withValues(alpha: .1 * intensity), AppTheme.blue.withValues(alpha: .6 * intensity), AppTheme.accent.withValues(alpha: .5 * intensity), AppTheme.accent.withValues(alpha: .1 * intensity)]).createShader(orbit);
    canvas.drawOval(orbit, stroke);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: orbit.width * .76, height: orbit.height * .76), stroke);
    for (final (angle, color) in [(math.pi * .83, AppTheme.cyan), (math.pi * 1.8, AppTheme.accent)]) {
      final point = Offset(math.cos(angle + progress * .08) * orbit.width / 2, math.sin(angle + progress * .08) * orbit.height / 2);
      canvas.drawCircle(point, 14, Paint()..shader = RadialGradient(colors: [color.withValues(alpha: .5 * intensity), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: point, radius: 14)));
      canvas.drawCircle(point, 1.2, Paint()..color = color.withValues(alpha: .85 * intensity));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaunchOrbitPainter oldDelegate) => progress != oldDelegate.progress || dark != oldDelegate.dark;
}
