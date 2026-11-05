import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/account/failure.dart';

/// This device as account requests name it: the HWID the panel counts and
/// the platform.
final class DeviceClaim {
  const DeviceClaim._({required this.hwid, required this.platform, this.model});

  final String hwid;

  /// `android` or `ios`.
  final String platform;

  /// Null when the system names none.
  final String? model;

  /// The `hwid` and `platform` fields of a sign-in body.
  Map<String, Object?> toJson() => {'hwid': hwid, 'platform': platform};

  /// Reads this device through [readDevice]. Throws
  /// [AccountError.unexpected] when it cannot.
  static Future<DeviceClaim> read(
    Future<DeviceIdentity?> Function() readDevice,
  ) async {
    try {
      if (await readDevice() case final device?) {
        return DeviceClaim._(
          hwid: device.hwid,
          platform: device.os.toLowerCase(),
          model: device.model.isEmpty ? null : device.model,
        );
      }
    } catch (error) {
      ygLogger('read device identity failed (${error.runtimeType})');
    }
    throw const AccountException(AccountError.unexpected);
  }
}
