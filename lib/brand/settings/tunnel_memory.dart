import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onexray/brand/theme.dart';
import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/shared/page_cubit.dart';
import 'package:onexray/service/tester/tunnel_memory.dart';

/// Reads the tunnel's memory every [interval] while its screen is open. Null
/// in a build that does not show it, and while no tunnel runs.
class TunnelMemoryController extends PageCubit<TunnelMemory?> {
  TunnelMemoryController({TunnelMemoryService? service})
    : _service = service ?? TunnelMemoryService.instance,
      super(null);

  static const interval = Duration(seconds: 2);

  final TunnelMemoryService _service;
  Timer? _timer;
  bool _reading = false;

  Future<void> start() async {
    if (!await _service.isTestFlight || !isPageActive) return;
    _timer = Timer.periodic(interval, (_) => _readOnce());
    await _readOnce();
  }

  /// A tick that comes while the last read is still waiting is skipped.
  Future<void> _readOnce() async {
    if (_reading) return;
    _reading = true;
    try {
      emit(await _service.read());
    } finally {
      _reading = false;
    }
  }

  @override
  void disposePageResources() => _timer?.cancel();
}

/// One caption line with the memory now, at its peak, and the headroom left
/// below the limit at the peak, in megabytes. Takes no space when there is
/// nothing to show.
class TunnelMemoryLine extends StatefulWidget {
  const TunnelMemoryLine({super.key, this.service});

  final TunnelMemoryService? service;

  @override
  State<TunnelMemoryLine> createState() => _TunnelMemoryLineState();
}

class _TunnelMemoryLineState extends State<TunnelMemoryLine> {
  late final _controller = TunnelMemoryController(service: widget.service);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TunnelMemoryController, TunnelMemory?>(
        bloc: _controller,
        builder: (context, memory) => switch (memory) {
          null => const SizedBox.shrink(),
          final memory => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppLocalizations.of(context)!.aboutTunnelMemory(
                _megabytes(memory.footprint),
                _megabytes(memory.peak),
                _megabytes(memory.limit - memory.peak),
              ),
              style: BrandText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        },
      );

  static double _megabytes(int bytes) => bytes / (1 << 20);
}
