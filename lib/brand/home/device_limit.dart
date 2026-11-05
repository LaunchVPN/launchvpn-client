import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/devices.dart';
import 'package:onexray/brand/state_hero.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/account/model.dart';

/// «Лимит устройств»: why this phone cannot connect. Signed in, it counts the
/// account's devices; from a link only, support is the way out.
class DeviceLimitHero extends StatelessWidget {
  const DeviceLimitHero({super.key, required this.account});

  final AccountController account;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return BlocBuilder<AccountController, AccountState>(
      bloc: account,
      builder: (context, state) => StateHero.warning(
        icon: LucideIcons.smartphone,
        title: l.homeDeviceLimitTitle,
        body: switch ((state.signedIn, state.devices, state.deviceLimit)) {
          (false, _, _) => l.homeDeviceLimitBodyLinkOnly,
          (true, AccountDevices(:final items), final max?) =>
            l.homeDeviceLimitBody(items.length, max),
          (true, _, _) => l.homeDeviceLimitBodyAccount,
        },
      ),
    );
  }
}

/// Below the hero: signed in, the other devices to remove and «Обновить»;
/// [support] for everyone whose panel sent a support link.
class DeviceLimitActions extends StatefulWidget {
  const DeviceLimitActions({super.key, required this.account, this.support});

  final AccountController account;
  final Widget? support;

  @override
  State<DeviceLimitActions> createState() => _DeviceLimitActionsState();
}

class _DeviceLimitActionsState extends State<DeviceLimitActions> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.account.loadDevices());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return BlocBuilder<AccountController, AccountState>(
      bloc: widget.account,
      builder: (context, state) {
        final others = [
          for (final device in state.devices?.items ?? const <AccountDevice>[])
            if (!device.current) device,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            if (state.signedIn) ...[
              if (others.isNotEmpty)
                AccountDeviceCard(
                  controller: widget.account,
                  devices: others,
                  removeIcon: LucideIcons.trash2,
                ),
              FilledButton.icon(
                style: BrandTheme.secondaryButton,
                onPressed: state.refreshing ? null : widget.account.refresh,
                icon: state.refreshing
                    ? const ButtonProgressIndicator(size: 20)
                    : const Icon(LucideIcons.refreshCw),
                label: Text(l.homeDeviceLimitRefresh),
              ),
            ],
            ?widget.support,
          ],
        );
      },
    );
  }
}
