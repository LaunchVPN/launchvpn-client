import SwiftUI
import WidgetKit
import AppIntents

private let connectionURL = URL(string: "launchvpn://widget/connect")!

private var connectionWidgetFamilies: [WidgetFamily] {
    if #available(iOS 16.0, *) {
        return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    }
    return [.systemSmall, .systemMedium]
}

struct ConnectionWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AppleWidgetSnapshot?
    let details: AppleWidgetDetails?
    let languageCode: String

    var status: AppleWidgetStatus { snapshot?.displayedStatus(at: date) ?? .unknown }
}

struct ConnectionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ConnectionWidgetEntry {
        ConnectionWidgetEntry(date: Date(), snapshot: nil, details: nil, languageCode: "en")
    }

    func getSnapshot(in context: Context, completion: @escaping (ConnectionWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    /// Redraws when the observation expires, so a process that exits without a
    /// final callback never leaves «Подключено», and when the days left change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ConnectionWidgetEntry>) -> Void) {
        let current = entry(at: Date())
        var dates: [Date] = []
        if let snapshot = current.snapshot, snapshot.isCurrent(at: current.date) {
            dates.append(snapshot.observedAt.addingTimeInterval(AppleWidgetSnapshot.maximumAge))
        }
        if let change = current.details?.nextDayChange(after: current.date) {
            dates.append(change)
        }
        let later = dates.sorted().map {
            ConnectionWidgetEntry(
                date: $0, snapshot: current.snapshot, details: current.details,
                languageCode: current.languageCode
            )
        }
        completion(Timeline(entries: [current] + later, policy: later.isEmpty ? .never : .atEnd))
    }

    private func entry(at date: Date) -> ConnectionWidgetEntry {
        let store = AppleWidgetStore.shared
        return ConnectionWidgetEntry(
            date: date, snapshot: store?.snapshot(), details: store?.details(),
            languageCode: store?.languageCode() ?? "en"
        )
    }
}

struct ConnectionWidget: Widget {
    var body: some WidgetConfiguration {
        let language = AppleWidgetStore.shared?.languageCode() ?? "en"
        return StaticConfiguration(kind: AppleWidgetStore.kind, provider: ConnectionWidgetProvider()) { entry in
            ConnectionWidgetView(entry: entry)
                .environment(\.locale, Locale(identifier: entry.languageCode))
                .environment(\.layoutDirection, entry.languageCode == "fa" ? .rightToLeft : .leftToRight)
                .widgetURL(connectionURL)
        }
        .configurationDisplayName(Text(verbatim: widgetText("Connection", language)))
        .description(Text(verbatim: widgetText("VPN status and actions that open LaunchVPN.", language)))
        .supportedFamilies(connectionWidgetFamilies)
    }
}

/// The Home screen sizes follow the App: its dark surfaces, the status with a
/// dot, and Home's toggle as the one control. Medium adds the days left and the
/// location with the mode. The lock screen sizes stay in the system's tint.
private struct ConnectionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ConnectionWidgetEntry

    private var isAccessory: Bool {
        if #available(iOS 16.0, *) {
            return family == .accessoryCircular || family == .accessoryRectangular
        }
        return false
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                if !isAccessory { WidgetPalette.surface }
            }
        } else if isAccessory {
            content
        } else {
            content.padding(16).background(WidgetPalette.surface)
        }
    }

    @ViewBuilder private var content: some View {
        if #available(iOS 16.0, *), family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                LaunchMarkShape()
                    .stroke(style: LaunchMarkShape.style(for: 26))
                    .frame(width: 26, height: 26)
                    .opacity(entry.status == .connected ? 1 : 0.5)
            }
            .privacySensitive()
            .accessibilityLabel("LaunchVPN, \(copy.title)")
        } else if #available(iOS 16.0, *), family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "launchvpn").font(WidgetFont.wordmark(13))
                HStack(spacing: 6) {
                    Circle().frame(width: 7, height: 7).opacity(entry.status == .connected ? 1 : 0.45)
                    Text(copy.title).font(WidgetFont.semiBold(15)).lineLimit(1)
                }
                .privacySensitive()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if family == .systemMedium {
            medium.environment(\.colorScheme, .dark)
        } else {
            small.environment(\.colorScheme, .dark)
        }
    }

    private var copy: StatusCopy { StatusCopy(entry: entry) }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandRow()
            Spacer(minLength: 8)
            StatusBlock(copy: copy, titleSize: 15, subtitleSize: 12)
            Spacer(minLength: 8)
            ConnectionControl(status: entry.status, height: 56, language: entry.languageCode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                BrandRow()
                Spacer(minLength: 8)
                // An ended subscription shows no pill, as Home shows none.
                if entry.status != .unknown, let days = entry.details?.daysLeft(at: entry.date), days > 0 {
                    DaysPill(days: days, language: entry.languageCode)
                }
            }
            Spacer(minLength: 6)
            StatusBlock(copy: copy, titleSize: 17, subtitleSize: 13)
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                if entry.status != .unknown, let details = entry.details, details.location != nil {
                    LocationPill(details: details, language: entry.languageCode)
                } else {
                    Spacer(minLength: 0)
                }
                ConnectionControl(status: entry.status, height: 44, language: entry.languageCode)
                    .frame(width: 88)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The status line and what it means, in the Widget's language.
