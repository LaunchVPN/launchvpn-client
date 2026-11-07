import 'dart:async';
import 'dart:math' as math;

import 'package:country_flags/country_flags.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/pull.dart';
import 'package:onexray/brand/section_label.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/brand/top_bar.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/servers/locations.dart';

/// Lists the panel's groups and pops with the one the user taps. Home applies
/// the choice, so a reconnect that outlives this screen still reports to it.
///
/// Opening it measures every location. A pull measures them again, a tap on a
/// location's delay measures that one.
class LocationsPage extends StatefulWidget {
  const LocationsPage({super.key, required this.controller});

  final HomeController controller;

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.measureLocations());
  }

  /// A tunnel that captures all traffic leaves nothing to measure past it.
  Future<void> _measure({Location? only}) async {
    if (widget.controller.state.measuresOnlyWithVpnOff) {
      showBrandToast(
        context,
        AppLocalizations.of(context)!.locationsMeasureVpnOff,
      );
      return;
    }
    await widget.controller.measureLocations(only: only);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandTheme.statusBar,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              BrandTopBar(title: l.locationsTitle),
              Expanded(
                child: BlocConsumer<HomeController, HomeState>(
                  bloc: widget.controller,
                  // Opened mid-transition, or a sweep the tunnel stopped:
                  // measured once it can be.
                  listenWhen: (previous, next) =>
                      !previous.canMeasure && next.canMeasure,
                  listener: (context, state) =>
                      unawaited(widget.controller.measureLocations()),
                  builder: (context, state) {
                    Widget section(String title, Iterable<Location> items) =>
                        _Section(
                          title: title,
                          children: [
                            for (final item in items)
                              _LocationRow(
                                // A tunnel that captures all traffic leaves
                                // the last delays nothing to compare with.
                                location: state.measuresOnlyWithVpnOff
                                    ? item.withDelay(PingDelayConstants.unknown)
                                    : item,
                                selected: item.name == state.location?.name,
                                measuring: state.measuring.contains(item.id),
                                onTap: state.canChangeConnection
                                    ? () => Navigator.of(context).pop(item)
                                    : null,
                                onMeasure: () => _measure(only: item),
                              ),
                          ],
                        );
                    return CustomScrollView(
                      physics: BrandPull.physics,
                      slivers: [
                        CupertinoSliverRefreshControl(
                          onRefresh: _measure,
                          builder: _PullMark.build,
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            BrandSpacing.page,
                            0,
                            BrandSpacing.page,
                            MediaQuery.paddingOf(context).bottom + 20,
                          ),
                          sliver: SliverList.list(
                            children: [
                              if (state.locations.automatic.isNotEmpty)
                                section(
                                  l.locationsAutomatic,
                                  state.locations.automatic,
                                ),
                              if (state.locations.others.isNotEmpty)
                                section(
                                  l.locationsOthers,
                                  state.locations.others,
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        for (final child in children)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ],
    ),
  );
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.location,
    required this.selected,
    required this.measuring,
    required this.onTap,
    required this.onMeasure,
  });

  final Location location;
  final bool selected;
  final bool measuring;
  final VoidCallback? onTap;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null && !selected ? 0.5 : 1,
    child: LocationCard(
      location: location,
      delay: null,
      selected: selected,
      onTap: onTap,
      // The widest pill holds its place, so the name wraps the same way
      // whatever the delay shows.
      trailing: ConstrainedBox(
        constraints: BoxConstraints(minWidth: _Delay.widest(context)),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          widthFactor: 1,
          child: _Delay(
            delay: location.delay,
            // A sweep forgets the stored delay a moment after it starts,
            // and the dots wait for that, then for the answer.
            measuring:
                measuring && location.delay == PingDelayConstants.unknown,
            onAccent: selected,
            onTap: onMeasure,
          ),
        ),
      ),
    ),
  );
}

/// The delay in a pill with a dot for its quality. A location never measured
/// shows only the button that measures it.
class _Delay extends StatelessWidget {
  const _Delay({
    required this.delay,
    required this.measuring,
    required this.onAccent,
    required this.onTap,
  });

  static const _height = 28.0;
  static const _maxTextScale = 1.5;
  static const _padding = 10.0;
  static const _dot = 6.0;

  /// The width of «Нет ответа», the widest a pill gets.
  static double widest(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: AppLocalizations.of(context)!.locationsNoAnswer,
        // As the pill's text gets it, over the theme's.
        style: DefaultTextStyle.of(context).style.merge(BrandText.delay),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context)
          .clamp(maxScaleFactor: _maxTextScale),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return 2 * _padding + 2 * _dot + width;
  }

  /// Answers this fast count as good, and up to a second as usable.
  static const _good = 300;
  static const _usable = 1000;

  final int delay;
  final bool measuring;

  /// The selected card is accent, so the pill lightens it instead.
  final bool onAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final unmeasured = !measuring && delay == PingDelayConstants.unknown;
    final answered = PingDelayConstants.isSuccessful(delay);
    final Widget content;
    if (measuring) {
      content = const SizedBox(width: 52, child: _WaveDots());
    } else if (unmeasured) {
      content = const Icon(
        LucideIcons.refreshCw,
        size: 16,
        color: BrandColors.muted,
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _dot,
            height: _dot,
            decoration: BoxDecoration(
              color: !answered || delay > _usable
                  ? BrandColors.danger
                  : delay > _good
                  ? BrandColors.warning
                  : BrandColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: _dot),
          Text(
            locationDelayLabel(l, delay)!,
            style: BrandText.delay.copyWith(
              color: answered ? BrandColors.ink : BrandColors.muted,
            ),
          ),
        ],
      );
    }
    return Semantics(
      container: true,
      button: true,
      label: measuring
          ? l.locationsMeasuring
          : unmeasured
          ? l.locationsMeasure
          : locationDelayLabel(l, delay),
      onTapHint: unmeasured ? null : l.locationsMeasure,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: measuring ? null : onTap,
        child: Container(
          height: _height,
          constraints: const BoxConstraints(minWidth: _height),
          padding: EdgeInsets.symmetric(horizontal: unmeasured ? 0 : _padding),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onAccent
                ? BrandColors.accentSoftRaised
                : BrandColors.surfaceRaised,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          // The name beside it needs room at the largest system font.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: _maxTextScale,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Three dots rising one after another while a location is measured.
class _WaveDots extends StatefulWidget {
  const _WaveDots();

  @override
  State<_WaveDots> createState() => _WaveDotsState();
}

class _WaveDotsState extends State<_WaveDots>
    with SingleTickerProviderStateMixin {
  static const _size = 5.0;
  static const _lift = 3.0;

  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wave.stop();
    } else if (!_wave.isAnimating) {
      unawaited(_wave.repeat());
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _wave,
    builder: (context, _) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < 3; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          Transform.translate(
            offset: Offset(0, -_lift * _rise(_wave.value - index * 0.15)),
            child: Container(
              width: _size,
              height: _size,
              decoration: const BoxDecoration(
                color: BrandColors.muted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  /// Up and down once in the first half of a cycle, still in the rest.
  static double _rise(double phase) {
    final t = phase % 1;
    return t < 0.5 ? math.sin(t * 2 * math.pi) : 0;
  }
}

/// The LaunchVPN mark in a circle above the list. The chevron climbs as the
/// list is pulled, like a rocket before launch, then rises and sways gently
/// until the measurement ends.
class _PullMark extends StatefulWidget {
  const _PullMark({required this.mode, required this.progress});

  static const _size = 44.0;

  static Widget build(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulledExtent,
    double refreshTriggerPullDistance,
    double refreshIndicatorExtent,
  ) => _PullMark(
    mode: mode,
    progress: BrandPull.progress(
      mode,
      pulledExtent,
      refreshTriggerPullDistance,
    ),
  );

  final RefreshIndicatorMode mode;

  /// How far the pull has gone toward starting a measurement.
  final double progress;

  @override
  State<_PullMark> createState() => _PullMarkState();
}

class _PullMarkState extends State<_PullMark>
    with SingleTickerProviderStateMixin {
  /// How far the chevron sinks before a pull and rises after one.
  static const _sink = 6.0;
  static const _rise = 3.0;
  static const _sway = 2.0;

  late final _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Once the finger is off and the measurement runs.
  bool get _launched => widget.mode == RefreshIndicatorMode.refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_PullMark old) {
    super.didUpdateWidget(old);
    _follow();
  }

  void _follow() {
    if (_launched && !MediaQuery.disableAnimationsOf(context)) {
      if (!_flight.isAnimating) unawaited(_flight.repeat());
    } else {
      _flight
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: Opacity(
      opacity: widget.mode == RefreshIndicatorMode.done ? 0 : widget.progress,
      child: Container(
        width: _PullMark._size,
        height: _PullMark._size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BrandColors.accentSoft,
          shape: BoxShape.circle,
          border: Border.all(color: BrandColors.accent),
        ),
        child: AnimatedBuilder(
          animation: _flight,
          builder: (context, child) => TweenAnimationBuilder<double>(
            tween: Tween(end: _launched ? 1 : 0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            builder: (context, lift, child) => Transform.translate(
              offset: Offset(
                0,
                _sink * (1 - widget.progress) -
                    lift *
                        (_rise + _sway * math.sin(_flight.value * 2 * math.pi)),
              ),
              child: child,
            ),
            child: child,
          ),
          child: const LaunchMark.logo(color: BrandColors.accent),
        ),
      ),
    ),
  );
}

/// The card of one location, on Home and in the list.
class LocationCard extends StatelessWidget {
  const LocationCard({
    super.key,
    required this.location,
    required this.delay,
    required this.onTap,
    this.selected,
    this.trailing,
  });

  final Location location;
  final String? delay;
  final VoidCallback? onTap;

  /// Null where the card is not one of several choices.
  final bool? selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final highlighted = selected ?? false;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: delay == null ? location.name : '${location.name}, $delay',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: highlighted ? BrandColors.accentSoft : BrandColors.surface,
            borderRadius: BorderRadius.circular(BrandRadii.card),
            border: Border.all(
              color: highlighted ? BrandColors.accent : BrandColors.line,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      LocationBadge(location: location),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(location.name, style: BrandText.cardTitle),
                            if (delay != null)
                              Text(delay!, style: BrandText.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // A control of its own, which screen readers reach too.
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Null until a location has been measured.
String? locationDelayLabel(AppLocalizations l, int delay) {
  if (delay == PingDelayConstants.unknown) return null;
  return PingDelayConstants.isSuccessful(delay)
      ? l.locationsDelay(delay)
      : l.locationsNoAnswer;
}

/// A flag for a country, a symbol for an automatic group.
class LocationBadge extends StatelessWidget {
  const LocationBadge({super.key, required this.location});

  static const _size = 40.0;

  final Location location;

  @override
  Widget build(BuildContext context) {
    final code = location.countryCode;
    final hasFlag =
        !location.automatic &&
        code != null &&
        FlagCode.fromCountryCode(code) != null;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: BrandColors.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: hasFlag
          ? CountryFlag.fromCountryCode(
              code,
              theme: const ImageTheme(
                width: _size,
                height: _size,
                shape: Circle(),
              ),
            )
          : Icon(
              location.bypass
                  ? LucideIcons.shield
                  : location.automatic
                  ? LucideIcons.zap
                  : LucideIcons.globe,
              size: 20,
              color: BrandColors.accent,
            ),
    );
  }
}
