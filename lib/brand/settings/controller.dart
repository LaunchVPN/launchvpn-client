import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/launch/app_startup.dart';
import 'package:onexray/service/servers/subscription/renewal_reminders.dart';

class SettingsState {
  const SettingsState({this.connectOnLaunch, this.renewalReminders});

  /// Null until the saved value is read.
  final bool? connectOnLaunch;

  /// Null until read. On only while reminders work: the setting is on and the
  /// system allows notifications.
  final bool? renewalReminders;

  SettingsState copyWith({bool? connectOnLaunch, bool? renewalReminders}) =>
      SettingsState(
        connectOnLaunch: connectOnLaunch ?? this.connectOnLaunch,
        renewalReminders: renewalReminders ?? this.renewalReminders,
      );
}

class SettingsController extends PageCubit<SettingsState> {
  SettingsController({RenewalReminders? reminders})
    : _reminders = reminders ?? RenewalReminders.instance,
      super(const SettingsState());

  final RenewalReminders _reminders;
  bool _savingLaunch = false;
  bool _savingReminders = false;

  Future<void> initialize() async {
    try {
      final value = await AppStartupService().readConnectOnAppLaunch();
      emit(state.copyWith(connectOnLaunch: value));
    } catch (error) {
      ygLogger('read connect at launch failed (${error.runtimeType})');
      // What the launch itself assumes, and the row stays usable.
      emit(state.copyWith(connectOnLaunch: false));
    }
    await readRenewalReminders();
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

  /// Turning reminders on may end in the system settings; the switch then
  /// stays off until notifications are allowed there.
  Future<void> setRenewalReminders(bool value) async {
    if (_savingReminders) return;
    _savingReminders = true;
    emit(state.copyWith(renewalReminders: value));
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
}
