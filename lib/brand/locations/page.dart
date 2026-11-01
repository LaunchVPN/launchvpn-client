import 'dart:async';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/servers/locations.dart';

/// Lists the panel's groups and pops with the one the user taps. Home applies
/// the choice, so a reconnect that outlives this screen still reports to it.
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
              const _TopBar(),
              Expanded(
                child: BlocBuilder<HomeController, HomeState>(
                  bloc: widget.controller,
                  builder: (context, state) {
                    Widget section(String title, Iterable<Location> items) =>
                        _Section(
                          title: title,
                          children: [
                            for (final item in items)
                              _LocationRow(
                                location: item,
                                selected: item.name == state.location?.name,
                                onTap: state.canChangeConnection
                                    ? () => Navigator.of(context).pop(item)
                                    : null,
                              ),
                          ],
                        );
                    return ListView(
                      padding: EdgeInsets.fromLTRB(
                        BrandSpacing.page,
                        0,
                        BrandSpacing.page,
                        MediaQuery.paddingOf(context).bottom + 20,
                      ),
                      children: [
                        if (state.locations.automatic.isNotEmpty)
                          section(
                            l.locationsAutomatic,
                            state.locations.automatic,
                          ),
                        if (state.locations.others.isNotEmpty)
                          section(l.locationsOthers, state.locations.others),
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

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BrandSpacing.page,
        8,
        BrandSpacing.page,
        16,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: MaterialLocalizations.of(context).backButtonTooltip,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BrandColors.surface,
                  borderRadius: BorderRadius.circular(BrandRadii.iconButton),
                ),
                child: const Icon(
                  LucideIcons.chevronLeft,
                  size: 20,
                  color: BrandColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l.locationsTitle, style: BrandText.topBar)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 8),
        child: Text(title.toUpperCase(), style: BrandText.sectionLabel),
      ),
      for (final child in children)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
    ],
  );
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.location,
    required this.selected,
    required this.onTap,
  });

  final Location location;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final delay = locationDelayLabel(AppLocalizations.of(context)!, location);
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: selected,
      label: delay == null ? location.name : '${location.name}, $delay',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: onTap == null && !selected ? 0.5 : 1,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
              decoration: BoxDecoration(
                color: selected ? BrandColors.accentSoft : BrandColors.surface,
                borderRadius: BorderRadius.circular(BrandRadii.card),
                border: Border.all(
                  color: selected ? BrandColors.accent : BrandColors.line,
                ),
              ),
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
                          Text(delay, style: BrandText.caption),
                      ],
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 12),
                    const Icon(
                      LucideIcons.check,
                      size: 18,
                      color: BrandColors.accent,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Null until a location has been measured.
String? locationDelayLabel(AppLocalizations l, Location location) {
  if (location.delay == PingDelayConstants.unknown) return null;
  return PingDelayConstants.isSuccessful(location.delay)
      ? l.locationsDelay(location.delay)
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
