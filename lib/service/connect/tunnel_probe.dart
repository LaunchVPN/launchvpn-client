import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/ping/state.dart';

/// Opens an address through the tunnel. Returns the delay in milliseconds as
/// «Локации» measures it, or null when no answer came.
typedef ProbeTunnel = Future<int?> Function();

/// The network under the VPN, as the event about a silent server tells it.
enum NetworkKind { none, wifi, cellular, other }

/// The App's own traffic takes the tunnel on Android and iOS, so a request
/// from here goes the way the person's apps do, through routing and the
/// group's balancer. Any HTTP answer means the server got it through.
Future<int?> probeTunnel() async {
  final ping = PingState();
  try {
    await ping.readFromPreferences();
  } catch (error) {
    // The default address still tells whether the tunnel works.
    ygLogger('read ping settings failed (${error.runtimeType})');
  }
  return timeWarmHead(Uri.parse(ping.realUrl));
}

/// Sends two HEAD requests on one connection and returns how long the second
/// took, the way «Локации» measures: the first pays for DNS and every
/// handshake. Null when either gets no answer within [timeout].
@visibleForTesting
Future<int?> timeWarmHead(
  Uri url, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await () async {
      late int elapsed;
      for (var request = 0; request < 2; request++) {
        final watch = Stopwatch()..start();
        final head = await client.headUrl(url);
        head.followRedirects = false;
        // A drained response hands the connection to the next request.
        await (await head.close()).drain<void>();
        elapsed = watch.elapsedMilliseconds;
      }
      return elapsed;
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
