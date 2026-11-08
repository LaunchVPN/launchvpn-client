import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/tools/logger.dart';

/// The animated backdrop of app.launch.tel behind [child], which fills the
/// screen above it, as on «Вход» and «Проверьте почту». Under reduced motion
/// it holds a still frame, it stops while its screen is covered or the app is
/// in the background, and it stays the plain page background if the shader
/// fails to load.
class ShaderBackdrop extends StatefulWidget {
  const ShaderBackdrop({
    super.key,
    required this.child,
    this.loadProgram = _loadDarkVeil,
  });

  final Widget child;

  /// Loads the compiled `shaders/dark_veil.frag`; by default once per run.
  final Future<FragmentProgram> Function() loadProgram;

  @override
  State<ShaderBackdrop> createState() => _ShaderBackdropState();
}

final _darkVeil = FragmentProgram.fromAsset('shaders/dark_veil.frag');

Future<FragmentProgram> _loadDarkVeil() => _darkVeil;

/// The site's `speed`: shader seconds per real second.
const _speed = 0.5;

/// The site's resolution cap: the veil is soft, so a denser screen only
/// costs GPU time.
const _maxPixelRatio = 1.5;

class _ShaderBackdropState extends State<ShaderBackdrop> {
  late final _ticker = Ticker(_tick, debugLabel: 'ShaderBackdrop');
  late final AppLifecycleListener _lifecycle;
  final _time = ValueNotifier<double>(0);

  /// The shader time the ticker resumes from.
  double _held = 0;
  FragmentShader? _veil;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _sync());
    unawaited(_load());
  }

  /// Leaves the plain background in place if the shader cannot be loaded.
  Future<void> _load() async {
    final FragmentProgram program;
    try {
      program = await widget.loadProgram();
    } catch (error) {
      ygLogger('load backdrop shader failed (${error.runtimeType})');
      return;
    }
    if (!mounted) return;
    setState(() => _veil = _DarkVeilPainter.colored(program.fragmentShader()));
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  /// Runs the ticker while the veil may move, and otherwise holds its frame.
  void _sync() {
    final moves =
        _veil != null &&
        !BrandMotion.reduced(context) &&
        TickerMode.valuesOf(context).enabled &&
        _appVisible;
    if (moves == _ticker.isActive) return;
    if (moves) {
      unawaited(_ticker.start());
    } else {
      _ticker.stop();
      _held = _time.value;
    }
  }

  bool get _appVisible => switch (SchedulerBinding.instance.lifecycleState) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => true,
  };

  void _tick(Duration elapsed) => _time.value =
      _held + elapsed.inMicroseconds / Duration.microsecondsPerSecond * _speed;

  @override
  void dispose() {
    _lifecycle.dispose();
    _ticker.dispose();
    _time.dispose();
    _veil?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final veil = _veil;
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        if (veil == null)
          const ColoredBox(color: BrandBackdrop.base)
        else
          RepaintBoundary(
            child: CustomPaint(
              painter: _DarkVeilPainter(
                veil,
                _time,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
        widget.child,
      ],
    );
  }
}

/// Draws the veil at [time] over the whole canvas. A screen denser than
/// [_maxPixelRatio] gets it rendered off screen at that cap and scaled up;
/// [Picture.toImageSync] rasterizes on the raster thread, where one pass at
/// the cap costs far less than this fragment shader at full density.
class _DarkVeilPainter extends CustomPainter {
  _DarkVeilPainter(this.shader, this.time, {required this.devicePixelRatio})
    : super(repaint: time);

  /// [shader] in the brand's colors, set once.
  static FragmentShader colored(FragmentShader shader) {
    void color(String name, Color value) =>
        shader.getUniformVec4(name).set(value.r, value.g, value.b, value.a);
    const base = BrandBackdrop.base;
    shader.getUniformVec3('uBase').set(base.r, base.g, base.b);
    color('uGlow', BrandBackdrop.glow);
    color('uTintFrom', BrandBackdrop.tintFrom);
    color('uTintTo', BrandBackdrop.tintTo);
    color('uHighlight', BrandBackdrop.highlight);
    color('uLowlight', BrandBackdrop.lowlight);
    return shader;
  }

  final FragmentShader shader;
  final ValueListenable<double> time;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    shader.getUniformFloat('uTime').set(time.value);
    // Within the cap, a pass off screen would only add a copy.
    if (devicePixelRatio <= _maxPixelRatio) {
      shader.getUniformVec2('uSize').set(size.width, size.height);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }
    final width = (size.width * _maxPixelRatio).ceil();
    final height = (size.height * _maxPixelRatio).ceil();
    final rendered = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    shader.getUniformVec2('uSize').set(rendered.width, rendered.height);
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(rendered, Paint()..shader = shader);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    canvas.drawImageRect(
      image,
      rendered,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
    // The canvas keeps its own reference until the frame is drawn.
    image.dispose();
  }

  @override
  bool shouldRepaint(_DarkVeilPainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.time != time ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
