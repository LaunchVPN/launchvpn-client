#if os(iOS)
import Foundation
import NetworkExtension

/// Keeps this run's record for the App's crash reports: when it started, its
/// memory and, once iOS stops the tunnel, why. The heartbeat dates the end of
/// a process that dies without a stop.
final class TunnelRunRecorder: @unchecked Sendable {
    private static let heartbeat = DispatchTimeInterval.seconds(60)

    private let queue = DispatchQueue(label: "com.launchvpn.dev.tunnel.run", qos: .utility)
    private let store = TunnelRunStore.shared
    private var run: TunnelRun?
    private var timer: DispatchSourceTimer?
    /// A stop that comes while the start still runs leaves no run to record.
    private var stopped = false

    func start() {
        queue.async {
            guard self.run == nil, !self.stopped else { return }
            let now = Date()
            self.run = TunnelRun(
                id: UUID(), startedAt: now, seenAt: now,
                memory: TunnelMemoryReading.current(), stopReason: nil
            )
            self.save()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.heartbeat, repeating: Self.heartbeat, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in self?.update(stopReason: nil) }
            timer.resume()
            self.timer = timer
        }
    }

    /// Synchronous so the reason is on disk before the extension exits.
    func stop(_ reason: NEProviderStopReason) {
        queue.sync {
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            self.update(stopReason: reason.name)
            self.run = nil
        }
    }

    private func update(stopReason: String?) {
        guard var run else { return }
        run.seenAt = Date()
        run.memory = TunnelMemoryReading.current() ?? run.memory
        run.stopReason = stopReason
        self.run = run
        save()
    }

    private func save() {
        guard let run, let store else { return }
        do {
            try store.save(run)
        } catch {
            YGLog("TunnelRunRecorder save failed: \(error)")
        }
    }
}

private extension NEProviderStopReason {
    /// The Swift case name, as crash reports group by it.
    var name: String {
        switch self {
        case .none: "none"
        case .userInitiated: "userInitiated"
        case .providerFailed: "providerFailed"
        case .noNetworkAvailable: "noNetworkAvailable"
        case .unrecoverableNetworkChange: "unrecoverableNetworkChange"
        case .providerDisabled: "providerDisabled"
        case .authenticationCanceled: "authenticationCanceled"
        case .configurationFailed: "configurationFailed"
        case .idleTimeout: "idleTimeout"
        case .configurationDisabled: "configurationDisabled"
        case .configurationRemoved: "configurationRemoved"
        case .superceded: "superceded"
        case .userLogout: "userLogout"
        case .userSwitch: "userSwitch"
        case .connectionFailed: "connectionFailed"
        case .sleep: "sleep"
        case .appUpdate: "appUpdate"
        // Cases newer than the SDK's oldest, such as internalError (17).
        default: rawValue == 17 ? "internalError" : "reason\(rawValue)"
        }
    }
}
#endif
