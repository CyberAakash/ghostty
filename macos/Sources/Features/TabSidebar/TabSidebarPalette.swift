import Foundation

/// An sRGB color with 8-bit channels. All sidebar colors are opaque.
struct TabSidebarRGB: Equatable {
    var r: Int
    var g: Int
    var b: Int

    init(_ r: Int, _ g: Int, _ b: Int) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        self.init(Int((hex >> 16) & 0xFF), Int((hex >> 8) & 0xFF), Int(hex & 0xFF))
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    static let white = TabSidebarRGB(255, 255, 255)
    static let black = TabSidebarRGB(0, 0, 0)

    /// CSS `color-mix(in srgb, a, b p%)`: each gamma-encoded channel interpolates linearly.
    static func mix(_ a: TabSidebarRGB, _ b: TabSidebarRGB, _ p: Double) -> TabSidebarRGB {
        func channel(_ x: Int, _ y: Int) -> Int {
            min(255, max(0, Int((Double(x) * (1 - p) + Double(y) * p).rounded())))
        }
        return TabSidebarRGB(channel(a.r, b.r), channel(a.g, b.g), channel(a.b, b.b))
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Int) -> Double {
            let s = Double(c) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    static func contrast(_ a: TabSidebarRGB, _ b: TabSidebarRGB) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// The six group colors (plus none). Their base colors are fixed per theme; tint, border and tile
/// are derived from the sidebar so they sit well on any terminal background.
enum TabSidebarGroupColor: String, CaseIterable, Codable {
    case none, red, orange, yellow, green, blue, purple

    func base(isDark: Bool) -> TabSidebarRGB {
        switch (self, isDark) {
        case (.none, true): return .init(hex: 0x98989D)
        case (.none, false): return .init(hex: 0x6E6E73)
        case (.red, true): return .init(hex: 0xFF6961)
        case (.red, false): return .init(hex: 0xD70015)
        case (.orange, true): return .init(hex: 0xFFA03A)
        case (.orange, false): return .init(hex: 0xC93400)
        case (.yellow, true): return .init(hex: 0xFFD60A)
        case (.yellow, false): return .init(hex: 0x946200)
        case (.green, true): return .init(hex: 0x32D74B)
        case (.green, false): return .init(hex: 0x1E7A35)
        case (.blue, true): return .init(hex: 0x409CFF)
        case (.blue, false): return .init(hex: 0x0040DD)
        case (.purple, true): return .init(hex: 0xDA8FFF)
        case (.purple, false): return .init(hex: 0x8944AB)
        }
    }

    var localizedName: String {
        switch self {
        case .none: return "None"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
}

/// Every color the sidebar uses, derived from the terminal's background (see the design spec,
/// section 1). Pure math with no UI types, so it can be unit tested against the spec's tables.
struct TabSidebarPalette: Equatable {
    let terminal: TabSidebarRGB
    let isDark: Bool
    /// White on dark themes, black on light ones.
    let ink: TabSidebarRGB

    let sidebar: TabSidebarRGB
    let field: TabSidebarRGB
    let hairline: TabSidebarRGB
    let text: TabSidebarRGB
    let text2: TabSidebarRGB
    let text3: TabSidebarRGB
    let glyph: TabSidebarRGB

    let popover: TabSidebarRGB
    let popoverBorder: TabSidebarRGB
    let popoverHover: TabSidebarRGB
    let popoverText: TabSidebarRGB
    let popoverText2: TabSidebarRGB
    let popoverText3: TabSidebarRGB
    let segmentedTrack: TabSidebarRGB
    let segmentedSelected: TabSidebarRGB

    let claude: TabSidebarRGB
    let done: TabSidebarRGB
    let doneGlyph: TabSidebarRGB
    let working: TabSidebarRGB
    let error: TabSidebarRGB
    let errorGlyph: TabSidebarRGB
    let cancelled: TabSidebarRGB
    let cancelledGlyph: TabSidebarRGB
    let blocked: TabSidebarRGB
    let blockedGlyph: TabSidebarRGB
    let accent: TabSidebarRGB

    init(terminal: TabSidebarRGB) {
        self.terminal = terminal
        isDark = TabSidebarRGB.contrast(terminal, .white) >= TabSidebarRGB.contrast(terminal, .black)
        ink = isDark ? .white : .black
        let d = isDark

        func mix(_ a: TabSidebarRGB, _ b: TabSidebarRGB, _ p: Double) -> TabSidebarRGB { .mix(a, b, p) }

        sidebar = mix(terminal, ink, d ? 0.035 : 0.03)
        field = mix(sidebar, ink, d ? 0.075 : 0.06)
        hairline = mix(sidebar, ink, 0.10)
        text = mix(sidebar, ink, d ? 0.92 : 0.88)
        text2 = mix(sidebar, ink, d ? 0.74 : 0.66)
        text3 = mix(sidebar, ink, d ? 0.58 : 0.62)
        glyph = mix(sidebar, ink, d ? 0.78 : 0.70)

        popover = mix(terminal, .white, d ? 0.105 : 0.88)
        popoverBorder = mix(popover, ink, d ? 0.12 : 0.14)
        popoverHover = mix(popover, ink, d ? 0.07 : 0.05)
        popoverText = mix(popover, ink, d ? 0.92 : 0.88)
        popoverText2 = mix(popover, ink, d ? 0.64 : 0.62)
        popoverText3 = mix(popover, ink, d ? 0.40 : 0.35)
        segmentedTrack = mix(popover, ink, 0.08)
        segmentedSelected = d ? mix(popover, .white, 0.16) : .white

        claude = .init(hex: d ? 0xD97757 : 0xC15F3C)
        done = .init(hex: d ? 0x32D74B : 0x1E7A35)
        doneGlyph = .init(hex: d ? 0x1D1D1F : 0xFFFFFF)
        working = .init(hex: d ? 0x0A84FF : 0x007AFF)
        error = .init(hex: d ? 0xFF453A : 0xD70015)
        errorGlyph = .white
        cancelled = .init(hex: 0x8E8E93)
        cancelledGlyph = .white
        blocked = .init(hex: d ? 0xFFD60A : 0xC27C00)
        blockedGlyph = .init(hex: d ? 0x1D1D1F : 0xFFFFFF)
        accent = .init(hex: d ? 0x0A84FF : 0x007AFF)
    }

    // MARK: Row states (mixed over the row's base surface: the sidebar, or a group's tint)

    /// The Pinned container's own fill: a step darker or lighter than the sidebar, so it reads as a shelf.
    var pinnedFill: TabSidebarRGB { .mix(sidebar, ink, isDark ? 0.045 : 0.035) }
    func hover(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.06 : 0.045) }
    func pressed(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.095 : 0.08) }
    func selected(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.115 : 0.095) }
    func selectedHover(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.135 : 0.11) }
    func selectedBorder(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.19 : 0.17) }
    func tile(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.10 : 0.075) }
    func claudeTile(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, claude, isDark ? 0.20 : 0.14) }
    /// The fill of the diff badge: the row's fill nudged toward ink by the field step.
    func diffBadgeFill(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, isDark ? 0.075 : 0.06) }
    func highlight(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, accent, 0.38) }
    func skeleton(over base: TabSidebarRGB) -> TabSidebarRGB { .mix(base, ink, 0.10) }
    func focusHalo() -> TabSidebarRGB { .mix(sidebar, accent, isDark ? 0.45 : 0.40) }
    func settleFlash() -> TabSidebarRGB { .mix(sidebar, accent, isDark ? 0.22 : 0.18) }

    // MARK: Groups

    func groupBase(_ color: TabSidebarGroupColor) -> TabSidebarRGB { color.base(isDark: isDark) }
    /// A group with no color is neutral: fill ink +6%, border ink +14%, no rail.
    func groupTint(_ color: TabSidebarGroupColor) -> TabSidebarRGB {
        if color == .none { return .mix(sidebar, ink, 0.06) }
        return .mix(sidebar, groupBase(color), isDark ? 0.13 : 0.10)
    }
    func groupBorder(_ color: TabSidebarGroupColor) -> TabSidebarRGB {
        if color == .none { return .mix(sidebar, ink, 0.14) }
        return .mix(sidebar, groupBase(color), isDark ? 0.34 : 0.32)
    }
    /// The icon fill of a colored loose tab.
    func groupTile(_ color: TabSidebarGroupColor) -> TabSidebarRGB {
        .mix(sidebar, groupBase(color), isDark ? 0.30 : 0.22)
    }
    func groupCountPill(_ color: TabSidebarGroupColor) -> TabSidebarRGB { .mix(groupTint(color), ink, 0.08) }
    func groupIntoFill(_ color: TabSidebarGroupColor) -> TabSidebarRGB { .mix(groupTint(color), ink, 0.04) }
}
