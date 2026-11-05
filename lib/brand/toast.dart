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
  }

  @override
  void dispose() {
    _shown.remove(this);
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
void showBrandToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = _readingTime,
}) {
  final toaster = ShadToaster.of(context);
  // The system bar's inset even while a closing keyboard still hides it.
  final bottom =
      MediaQuery.viewPaddingOf(toaster.context).bottom + ToastArea._bottom + 16;
  final width = MediaQuery.sizeOf(context).width;
  toaster.show(
    ShadToast(
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: kind.icon,
            color: kind.color,
            fill: kind.fill,
            size: 32,
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
      duration: duration,
    ),
  );
}

/// One line centres on the tile. The first of more lines starts at the
/// tile's top, as a paragraph centred on the tile reads as floating.
class _ToastMessage extends StatelessWidget {
  const _ToastMessage(this.message);

  final String message;

  /// The tile's centre is the line's: (32 - 22) / 2.
  static const _oneLineInset = 5.0;

  /// Lifts the first line so its capitals sit 2 px below the tile's top,
  /// which reads as level beside the tile's faint rounded edge. Measured on
  /// Manrope: its capitals start 6 px below the top of a 22 px line.
  static const _capitalsLift = 4.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: message, style: BrandText.body),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final oneLine = painter.computeLineMetrics().length == 1;
      painter.dispose();
      final text = Text(message, style: BrandText.body);
      return oneLine
          ? Padding(
              padding: const EdgeInsets.only(top: _oneLineInset),
              child: text,
            )
          : Transform.translate(
              offset: const Offset(0, -_capitalsLift),
              child: text,
            );
    },
  );
}
