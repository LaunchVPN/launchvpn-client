import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/core/tools/platform.dart';

/// The iOS tunnel extension's memory. iOS ends the extension, and with it the
/// VPN, at a hard limit, so testers watch how close it runs. Only TestFlight
/// builds show it; App Store installs of the same binary never ask.
final class TunnelMemoryService {
  TunnelMemoryService({required this._isTestFlight, required this._read});

  static final instance = _platform();

  static TunnelMemoryService _platform() {
    if (!AppPlatform.isIOS) {
      return TunnelMemoryService(
        isTestFlight: () async => false,
        read: () async => null,
      );
    }
    final api = TesterHostApi();
    return TunnelMemoryService(
      isTestFlight: api.isTestFlight,
      read: api.readTunnelMemory,
    );
  }

  final Future<bool> Function() _isTestFlight;
  final Future<TunnelMemory?> Function() _read;
  Future<bool>? _testFlight;

  /// Whether this is an install from TestFlight, the only builds that show
  /// the memory. Asked once per launch.
  Future<bool> get isTestFlight =>
      _testFlight ??= _isTestFlight().catchError((Object error) {
        ygLogger('read TestFlight failed (${error.runtimeType})');
        return false;
      });

  /// Null while no tunnel runs or when the extension does not answer.
  Future<TunnelMemory?> read() async {
    try {
      return await _read();
    } catch (error) {
      ygLogger('read tunnel memory failed (${error.runtimeType})');
      return null;
    }
  }
}
