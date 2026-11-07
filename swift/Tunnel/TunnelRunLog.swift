#if os(iOS)
import Foundation
import NetworkExtension
import os

/// Follows one run of the extension on a heartbeat, for two readers:
///
/// - The App's crash reports get the run's record in the App Group: its start,
///   its memory and, once iOS stops the tunnel, why. A process iOS kills, at
///   its memory limit or on a crash, never stops, so its record ends at the
///   last heartbeat.
/// - Testers get the memory appended to Xray's error log, which the App's log
///   viewer shows, but only while file logs are on. Xray opens the log with
///   O_APPEND too, so lines do not interleave with its own.
///
/// iOS terminates the extension at its memory limit, so `headroom` is the
/// limit minus the peak footprint: the closest this process has come to it,
/// including spikes between heartbeats.
final class TunnelRunLog: @unchecked Sendable {
    private static let heartbeat = DispatchTimeInterval.seconds(30)

    private let queue = DispatchQueue(label: "com.launchvpn.dev.tunnel.run", qos: .utility)
    private let store = TunnelRunStore.shared
    private lazy var timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return format
    }()
    private var logPath: String?
    private var run: TunnelRun?
    private var timer: DispatchSourceTimer?
    /// A stop that comes while the start still runs leaves no run to follow.
    private var stopped = false

    /// `errorLogPath` is the Xray config's `log.error`; "none" means logs are off.
    func start(errorLogPath: String?) {
        queue.async {
            guard self.run == nil, !self.stopped else { return }
            if let errorLogPath, !errorLogPath.isEmpty, errorLogPath != "none" {
                self.logPath = errorLogPath
            }
            let now = Date()
            self.run = TunnelRun(id: UUID(), startedAt: now, seenAt: now, memory: nil, stopReason: nil)
            self.beat("start")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.heartbeat, repeating: Self.heartbeat, leeway: .seconds(5))
            timer.setEventHandler { [weak self] in self?.beat("running") }
            timer.resume()
            self.timer = timer
        }
    }

    func mark(_ stage: String) {
        queue.async { self.beat(stage) }
    }

    /// Synchronous so the last beat is on disk before the extension exits.
    /// Without a reason the start failed: the App already shows that, so the
    /// run leaves no record.
    func stop(_ reason: NEProviderStopReason?) {
        queue.sync {
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            if let reason {
                self.run?.stopReason = reason.name
                self.beat("stop")
            } else {
                self.beat("stop", record: false)
                if let run = self.run { self.store?.remove(run.id) }
            }
            self.run = nil
            self.logPath = nil
        }
    }

    private func beat(_ stage: String, record: Bool = true) {
        let memory = TunnelMemoryReading.current()
        if memory == nil { YGLog("TunnelRunLog task_info failed") }
        if record, var run, let store {
            run.seenAt = Date()
            run.memory = memory ?? run.memory
            self.run = run
            do {
                try store.save(run)
            } catch {
                YGLog("TunnelRunLog save failed: \(error)")
            }
        }
        if let memory { appendLine(stage, memory) }
    }

    private func appendLine(_ stage: String, _ memory: TunnelMemoryReading) {
        guard let logPath else { return }
        let line = "\(timeFormat.string(from: Date())) [Memory] \(stage): "
            + "headroom \(Self.megabytes(memory.headroom)) MB, "
            + "available \(Self.megabytes(memory.limit - memory.footprint)) MB, "
            + "footprint \(Self.megabytes(memory.footprint)) MB, "
            + "peak \(Self.megabytes(memory.peak)) MB\n"
        let fd = open(logPath, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else {
            YGLog("TunnelRunLog open failed: \(errno)")
            return
        }
        defer { close(fd) }
        if line.withCString({ write(fd, $0, strlen($0)) }) < 0 {
            YGLog("TunnelRunLog write failed: \(errno)")
        }
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}

extension TunnelMemoryReading {
    /// This process's footprint, its peak and the limit iOS ends it at.
    /// The limit is the footprint plus what iOS still allows.
    static func current() -> TunnelMemoryReading? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(tunnel_task_self(), task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let footprint = Int(info.phys_footprint)
        return TunnelMemoryReading(
            footprint: footprint,
            peak: Int(info.ledger_phys_footprint_peak),
            limit: footprint + os_proc_available_memory()
        )
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
