#if os(iOS)
import Foundation
import os

/// Appends the extension's memory use to Xray's error log, where a device can show
/// it through the App's log viewer. iOS terminates the extension at its memory limit,
/// so `headroom` is the limit minus the peak footprint: the closest this process has
/// come to it, including spikes between lines. Writes nothing unless file logs are on.
/// Xray also opens the log with O_APPEND, so lines do not interleave with its own.
final class TunnelMemoryLog: @unchecked Sendable {
    private static let lineInterval = DispatchTimeInterval.seconds(30)

    private let queue = DispatchQueue(label: "com.launchvpn.dev.tunnel.memory", qos: .utility)
    private lazy var timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return format
    }()
    private var path: String?
    private var timer: DispatchSourceTimer?

    /// `errorLogPath` is the Xray config's `log.error`; "none" means logs are off.
    func start(errorLogPath: String?) {
        queue.async {
            guard self.timer == nil, let errorLogPath, !errorLogPath.isEmpty, errorLogPath != "none" else {
                return
            }
            self.path = errorLogPath
            self.append("start")
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.lineInterval, repeating: Self.lineInterval)
            timer.setEventHandler { [weak self] in self?.append("running") }
            timer.resume()
            self.timer = timer
        }
    }

    func mark(_ stage: String) {
        queue.async { self.append(stage) }
    }

    /// Synchronous so the last line is written before the extension exits.
    func stop() {
        queue.sync {
            self.timer?.cancel()
            self.timer = nil
            self.append("stop")
            self.path = nil
        }
    }

    private func append(_ stage: String) {
        guard let path else { return }
        guard let footprint = Self.footprint() else {
            YGLog("TunnelMemoryLog task_info failed")
            return
        }
        let available = os_proc_available_memory()
        let headroom = available + footprint.current - footprint.peak
        let line = "\(timeFormat.string(from: Date())) [Memory] \(stage): "
            + "headroom \(Self.megabytes(headroom)) MB, "
            + "available \(Self.megabytes(available)) MB, "
            + "footprint \(Self.megabytes(footprint.current)) MB, "
            + "peak \(Self.megabytes(footprint.peak)) MB\n"
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else {
            YGLog("TunnelMemoryLog open failed: \(errno)")
            return
        }
        defer { close(fd) }
        if line.withCString({ write(fd, $0, strlen($0)) }) < 0 {
            YGLog("TunnelMemoryLog write failed: \(errno)")
        }
    }

    private static func footprint() -> (current: Int, peak: Int)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(tunnel_task_self(), task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (Int(info.phys_footprint), Int(info.ledger_phys_footprint_peak))
    }

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}
#endif
