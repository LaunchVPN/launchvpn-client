import Foundation

@MainActor
final class TunnelStopsApi: @preconcurrency TunnelStopsHostApi {
    func takeTunnelStops(completion: @escaping (Result<[TunnelStop], Error>) -> Void) {
        Task {
            guard let store = TunnelRunStore.shared else {
                completion(.success([]))
                return
            }
            let mayRun = await VPNManager.shared.tunnelMayRun()
            completion(.success(store.takeEnded(tunnelMayRun: mayRun).map(Self.stop)))
        }
    }

    private static func stop(_ run: TunnelRun) -> TunnelStop {
        TunnelStop(
            reason: run.stopReason,
            startedAtMs: Int64(run.startedAt.timeIntervalSince1970 * 1000),
            endedAtMs: Int64(run.seenAt.timeIntervalSince1970 * 1000),
            startedByApp: run.startedByApp,
            memory: run.memory.map(TunnelMemory.init)
        )
    }
}
