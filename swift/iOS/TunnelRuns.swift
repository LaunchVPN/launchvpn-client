import Foundation

/// One run of the tunnel extension, for crash reports. The extension writes
/// it while it runs; the App removes it once it has told how the run ended.
struct TunnelRun: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    /// The stop, or the extension's last heartbeat while it runs. A process
    /// iOS kills, at its memory limit or on a crash, never stops, so its run
    /// ends at the last heartbeat.
    var seenAt: Date
    var memory: TunnelMemoryReading?
    /// `NEProviderStopReason`'s name once iOS stopped the tunnel.
    var stopReason: String?
}

/// A file per run in the App Group, so the extension and the App never
/// overwrite each other: the extension writes only its own run, and the App
/// removes only runs that are over.
struct TunnelRunStore: Sendable {
    let directory: URL

    static var shared: TunnelRunStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId())
            .map { TunnelRunStore(directory: $0.appendingPathComponent("tunnel-runs", isDirectory: true)) }
    }

    func save(_ run: TunnelRun) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(run).write(
            to: directory.appendingPathComponent("\(run.id.uuidString).json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    /// A run without a heartbeat for this long has no process behind it. The
    /// heartbeat also pauses while the device sleeps, so a stale run alone
    /// does not prove it.
    static let silence: TimeInterval = 3 * 60

    /// Removes and returns the runs that are over, oldest first: stopped ones
    /// and ones whose process died. An unstopped run counts as dead only once
    /// silent, and not while it is the newest and a tunnel may be up. One the
    /// device's restart ended is removed without being returned.
    func takeEnded(tunnelMayRun: Bool, bootedAt: Date?, now: Date = Date()) -> [TunnelRun] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var runs: [(file: URL, run: TunnelRun)] = []
        for file in files {
            if let data = try? Data(contentsOf: file), let run = try? JSONDecoder().decode(TunnelRun.self, from: data) {
                runs.append((file, run))
            } else {
                // Unreadable, so never reported: it would stay forever.
                try? FileManager.default.removeItem(at: file)
            }
        }
        runs.sort { $0.run.startedAt < $1.run.startedAt }
        let newest = runs.last?.run.id
        let ended = runs.filter { entry in
            entry.run.stopReason != nil
                || (now.timeIntervalSince(entry.run.seenAt) > Self.silence
                    && !(tunnelMayRun && entry.run.id == newest))
        }
        for entry in ended {
            try? FileManager.default.removeItem(at: entry.file)
        }
        return ended.map { $0.run }.filter { run in
            guard run.stopReason == nil, let bootedAt else { return true }
            return run.seenAt > bootedAt
        }
    }
}
