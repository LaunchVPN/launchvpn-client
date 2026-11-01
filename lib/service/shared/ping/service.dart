import 'dart:async';

import 'package:onexray/core/errors/failure.dart';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/shared/event_bus/service.dart';
import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/core/db/database/enum.dart';
import 'package:onexray/service/connect/compiler.dart';
import 'package:onexray/core/tools/empty.dart';
import 'package:onexray/service/shared/ping/batch.dart';
import 'package:onexray/service/shared/ping/state.dart';
import 'package:onexray/service/shared/command_serial_executor.dart';
import 'package:onexray/service/servers/outbound/map.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';

class PingService {
  static final PingService _singleton = PingService._internal();

  factory PingService() => _singleton;

  PingService._internal() : _databaseOverride = null, _batchOverride = null;

  PingService.forTesting({
    required AppDatabase database,
    bool automaticEnabled = true,
    required Future<List<PingBatchResult>> Function(
      List<PingBatchSource>,
      PingState,
    )
    runBatch,
  }) : _databaseOverride = database,
       _batchOverride = runBatch {
    _automaticEnabled = automaticEnabled;
  }

  final AppDatabase? _databaseOverride;
  final Future<List<PingBatchResult>> Function(
    List<PingBatchSource>,
    PingState,
  )?
  _batchOverride;

  AppDatabase get _database => _databaseOverride ?? AppDatabase();

  final _pingQueue = CommandSerialExecutor();
  var _pingingTaskCount = 0;
  var _automaticEnabled = false;

  bool get isPinging => _pingingTaskCount > 0;

  Future<void> pauseForDataClear() => _pingQueue.pause();

  void resumeAfterDataClear() => _pingQueue.resume();

  /// Setup only imports. Normal startup enables background probes after native
  /// readiness checks; unmeasured DB rows are the backlog, not a second queue.
  void startAutomatic() {
    if (_automaticEnabled) return;
    _automaticEnabled = true;
    unawaited(
      _scheduleUnmeasured().catchError((Object error, StackTrace stackTrace) {
        ygLogger(
          'Schedule unmeasured nodes failed (${error.runtimeType})\n$stackTrace',
        );
      }),
    );
  }

  void stopAutomatic() => _automaticEnabled = false;

  Future<void> _scheduleUnmeasured() async {
    final ids = await _database.coreConfigDao.unmeasuredOutboundIds;
    schedulePingConfigIds(ids);
  }

  void schedulePingConfigIds(List<int> ids) {
    if (!_automaticEnabled || _pingQueue.isPaused) return;
    unawaited(pingConfigIds(ids));
  }

  /// Shares the existing serialized queue with automatic imports. Each batch
  /// commits independently, so DB watchers may finish selecting before this does.
  Future<void> pingConfigIds(
    List<int> ids, {
    bool force = false,
    bool Function()? isCancelled,
  }) {
    final targetIds = ids
        .where((id) => id > DBConstants.defaultId)
        .toSet()
        .toList();
    if (targetIds.isEmpty) {
      return Future.value();
    }
    return _enqueuePing(() async {
      final db = _database;
      final rows = <CoreConfigData>[];
      for (final id in targetIds) {
        final row = await db.coreConfigDao.searchActiveOutboundRow(id);
        if (row != null &&
            _isPingableConfig(row) &&
            (force || isUnmeasured(row))) {
          rows.add(row);
        }
      }
      if (rows.isEmpty) {
        return;
      }
      await _pingConfigs(db, rows, isCancelled: isCancelled);
    });
  }

  void schedulePingSubscription(int subId) {
    schedulePingSubscriptions([subId]);
  }

  void schedulePingSubscriptions(Iterable<int> subIds) {
    if (!_automaticEnabled || _pingQueue.isPaused) return;
    final targetSubIds = subIds
        .where((id) => id > DBConstants.defaultId)
        .toSet()
        .toList(growable: false);
    for (final subId in targetSubIds) {
      unawaited(
        _enqueuePing(() async {
          final db = _database;
          final rows = (await db.coreConfigDao.allOutboundRowsWithDataBySubId(
            subId,
          )).where(isUnmeasured).toList();
          if (rows.isNotEmpty) await _pingConfigs(db, rows);
        }),
      );
    }
  }

  Future<void> _enqueuePing(Future<void> Function() task) {
    _startPinging();
    final next = _pingQueue.run(task).whenComplete(_stopPinging);
    unawaited(
      next.catchError((Object error, StackTrace stackTrace) {
        if (!_pingQueue.isPaused) {
          ygLogger('Queued ping failed: ${failureDetails(error)}\n$stackTrace');
        }
      }),
    );
    return next;
  }

  static bool isUnmeasured(CoreConfigData row) =>
      row.delay == PingDelayConstants.unknown;

  void _startPinging() {
    _pingingTaskCount += 1;
    if (_pingingTaskCount == 1) {
      AppEventBus.instance.updatePinging(true);
    }
  }

  void _stopPinging() {
    if (_pingingTaskCount > 0) {
      _pingingTaskCount -= 1;
    }
    if (_pingingTaskCount == 0) {
      AppEventBus.instance.updatePinging(false);
    }
  }

  bool _isPingableConfig(CoreConfigData row) {
    return CoreConfigType.fromString(row.type) == CoreConfigType.outbound;
  }