private struct StatusCopy {
    let entry: ConnectionWidgetEntry

    private func text(_ key: String) -> String { widgetText(key, entry.languageCode) }

    var title: String {
        switch entry.status {
        case .unknown: text("No data")
        case .disconnected: text("Disconnected")
        case .connecting: text("Connecting")
        case .connected: text("Connected")
        case .disconnecting: text("Disconnecting")
        }
    }

    var subtitle: String {
        switch entry.status {
        case .unknown: text("Open the app")
        case .disconnected: text("IP visible")
        case .connecting, .disconnecting: text("One moment")
        case .connected: text("IP hidden")
        }
    }

    /// Counts up while connected, as Home's timer does.
    var connectedAt: Date? { entry.status == .connected ? entry.snapshot?.connectedAt : nil }

    var dot: Color {
        switch entry.status {
        case .connected: WidgetPalette.success
        case .connecting, .disconnecting: WidgetPalette.warning
        case .disconnected, .unknown: WidgetPalette.muted
        }
    }
}

private struct BrandRow: View {
    var body: some View {
        HStack(spacing: 4) {
            LaunchMarkShape()
                .stroke(WidgetPalette.accent, style: LaunchMarkShape.style(for: 16))
                .frame(width: 16, height: 16)
            Text(verbatim: "launchvpn")
                .font(WidgetFont.wordmark(11))
                .foregroundStyle(WidgetPalette.ink.opacity(0.9))
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("LaunchVPN")
    }
}

private struct StatusBlock: View {
    let copy: StatusCopy
    let titleSize: CGFloat
    let subtitleSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(copy.dot).frame(width: 8, height: 8)
                Text(copy.title)
                    .font(WidgetFont.semiBold(titleSize))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(spacing: 4) {
                if let since = copy.connectedAt {
                    Text(since, style: .timer).monospacedDigit()
                    Text(verbatim: "·")
                }
                Text(copy.subtitle).lineLimit(1)
            }
            .font(WidgetFont.medium(subtitleSize))
            .foregroundStyle(WidgetPalette.muted)
        }
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
}

/// Home's toggle: tapping it starts or stops the VPN in the App. While the
/// VPN disconnects it waits, and when the status is too old to trust it only
/// opens the App.
private struct ConnectionControl: View {
    let status: AppleWidgetStatus
    let height: CGFloat
    let language: String

    var body: some View {
        if status == .unknown {
            Link(destination: connectionURL) {
                Text(widgetText("Open", language))
                    .font(WidgetFont.semiBold(height > 50 ? 14 : 13))
                    .foregroundStyle(WidgetPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                    .background(Capsule().fill(WidgetPalette.raised))
                    .overlay(Capsule().strokeBorder(WidgetPalette.line, lineWidth: 1))
            }
        } else if status == .disconnecting {
            // Home's toggle waits for the teardown too.
            track.accessibilityHidden(true)
        } else if #available(iOS 17.0, *) {
            if status == .connected || status == .connecting {
                Button(intent: StopVpnWidgetIntent()) { track }
                    .buttonStyle(.plain)
                    .accessibilityLabel(widgetText("Stop VPN", language))
            } else {
                Button(intent: StartVpnWidgetIntent()) { track }
                    .buttonStyle(.plain)
                    .accessibilityLabel(widgetText("Start VPN", language))
            }
        } else {
            track.accessibilityHidden(true)
        }
    }

    private var on: Bool { status == .connected || status == .connecting }

    /// The App's proportions: the knob keeps 9/104 of the height free on every
    /// side, so it stays concentric with the track's ends.
    private var track: some View {
        let gap = height * 9 / 104
        let knob = height - gap * 2
        return ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? WidgetPalette.accent : WidgetPalette.raised.opacity(0.6))
                .overlay(Capsule().strokeBorder(on ? .clear : WidgetPalette.line, lineWidth: 1))
            Circle()
                .fill(on ? Color.white : WidgetPalette.raised)
                .overlay(Circle().strokeBorder(on ? .clear : WidgetPalette.line, lineWidth: 1))
                .overlay(
                    LaunchMarkShape()
                        .stroke(
                            on ? WidgetPalette.accent : WidgetPalette.muted,
                            style: LaunchMarkShape.style(for: knob * 0.465, stroke: 0.1125)
                        )
                        .frame(width: knob * 0.465, height: knob * 0.465)
                )
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .padding(gap)
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
        .opacity(status == .connecting || status == .disconnecting ? 0.55 : 1)
        .contentShape(Capsule())
    }
}

