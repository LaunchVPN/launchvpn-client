import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/ping/state.dart';

/// Opens an address through the tunnel. Returns how long the answer took in
/// milliseconds, or null when none came.
typedef ProbeTunnel = Future<int?> Function();

/// The network under the VPN, as the event about a silent server tells it.
enum NetworkKind { none, wifi, cellular, other }

/// The App's own traffic takes the tunnel on Android and iOS, so a request
/// from here goes the way the person's apps do, through routing and the
/// group's balancer. Any HTTP answer means the server got it through, so
/// the headers end the wait and the body is never read.
Future<int?> probeTunnel() async {
  const timeout = Duration(seconds: 4);
  final ping = PingState();
  try {
    await ping.readFromPreferences();
  } catch (error) {
    // The default address still tells whether the tunnel works.
    ygLogger('read ping settings failed (${error.runtimeType})');
  }
  final client = HttpClient()..connectionTimeout = timeout;
  final watch = Stopwatch()..start();
  try {
    return await () async {
      final request = await client.getUrl(Uri.parse(ping.realUrl));
      request.followRedirects = false;
      await request.close();
      return watch.elapsedMilliseconds;
    }().timeout(timeout);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Wi-Fi first, as a phone on Wi-Fi with mobile data on uses it.
Future<NetworkKind> readNetwork() async {
  try {
    final kinds = await Connectivity().checkConnectivity();
    if (kinds.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
    if (kinds.contains(ConnectivityResult.mobile)) return NetworkKind.cellular;
    if (kinds.every((kind) => kind == ConnectivityResult.none)) {
      return NetworkKind.none;
    }
    return NetworkKind.other;
  } catch (error) {
    ygLogger('read network failed (${error.runtimeType})');
    return NetworkKind.other;
  }
}