  Future<void> _pingConfigs(
    AppDatabase db,
    List<CoreConfigData> rows, {
    bool Function()? isCancelled,
  }) async {
    final pingState = PingState();
    await pingState.readFromPreferences();

    // Manual selections may span subscriptions too. Never mix them
    // within a native batch; finish one subscription before starting the next.
    final batches = rows
        .groupListsBy((row) => row.subId)
        .values
        .expand((group) => group.slices(PingBatchRunner.maxBatchSize));
    for (final rowSlice in batches) {
      // ponytail: finish and save the current batch; native cancellation can
      // be added if stopping up to five in-flight probes immediately is needed.
      if (_pingQueue.isPaused || (isCancelled?.call() ?? false)) break;
      final batchRows = <CoreConfigData>[];
      final sources = <PingBatchSource>[];
      for (final row in rowSlice) {
        final current = await db.coreConfigDao.searchActiveOutboundRow(row.id);
        if (current == null ||
            current.data != row.data ||
            current.subId != row.subId) {
          continue;
        }
        final source = _makePingSource(row);
        if (source != null) {
          batchRows.add(row);
          sources.add(source);
        }
      }
      if (sources.isEmpty) continue;
      final results = await (_batchOverride ?? PingBatchRunner.run)(
        sources,
        pingState,
      );
      await db.transaction(() async {
        for (var index = 0; index < results.length; index++) {
          final result = results[index];
          await _updateRow(db, batchRows[index], _storedDelay(result));
        }
      });
      AppEventBus.instance.updatePingResults({
        for (var index = 0; index < results.length; index++)
          batchRows[index].id: results[index],
      });
    }
  }

  static int _storedDelay(PingBatchResult result) => result.success
      ? result.delay
      : result.delay == PingDelayConstants.timeout
      ? PingDelayConstants.timeout
      : PingDelayConstants.error;

  /// Measures what the locations screen lists, using only the app's own core.
  /// A provider group takes the delay of its first server that answers, trying
  /// at most [_locationAttempts] of them, so one sweep stays seconds long. A
  /// cancelled sweep leaves the last delays of the rows it did not finish.
  Future<void> pingLocations(
    List<CoreConfigData> rows, {
    bool Function()? isCancelled,
  }) => _enqueuePing(() async {
    final db = _database;
    final pingState = PingState();
    await pingState.readFromPreferences();
    final servers = {for (final row in rows) row: _locationServers(row)};
    final unanswered = <CoreConfigData, PingBatchResult>{
      for (final row in rows) row: PingBatchResult.failed(),
    };
    for (var attempt = 0; attempt < _locationAttempts; attempt++) {
      final round = unanswered.keys
          .where((row) => attempt < servers[row]!.length)
          .toList();
      for (final slice in round.slices(PingBatchRunner.maxBatchSize)) {
        if (_pingQueue.isPaused || (isCancelled?.call() ?? false)) return;
        final results = await (_batchOverride ?? PingBatchRunner.run)([
          for (final row in slice) PingBatchSource(servers[row]![attempt]),
        ], pingState);
        await db.transaction(() async {
          for (var index = 0; index < results.length; index++) {
            unanswered[slice[index]] = results[index];
            if (results[index].success) {
              await _updateRow(db, slice[index], results[index].delay);
              unanswered.remove(slice[index]);
            }
          }
        });
      }
    }
    await db.transaction(() async {
      for (final entry in unanswered.entries) {
        await _updateRow(db, entry.key, _storedDelay(entry.value));
      }
    });
  });

  static const _locationAttempts = 3;
  static const _notServers = {'freedom', 'blackhole', 'dns', 'loopback'};

  List<String> _locationServers(CoreConfigData row) {
    try {
      if (CoreConfigType.fromString(row.type) != CoreConfigType.Remnawave) {
        return [encodeSingleOutbound(readOutboundFromDbData(row))];
      }
      final outbounds =
          ResolvedProfile.fromRow(row).config['outbounds'] as List;
      return [
        for (final outbound in outbounds.cast<Map<String, dynamic>>())
          // A chained server cannot be reached on its own.
          if (!_notServers.contains(outbound['protocol']) &&
              outboundDialerProxy(outbound)?.isNotEmpty != true &&
              outboundProxyTag(outbound)?.isNotEmpty != true)
            encodeSingleOutbound(outbound),
      ];
    } on FormatException catch (error) {
      ygLogger('Read location servers failed (${error.runtimeType})');
      return const [];
    }
  }

  PingBatchSource? _makePingSource(CoreConfigData row) {
    if (!EmptyTool.checkString(row.data)) {
      return null;
    }
    try {
      final outbound = readOutboundFromDbData(row);
      return PingBatchSource(encodeSingleOutbound(outbound));
    } catch (error) {
      ygLogger("Prepare ping source failed: ${row.id}, ${error.runtimeType}");
      return null;
    }
  }

  Future<void> _updateRow(AppDatabase db, CoreConfigData row, int delay) async {
    if (delay == PingDelayConstants.unknown || row.data == null) return;
    // A slow result must not overwrite an edit, favorite, or restored asset.
    await (db.update(db.coreConfig)..where(
          (table) =>
              table.id.equals(row.id) &
              table.subId.equals(row.subId) &
              table.type.equals(row.type) &
              table.data.equals(row.data!),
        ))
        .write(CoreConfigCompanion(delay: Value(delay)));
  }
}
