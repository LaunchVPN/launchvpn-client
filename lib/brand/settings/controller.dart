import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/crash_reports/service.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';
import 'package:onexray/service/shared/event_bus/enum.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsState {
  const SettingsState({
    this.connectOnLaunch,
    this.renewalReminders,
    this.crashReports,
    this.app,
  });

  /// Null until the saved value is read.
  final bool? connectOnLaunch;

  /// Null until read. On only while reminders work: the setting is on and the
  /// system allows notifications.
  final bool? renewalReminders;

  /// Null until the saved value is read.
  final bool? crashReports;

  /// The installed version and build. Null until read.
  final PackageInfo? app;

  SettingsState copyWith({
    bool? connectOnLaunch,
    bool? renewalReminders,
    bool? crashReports,
    PackageInfo? app,
  }) => SettingsState(
    connectOnLaunch: connectOnLaunch ?? this.connectOnLaunch,
    renewalReminders: renewalReminders ?? this.renewalReminders,
    crashReports: crashReports ?? this.crashReports,
    app: app ?? this.app,
  );
}

class SettingsController extends PageCubit<SettingsState> {
  SettingsController({RenewalReminders? reminders, CrashReports? crashReports})
    : _reminders = reminders ?? RenewalReminders.instance,
      _crashReports = crashReports ?? CrashReports.instance,
      super(const SettingsState());

  final RenewalReminders _reminders;
  final CrashReports _crashReports;
  bool _savingLaunch = false;
  bool _savingReminders = false;
  bool _savingCrashReports = false;
  Future<void> _languageSaves = Future.value();

  Future<void> initialize() async {
    try {
      emit(state.copyWith(app: await PackageInfo.fromPlatform()));
    } catch (error) {
      ygLogger('read app version failed (${error.runtimeType})');
    }
    try {
      final value = await AppStartupService().readConnectOnAppLaunch();
      emit(state.copyWith(connectOnLaunch: value));
    } catch (error) {
      ygLogger('read connect at launch failed (${error.runtimeType})');
      // What the launch itself assumes, and the row stays usable.
      emit(state.copyWith(connectOnLaunch: false));
    }
    await readRenewalReminders();
    try {
      emit(state.copyWith(crashReports: await _crashReports.enabled));
    } catch (error) {
      ygLogger('read crash reports failed (${error.runtimeType})');
      // What the launch assumes when the value is unreadable.
      emit(state.copyWith(crashReports: true));
    }
  }

  /// A failed save puts the switch back. Taps during a save are ignored, so an
  /// older save can neither overwrite a newer one nor undo it.
  Future<void> setConnectOnLaunch(bool value) async {
    if (_savingLaunch) return;
    _savingLaunch = true;
    final previous = state.connectOnLaunch;
    emit(state.copyWith(connectOnLaunch: value));
    try {
      await AppStartupService().saveConnectOnAppLaunch(value);
    } catch (error) {
      ygLogger('save connect at launch failed (${error.runtimeType})');
      emit(state.copyWith(connectOnLaunch: previous));
    } finally {
      _savingLaunch = false;
    }
  }

  /// Every screen switches at once. Reminders already set are rewritten in
  /// the new language. Each tap waits for the save before it, so the last
  /// one wins.
  Future<void> setLanguage(LanguageCode value) =>
      _languageSaves = _languageSaves.then((_) => _saveLanguage(value));

  Future<void> _saveLanguage(LanguageCode value) async {
    if (value == AppEventBus.instance.state.languageCode) return;
    try {
      await AppEventBus.instance.updateLanguageCode(value);
    } catch (error) {
      ygLogger('save language failed (${error.runtimeType})');
      return;
    }
    await _reminders.update();
  }

  /// Read again when the App returns, since the system settings may have
  /// allowed or blocked notifications meanwhile.
  Future<void> readRenewalReminders() async {
    try {
      final active = await _reminders.active;
      if (!isClosed) emit(state.copyWith(renewalReminders: active));
    } catch (error) {
      ygLogger('read renewal reminders failed (${error.runtimeType})');
      if (!isClosed) emit(state.copyWith(renewalReminders: false));
    }
  }

  /// Turning reminders on may end in the system settings, so the switch turns
  /// on only once they work; turning them off shows at once.
  Future<void> setRenewalReminders(bool value) async {
    if (_savingReminders) return;
    _savingReminders = true;
    if (!value) emit(state.copyWith(renewalReminders: false));
    try {
      if (value) {
        await _reminders.enable();
      } else {
        await _reminders.disable();
      }
    } catch (error) {
      ygLogger('save renewal reminders failed (${error.runtimeType})');
    } finally {
      _savingReminders = false;
    }
    await readRenewalReminders();
  }

  /// Off stops sending at once; on starts it at once. A failed save puts the
  /// switch back, and taps during a save are ignored.
  Future<void> setCrashReports(bool value) async {
    if (_savingCrashReports) return;
    _savingCrashReports = true;
    final previous = state.crashReports;
    emit(state.copyWith(crashReports: value));
    try {
      await _crashReports.setEnabled(value);
    } catch (error) {
      ygLogger('save crash reports failed (${error.runtimeType})');
      if (!isClosed) emit(state.copyWith(crashReports: previous));
    } finally {
      _savingCrashReports = false;
    }
  }
}
