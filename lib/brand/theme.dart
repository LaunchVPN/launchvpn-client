import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:onexray/gen/fonts.gen.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Color variables of the Figma file. The mockups have a single dark mode.
abstract final class BrandColors {
  static const bg = Color(0xFF0E0C12);
  static const surface = Color(0xFF18161D);
  static const surfaceRaised = Color(0xFF23202A);
  static const line = Color(0xFF322E39);
  static const ink = Color(0xFFF5F5F5);
  static const muted = Color(0xFFA09CA9);
  static const accent = Color(0xFF9C5EEF);
  static const accentSoft = Color(0xFF3B1B62);
  static const accentInk = Color(0xFFFFFFFF);
  static const danger = Color(0xFFF14D4C);
  static const warning = Color(0xFFF5AE39);
  static const success = Color(0xFF4BCB71);
}

abstract final class BrandRadii {
  static const md = 16.0;
  static const card = 20.0;
  static const full = 999.0;
}

abstract final class BrandShadows {
  static const knob = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.3),
      offset: Offset(0, 4),
      blurRadius: 12,
    ),
  ];
}

abstract final class BrandSpacing {
  static const page = 24.0;
}

abstract final class BrandText {
  static const _display = FontFamily.unbounded;
  static const _body = FontFamily.manrope;

  static const wordmark = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    height: 21.08 / 17,
    letterSpacing: -0.34,
    color: BrandColors.ink,
  );
  static const screenTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 22,
    height: 28 / 22,
    letterSpacing: -0.11,
    color: BrandColors.ink,
  );
  static const hint = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 22 / 15,
    color: BrandColors.muted,
  );
  static final timer = hint.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  static const cardTitle = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 22 / 15,
    color: BrandColors.ink,
  );
  static const pill = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 18 / 13,
    color: BrandColors.ink,
  );
  static const tab = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 18 / 11,
    color: BrandColors.muted,
  );
  static const selectedTab = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    height: 18 / 11,
    color: BrandColors.accent,
  );
}

abstract final class BrandTheme {
  /// Upstream's semantic roles in our colors, so shared dialogs and toasts
  /// match the brand screens.
  static const palette = AppPalette(
    background: BrandColors.bg,
    foreground: BrandColors.ink,
    card: BrandColors.surface,
    cardForeground: BrandColors.ink,
    popover: BrandColors.surface,
    popoverForeground: BrandColors.ink,
    primary: BrandColors.accent,
    primaryHover: BrandColors.accent,
    primaryText: BrandColors.accent,
    primarySolid: BrandColors.accent,
    primarySolidHover: BrandColors.accent,
    primaryForeground: BrandColors.accentInk,
    surfaceHover: BrandColors.surfaceRaised,
    secondary: BrandColors.surface,
    secondaryForeground: BrandColors.ink,
    muted: BrandColors.surfaceRaised,
    mutedForeground: BrandColors.muted,
    mutedStrong: BrandColors.muted,
    accent: BrandColors.accentSoft,
    accentForeground: BrandColors.ink,
    destructive: BrandColors.danger,
    destructiveSolid: BrandColors.danger,
    destructiveSolidHover: BrandColors.danger,
    destructiveForeground: BrandColors.accentInk,
    border: BrandColors.line,
    borderStrong: BrandColors.line,
    input: BrandColors.line,
    ring: BrandColors.accent,
    selection: BrandColors.accentSoft,
    scannerBackground: BrandColors.bg,
    overlay: Color.fromRGBO(0, 0, 0, 0.6),
    header: BrandColors.bg,
    brand: BrandColors.accent,
    sidebar: BrandColors.surface,
    sidebarForeground: BrandColors.muted,
    sidebarPrimary: BrandColors.accent,
    sidebarPrimaryForeground: BrandColors.accentInk,
    sidebarAccent: BrandColors.accentSoft,
    sidebarAccentForeground: BrandColors.ink,
    sidebarBorder: BrandColors.line,
    sidebarRing: BrandColors.accent,
    selectedSurface: BrandColors.accentSoft,
    running: BrandColors.success,
    runningText: BrandColors.success,
    runningBadge: BrandColors.success,
    runningBadgeForeground: BrandColors.bg,
    runningForeground: BrandColors.bg,
    runningSurface: BrandColors.surfaceRaised,
    restarting: BrandColors.warning,
    restartingText: BrandColors.warning,
    warningSurface: BrandColors.surfaceRaised,
    destructiveSurface: BrandColors.surfaceRaised,
    chart1: BrandColors.accent,
    chart2: BrandColors.success,
    chart3: BrandColors.warning,
    chart4: BrandColors.danger,
    chart5: BrandColors.muted,
  );

  static ThemeData material() {
    final base = AppTheme.material(
      Brightness.dark,
      mobile: true,
      palette: palette,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: BrandText._body),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: BrandText._body,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BrandColors.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BrandText.selectedTab
              : BrandText.tab,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? BrandColors.accent
                : BrandColors.muted,
          ),
        ),
      ),
    );
  }

  static ShadThemeData shad(TextScaler textScaler) {
    final base = AppTheme.shad(
      Brightness.dark,
      mobile: true,
      textScaler: textScaler,
      palette: palette,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(family: BrandText._body),
    );
  }

  static const statusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
