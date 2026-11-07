import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/pigeon/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/com/launchvpn/app/pigeon/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: "com.launchvpn.app.pigeon"),
    swiftOut: 'swift/App/pigeon/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'onexray',
  ),
)
@HostApi()
abstract class BridgeHostApi {
  @asyncCallback
  String getTunFilesDir();

  @asyncCallback
  NativeVpnCommandResult readVpnStatus();

  @asyncCallback
  NativeVpnCommandResult startVpn();

  @asyncCallback
  NativeVpnCommandResult stopVpn();

  @asyncCallback
  String invoke(String requestJson);

  @asyncCallback
  DeviceIdentity getDeviceIdentity();

  //platform======================
  @asyncCallback
  PlatformPermissionResult queryPlatformPermission();

  @asyncCallback
  PlatformPermissionResult requestPlatformPermission();

  //android=======================

  @asyncCallback
  List<AndroidAppInfo> getInstalledApps();

  @asyncCallback
  Uint8List? getAppIcon(String packageName);

  //macOS======================
  @asyncCallback
  bool useSystemExtension();

  @asyncCallback
  AppleVpnCapabilities appleVpnCapabilities();

  @asyncCallback
  NativeLaunchAtLoginResult queryLaunchAtLogin();

  @asyncCallback
  NativeLaunchAtLoginResult setLaunchAtLogin(bool enabled);

  @asyncCallback
  bool openLaunchAtLoginSettings();

  //Apple app icon======================
  @asyncCallback
  bool setAppIcon(String appIcon);

  @asyncCallback
  String getCurrentAppIcon();
}

enum VpnStatus { disconnecting, disconnected, connecting, connected }

/// What the iOS Widget shows next to the status, as Home shows it.
class AppleWidgetContext {
  AppleWidgetContext({
    this.location,
    this.countryCode,
    required this.automatic,
    this.mode,
    this.expiresAtMs,
  });

  /// The chosen location's name, without the panel's flag and prefix.
  final String? location;

  /// ISO letters of the location's flag.
  final String? countryCode;
  final bool automatic;

  /// `ConnectionPreset.name`.
  final String? mode;

  /// When the subscription ends, in milliseconds since the epoch.
  final int? expiresAtMs;
}

@HostApi()
abstract class AppleWidgetHostApi {
  @asyncCallback
  String? takeAction();

  @asyncCallback
  void setLanguage(String languageCode);

  @asyncCallback
  void setContext(AppleWidgetContext context);
}

/// The iOS tunnel extension's memory, in bytes. iOS ends the extension, and
/// with it the VPN, once its footprint reaches [limit].
class TunnelMemory {
  TunnelMemory({
    required this.footprint,
    required this.peak,
    required this.limit,
  });
  final int footprint;

  /// The highest footprint since the tunnel started, spikes included.
  final int peak;
  final int limit;
}

/// What only testers see, in builds installed from TestFlight.
@HostApi()
abstract class TesterHostApi {
  @asyncCallback
  bool isTestFlight();

  /// Null while no tunnel runs.
  @asyncCallback
  TunnelMemory? readTunnelMemory();
}

/// How a run of the iOS tunnel extension ended.
class TunnelStop {
  TunnelStop({
    this.reason,
    required this.startedAtMs,
    required this.endedAtMs,
    this.memory,
  });

  /// `NEProviderStopReason`'s name, such as `noNetworkAvailable`. Null when
  /// the process ended without a stop: it crashed, or iOS ended it at its
  /// memory limit.
  final String? reason;

  /// In milliseconds since the epoch.
  final int startedAtMs;

  /// The stop, or without one the extension's last heartbeat, at most half a
  /// minute before it ended.
  final int endedAtMs;

  /// The last reading; its peak is the highest since the start.
  final TunnelMemory? memory;
}

/// The iOS tunnel extension's record of its runs, kept in the App Group.
@HostApi()
abstract class TunnelStopsHostApi {
  /// The runs that ended since the last call, each handed over once. A run
  /// that may still be going stays for a later call.
  @asyncCallback
  List<TunnelStop> takeTunnelStops();
}

class AndroidAutomationSettings {
  AndroidAutomationSettings({required this.enabled, this.token});
  final bool enabled;
  final String? token;
}

@HostApi()
abstract class AndroidAutomationHostApi {
  @asyncCallback
  AndroidAutomationSettings read();

  @asyncCallback
  AndroidAutomationSettings setEnabled(bool enabled);

  @asyncCallback
  AndroidAutomationSettings resetToken();

  @asyncCallback
  void setStartBlocked(bool blocked);

  @asyncCallback
  void clear();
}

class BackupLocation {
  BackupLocation({required this.identifier, required this.label});
  final String identifier;
  final String label;
}

@HostApi()
abstract class FileExportHostApi {
  @asyncCallback
  bool saveFile(String path, String name);
}

@HostApi()
abstract class BackupHostApi {
  @asyncCallback
  BackupLocation? selectBackupFile(bool create);

  @asyncCallback
  void requireBackupAccess(String identifier);

  @asyncCallback
  void releaseBackupFile(String identifier);
}

@HostApi()
abstract class AppleBackupHostApi {
  @asyncCallback
  bool hasBackupFileContents(String identifier);

  @asyncCallback
  Uint8List readBackupFile(String identifier);

  @asyncCallback
  void writeBackupFile(String identifier, Uint8List bytes);
}

/// What the app tells a subscription panel about this device.
class DeviceIdentity {
  DeviceIdentity({
    required this.hwid,
    required this.os,
    required this.osVersion,
    required this.model,
  });
  final String hwid;
  final String os;
  final String osVersion;
  final String model;
}

class AppleVpnCapabilities {
  AppleVpnCapabilities({
    required this.serviceExclusions,
    required this.deviceCommunication,
  });
  final bool serviceExclusions;
  final bool deviceCommunication;
}

enum PlatformPermissionKind {
  none,
  androidVpn,
  macosSystemExtension,
  appleVpn,
  androidLocalNetwork,
}

enum PlatformPermissionState {
  notRequired,
  notDetermined,
  awaitingUserApproval,
  granted,
  denied,
  failed,
}

enum NativeVpnCommandState { success, waitingForPlatformPermission, failed }

enum NativeLaunchAtLoginState {
  enabled,
  disabled,
  requiresApproval,
  unavailable,
  error,
}

class NativeLaunchAtLoginResult {
  NativeLaunchAtLoginResult({required this.state, this.message});

  final NativeLaunchAtLoginState state;
  final String? message;
}

class PlatformPermissionResult {
  PlatformPermissionResult({
    required this.kind,
    required this.state,
    this.message,
  });

  final PlatformPermissionKind kind;
  final PlatformPermissionState state;
  final String? message;
}

class NativeVpnCommandResult {
  NativeVpnCommandResult({
    required this.state,
    this.permission,
    this.message,
    this.status,
  });

  final NativeVpnCommandState state;
  // Successful status reads and commands supply the confirmed native status.
  // Failures and permission-waiting results may omit it.
  final VpnStatus? status;
  final PlatformPermissionResult? permission;
  final String? message;
}

class AndroidAppInfo {
  AndroidAppInfo({required this.name, required this.packageName});

  final String name;
  final String packageName;
}

@FlutterApi()
abstract class BridgeFlutterApi {
  @asyncCallback
  void appleWidgetActionAvailable();

  @asyncCallback
  void vpnStatusChanged(VpnStatus status);

  @asyncCallback
  void openSettings();
}
