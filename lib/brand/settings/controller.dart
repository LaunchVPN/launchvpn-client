import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/launch/app_startup.dart';

class SettingsState {
  const SettingsState({this.connectOnLaunch});

  /// Null until the saved value is read.
  final bool? connectOnLaunch;
}

class SettingsController extends PageCubit<SettingsState> {
  SettingsController() : super(const SettingsState());

  bool _saving = false;

  Future<void> initialize() async {
    try {
      final value = await AppStartupService().readConnectOnAppLaunch();
      emit(SettingsState(connectOnLaunch: value));
    } catch (error) {
      ygLogger('read connect at launch failed (${error.runtimeType})');
      // What the launch itself assumes, and the row stays usable.
      emit(const SettingsState(connectOnLaunch: false));
    }
  }

  /// A failed save puts the switch back. Taps during a save are ignored, so an
  /// older save can neither overwrite a newer one nor undo it.
  Future<void> setConnectOnLaunch(bool value) async {
    if (_saving) return;
    _saving = true;
    final previous = state.connectOnLaunch;
    emit(SettingsState(connectOnLaunch: value));
    try {
      await AppStartupService().saveConnectOnAppLaunch(value);
    } catch (error) {
      ygLogger('save connect at launch failed (${error.runtimeType})');
      emit(SettingsState(connectOnLaunch: previous));
    } finally {
      _saving = false;
    }
  }
}
