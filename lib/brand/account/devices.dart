import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/sheet.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/service/account/model.dart';

/// The devices on the account's subscription as rows of one card. Another
/// device opens the removal sheet; this one cannot be removed from here.
class AccountDeviceCard extends StatelessWidget {
  const AccountDeviceCard({
    super.key,
    required this.controller,
    required this.devices,
    this.removeIcon = LucideIcons.chevronRight,
  });

  final AccountController controller;
  final List<AccountDevice> devices;

  /// «Аккаунт» leads to the sheet with a chevron, «Лимит устройств» with a
  /// trash icon.
  final IconData removeIcon;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    return SettingsCard(
      children: [
        for (final device in devices)
          SettingsRow(
            key: ValueKey('device-${device.hwid}'),
            icon: LucideIcons.smartphone,
            title: _name(l, device),
            subtitle: _details(
              device,
              device.current ? l.accountThisDevice : _seen(l, device, now),
            ),
            onTap: device.current
                ? null
                : () => _confirmRemoval(context, controller, device),
            trailing: device.current
                ? null
                : Icon(removeIcon, size: 18, color: BrandColors.muted),
          ),
      ],
    );
  }
}

/// Asks in a sheet, then removes [device]. A toast tells how it went.
Future<void> _confirmRemoval(
  BuildContext context,
  AccountController controller,
  AccountDevice device,
) async {
  final l = AppLocalizations.of(context)!;
  final name = _name(l, device);
  final online = switch (_seen(l, device, DateTime.now())) {
    final seen? => l.accountDeviceOnline(seen),
    null => null,
  };
  final confirmed = await ConfirmSheet.show(
    context,
    title: name,
    body: l.accountDeviceSheetBody(_details(device, online) ?? name),
    action: l.accountDeviceRemove,
  );
  if (!confirmed || !context.mounted) return;
  final removed = await controller.removeDevice(device);
  if (!context.mounted) return;
  showBrandToast(
    context,
    removed ? l.accountDeviceRemoved(name) : l.accountDeviceRemoveFailed,
    kind: removed ? ToastKind.success : ToastKind.error,
  );
}

String _name(AppLocalizations l, AccountDevice device) =>
    device.model ?? device.platform ?? l.accountDevice;

/// «Android 16 · [tail]», with whatever of it is known.
String? _details(AccountDevice device, String? tail) {
  final system = [?device.platform, ?device.osVersion].join(' ');
  final parts = [if (system.isNotEmpty) system, ?tail];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// When the device last loaded the subscription, in days, weeks or months.
String? _seen(AppLocalizations l, AccountDevice device, DateTime now) {
  final seen = device.lastSeen;
  if (seen == null) return null;
  final days = now.difference(seen).inDays;
  if (days < 1) return l.accountSeenToday;
  if (days < 7) return l.accountSeenDays(days);
  if (days < 30) return l.accountSeenWeeks(days ~/ 7);
  return l.accountSeenMonths(days ~/ 30);
}
