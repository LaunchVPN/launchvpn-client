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

  /// The latest area still showing, or none.
  static double get _bottom =>
      _ToastAreaState._shown.lastOrNull?.widget.bottom ?? 0;

  @override
  State<ToastArea> createState() => _ToastAreaState();
}

class _ToastAreaState extends State<ToastArea> {
  static final _shown = <_ToastAreaState>[];

  @override
  void initState() {
    super.initState();
    _shown.add(this);
    _ShownToast.moveAfterFrame();
  }

  @override
  void dispose() {
    _shown.remove(this);
    _ShownToast.moveAfterFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Long enough to read a line or two.
const _readingTime = Duration(seconds: 3);

/// The width of a toast on a tablet or desktop.
const _wideWidth = 420.0;

/// Shows [message] at the bottom, above the tab bar on a tab, for [duration].
///
/// With [top], it shows that far below the status bar instead, as a compact
/// line: the answer to a pull, where the pull happened.
void showBrandToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = _readingTime,
  double? top,
}) => _ShownToast(
  ShadToaster.of(context),
  message,
  kind,
  DateTime.now().add(duration),
  top,
).show();

/// The toast on screen, so it can move when the tab bar comes or goes.
class _ShownToast {
  _ShownToast(this.toaster, this.message, this.kind, this.until, this.top);

  final ShadToasterState toaster;
  final String message;
  final ToastKind kind;
  final DateTime until;
  final double? top;

  static _ShownToast? _current;

  /// Shows it again at the new height for the time it has left, once the
  /// screen that added or removed a [ToastArea] has built.
  static void moveAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final toast = _current;
        if (toast == null || !toast.toaster.mounted) return;
        if (toast.until.isAfter(DateTime.now())) toast.show();
      });

  void show() {
    _current = this;
    if (top case final top?) return _showAtTop(top);
    final screen = toaster.context;
    // The system bar's inset even while a closing keyboard still hides it.
    final bottom =
        MediaQuery.viewPaddingOf(screen).bottom + ToastArea._bottom + 16;
    final width = MediaQuery.sizeOf(screen).width;
    toaster.show(
      ShadToast(
        title: Row(
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
        alignment: Alignment.bottomCenter,
        offset: Offset(BrandSpacing.page, bottom),
        constraints: BoxConstraints.tightFor(
          width: (width - 2 * BrandSpacing.page).clamp(0, _wideWidth),
        ),
        backgroundColor: BrandColors.surfaceRaised,
        border: ShadBorder.none,
        radius: BorderRadius.circular(BrandRadii.card),
        shadows: BrandShadows.toast,
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        closeIcon: const SizedBox.shrink(),
        duration: until.difference(DateTime.now()),
      ),
    );
  }

  void _showAtTop(double top) {
    final screen = toaster.context;
    final width = MediaQuery.sizeOf(screen).width;
    toaster.show(
      ShadToast(
        title: Row(
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
        ),
        alignment: Alignment.topCenter,
        offset: Offset(
          BrandSpacing.page,
          MediaQuery.viewPaddingOf(screen).top + top,
        ),
        constraints: BoxConstraints(
          maxWidth: (width - 2 * BrandSpacing.page).clamp(0, _wideWidth),
        ),
        mainAxisSize: MainAxisSize.min,
        backgroundColor: BrandColors.surfaceRaised,
        border: ShadBorder.all(color: BrandColors.line),
        radius: BorderRadius.circular(BrandRadii.md),
        shadows: BrandShadows.toast,
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
        closeIcon: const SizedBox.shrink(),
        duration: until.difference(DateTime.now()),
      ),
    );
  }
}

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
