import Foundation

enum AppleWidgetStatus: String, Codable, Sendable {
    case unknown
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// A display snapshot, never an input for starting or configuring a tunnel.
struct AppleWidgetSnapshot: Codable, Equatable, Sendable {
    static let maximumAge: TimeInterval = 15 * 60
    let version: Int
    let status: AppleWidgetStatus
    let observedAt: Date
    /// When the system connected; set only with `connected`. Older snapshots
    /// have none.
    let connectedAt: Date?

    init(status: AppleWidgetStatus, observedAt: Date = Date(), connectedAt: Date? = nil) {
        version = 1
        self.status = status
        self.observedAt = observedAt
        self.connectedAt = status == .connected ? connectedAt : nil
    }

    func isCurrent(at date: Date) -> Bool {
        let age = date.timeIntervalSince(observedAt)
        return version == 1 && age >= -60 && age < Self.maximumAge
    }

    func displayedStatus(at date: Date) -> AppleWidgetStatus {
        isCurrent(at: date) ? status : .unknown
    }
}

/// What the Widget shows next to the status, as Home shows it. The App writes
/// it whenever Home changes; it carries no configuration.
struct AppleWidgetDetails: Codable, Equatable, Sendable {
    var location: String?
    /// ISO letters of the location's flag.
    var countryCode: String?
    var automatic: Bool
    /// `ConnectionPreset.name` in the App: smart, allVpn or apps.
    var mode: String?
    var expiresAt: Date?

    /// Whole days left, rounded up as Home does. Nil without an end date.
    func daysLeft(at date: Date) -> Int? {
        guard let expiresAt else { return nil }
        let left = expiresAt.timeIntervalSince(date)
        return left <= 0 ? 0 : Int((left / 86_400).rounded(.up))
    }

    /// The next moment `daysLeft` changes, for the Widget's timeline.
    func nextDayChange(after date: Date) -> Date? {
        guard let expiresAt, expiresAt > date else { return nil }
        let left = expiresAt.timeIntervalSince(date)
        let whole = (left / 86_400).rounded(.up) - 1
        return expiresAt.addingTimeInterval(-whole * 86_400)
    }

    /// The flag emoji for `countryCode`.
    var flag: String? {
        guard let countryCode, countryCode.count == 2 else { return nil }
        let scalars = countryCode.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(0x1F1E6 + $0.value - 0x41)
        }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }
}

enum AppleWidgetLanguage {
    static func normalized(_ code: String) -> String {
        switch code.replacingOccurrences(of: "_", with: "-").lowercased() {
        case "zh", "zh-hans": return "zh-Hans"
        case "zh-hant": return "zh-Hant"
        case "ru": return "ru"
        case "fa": return "fa"
        default: return "en"
        }
    }
}

/// Separate files let the app change language without overwriting a tunnel event.
struct AppleWidgetStore: Sendable {
    static let appGroup = "group.com.launchvpn.dev"
    static let kind = "com.launchvpn.dev.connection"
    let directory: URL

    static var shared: AppleWidgetStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { AppleWidgetStore(directory: $0.appendingPathComponent("widget", isDirectory: true)) }
    }

    func snapshot() -> AppleWidgetSnapshot? {
        guard let data = read("status.json"),
              let value = try? JSONDecoder().decode(AppleWidgetSnapshot.self, from: data),
              value.version == 1 else { return nil }
        return value
    }

    func details() -> AppleWidgetDetails? {
        guard let data = read("details.json") else { return nil }
        return try? JSONDecoder().decode(AppleWidgetDetails.self, from: data)
    }

    func languageCode() -> String {
        guard let data = read("language.json"),
              let code = try? JSONDecoder().decode(String.self, from: data) else { return "en" }
        return AppleWidgetLanguage.normalized(code)
    }

    /// Repeated native reads do not spend a widget reload on an unchanged state.
    @discardableResult
    func writeStatus(_ status: AppleWidgetStatus, connectedAt: Date? = nil, at date: Date = Date()) throws -> Bool {
        let next = AppleWidgetSnapshot(status: status, observedAt: date, connectedAt: connectedAt)
        if let previous = snapshot(), previous.status == status, previous.connectedAt == next.connectedAt,
           previous.isCurrent(at: date), date.timeIntervalSince(previous.observedAt) < 60 {
            return false
        }
        try write(JSONEncoder().encode(next), name: "status.json")
        return true
    }

    @discardableResult
    func writeDetails(_ details: AppleWidgetDetails) throws -> Bool {
        if self.details() == details { return false }
        try write(JSONEncoder().encode(details), name: "details.json")
        return true
    }

    @discardableResult
    func writeLanguage(_ code: String) throws -> Bool {
        let normalized = AppleWidgetLanguage.normalized(code)
        if read("language.json") != nil, languageCode() == normalized { return false }
        try write(JSONEncoder().encode(normalized), name: "language.json")
        return true
    }

    private func read(_ name: String) -> Data? {
        let url = directory.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 4096 else { return nil }
        return try? Data(contentsOf: url)
    }

    private func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
