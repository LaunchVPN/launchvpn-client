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

  Future<void> initialize() async {
    try {
      final value = await AppStartupService().readConnectOnAppLaunch();
      emit(SettingsState(connectOnLaunch: value));
    } catch (error) {
      ygLogger('read connect at launch failed (${error.runtimeType})');
    }
  }

  /// A failed save puts the switch back.
  Future<void> setConnectOnLaunch(bool value) async {
    final previous = state.connectOnLaunch;
    emit(SettingsState(connectOnLaunch: value));
    try {
      await AppStartupService().saveConnectOnAppLaunch(value);
    } catch (error) {
      ygLogger('save connect at launch failed (${error.runtimeType})');
      emit(SettingsState(connectOnLaunch: previous));
    }
  }
}
