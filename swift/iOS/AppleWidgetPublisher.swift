import Foundation
import WidgetKit

enum AppleWidgetPublisher {
    /// `connectedAt` is when the system connected, for the Widget's timer.
    static func publish(_ status: AppleWidgetStatus, connectedAt: Date? = nil) {
        // A missing shared container must never affect the VPN command itself.
        guard let store = AppleWidgetStore.shared,
              (try? store.writeStatus(status, connectedAt: connectedAt)) == true else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
    }

    static func setDetails(_ details: AppleWidgetDetails) throws {
        guard let store = AppleWidgetStore.shared else { return }
        if try store.writeDetails(details) {
            WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
        }
    }

    static func setLanguage(_ code: String) throws {
        guard let store = AppleWidgetStore.shared else { return }
        if try store.writeLanguage(code) {
            WidgetCenter.shared.reloadTimelines(ofKind: AppleWidgetStore.kind)
        }
    }
}
