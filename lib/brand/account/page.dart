import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/account/controller.dart';
import 'package:onexray/brand/account/devices.dart';
import 'package:onexray/brand/external_link.dart';
import 'package:onexray/brand/login/controller.dart';
import 'package:onexray/brand/login/page.dart';
import 'package:onexray/brand/settings/row.dart';
import 'package:onexray/brand/sheet.dart';
import 'package:onexray/brand/state_hero.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/brand/toast.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/distribution.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/service/account/failure.dart';
import 'package:onexray/service/account/model.dart';
import 'package:onexray/service/account/service.dart';

/// «Аккаунт»: days and traffic for everyone; the devices, the account,
/// «Выйти» and «Удалить аккаунт» once signed in, «Войти» and «Создать
/// аккаунт» otherwise.
class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.controller,
    required this.account,
    required this.openLink,
    this.distribution = AppDistribution.current,
  });

  final AccountController controller;

  /// For «Вход», which «Войти» opens over the tabs.
  final AccountService account;
  final void Function(Uri) openLink;

  /// Only an APK build renews on the site: a store takes no payment outside
  /// its own.
  final AppDistribution distribution;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  AccountController get _controller => widget.controller;
  bool _visible = false;

  /// The tabs keep this page alive, muting its tickers while another tab is
  /// shown, so the ticker mode turning on is the tab opening.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      unawaited(_controller.refresh());
      WidgetsBinding.instance.addPostFrameCallback((_) => _tellResumedLink());
    }
    _visible = visible;
  }

  Future<void> _openLogin(LoginMode mode) => LoginPage.showOverTabs(
    context,
    account: widget.account,
    openLink: widget.openLink,
    mode: mode,
    signedIn: _controller.stream.map((state) => state.signedIn),
  );

  Future<void> _logout() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.accountLogoutTitle,
      body: l.accountLogoutBody,
      action: l.accountLogout,
    );
    if (confirmed) await _controller.logout();
  }

  /// Deletes the account once confirmed; one that stays says so. A session
  /// already gone leads to «Вход»: the gate's, or over the tabs a
  /// subscription from a link keeps.
  Future<void> _deleteAccount() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await ConfirmSheet.show(
      context,
      title: l.accountDeleteTitle,
      body: l.accountDeleteBody,
      action: l.accountDelete,
    );
    if (!confirmed) return;
    final deletion = await _controller.deleteAccount();
    if (!mounted) return;
    switch (deletion) {
      case AccountDeletion.deleted:
        break;
      case AccountDeletion.signInAgain:
        if (_controller.state.subscription != null) {
          await _openLogin(LoginMode.signIn);
        }
      case AccountDeletion.failed:
        ContextAlert.showToast(context, l.accountDeleteFailed);
    }
  }

  Future<void> _linkTelegram() async {
    final outcome = await _controller.linkTelegram();
    if (mounted) await _tellLink(outcome);
  }

  /// Tells, once the tab shows, how a link the system closed the App during
  /// ended.
  void _tellResumedLink() {
    final outcome = _controller.state.resumedLink;
    if (!mounted || !_visible || outcome == null) return;
    _controller.resumedLinkShown();
    unawaited(_tellLink(outcome));
  }

  /// Tells how «Привязать Telegram» ended; turning Telegram down says nothing.
  Future<void> _tellLink(TelegramLinkOutcome outcome) async {
    final l = AppLocalizations.of(context)!;
    switch (outcome) {
      case TelegramLinked(:final addedDays):
        showReadingToast(
          context,
          addedDays > 0
              ? l.accountTelegramLinkedDays(addedDays)
              : l.accountTelegramLinked,
        );
      case TelegramLinkFailed(error: AccountError.cancelled):
        break;
      case TelegramLinkFailed(error: AccountError.telegramTaken):
        await NoticeSheet.show(
          context,
          title: l.accountTelegramTakenTitle,
          body: l.accountTelegramTakenBody,
          action: l.accountTelegramTakenOk,
        );
      case TelegramLinkFailed():
        ContextAlert.showToast(context, l.accountLinkTelegramFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: BrandTheme.statusBar,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: BlocConsumer<AccountController, AccountState>(
            bloc: _controller,
            listenWhen: (previous, current) =>
                current.resumedLink != null &&
                current.resumedLink != previous.resumedLink,
            listener: (_, _) => _tellResumedLink(),
            builder: (context, state) {
              final devices = state.devices;
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  BrandSpacing.page,
                  8,
                  BrandSpacing.page,
                  BrandSpacing.page,
                ),
                children: [
                  Text(l.accountTab, style: BrandText.screenTitle),
                  ..._subscription(l, state),
                  // From a link too: the cabinet renews any subscription.
                  if ((state.signedIn || state.subscription != null) &&
                      widget.distribution == AppDistribution.apk) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: BrandTheme.primaryButton,
                      onPressed: () => openExternalLink(
                        Uri.parse(Brand.renewalUrl),
                        'renewal',
                      ),
                      icon: const Icon(LucideIcons.externalLink),
                      label: Text(l.accountRenew),
                    ),
                  ],
                  if (!state.signedIn) ...[
                    const SizedBox(height: 20),
                    FilledButton(
                      style: BrandTheme.primaryButton,
                      onPressed: () => _openLogin(LoginMode.signIn),
                      child: Text(l.loginSubmit),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      style: BrandTheme.secondaryButton,
                      onPressed: () => _openLogin(LoginMode.create),
                      child: Text(l.loginCreate),
                    ),
                  ],
                  if (devices != null && devices.items.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    SettingsSectionLabel(switch (state.deviceLimit) {
                      final max? => l.accountDevices(devices.items.length, max),
                      null => l.accountDevicesUnlimited(devices.items.length),
                    }),
                    AccountDeviceCard(
                      controller: _controller,
                      devices: devices.items,
                    ),
                  ],
                  const SizedBox(height: 16),
                  SettingsCard(children: _details(l, state)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Days and traffic, or the ended subscription as Home tells it.
  List<Widget> _subscription(AppLocalizations l, AccountState state) {
    final now = DateTime.now();
    final usage = state.usage;
    if ((state.signedIn && state.inactive) ||
        (usage?.isExpired(now) ?? false)) {
      return [
        const SizedBox(height: 24),
        StateHero.warning(
          icon: LucideIcons.calendar,
          title: l.homeExpiredTitle,
          body: l.homeExpiredBody,
        ),
      ];
    }
    if (usage == null) return const [];
    final locale = l.localeName;
    final days = usage.daysLeft(now);
    final expiresAt = usage.expiresAt;
    final used = usage.usedBytes;
    final total = usage.totalBytes;
    return [
      if (days != null && expiresAt != null) ...[
        const SizedBox(height: 16),
        Text(l.homeDaysLeft(days), style: BrandText.days),
        const SizedBox(height: 4),
        Text(
          l.accountUntil(
            DateFormat('d MMMM y', locale).format(expiresAt.toLocal()),
          ),
          style: BrandText.hint,
        ),
      ],
      if (used != null) ...[
        if (!usage.unlimited && total != null) ...[
          const SizedBox(height: 16),
          _TrafficBar(used: used, total: total),
        ],
        const SizedBox(height: 12),
        Text(
          usage.unlimited || total == null
              ? l.accountTrafficUnlimited(_bytes(l, used))
              : l.accountTrafficLimited(_bytes(l, used), _bytes(l, total)),
          style: BrandText.caption,
        ),
      ],
    ];
  }

  /// Support for everyone, the panel's or the bot's; signed in, also the
  /// account, «Привязать Telegram», «Выйти» and «Удалить аккаунт».
  List<Widget> _details(AppLocalizations l, AccountState state) {
    final details = state.details;
    final support = state.subscription?.supportUrl ?? Brand.supportUrl;
    return [
      ?switch (details) {
        AccountDetails(:final email?, :final telegramLinked) => SettingsRow(
          icon: LucideIcons.user,
          title: email,
          subtitle: telegramLinked
              ? l.accountTelegramLinked
              : l.accountEmailSignIn,
          onTap: null,
        ),
        AccountDetails() => SettingsRow(
          icon: LucideIcons.send,
          title: l.accountTelegram,
          subtitle: l.accountTelegramSignIn,
          onTap: null,
        ),
        null => null,
      },
      if (state.signedIn && details != null && !details.telegramLinked)
        SettingsRow(
          icon: LucideIcons.send,
          title: l.accountLinkTelegram,
          subtitle: l.accountLinkTelegramHint,
          onTap: state.linkingTelegram ? null : _linkTelegram,
          trailing: state.linkingTelegram
              ? const ButtonProgressIndicator(size: 20)
              : const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: BrandColors.muted,
                ),
        ),
      SettingsLinkRow(
        icon: LucideIcons.messageCircle,
        title: l.accountSupport,
        value: null,
        onTap: () => openExternalLink(Uri.parse(support), 'support'),
      ),
      if (state.signedIn)
        SettingsRow(
          key: const ValueKey('account-logout'),
          icon: LucideIcons.logOut,
          title: l.accountLogout,
          color: BrandColors.danger,
          onTap: _logout,
        ),
      if (state.signedIn)
        SettingsRow(
          key: const ValueKey('account-delete'),
          title: l.accountDelete,
          color: BrandColors.danger,
          onTap: state.deletingAccount ? null : _deleteAccount,
          trailing: state.deletingAccount
              ? const ButtonProgressIndicator(size: 20)
              : null,
        ),
    ];
  }
}

/// [bytes] in the largest binary unit that keeps it at or above one.
String _bytes(AppLocalizations l, int bytes) {
  const units = ['b', 'kb', 'mb', 'gb', 'tb'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final number = NumberFormat(unit == 0 ? '0' : '0.#', l.localeName);
  return l.accountBytes(number.format(value), units[unit]);
}

/// How much of a limited plan the period used.
class _TrafficBar extends StatelessWidget {
  const _TrafficBar({required this.used, required this.total});

  final int used;
  final int total;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(BrandRadii.full),
    child: LinearProgressIndicator(
      value: total == 0 ? 0 : (used / total).clamp(0, 1).toDouble(),
      minHeight: 4,
      color: BrandColors.accent,
      backgroundColor: BrandColors.line,
    ),
  );
}
