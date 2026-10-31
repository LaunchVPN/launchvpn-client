import 'package:onexray/core/brand.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/core/network/client.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/servers/subscription/model.dart';
import 'package:onexray/service/servers/subscription/service.dart';

/// `launchvpn://sub/add?url=<https-url>`: the link the bot and the site open.
final class SubscriptionDeepLink {
  const SubscriptionDeepLink._(this.url);

  final String url;

  /// Null for any other link shape and for another provider's subscription.
  static SubscriptionDeepLink? parse(Uri uri) {
    if (uri.scheme.toLowerCase() != Brand.scheme ||
        uri.host.toLowerCase() != Brand.subscriptionLinkHost ||
        uri.path != '/add' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.queryParametersAll.keys.any((key) => key != 'url')) {
      return null;
    }
    final values = uri.queryParametersAll['url'];
    if (values == null || values.length != 1) return null;
    final url = Uri.tryParse(SubscriptionUrl.normalize(values.single));
    if (url == null || !NetClient.isHttpsDownloadUri(url) || !_isOwn(url)) {
      return null;
    }
    return SubscriptionDeepLink._(url.toString());
  }

  static bool _isOwn(Uri url) {
    final host = url.host.toLowerCase();
    return host == Brand.subscriptionDomain ||
        host.endsWith('.${Brand.subscriptionDomain}');
  }
}

/// Keeps a user on the one subscription their latest deep link names.
final class SubscriptionLinkService {
  SubscriptionLinkService({
    AppDatabase? database,
    SubscriptionService? subscriptions,
    ServerAssetService? servers,
  }) : _database = database ?? AppDatabase(),
       _subscriptions = subscriptions ?? SubscriptionService(),
       _servers = servers ?? ServerAssetService();

  final AppDatabase _database;
  final SubscriptionService _subscriptions;
  final ServerAssetService _servers;

  /// Whether [apply] would delete a subscription, which the UI confirms first.
  Future<bool> replacesAnother(SubscriptionDeepLink link) async =>
      (await _database.subscriptionDao.allRows).any(
        (row) => row.url != link.url,
      );

  /// Loads the new subscription before deleting the others, so a failure leaves
  /// the old one working. Opening the link again finishes a partial replacement.
  Future<SubscriptionInsertResult> apply(SubscriptionDeepLink link) async {
    try {
      final rows = await _database.subscriptionDao.allRows;
      final current = rows.where((row) => row.url == link.url).firstOrNull;
      final loaded = await _load(link, current);
      if (!loaded.success) return loaded;
      for (final row in rows.where((row) => row.url != link.url)) {
        await _servers.remove(await _servers.previewRemoval(sourceId: row.id));
      }
      return loaded;
    } catch (error, stackTrace) {
      ygLogger(
        'replace subscription failed (${error.runtimeType})\n$stackTrace',
      );
      return SubscriptionInsertResult(
        status: SubscriptionUpdateResult.writeFailed,
        error: error,
      );
    }
  }

  Future<SubscriptionInsertResult> _load(
    SubscriptionDeepLink link,
    SubscriptionData? current,
  ) async {
    if (current != null) {
      final result = await _subscriptions.refreshSubscriptionResult(current);
      return SubscriptionInsertResult(
        status: result.status,
        subId: current.id,
        count: result.count,
        error: result.error,
      );
    }
    return _subscriptions.insertSubscription(
      SubscriptionInput(
        name: Brand.name,
        url: link.url,
        panel: SubscriptionPanel.remnawave,
      ),
    );
  }
}
