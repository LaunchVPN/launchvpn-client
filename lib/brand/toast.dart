import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/icon_tile.dart';
import 'package:onexray/brand/theme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// What a toast tells: its icon and the icon's color.
enum ToastKind {
  success(LucideIcons.check, BrandColors.success, BrandColors.successBadge),
  error(LucideIcons.triangleAlert, BrandColors.danger, BrandColors.dangerBadge),
  info(LucideIcons.info, BrandColors.muted, BrandColors.mutedBadge);

  const ToastKind(this.icon, this.color, this.fill);

  final IconData icon;
  final Color color;
  final Color fill;
}

/// Keeps toasts clear of [bottom] above the screen's bottom edge while
/// [child] shows, such as the tab bar. There is one toaster, so this holds
/// whatever context shows the toast.
class ToastArea extends StatefulWidget {
  const ToastArea({super.key, required this.bottom, required this.child});

  final double bottom;
  final Widget child;

  /// What the latest area still showing keeps clear, or none.
  static final _bottom = ValueNotifier(0.0);

  @override
  State<ToastArea> createState() => _ToastAreaState();
}

class _ToastAreaState extends State<ToastArea> {
  static final _shown = <_ToastAreaState>[];

  @override
  void initState() {
    super.initState();
    _shown.add(this);
    _settleAfterFrame();
  }

  @override
  void didUpdateWidget(ToastArea old) {
    super.didUpdateWidget(old);
    if (widget.bottom != old.bottom) _settleAfterFrame();
  }

  @override
  void dispose() {
    _shown.remove(this);
    _settleAfterFrame();
    super.dispose();
  }

  /// Once the screen that added or removed an area has built, so a toast on
  /// screen moves with it.
  static void _settleAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ToastArea._bottom.value = _shown.lastOrNull?.widget.bottom ?? 0;
      });

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Long enough to read a line or two.
const _readingTime = Duration(seconds: 3);

/// The width of a toast on a tablet or desktop.
const _wideWidth = 420.0;

/// Shows [message] at the bottom, above the tab bar on a tab, for [duration].
/// It rises into place as it fades in, and sinks back as it fades out.
///
/// With [top], it shows that far below the status bar instead, as a compact
/// line that drops into place: the answer to a pull, where the pull happened.
void showBrandToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = _readingTime,
  double? top,
}) {
  final toaster = ShadToaster.of(context);
  final screen = toaster.context;
  final width = (MediaQuery.sizeOf(screen).width - 2 * BrandSpacing.page).clamp(
    0.0,
    _wideWidth,
  );
  final compact = top != null;
  // Where it comes from and goes back to: below its place, or above at the top.
  final away = Offset(0, compact ? -BrandMotion.step : BrandMotion.step);
  final arrive = BrandMotion.of(screen, BrandMotion.slow);
  final leave = BrandMotion.of(screen, BrandMotion.medium);
  // The toaster plays the entrance and the exit on one controller and, when
  // their lengths differ, restarts it on a hide, which then never takes the
  // toast away. So the exit fades in [leave] but both last [arrive], and both
  // keep one shape, so the toast is not rebuilt as it starts to leave.
  final span = CustomEffect(duration: arrive, builder: (_, _, child) => child);
  final inset = MediaQuery.viewPaddingOf(screen);
  toaster.show(
    ShadToast(
      title: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(
                  icon: kind.icon,
                  color: kind.color,
                  fill: kind.fill,
                  size: _compactTile,
                  iconSize: 14,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(message, style: BrandText.notice)),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(
                  icon: kind.icon,
                  color: kind.color,
                  fill: kind.fill,
                  size: _tile,
                ),
                const SizedBox(width: 12),
                Expanded(child: _ToastMessage(message)),
              ],
            ),
      alignment: compact ? Alignment.topCenter : Alignment.bottomCenter,
      // The system bar's inset even while a closing keyboard still hides it.
      // At the bottom, [_clearOfArea] adds the tab bar.
      offset: Offset(
        BrandSpacing.page,
        compact ? inset.top + top : inset.bottom + 16,
      ),
      constraints: compact
          ? BoxConstraints(maxWidth: width)
          : BoxConstraints.tightFor(width: width),
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      backgroundColor: BrandColors.surfaceRaised,
      border: compact
          ? ShadBorder.all(color: BrandColors.line)
          : ShadBorder.none,
      radius: BorderRadius.circular(compact ? BrandRadii.md : BrandRadii.card),
      shadows: BrandShadows.toast,
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 10, 16, 10)
          : const EdgeInsets.fromLTRB(12, 12, 16, 12),
      closeIcon: const SizedBox.shrink(),
      duration: duration,
      animateIn: [
        FadeEffect(duration: arrive, curve: BrandMotion.smoothOut),
        MoveEffect(begin: away, end: Offset.zero),
        if (!compact) _clearOfArea,
        span,
      ],
      animateOut: [
        FadeEffect(
          begin: 1,
          end: 0,
          duration: leave,
          curve: BrandMotion.smoothOut,
        ),
        MoveEffect(begin: Offset.zero, end: away),
        if (!compact) _clearOfArea,
        span,
      ],
    ),
  );
}

/// Lifts a bottom toast over the latest [ToastArea], gliding as one comes or
/// goes, without the toast showing again.
final _clearOfArea = CustomEffect(
  duration: Duration.zero,
  builder: (context, _, child) => ValueListenableBuilder(
    valueListenable: ToastArea._bottom,
    builder: (context, bottom, child) => TweenAnimationBuilder(
      tween: Tween(end: bottom),
      duration: BrandMotion.of(context, BrandMotion.fast),
      curve: BrandMotion.smoothOut,
      builder: (context, lift, child) =>
          Transform.translate(offset: Offset(0, -lift), child: child),
      child: child,
    ),
    child: child,
  ),
);

const _tile = 32.0;
const _compactTile = 22.0;

/// One line centres on the tile. The first of more lines starts at the
/// tile's top, as a paragraph centred on the tile reads as floating.
class _ToastMessage extends StatelessWidget {
  const _ToastMessage(this.message);

  final String message;

  /// Manrope's capitals start this far below the top of a line, per pixel
  /// of font size: 6 px in a 15 px font's 22 px line.
  static const _capitalsDrop = 6 / 15;

  /// Where the capitals of more lines sit below the tile's top, which reads as
  /// level beside the tile's faint rounded edge.
  static const _capitalsBelowTile = 2.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = BrandText.body;
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        text: TextSpan(text: message, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: constraints.maxWidth);
      final oneLine = painter.computeLineMetrics().length == 1;
      painter.dispose();
      // The system's text size changes the line and its capitals with it.
      final fontSize = scaler.scale(style.fontSize!);
      final text = Text(message, style: style);
      return oneLine
          ? Padding(
              padding: EdgeInsets.only(
                top: math.max(0, (_tile - fontSize * style.height!) / 2),
              ),
              child: text,
            )
          : Transform.translate(
              offset: Offset(0, _capitalsBelowTile - fontSize * _capitalsDrop),
              child: text,
            );
    },
  );
}
