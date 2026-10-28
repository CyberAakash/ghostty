import AppKit
import SwiftUI

// MARK: - Colors

extension TabSidebarRGB {
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// The palette input from any NSColor (the terminal background).
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        self.init(
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded()))
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = TabSidebarPalette(terminal: TabSidebarRGB(hex: 0x17181A))
}

extension EnvironmentValues {
    /// The sidebar's colors, derived from the terminal's background.
    var sidebarPalette: TabSidebarPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Motion (spec part 2B section 2)

enum TabSidebarMotion {
    /// Reduce Motion: every animation collapses to nothing (the spec's alternative for most of them).
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// cubic-bezier(.2,.8,.2,1)
    static func out(_ duration: Double) -> Animation? {
        reduced ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: duration)
    }

    /// cubic-bezier(.4,0,.2,1)
    static func inOut(_ duration: Double) -> Animation? {
        reduced ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }

    /// The layout curve: cubic-bezier(.25,.9,.3,1) over 280 ms.
    static var layout: Animation? {
        reduced ? nil : .spring(response: 0.28, dampingFraction: 0.9)
    }

    static var hover: Animation? { out(0.08) }
    static var pill: Animation? { out(0.10) }
    static var selection: Animation? { out(0.08) }
    static var groupToggle: Animation? { inOut(0.20) }
    static var chevron: Animation? { inOut(0.16) }
    static var swatch: Animation? { out(0.16) }
    static var viewMode: Animation? { out(0.12) }
    static var flash: Animation? { out(0.40) }
}
