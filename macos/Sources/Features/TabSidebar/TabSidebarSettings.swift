import AppKit
import Combine

/// App-wide sidebar preferences. Changes are pushed to every window's container.
final class TabSidebarSettings: ObservableObject {
    static let shared = TabSidebarSettings()
    static let widthRange: ClosedRange<CGFloat> = TabSidebarMetrics.minWidth...TabSidebarMetrics.maxWidth

    private enum Keys {
        static let visible = "TabSidebarVisible"
        static let width = "TabSidebarWidth"
        static let prefs = "TabSidebarPrefsV3"
    }

    @Published var isVisible: Bool {
        didSet { UserDefaults.ghostty.set(isVisible, forKey: Keys.visible) }
    }

    /// How tabs are displayed (view mode, density, titles, metadata).
    /// Off while rendering previews so they never overwrite the saved preferences.
    static var persists = true

    @Published var prefs: TabSidebarPrefs {
        didSet {
            guard Self.persists, prefs != oldValue, let data = try? JSONEncoder().encode(prefs) else { return }
            UserDefaults.ghostty.set(data, forKey: Keys.prefs)
        }
    }

    /// Updated continuously while dragging the divider; call `persistWidth()` when the drag ends so
    /// we do not write preferences on every mouse move.
    @Published var width: CGFloat

    private init() {
        let defaults = UserDefaults.ghostty
        // The sidebar is the point of this fork, so it is on unless the user turned it off.
        isVisible = defaults.object(forKey: Keys.visible) as? Bool ?? true
        let stored = defaults.double(forKey: Keys.width)
        width = stored > 0 ? Self.clamp(CGFloat(stored)) : TabSidebarMetrics.defaultWidth
        prefs = defaults.data(forKey: Keys.prefs)
            .flatMap { try? JSONDecoder().decode(TabSidebarPrefs.self, from: $0) } ?? TabSidebarPrefs()
    }

    func persistWidth() {
        UserDefaults.ghostty.set(Double(width), forKey: Keys.width)
    }

    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, widthRange.lowerBound), widthRange.upperBound)
    }
}

extension Notification.Name {
    /// Posted whenever something the sidebar shows may have changed. Receivers coalesce it.
    static let tabSidebarNeedsRefresh = Notification.Name("com.mitchellh.ghostty.tabSidebarNeedsRefresh")
}

enum TabSidebarEvents {
    /// Cheap enough to call from hot paths: it only posts a notification, and models that are not
    /// visible ignore it until they are shown.
    static func requestRefresh() {
        NotificationCenter.default.post(name: .tabSidebarNeedsRefresh, object: nil)
    }
}
