import 'package:onexray/core/pigeon/messages.g.dart';

final class DownloadRequestHeaders {
  const DownloadRequestHeaders({
    this.agePublicKey,
    this.device,
    this.userAgent,
  });

  static const _hwidHeader = 'x-hwid';
  static const _osHeader = 'x-device-os';
  static const _osVersionHeader = 'x-ver-os';
  static const _modelHeader = 'x-device-model';

  final String? agePublicKey;
  final DeviceIdentity? device;
  final String? userAgent;

  static bool isValidUserAgent(String? value) =>
      value == null || _isPrintableAscii(value);

  static bool _isPrintableAscii(String value) =>
      value.codeUnits.every((code) => code >= 0x20 && code <= 0x7e);

  /// The identity belongs to the subscription origin, not a redirect target.
  static void removeDeviceHeaders(Map<String, String> headers) {
    for (final name in const [
      _hwidHeader,
      _osHeader,
      _osVersionHeader,
      _modelHeader,
    ]) {
      headers.remove(name);
    }
  }

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
    bool sendable(String value) => value.isNotEmpty && _isPrintableAscii(value);
    return {
      _hwidHeader: identity.hwid,
      if (sendable(identity.os)) _osHeader: identity.os,
      if (sendable(identity.osVersion)) _osVersionHeader: identity.osVersion,
      if (sendable(identity.model)) _modelHeader: identity.model,
    };
  }
}
