import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/locations/page.dart';
import 'package:onexray/brand/mark.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/locations.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.controller});

  final HomeController? controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeController _controller = widget.controller ?? HomeController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (widget.controller == null) unawaited(_controller.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    await runConnectionAction(context, _controller.coordinator, action);
  }

  Future<void> _toggle() => _controller.toggle(_run);

  // Above the tab bar, as the mockup has it.
  Future<void> _openLocations() async {
    final chosen = await Navigator.of(context, rootNavigator: true)
        .push<Location>(
          MaterialPageRoute(
            builder: (_) => LocationsPage(controller: _controller),
          ),
        );
    if (chosen != null && mounted) {
      await _controller.selectLocation(chosen, _run);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: BrandTheme.statusBar,
    child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<HomeController, HomeState>(
          bloc: _controller,
          builder: (context, state) => CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BrandSpacing.page,
                    8,
                    BrandSpacing.page,
                    20,
                  ),
                  child: Column(
                    children: [
                      _Header(daysLeft: state.daysLeft(DateTime.now())),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: _Hero(state: state, onToggle: _toggle),
                          ),
                        ),
                      ),
                      if (state.location case final location?)
                        LocationCard(
                          key: const ValueKey('home-location'),
                          location: location,
                          // "No answer" would contradict a tunnel that works.
                          delay: PingDelayConstants.isSuccessful(location.delay)
                              ? locationDelayLabel(
                                  AppLocalizations.of(context)!,
                                  location,
                                )
                              : null,
                          onTap: _openLocations,
                          trailing: const Icon(
                            LucideIcons.chevronRight,
                            size: 20,
                            color: BrandColors.muted,
                          ),
                        ),
                      if (state.subscription != null) ...[
                        const SizedBox(height: 20),
                        _PresetSwitch(
                          selected: state.preset,
                          onSelect: state.canChangeConnection
                              ? (preset) =>
                                    _controller.selectPreset(preset, _run)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.daysLeft});

  final int? daysLeft;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // A logo keeps its size when the system font grows.
      const LaunchMark.logo(color: BrandColors.accent),
      const SizedBox(width: 8),
      const Text(
        Brand.wordmark,
        style: BrandText.wordmark,
        textScaler: TextScaler.noScaling,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: daysLeft == null ? null : _DaysPill(days: daysLeft!),
        ),
      ),
    ],
  );
}

class _DaysPill extends StatelessWidget {
  const _DaysPill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(BrandRadii.full),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.calendar, size: 14, color: BrandColors.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              days == 0 ? l.subscriptionPackageExpired : l.homeDaysLeft(days),
              style: BrandText.pill,
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state, required this.onToggle});

  final HomeState state;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final status = state.status;
    final title = switch (status) {
      HomeStatus.off || HomeStatus.failed => l.homeStatusOff,
      HomeStatus.connecting => l.homeStatusConnecting,
      HomeStatus.reconnecting => l.homeStatusReconnecting,
      HomeStatus.connected => l.homeStatusConnected,
      HomeStatus.disconnecting => l.homeStatusDisconnecting,
      HomeStatus.uncertain => l.homeStatusUncertain,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectToggle(
          key: const ValueKey('home-toggle'),
          label: title,
          state: switch (status) {
            HomeStatus.off || HomeStatus.failed => ConnectToggleState.off,
            HomeStatus.connected => ConnectToggleState.on,
            _ => ConnectToggleState.transitioning,
          },
          onPressed: state.canToggle ? onToggle : null,
        ),
        const SizedBox(height: 24),
        Text(title, textAlign: TextAlign.center, style: BrandText.screenTitle),
        const SizedBox(height: 6),
        _Hint(state: state),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Widget text(String value, {Color? color}) => Text(
      value,
      textAlign: TextAlign.center,
      style: BrandText.hint.copyWith(color: color),
    );
    return switch (state.status) {
      HomeStatus.off => text(
        state.subscription == null ? l.homeNoSubscription : l.homeHintOff,
      ),
      HomeStatus.failed => text(l.homeConnectFailed, color: BrandColors.danger),
      HomeStatus.connecting => text(l.homeHintConnecting),
      HomeStatus.reconnecting => text(l.homeHintReconnecting),
      HomeStatus.connected => _ConnectedHint(since: state.connectedSince),
      HomeStatus.disconnecting => const SizedBox.shrink(),
      HomeStatus.uncertain => text(l.homeHintUncertain),
    };
  }
}

/// Counts from the session's own start, so reopening the app keeps the time.
class _ConnectedHint extends StatefulWidget {
  const _ConnectedHint({required this.since});

  final DateTime? since;

  @override
  State<_ConnectedHint> createState() => _ConnectedHintState();
}

class _ConnectedHintState extends State<_ConnectedHint> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsed(DateTime since) {
    final elapsed = DateTime.now().difference(since);
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(elapsed.inHours)}:${pad(elapsed.inMinutes % 60)}:'
        '${pad(elapsed.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final since = widget.since;
    final hidden = AppLocalizations.of(context)!.homeIpHidden;
    return Text(
      since == null ? hidden : '${_elapsed(since)} · $hidden',
      textAlign: TextAlign.center,
      style: BrandText.timer,
    );
  }
}

class _PresetSwitch extends StatelessWidget {
  const _PresetSwitch({required this.selected, required this.onSelect});

  final TrafficMode? selected;
  final ValueChanged<TrafficMode>? onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    Widget segment(TrafficMode preset, String label) => Expanded(
      child: _PresetSegment(
        label: label,
        selected: preset == selected,
        onTap: onSelect == null ? null : () => onSelect!(preset),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(BrandRadii.control),
        border: Border.all(color: BrandColors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            segment(TrafficMode.smart, l.homePresetSmart),
            const SizedBox(width: 4),
            segment(TrafficMode.allVpn, l.homePresetAllVpn),
          ],
        ),
      ),
    );
  }
}

class _PresetSegment extends StatelessWidget {
  const _PresetSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    selected: selected,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 34),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? BrandColors.accentSoft : null,
            borderRadius: BorderRadius.circular(BrandRadii.segment),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: selected ? BrandText.selectedPreset : BrandText.preset,
          ),
        ),
      ),
    ),
  );
}
