import Flutter
import UIKit

/// Tells Dart where iOS puts its vertical bar, the column on iPhone Duo that
/// holds the status bar and the camera, so the App's tabs can move into it.
@MainActor
final class VerticalBarApi: @preconcurrency VerticalBarHostApi {
    private let flutterApi: VerticalBarFlutterApi
    private var watcher: UIView?

    init(flutterApi: VerticalBarFlutterApi) {
        self.flutterApi = flutterApi
    }

    func watchVerticalBar() throws {
        guard #available(iOS 27.1, *), let view = Self.appView() else {
            send(nil)
            return
        }
        watcher?.removeFromSuperview()
        let watcher = VerticalBarWatcher { [weak self] bar in self?.send(bar) }
        watcher.frame = view.bounds
        view.addSubview(watcher)
        self.watcher = watcher
    }

    private func send(_ bar: VerticalBar?) {
        Task {
            do {
                try await flutterApi.verticalBarChanged(bar: bar)
            } catch {
                NSLog("Send vertical bar failed: %@", String(describing: error))
            }
        }
    }

    private static func appView() -> UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .compactMap { $0.rootViewController as? FlutterViewController }
            .first?.view
    }
}

/// An invisible view over the App's that reads the bar whenever the safe
/// area, the traits or the reserved regions change, and reports each change.
@available(iOS 27.1, *)
private final class VerticalBarWatcher: UIView {
    private let report: (VerticalBar?) -> Void
    private var reported: VerticalBar??

    init(report: @escaping (VerticalBar?) -> Void) {
        self.report = report
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
            (self: Self, _) in self.setNeedsUpdateConstraints()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // UIKit runs updateConstraints() again when the regions it read change.
    override class var requiresConstraintBasedLayout: Bool { true }

    override func updateConstraints() {
        update()
        super.updateConstraints()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        update()
    }

    private func update() {
        let bar = currentBar()
        guard reported != .some(bar) else { return }
        reported = .some(bar)
        report(bar)
    }

    private func currentBar() -> VerticalBar? {
        let left: Bool
        switch (traitCollection.verticalBarEdge, effectiveUserInterfaceLayoutDirection) {
        case (.leading, .leftToRight), (.trailing, .rightToLeft): left = true
        case (.trailing, .leftToRight), (.leading, .rightToLeft): left = false
        default: return nil
        }
        // The trait names the edge even while no bar shows.
        let width = left ? safeAreaInsets.left : safeAreaInsets.right
        guard width > 0 else { return nil }
        let column = CGRect(x: left ? 0 : bounds.width - width, y: 0, width: width, height: bounds.height)
        // The status bar and the camera are regions too; in landscape the
        // camera sits low in the column, and the tabs end above it.
        let bottom = reservedRegions(kind: .occlusion)
            .map(\.frame)
            .filter { $0.intersects(column) && $0.midY >= column.midY }
            .map(\.minY)
            .min() ?? bounds.height
        return VerticalBar(side: left ? .left : .right, bottom: bottom)
    }
}
