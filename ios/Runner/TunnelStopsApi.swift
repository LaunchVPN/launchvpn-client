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
            let runs = store.takeEnded(tunnelMayRun: mayRun, bootedAt: Self.bootedAt())
            completion(.success(runs.map(Self.tunnelStop)))
        }
    }

    private static func tunnelStop(_ run: TunnelRun) -> TunnelStop {
        TunnelStop(
            reason: run.stopReason,
            startedAtMs: Int64(run.startedAt.timeIntervalSince1970 * 1000),
            endedAtMs: Int64(run.seenAt.timeIntervalSince1970 * 1000),
            memory: run.memory.map(TunnelMemory.init)
        )
    }

    /// When the device last started; a restart ends the tunnel without a stop.
    private static func bootedAt() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
