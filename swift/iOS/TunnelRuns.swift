import Foundation

/// One run of the tunnel extension, for crash reports. The extension writes
/// it while it runs; the App removes it once it has told how the run ended.
struct TunnelRun: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    /// False when On Demand started the tunnel without the App.
    let startedByApp: Bool
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

    /// Removes and returns the runs that are over, oldest first: stopped ones
    /// and ones whose process died. While a tunnel may be up, the newest run
    /// is the live one unless it stopped, and stays.
    func takeEnded(tunnelMayRun: Bool) -> [TunnelRun] {
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
        if tunnelMayRun, let newest = runs.last, newest.run.stopReason == nil {
            runs.removeLast()
        }
        for entry in runs {
            try? FileManager.default.removeItem(at: entry.file)
        }
        return runs.map { $0.run }
    }
}