private struct DaysPill: View {
    let days: Int
    let language: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.system(size: 10, weight: .medium))
            // Plural rules of the Widget's language, not the system's.
            Text(String(
                format: widgetText("%d days", language),
                locale: Locale(identifier: AppleWidgetLanguage.normalized(language)),
                days
            ))
                .font(WidgetFont.medium(11))
                .lineLimit(1)
        }
        .foregroundStyle(WidgetPalette.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .overlay(Capsule().strokeBorder(WidgetPalette.line, lineWidth: 1))
        .privacySensitive()
    }
}

/// The location as Home's card names it, with the mode under it.
private struct LocationPill: View {
    let details: AppleWidgetDetails
    let language: String

    private var mode: String? {
        switch details.mode {
        case "smart": widgetText("Smart", language)
        case "allVpn": widgetText("Everything through VPN", language)
        case "apps": widgetText("Apps", language)
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                if !details.automatic, let flag = details.flag {
                    Text(verbatim: flag).font(.system(size: 15))
                } else {
                    Image(systemName: "bolt")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.accent)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(details.location ?? "")
                    .font(WidgetFont.semiBold(12))
                    .foregroundStyle(WidgetPalette.ink)
                if let mode {
                    Text(mode)
                        .font(WidgetFont.medium(11))
                        .foregroundStyle(WidgetPalette.muted)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
        .background(Capsule().fill(WidgetPalette.raised.opacity(0.6)))
        .overlay(Capsule().strokeBorder(WidgetPalette.line, lineWidth: 1))
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }
}

/// The App's chevron (`_MarkPainter`): the same proportions at any size.
private struct LaunchMarkShape: Shape {
    var inset: CGFloat = 0.28125

    static func style(for side: CGFloat, stroke: CGFloat = 0.09375) -> StrokeStyle {
        StrokeStyle(lineWidth: side * stroke, lineCap: .round, lineJoin: .round)
    }

    func path(in rect: CGRect) -> Path {
        let side = rect.width
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + side * inset, y: rect.minY + side * (1 - inset * 1.15)))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + side * inset))
        path.addLine(to: CGPoint(x: rect.minX + side * (1 - inset), y: rect.minY + side * (1 - inset * 1.15)))
        return path
    }
}

/// `BrandColors` from the App. The Widget is always dark, like the App.
private enum WidgetPalette {
    static let surface = Color(red: 0x18 / 255, green: 0x16 / 255, blue: 0x1D / 255)
    static let raised = Color(red: 0x23 / 255, green: 0x20 / 255, blue: 0x2A / 255)
    static let line = Color(red: 0x32 / 255, green: 0x2E / 255, blue: 0x39 / 255)
    static let ink = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    static let muted = Color(red: 0xA0 / 255, green: 0x9C / 255, blue: 0xA9 / 255)
    static let accent = Color(red: 0x9C / 255, green: 0x5E / 255, blue: 0xEF / 255)
    static let success = Color(red: 0x4B / 255, green: 0xCB / 255, blue: 0x71 / 255)
    static let warning = Color(red: 0xF5 / 255, green: 0xAE / 255, blue: 0x39 / 255)
}

/// The App's fonts, bundled with the Widget (`UIAppFonts`).
private enum WidgetFont {
    static func wordmark(_ size: CGFloat) -> Font { .custom("Unbounded-SemiBold", fixedSize: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("Manrope-SemiBold", fixedSize: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("Manrope-Medium", fixedSize: size) }
}

private func widgetText(_ key: String, _ language: String) -> String {
    let path = Bundle.main.path(forResource: AppleWidgetLanguage.normalized(language), ofType: "lproj")
    let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
    return bundle.localizedString(forKey: key, value: key, table: "Widget")
}

struct ConnectionWidgetPreviews: PreviewProvider {
    static var previews: some View {
        let details = AppleWidgetDetails(
            location: "Самые быстрые", countryCode: "EU", automatic: true, mode: "smart",
            expiresAt: Date().addingTimeInterval(47 * 86_400)
        )
        ForEach([AppleWidgetStatus.disconnected, .connected, .unknown], id: \.rawValue) { status in
            ForEach(connectionWidgetFamilies, id: \.self) { family in
                ConnectionWidgetView(entry: ConnectionWidgetEntry(
                    date: Date(),
                    snapshot: AppleWidgetSnapshot(status: status, connectedAt: Date().addingTimeInterval(-767)),
                    details: details, languageCode: "ru"
                ))
                .previewContext(WidgetPreviewContext(family: family))
                .previewDisplayName("\(family) · \(status.rawValue)")
            }
        }
    }
}
