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
