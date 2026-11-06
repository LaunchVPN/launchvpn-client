import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/shader_backdrop.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/brand.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

enum StorePlatform {
  ios(
    target: TargetPlatform.iOS,
    connection: ConnectionPlatform.ios,
    model: 'iPhone 16 Pro',
    system: 'iOS',
  ),
  android(
    target: TargetPlatform.android,
    connection: ConnectionPlatform.android,
    model: 'Pixel 9',
    system: 'Android',
  );

  const StorePlatform({
    required this.target,
    required this.connection,
    required this.model,
    required this.system,
  });
  final TargetPlatform target;
  final ConnectionPlatform connection;

  /// This device on «Аккаунт».
  final String model;
  final String system;
}

/// A store listing language: App Store Connect's folder and Google Play's.
enum StoreLanguage {
  ru(appStore: 'ru', play: 'ru-RU'),
  en(appStore: 'en-US', play: 'en-US');

  const StoreLanguage({required this.appStore, required this.play});
  final String appStore;
  final String play;

  Locale get locale => Locale(name);
}

/// A screenshot size a store asks for, and the phone or tablet drawn on it.
enum StoreDevice {
  /// App Store's 6.9" iPhone, 1320×2868; iPhone 16 Pro inside.
  iphone(
    platform: StorePlatform.ios,
    canvas: Size(440, 956),
    pixelRatio: 3,
    screen: Size(402, 874),
    insets: EdgeInsets.only(top: 62, bottom: 34),
    corner: 55,
  ),

  /// App Store's 13" iPad, 2064×2752; iPad Pro 11" inside.
  ipad(
    platform: StorePlatform.ios,
    canvas: Size(1032, 1376),
    pixelRatio: 2,
    screen: Size(834, 1194),
    insets: EdgeInsets.only(top: 24, bottom: 20),
    corner: 18,
  ),

  /// Google Play's 9:16 phone, 1080×1920; Pixel 9 inside.
  android(
    platform: StorePlatform.android,
    canvas: Size(360, 640),
    pixelRatio: 3,
    screen: Size(412, 915),
    insets: EdgeInsets.only(top: 40, bottom: 24),
    corner: 44,
  );

  const StoreDevice({
    required this.platform,
    required this.canvas,
    required this.pixelRatio,
    required this.screen,
    required this.insets,
    required this.corner,
  });

  final StorePlatform platform;

  /// The screenshot, in logical pixels.
  final Size canvas;
  final double pixelRatio;

  /// The device's screen and its system bars.
  final Size screen;
  final EdgeInsets insets;

  /// The screen's corner radius.
  final double corner;

  /// fastlane `deliver` tells the display apart by the image size, and
  /// `supply` reads the folder.
  String screenshot(
    StoreLanguage language,
    int order,
    String shot,
  ) => switch (platform) {
    StorePlatform.ios =>
      'ios/fastlane/screenshots/${language.appStore}/${order}_${name}_$shot.png',
    StorePlatform.android =>
      '${playImages(language)}/phoneScreenshots/${order}_$shot.png',
  };

  static String playImages(StoreLanguage language) =>
      'android/fastlane/metadata/android/${language.play}/images';

  static String playImage(StoreLanguage language, String file) =>
      '${playImages(language)}/$file';
}

/// A caption over the App's [screen], which rises from the bottom edge, on the
/// backdrop of app.launch.tel.
class StoreFrame extends StatelessWidget {
  const StoreFrame({
    super.key,
    required this.device,
    required this.caption,
    required this.screen,
  });

  final StoreDevice device;
  final String caption;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    final canvas = device.canvas;
    final captionHeight = canvas.height * 0.2;
    // Room for the caption and a cut-off bottom edge, within the margins.
    final height = canvas.height - captionHeight + canvas.height * 0.04;
    final width = (height * device.screen.aspectRatio).clamp(
      0.0,
      canvas.width * 0.86,
    );
    final bezel = width * 0.022;
    // The screen inside the bezel keeps the device's proportions.
    final scale = (width - 2 * bezel) / device.screen.width;
    final radius = device.corner * scale + bezel;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ShaderBackdrop(
        child: Stack(
          children: [
            Positioned(
              left: canvas.width * 0.08,
              right: canvas.width * 0.08,
              top: 0,
              height: captionHeight,
              child: Center(
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: BrandText.heroTitle.copyWith(
                    fontSize: canvas.shortestSide * 0.07,
                  ),
                ),
              ),
            ),
            Positioned(
              top: captionHeight,
              left: (canvas.width - width) / 2,
              width: width,
              height: device.screen.height * scale + 2 * bezel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: BrandColors.line),
                  boxShadow: BrandShadows.toast,
                ),
                child: Padding(
                  padding: EdgeInsets.all(bezel),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius - bezel),
                    child: FittedBox(
                      child: SizedBox.fromSize(
                        size: device.screen,
                        child: MediaQuery(
                          data: MediaQueryData(
                            size: device.screen,
                            devicePixelRatio: device.pixelRatio,
                            padding: device.insets,
                            viewPadding: device.insets,
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(child: screen),
                              _StatusBar(device),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The time and the signal, Wi-Fi and battery icons, beside the camera: the
/// iPhone's Dynamic Island or the Pixel's punch hole. The iPad's camera sits in
/// the bezel.
class _StatusBar extends StatelessWidget {
  const _StatusBar(this.device);

  final StoreDevice device;

  @override
  Widget build(BuildContext context) {
    final ios = device.platform == StorePlatform.ios;
    // The camera's box; the bar's items center on it.
    final camera = switch (device) {
      StoreDevice.iphone => const Rect.fromLTWH(0, 11, 126, 37),
      StoreDevice.android => const Rect.fromLTWH(0, 9, 22, 22),
      StoreDevice.ipad => null,
    };
    final band = camera ?? Rect.fromLTWH(0, 0, 0, device.insets.top);
    return Positioned(
      left: 0,
      right: 0,
      top: band.top,
      height: band.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (camera != null)
            Container(
              width: camera.width,
              height: camera.height,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(camera.height / 2),
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: ios ? 36 : 24),
            child: Row(
              children: [
                Text(
                  ios ? '9:41' : '12:30',
                  style: BrandText.cardTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                for (final icon in [
                  LucideIcons.signal,
                  LucideIcons.wifi,
                  LucideIcons.batteryFull,
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(icon, size: 17, color: BrandColors.ink),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The App's mark on the accent, as the iOS icon draws it
/// (`swift/App/AppIcon/IconBlue.icon`). Google Play rounds the corners itself.
class StoreIcon extends StatelessWidget {
  const StoreIcon({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: BrandColors.accent,
    child: CustomPaint(painter: _IconMark(), size: Size.infinite),
  );
}

class _IconMark extends CustomPainter {
  const _IconMark();

  /// `mark-white.svg`: M307 681 L512 307 L717 681 on 1024, stroke 92.
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 1024;
    canvas.drawPath(
      Path()
        ..moveTo(307 * unit, 681 * unit)
        ..lineTo(512 * unit, 307 * unit)
        ..lineTo(717 * unit, 681 * unit),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 92 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconMark oldDelegate) => false;
}

/// Google Play's feature graphic: the icon and the name on the backdrop.
class StoreBanner extends StatelessWidget {
  const StoreBanner({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ShaderBackdrop(
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: const SizedBox.square(dimension: 144, child: StoreIcon()),
            ),
            const SizedBox(width: 40),
            Text(
              Brand.wordmark,
              style: BrandText.wordmark.copyWith(
                fontSize: 72,
                letterSpacing: -1.44,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
