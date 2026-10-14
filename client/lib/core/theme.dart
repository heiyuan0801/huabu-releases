import 'package:flutter/foundation.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

abstract final class AppLayout {
  static bool get isDesktop => switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
    _ => false,
  };
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const desktopBreakpoint = 900.0;
}

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

abstract final class AppMotion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 200);
  static const page = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;
}

abstract final class AppTheme {
  static const accent = Color(0xFF7958FF);
  static const blue = Color(0xFF3788FF);
  static const cyan = Color(0xFF65CCDF);
  static const creativeGradient = LinearGradient(colors: [blue, accent], begin: Alignment.centerLeft, end: Alignment.centerRight);
  static const imageOverlay = LinearGradient(colors: [Color(0x000B0D14), Color(0xE60B0D14)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  static const imageForeground = Color(0xFFFFFFFF);
  static const updateBlue = Color(0xFF176BFF);
  static const updateGradient = LinearGradient(colors: [Color(0xFF2C9EFF), Color(0xFF075AFF)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  static const updateDesktopTitleSize = 30.0;
  static const updateMobileTitleSize = 23.0;
  static const studioColors = [cyan, accent, Color(0xFFF59B78), Color(0xFF72CC9E)];
  static const studioForeground = Color(0xFF191C22);
  static final _lightTouch = _create(false, true);
  static final _lightDesktop = _create(false, false);
  static final _darkTouch = _create(true, true);
  static final _darkDesktop = _create(true, false);

  static FThemeData light({required bool touch}) => touch ? _lightTouch : _lightDesktop;
  static FThemeData dark({required bool touch}) => touch ? _darkTouch : _darkDesktop;

  static FThemeData softwareUpdates(FThemeData base) {
    final colors = base.colors.copyWith(primary: updateBlue, primaryForeground: imageForeground,
      secondary: Color.alphaBlend(updateBlue.withValues(alpha: .08), base.colors.card), secondaryForeground: base.colors.foreground);
    final buttons = FButtonStyles.inherit(colors: colors, typography: base.typography, style: base.style, touch: !AppLayout.isDesktop);
    final primary = FButtonSizeStyles.inherit(typography: base.typography, style: base.style, touch: !AppLayout.isDesktop,
      foregroundColor: colors.primaryForeground, disabledForegroundColor: colors.disable(colors.primaryForeground),
      decoration: (radius) => FVariants(ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), gradient: updateGradient), variants: {
        [FTappableVariant.hovered, FTappableVariant.pressed]: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), gradient: updateGradient, shadows: [BoxShadow(color: updateBlue.withValues(alpha: .2), blurRadius: 12)]),
        [FTappableVariant.disabled]: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), color: colors.disable(updateBlue)),
      }));
    final track = BoxDecoration(color: updateBlue.withValues(alpha: .1), borderRadius: BorderRadius.circular(AppRadius.xl));
    const fill = BoxDecoration(gradient: updateGradient, borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl)));
    return FThemeData(colors: colors, touch: !AppLayout.isDesktop, typography: base.typography, icons: base.icons, style: base.style,
      cardStyle: base.cardStyle, dialogRouteStyle: base.dialogRouteStyle,
      buttonStyles: FVariants(primary, variants: {
        [FButtonVariant.primary]: primary, [FButtonVariant.secondary]: buttons.secondary,
        [FButtonVariant.destructive]: buttons.destructive, [FButtonVariant.outline]: buttons.outline, [FButtonVariant.ghost]: buttons.ghost,
      }),
      dialogStyle: base.dialogStyle.copyWith(insetPadding: const EdgeInsetsGeometryDelta.value(EdgeInsets.all(AppSpace.lg)), decoration: DecorationDelta.value(BoxDecoration(
        color: Color.alphaBlend(updateBlue.withValues(alpha: .025), colors.card), borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.border), boxShadow: [BoxShadow(color: colors.foreground.withValues(alpha: .12), blurRadius: 48, offset: const Offset(0, 16))],
      ))),
      progressStyle: base.progressStyle.copyWith(trackDecoration: DecorationDelta.value(track), fillDecoration: const DecorationDelta.value(fill), constraints: const BoxConstraints.tightFor(height: 10)),
      determinateProgressStyle: base.determinateProgressStyle.copyWith(trackDecoration: DecorationDelta.value(track), fillDecoration: const DecorationDelta.value(fill), constraints: const BoxConstraints.tightFor(height: 10)),
    );
  }

  static FThemeData _create(bool dark, bool touch) {
    final colors = dark
        ? FColors.neutralDark.copyWith(
            background: const Color(0xFF0B0D14),
            foreground: const Color(0xFFF3F1FA),
            primary: accent,
            primaryForeground: const Color(0xFFFFFFFF),
            secondary: const Color(0xFF242A3D),
            secondaryForeground: const Color(0xFFE4DEF9),
            muted: const Color(0xFF141824),
            mutedForeground: const Color(0xFF9AA4B8),
            card: const Color(0xFF171A26),
            border: const Color(0xFF252A3A),
          )
        : FColors.neutralLight.copyWith(
            background: const Color(0xFFF8F9FB),
            foreground: const Color(0xFF191C22),
            primary: accent,
            primaryForeground: const Color(0xFFFFFFFF),
            secondary: const Color(0xFFEEEDF7),
            secondaryForeground: const Color(0xFF39314F),
            muted: const Color(0xFFF0F1F5),
            mutedForeground: const Color(0xFF797B88),
            card: const Color(0xFFFFFFFF),
            border: const Color(0xFFE5E5EB),
          );
    final base = FTypeface.inherit(
      colors: colors,
      touch: touch,
      fontFamily: 'PlusJakartaSans',
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'Noto Sans CJK SC', 'sans-serif'],
    );
    final typography = FTypography(
      body: base.copyWith(
        sm: base.sm.copyWith(fontSize: touch ? 15 : 14, height: 1.45),
        md: base.md.copyWith(fontSize: touch ? 17 : 16, height: 1.5),
      ),
      display: base.copyWith(
        lg: base.lg.copyWith(fontWeight: FontWeight.w600, height: 1.3),
        xl: base.xl.copyWith(fontWeight: FontWeight.w600, height: 1.25),
        xl2: base.xl2.copyWith(fontSize: touch ? 26 : 24, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -.6),
      ),
    );
    final style = FStyle.inherit(colors: colors, typography: typography, touch: touch).copyWith(
      pagePadding: const EdgeInsetsDelta.value(EdgeInsets.all(AppSpace.xl)),
      borderRadius: const FBorderRadius(
        sm: BorderRadius.all(Radius.circular(AppRadius.sm)),
        md: BorderRadius.all(Radius.circular(AppRadius.md)),
        lg: BorderRadius.all(Radius.circular(AppRadius.lg)),
        xl: BorderRadius.all(Radius.circular(AppRadius.xl)),
      ),
      shadow: [BoxShadow(color: colors.foreground.withValues(alpha: .04), offset: const Offset(0, 4), blurRadius: 20)],
    );
    final buttons = FButtonStyles.inherit(colors: colors, typography: typography, style: style, touch: touch);
    final primary = FButtonSizeStyles.inherit(
      typography: typography, style: style, touch: touch,
      foregroundColor: colors.primaryForeground, disabledForegroundColor: colors.disable(colors.primaryForeground),
      decoration: (radius) => FVariants(
        ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), gradient: creativeGradient),
        variants: {
          [FTappableVariant.hovered, FTappableVariant.pressed]: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), gradient: creativeGradient, shadows: [BoxShadow(color: accent.withValues(alpha: .22), blurRadius: 14)]),
          [FTappableVariant.disabled]: ShapeDecoration(shape: RoundedSuperellipseBorder(borderRadius: radius), gradient: LinearGradient(colors: [blue.withValues(alpha: .3), accent.withValues(alpha: .3)])),
        },
      ),
    );
    return FThemeData(colors: colors, typography: typography, style: style, touch: touch,
      cardStyle: FCardStyle.inherit(colors: colors, typography: typography, style: style, touch: touch).copyWith(padding: EdgeInsetsGeometryDelta.value(EdgeInsets.all(touch ? 20 : 24))),
      buttonStyles: FVariants(primary, variants: {
        [FButtonVariant.primary]: primary, [FButtonVariant.secondary]: buttons.secondary,
        [FButtonVariant.destructive]: buttons.destructive, [FButtonVariant.outline]: buttons.outline, [FButtonVariant.ghost]: buttons.ghost,
      }),
      debugLabel: '未来画布${dark ? '深色' : '浅色'}');
  }
}
