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

  /// A control on an [accentSoft] card.
  static const accentSoftRaised = Color(0x14FFFFFF);

  /// The tinted circle behind an icon and its outline.
  static const accentBadge = Color(0x249C5EEF);
  static const accentBadgeLine = Color(0x669C5EEF);
  static const accentInk = Color(0xFFFFFFFF);
  static const danger = Color(0xFFF14D4C);
  static const dangerBadge = Color(0x24F14D4C);
  static const dangerBadgeLine = Color(0x66F14D4C);
  static const warning = Color(0xFFF5AE39);
  static const warningBadge = Color(0x24F5AE39);
  static const warningBadgeLine = Color(0x66F5AE39);
  static const success = Color(0xFF4BCB71);
  static const successBadge = Color(0x244BCB71);
  static const mutedBadge = Color(0x24A09CA9);
}

/// The colors of `.shader-backdrop` on app.launch.tel, which `ShaderBackdrop`
/// lays over its veil: a glow on the page background, a tint from the top
/// left to the bottom right, and two lights.
abstract final class BrandBackdrop {
  static const base = BrandColors.bg;
  static const glow = Color(0x6B42007B);
  static const tintFrom = Color(0x8C6C00BF);
  static const tintTo = Color(0xB81B0058);
  static const highlight = Color(0x479C5EEF);
  static const lowlight = Color(0x2E4A3CC2);
}

abstract final class BrandRadii {
  static const segment = 10.0;
  static const iconButton = 12.0;
  static const control = 14.0;
  static const md = 16.0;
  static const card = 20.0;
  static const sheet = 28.0;
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

  /// Lifts a toast off whatever it covers.
  static const toast = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.45),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];
}

abstract final class BrandSpacing {
  static const page = 24.0;
}

/// The one motion scale, after transitions.dev's tokens. A screen picks the
/// step its motion plays, such as [fast] for a control changing state, and
/// passes it through [of].
abstract final class BrandMotion {
  /// A close, a press.
  static const quick = Duration(milliseconds: 150);

  /// A control changing state.
  static const fast = Duration(milliseconds: 250);

  /// A surface leaving, a reveal.
  static const medium = Duration(milliseconds: 350);

  /// A surface arriving.
  static const slow = Duration(milliseconds: 400);

  /// A moment of emphasis.
  static const verySlow = Duration(milliseconds: 500);

  /// Opening, closing and moving: fast start, long settle.
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// A pop that overshoots a little.
  static const bounce = Cubic(0.34, 1.36, 0.64, 1);

  /// A springy return.
  static const bounceStrong = Cubic(0.34, 3.85, 0.64, 1);

  /// How far motion travels: a nudge, a step, a reveal.
  static const nudge = 4.0;
  static const step = 8.0;
  static const reveal = 12.0;

  /// The size of a control under a finger.
  static const press = 0.97;

  /// [duration], or none when the system asks for less motion.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
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

  /// The large two-line title of «Вход».
  static const heroTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 30,
    height: 36 / 30,
    letterSpacing: -0.3,
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

  /// The days left at the top of «Аккаунт».
  static const days = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 40,
    height: 44 / 40,
    letterSpacing: -0.4,
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
  static final body = hint.copyWith(color: BrandColors.ink);
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
  static const banner = pill;
  static const caption = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 18 / 13,
    color: BrandColors.muted,
  );
  static const preset = caption;

  /// Why an attempt failed, under the field or the button it concerns.
  static final error = caption.copyWith(color: BrandColors.danger);
  static const topBar = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w500,
    fontSize: 17,
    height: 22 / 17,
    color: BrandColors.ink,
  );

  /// Delays line up in a column, so their digits are all one width.
  static const delay = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    height: 18 / 13,
    color: BrandColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A compact toast's one line.
  static const notice = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    height: 18 / 13,
    color: BrandColors.ink,
  );
  static const sectionLabel = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    height: 14 / 13,
    color: BrandColors.muted,
  );
  static const selectedPreset = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w700,
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
      bottomSheetTheme: const BottomSheetThemeData(
        dragHandleColor: BrandColors.line,
        dragHandleSize: Size(36, 5),
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

  /// The mockup's full-width buttons: the main action, a second one on a raised
  /// surface, the quiet one below and a muted link.
  static final primaryButton = _wide(
    FilledButton.styleFrom(
      backgroundColor: BrandColors.accent,
      foregroundColor: BrandColors.accentInk,
    ),
  );
  static final secondaryButton = _wide(
    FilledButton.styleFrom(
      backgroundColor: BrandColors.surfaceRaised,
      foregroundColor: BrandColors.ink,
      side: const BorderSide(color: BrandColors.line),
    ),
  );

  /// The action of a sheet that deletes something.
  static final dangerButton = _wide(
    FilledButton.styleFrom(
      backgroundColor: BrandColors.danger,
      foregroundColor: BrandColors.accentInk,
    ),
  );
  static final quietButton = _wide(
    TextButton.styleFrom(foregroundColor: BrandColors.ink),
  );
  static final linkButton = _wide(
    TextButton.styleFrom(
      foregroundColor: BrandColors.muted,
      minimumSize: const Size.fromHeight(44),
    ),
  );

  /// A link inside a line of text, such as «Войти» after «Уже есть аккаунт?».
  static final inlineLinkButton = TextButton.styleFrom(
    foregroundColor: BrandColors.accent,
    textStyle: BrandText.cardTitle,
    minimumSize: const Size(48, 44),
    padding: const EdgeInsets.symmetric(horizontal: 6),
  );

  /// [style] on [_wideButton]. `styleFrom` sets a text style even when given
  /// none, which `merge` would keep over the wide one.
  static ButtonStyle _wide(ButtonStyle style) =>
      style.copyWith(textStyle: _wideButton.textStyle).merge(_wideButton);

  static final _wideButton = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
    iconSize: const WidgetStatePropertyAll(20),
    textStyle: const WidgetStatePropertyAll(BrandText.cardTitle),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(BrandRadii.md)),
      ),
    ),
  );

  static const statusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );
}
