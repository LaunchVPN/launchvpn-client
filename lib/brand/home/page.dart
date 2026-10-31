import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/home/toggle.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/connection_action.dart';

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

  Future<void> _toggle() => _controller.toggle((action) async {
    await runConnectionAction(context, _controller.coordinator, action);
  });

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
                        _LocationCard(name: location),
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
        'launchvpn',
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
      style: BrandText.hint.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 72),
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
    decoration: BoxDecoration(
      color: BrandColors.surface,
      borderRadius: BorderRadius.circular(BrandRadii.card),
      border: Border.all(color: BrandColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: BrandColors.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.zap,
            size: 20,
            color: BrandColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: BrandText.cardTitle)),
      ],
    ),
  );
}
