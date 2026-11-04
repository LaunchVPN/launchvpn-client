import 'package:collection/collection.dart';
import 'package:onexray/brand/home/controller.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/pages/shared/page_cubit.dart';

class VpnAppsState {
  const VpnAppsState({
    required this.chosen,
    this.apps,
    this.failed = false,
    this.query = '',
    this.listedFirst = const {},
  });

  /// Null until the list arrives.
  final List<AndroidAppInfo>? apps;
  final bool failed;
  final String query;
  final Set<String> chosen;

  /// The apps chosen when the list arrived. They stay on top while the person
  /// switches them, so a row does not jump away from the finger.
  final Set<String> listedFirst;

  VpnAppsState copyWith({
    List<AndroidAppInfo>? apps,
    bool? failed,
    String? query,
    Set<String>? chosen,
    Set<String>? listedFirst,
  }) => VpnAppsState(
    apps: apps ?? this.apps,
    failed: failed ?? this.failed,
    query: query ?? this.query,
    chosen: chosen ?? this.chosen,
    listedFirst: listedFirst ?? this.listedFirst,
  );

  List<AndroidAppInfo> get first => _shown(listedFirst.contains);

  List<AndroidAppInfo> get others => _shown((id) => !listedFirst.contains(id));

  List<AndroidAppInfo> _shown(bool Function(String id) inGroup) => [
    for (final app in apps ?? const <AndroidAppInfo>[])
      if (inGroup(app.packageName) &&
          app.name.toLowerCase().contains(query.toLowerCase()))
        app,
  ];

  /// What the screen saves, in the list's order. Null while the list is
  /// unknown, since then nothing was changed.
  List<String>? get result => apps == null
      ? null
      : [
          for (final app in apps!)
            if (chosen.contains(app.packageName)) app.packageName,
        ];
}

/// «Приложения через VPN»: installed apps by name, the chosen ones on top.
class VpnAppsController extends PageCubit<VpnAppsState> {
  VpnAppsController({required List<String> chosen, required this._load})
    : super(VpnAppsState(chosen: chosen.toSet()));

  final InstalledApps _load;

  /// An app that is gone drops out of the choice. The App itself is left
  /// out, since its own traffic never enters its tunnel. No apps at all means
  /// the system refused the list, which must not clear the choice.
  Future<void> load() async {
    emit(state.copyWith(failed: false));
    try {
      final installed = await _load();
      if (installed.isEmpty) throw StateError('no installed apps');
      final apps = installed
          .where((app) => app.packageName != Brand.androidId)
          .sortedBy((app) => app.name.toLowerCase());
      if (isClosed) return;
      final chosen = state.chosen.intersection({
        for (final app in apps) app.packageName,
      });
      emit(state.copyWith(apps: apps, chosen: chosen, listedFirst: chosen));
    } catch (error) {
      ygLogger('read installed apps failed (${error.runtimeType})');
      if (!isClosed) emit(state.copyWith(failed: true));
    }
  }

  void search(String query) => emit(state.copyWith(query: query.trim()));

  void toggle(String id) {
    final chosen = {...state.chosen};
    if (!chosen.remove(id)) chosen.add(id);
    emit(state.copyWith(chosen: chosen));
  }
}
