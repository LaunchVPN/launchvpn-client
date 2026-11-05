import 'package:onexray/core/brand.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the App, such as the renewal site or support. A device
/// with nothing to open it leaves the screen as it is; only [name] is logged.
Future<void> openExternalLink(Uri uri, String name) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    ygLogger('open $name link failed: nothing handled it');
  } catch (error) {
    ygLogger('open $name link failed (${error.runtimeType})');
  }
}

/// Support for [subscription]: the panel's link, or the bot's when the panel
/// sent none or there is no subscription.
Uri supportUri(SubscriptionData? subscription) =>
    Uri.parse(subscription?.supportUrl ?? Brand.supportUrl);

/// Opens [supportUri] for [subscription].
Future<void> openSupport(SubscriptionData? subscription) =>
    openExternalLink(supportUri(subscription), 'support');
