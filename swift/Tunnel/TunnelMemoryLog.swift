#if os(iOS)
import Foundation
import os

/// Appends the extension's remaining memory budget to Xray's error log, where a
/// device can show it through the App's log viewer. iOS terminates the extension
/// when this budget runs out, so `lowest` is the session's real headroom.
/// Writes nothing unless file logs are on. Xray also opens the log with O_APPEND,
/// so single-line writes do not interleave with its own.
final class TunnelMemoryLog: @unchecked Sendable {
    private static let sampleInterval = DispatchTimeInterval.seconds(1)
    private static let samplesPerLine = 30
    private static let notableDrop = 1024 * 1024

    private let queue = DispatchQueue(label: "com.launchvpn.dev.tunnel.memory", qos: .utility)
    private let availableAtLaunch = os_proc_available_memory()
    private lazy var timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return format
    }()
    private var path: String?
    private var timer: DispatchSourceTimer?
    private var lowest = Int.max
    private var lowestLogged = Int.max
    private var samplesSinceLine = 0

    /// `errorLogPath` is the Xray config's `log.error`; "none" means logs are off.
    func start(errorLogPath: String?) {
        queue.async {
            guard self.timer == nil, let errorLogPath, !errorLogPath.isEmpty, errorLogPath != "none" else {
                return
            }
            self.path = errorLogPath
            self.append("launch", available: self.availableAtLaunch)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: Self.sampleInterval)
            timer.setEventHandler { [weak self] in self?.sample() }
            timer.resume()
            self.timer = timer
        }
    }

    func mark(_ stage: String) {
        queue.async { self.append(stage, available: os_proc_available_memory()) }
    }

    func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.append("stop", available: os_proc_available_memory())
            self.path = nil
        }
    }

    private func sample() {
        let available = os_proc_available_memory()
        lowest = min(lowest, available)
        samplesSinceLine += 1
        if samplesSinceLine >= Self.samplesPerLine || lowest <= lowestLogged - Self.notableDrop {
            append("running", available: available)
        }
    }

    private func append(_ stage: String, available: Int) {
        guard let path else { return }
        lowest = min(lowest, available)
        lowestLogged = lowest
        samplesSinceLine = 0
        let time = timeFormat.string(from: Date())
        let line = "\(time) [Memory] \(stage): available \(Self.megabytes(available)) MB, lowest \(Self.megabytes(lowest)) MB\n"
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

    private static func megabytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / 1_048_576)
    }
}
#endif
