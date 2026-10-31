import 'package:onexray/core/pigeon/messages.g.dart';

final class DownloadRequestHeaders {
  const DownloadRequestHeaders({
    this.agePublicKey,
    this.device,
    this.userAgent,
  });

  /// Headers that identify this device, sent only to the subscription origin.
  static const deviceHeaderNames = [
    'x-hwid',
    'x-device-os',
    'x-ver-os',
    'x-device-model',
  ];

  final String? agePublicKey;
  final DeviceIdentity? device;
  final String? userAgent;

  static bool isValidUserAgent(String? value) =>
      value == null ||
      value.codeUnits.every((code) => code >= 0x20 && code <= 0x7e);

  Map<String, String>? toHttpHeaders() {
    final publicKey = agePublicKey?.trim();
    final agent = userAgent?.trim();
    final identity = device;
    final headers = <String, String>{
      if (agent != null && agent.isNotEmpty) 'User-Agent': agent,
      if (publicKey != null && publicKey.isNotEmpty)
        'X-Age-Public-Key': publicKey,
      if (identity != null) ..._deviceHeaders(identity),
    };
    return headers.isEmpty ? null : headers;
  }

  // The panel only needs the HWID. Details are display text for its device
  // list, so one a header cannot carry must not fail the download.
  static Map<String, String> _deviceHeaders(DeviceIdentity identity) {
    bool sendable(String value) => value.isNotEmpty && isValidUserAgent(value);
    return {
      'x-hwid': identity.hwid,
      if (sendable(identity.os)) 'x-device-os': identity.os,
      if (sendable(identity.osVersion)) 'x-ver-os': identity.osVersion,
      if (sendable(identity.model)) 'x-device-model': identity.model,
    };
  }
}
