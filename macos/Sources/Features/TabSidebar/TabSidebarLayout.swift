import Foundation

// This file is pure logic with no UI types, so it can be tested on its own. The rules follow the
// design spec ("Vertical Tab Sidebar UX Design"): spec part 1 section 4-5, part 2A sections 3-5.

// MARK: - Preferences

/// How the sidebar is displayed. Defaults are the spec's defaults (part 1, section 5).
struct TabSidebarPrefs: Codable, Equatable {
    enum ViewAs: String, Codable { case panes, tabs }
    /// Tabs view only: what one tab's row shows.
    enum TabItem: String, Codable { case focusedSession, summary }
    enum Density: String, Codable { case compact, expanded }
    enum PaneTitle: String, Codable { case command, directory, branch }

    var viewAs: ViewAs = .panes
    var tabItem: TabItem = .focusedSession
    var density: Density = .compact
    var paneTitle: PaneTitle = .command
    var showBranch: Bool = true
    var showDirectory: Bool = true
    var showDetailsOnHover: Bool = true
    /// Pane controls (More, Close) on a tab's only pane; always on when there are several.
    var paneControlsOnSinglePanes: Bool = false

    init() {}

    // Tolerant decoding so preferences saved by an older build never break the sidebar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        viewAs = (try? c.decodeIfPresent(ViewAs.self, forKey: .viewAs)) ?? .panes
        tabItem = (try? c.decodeIfPresent(TabItem.self, forKey: .tabItem)) ?? .focusedSession
        density = (try? c.decodeIfPresent(Density.self, forKey: .density)) ?? .compact
        paneTitle = (try? c.decodeIfPresent(PaneTitle.self, forKey: .paneTitle)) ?? .command
        showBranch = (try? c.decodeIfPresent(Bool.self, forKey: .showBranch)) ?? true
        showDirectory = (try? c.decodeIfPresent(Bool.self, forKey: .showDirectory)) ?? true
        showDetailsOnHover = (try? c.decodeIfPresent(Bool.self, forKey: .showDetailsOnHover)) ?? true
        paneControlsOnSinglePanes = (try? c.decodeIfPresent(Bool.self, forKey: .paneControlsOnSinglePanes)) ?? false
    }
}

// MARK: - Status

/// What a Claude Code session is doing. Claude Code puts a glyph first in the terminal title: a
/// star when it is idle (done) and a braille spinner while it works. The other statuses in the
/// design (error, cancelled, waiting for approval) cannot be told from the title, so they are
/// never produced here, but they are part of the type so the views can draw them.
enum TabSidebarStatus: String, Equatable {
    case done, working, error, cancelled, blocked

    var word: String {
        switch self {
        case .done: return "Done"
        case .working: return "Working"
        case .error: return "Error"
        case .cancelled: return "Cancelled"
        case .blocked: return "Waiting for approval"
        }
    }
}

// MARK: - Snapshot types

struct TabSidebarDiffStats: Equatable {
    var added: Int
    var removed: Int
}

/// One terminal surface (a split) inside a tab.
struct TabSidebarPane: Equatable, Identifiable {
    /// The surface's UUID string.
    let id: String
    /// The terminal title as set by the shell or program.
    var rawTitle: String
    /// Absolute working directory ("" when unknown).
    var cwd: String
    /// The working directory with the home folder shown as "~".
    var cwdDisplay: String
    var branch: String?
    var diff: TabSidebarDiffStats?
    var isFocused: Bool
    var hasBell: Bool
    var hasExited: Bool = false

    static let claudeGlyphs: Set<Unicode.Scalar> = Set("✳✻✶✷✸✹✺".unicodeScalars)

    var isClaude: Bool {
        guard let first = rawTitle.unicodeScalars.first else { return false }
        return Self.claudeGlyphs.contains(first) || (0x2800...0x28FF).contains(first.value)
    }

    var status: TabSidebarStatus? {
        guard let first = rawTitle.unicodeScalars.first else { return nil }
        if Self.claudeGlyphs.contains(first) { return .done }
        if (0x2800...0x28FF).contains(first.value) { return .working }
        return nil
    }

    /// The Claude conversation title: the title without its status glyph, or nil when empty.
    var conversationTitle: String? {
        guard isClaude else { return nil }
        let text = String(String.UnicodeScalarView(rawTitle.unicodeScalars.dropFirst()))
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Spec 4.2: the title for "Pane title as".
    func title(_ prefs: TabSidebarPrefs) -> String {
        switch prefs.paneTitle {
        case .command:
            if isClaude { return conversationTitle ?? "Claude Code" }
            let text = rawTitle.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? (cwdDisplay.isEmpty ? "~" : cwdDisplay) : text
        case .directory:
            return cwdDisplay.isEmpty ? "~" : cwdDisplay
        case .branch:
            return branch ?? (cwdDisplay.isEmpty ? "~" : cwdDisplay)
        }
    }

    /// The title text that "Pane title as: Command" would show, whatever the setting.
    var commandTitle: String {
        var copy = TabSidebarPrefs()
        copy.paneTitle = .command
        return title(copy)
    }

    var kindName: String { isClaude ? "Claude Code" : "Terminal" }
}

/// Group attributes. Every member tab carries a copy; they are kept equal.
struct TabSidebarGroup: Equatable, Codable {
    var id: String
    var name: String
    var color: TabSidebarGroupColor
    var isCollapsed: Bool
    var isPinned: Bool
}

/// A snapshot of one tab as the sidebar shows it.
struct TabSidebarItem: Identifiable, Equatable {
    /// The window number of the tab's window.
    let id: Int
    /// The user's name for the tab, or nil to use the automatic title.
    var customName: String?
    var panes: [TabSidebarPane]
    /// The tab's own color (shown only while it is a loose tab).
    var color: TabSidebarGroupColor
    var isSelected: Bool
    var isPinned: Bool
    var group: TabSidebarGroup?
    /// Zero-based position in the tab group, used for the ⌘1…⌘9 hint.
    var position: Int = 0

    var focusedPane: TabSidebarPane? { panes.first(where: \.isFocused) ?? panes.first }
    var hasCustomName: Bool { customName != nil }

    /// A tab header is shown when the tab has more than one pane (Panes view only). A named tab with one
    /// pane has no header: its name is the row's title.
    var showsHeader: Bool { panes.count > 1 }

    /// Spec 4.1: the header text — the name, else the last path component of the focused pane's cwd.
    var headerText: String {
        if let customName { return customName }
        guard let cwd = focusedPane?.cwd, !cwd.isEmpty else { return "~" }
        let component = (cwd as NSString).lastPathComponent
        return component.isEmpty ? "~" : component
    }

    /// The name used in the Tabs view, in cards and in menus.
    func name(_ prefs: TabSidebarPrefs) -> String {
        customName ?? focusedPane?.title(prefs) ?? "Terminal"
    }
}

// MARK: - Row content (what one row shows)

/// A line under a row's title.
struct TabSidebarSubtitle: Equatable {
    enum Kind: Equatable { case branch, directory, changes }
    var kind: Kind
    var text: String
    var diff: TabSidebarDiffStats?
}

/// Everything a pane (or Tabs-view) row draws, resolved from the data and the preferences.
struct TabSidebarRowContent: Equatable {
    var title: String
    /// Path-like titles are head-truncated.
    var titleIsPath: Bool
    /// The Tabs view shows a named tab in the UI font instead of the monospaced one.
    var titleUsesUIFont: Bool
    var subtitles: [TabSidebarSubtitle]
    /// Relaxed shows the branch on its own line; Compact keeps the row to one line and shows it as a chip at the end.
    var branchChip: String?
    var isClaude: Bool
    var status: TabSidebarStatus?
    var hasBell: Bool
    var hasExited: Bool
    /// Tabs view, Focused: the number of panes when there is more than one.
    var paneCount: Int?
    /// Tabs view, Summary: up to three pane lines, then "+ N more".
    var summary: [TabSidebarSummaryLine]
    var moreCount: Int

    static func isPath(_ text: String) -> Bool { text.hasPrefix("~") || text.hasPrefix("/") }
}

struct TabSidebarSummaryLine: Equatable {
    var title: String
    var titleIsPath: Bool
    var isClaude: Bool
    var status: TabSidebarStatus?
}

enum TabSidebarRows {
    /// The subtitle lines for a pane. Compact has none (one line: the branch is a chip, see `branchChip`);
    /// Relaxed shows the branch with its diff, then the directory.
    static func subtitles(for pane: TabSidebarPane, title: String, prefs: TabSidebarPrefs) -> [TabSidebarSubtitle] {
        guard prefs.density == .expanded else { return [] }
        var lines: [TabSidebarSubtitle] = []

        if prefs.showBranch, prefs.paneTitle != .branch, let branch = pane.branch {
            lines.append(.init(kind: .branch, text: branch, diff: pane.diff))
        }
        if prefs.showDirectory, prefs.paneTitle != .directory, !pane.cwdDisplay.isEmpty, pane.cwdDisplay != title {
            lines.append(.init(kind: .directory, text: pane.cwdDisplay, diff: nil))
        }
        // A diff with no branch line gets a "Changes" line of its own.
        if let diff = pane.diff, !lines.contains(where: { $0.kind == .branch }) {
            lines.insert(.init(kind: .changes, text: "Changes", diff: diff), at: 0)
        }
        return lines
    }

    static func branchChip(for pane: TabSidebarPane, prefs: TabSidebarPrefs) -> String? {
        guard prefs.density == .compact, prefs.showBranch, prefs.paneTitle != .branch else { return nil }
        return pane.branch
    }

    /// The row for one pane in the Panes view.
    static func paneRow(_ pane: TabSidebarPane, prefs: TabSidebarPrefs) -> TabSidebarRowContent {
        let title = pane.title(prefs)
        return TabSidebarRowContent(
            title: title,
            titleIsPath: TabSidebarRowContent.isPath(title),
            titleUsesUIFont: false,
            subtitles: subtitles(for: pane, title: title, prefs: prefs),
            branchChip: branchChip(for: pane, prefs: prefs),
            isClaude: pane.isClaude,
            status: pane.status,
            hasBell: pane.hasBell,
            hasExited: pane.hasExited,
            paneCount: nil,
            summary: [],
            moreCount: 0)
    }

    /// The row for a whole tab in the Tabs view (Focused session or Summary).
    static func tabRow(_ tab: TabSidebarItem, prefs: TabSidebarPrefs) -> TabSidebarRowContent {
        guard let pane = tab.focusedPane else {
            return TabSidebarRowContent(
                title: tab.name(prefs), titleIsPath: false, titleUsesUIFont: false, subtitles: [], branchChip: nil,
                isClaude: false, status: nil, hasBell: false, hasExited: false, paneCount: nil,
                summary: [], moreCount: 0)
        }

        var row = paneRow(pane, prefs: prefs)
        if let name = tab.customName {
            row.title = name
            row.titleIsPath = TabSidebarRowContent.isPath(name)
            row.titleUsesUIFont = true
            // The name replaced the title, so directory lines are no longer duplicates of it.
            row.subtitles = subtitles(for: pane, title: name, prefs: prefs)
        }
        row.hasBell = tab.panes.contains(where: \.hasBell)

        if tab.panes.count > 1 {
            if prefs.tabItem == .summary {
                row.subtitles = []
                row.branchChip = nil
                row.summary = tab.panes.prefix(3).map { pane in
                    let text = pane.title(prefs)
                    return TabSidebarSummaryLine(
                        title: text, titleIsPath: TabSidebarRowContent.isPath(text),
                        isClaude: pane.isClaude, status: pane.status)
                }
                row.moreCount = max(0, tab.panes.count - 3)
            } else {
                row.paneCount = tab.panes.count
            }
        }
        return row
    }
}

// MARK: - Blocks

/// One tab's rows: an optional header plus its pane rows (Panes view) or a single row (Tabs view).
struct TabSidebarTabBlock: Identifiable, Equatable {
    var tab: TabSidebarItem
    var headerText: String?
    var rows: [TabSidebarBlockRow]
    var id: Int { tab.id }
}

struct TabSidebarBlockRow: Identifiable, Equatable {
    /// The pane's id in the Panes view; "tab" for the single row of the Tabs view.
    var id: String
    var paneID: String?
    var content: TabSidebarRowContent
    var isSelected: Bool
}

struct TabSidebarGroupBlock: Identifiable, Equatable {
    var group: TabSidebarGroup
    var tabs: [TabSidebarTabBlock]
    /// Collapsed group indicators: statuses present inside, bells, unread.
    var statuses: [TabSidebarStatus]
    var hasBell: Bool
    var containsSelected: Bool
    var id: String { group.id }
}

enum TabSidebarBlock: Identifiable, Equatable {
    case tab(TabSidebarTabBlock)
    case group(TabSidebarGroupBlock)

    var id: String {
        switch self {
        case .tab(let block): return "tab:\(block.id)"
        case .group(let block): return "group:\(block.id)"
        }
    }
}

/// The whole list: the pinned section, then the main list.
struct TabSidebarList: Equatable {
    var pinned: [TabSidebarBlock] = []
    var main: [TabSidebarBlock] = []
    /// True while searching and nothing matched.
    var isEmptyResult = false
}

extension Array where Element == TabSidebarBlock {
    /// Tabs in these blocks, a group counting each of its tabs.
    var tabCount: Int {
        reduce(0) { total, block in
            switch block {
            case .tab: return total + 1
            case .group(let group): return total + group.tabs.count
            }
        }
    }
}

// MARK: - Layout

enum TabSidebarLayout {
    // MARK: Ordering

    /// The "blocks" tabs are arranged in: a loose tab is its own block, a group is one block of
    /// its members, placed where its first member is. Pinned blocks come first, each section in
    /// the existing order (spec 5.1: no automatic sorting).
    static func blocks(_ items: [TabSidebarItem]) -> [[Int]] {
        var seen = Set<String>()
        var all: [(ids: [Int], pinned: Bool)] = []

        for item in items {
            if let group = item.group, !item.isPinned {
                guard seen.insert(group.id).inserted else { continue }
                let members = items.filter { $0.group?.id == group.id && !$0.isPinned }
                all.append((members.map(\.id), group.isPinned))
            } else {
                all.append(([item.id], item.isPinned))
            }
        }
        return all.filter(\.pinned).map(\.ids) + all.filter { !$0.pinned }.map(\.ids)
    }

    /// The order tabs must have in the tab group so the sidebar and the real tab order agree.
    static func desiredOrder(_ items: [TabSidebarItem]) -> [Int] {
        blocks(items).flatMap { $0 }
    }

    // MARK: Search (spec 2A section 3)

    /// Case-insensitive substring. No tokenizing and no fuzzy matching.
    static func paneMatches(_ pane: TabSidebarPane, query: String, prefs: TabSidebarPrefs) -> Bool {
        let fields = [
            pane.title(prefs), pane.commandTitle, pane.conversationTitle ?? "",
            pane.cwdDisplay, pane.branch ?? "",
        ]
        return fields.contains { $0.lowercased().contains(query) }
    }

    // MARK: Building

    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Builds the list to show.
    static func list(items: [TabSidebarItem], prefs: TabSidebarPrefs, query: String = "") -> TabSidebarList {
        let q = normalized(query)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ordered = blocks(items).map { $0.compactMap { byID[$0] } }

        var pinned: [TabSidebarBlock] = []
        var main: [TabSidebarBlock] = []

        for members in ordered {
            guard let first = members.first else { continue }
            let isPinnedBlock = first.isPinned || (first.group?.isPinned ?? false)

            let built: TabSidebarBlock?
            if let group = first.group, !first.isPinned {
                built = groupBlock(group, members: members, prefs: prefs, query: q)
            } else {
                built = tabBlock(first, prefs: prefs, query: q, forceAllPanes: false).map { .tab($0) }
            }
            if let built {
                if isPinnedBlock { pinned.append(built) } else { main.append(built) }
            }
        }

        var result = TabSidebarList(pinned: pinned, main: main)
        result.isEmptyResult = !q.isEmpty && pinned.isEmpty && main.isEmpty
        return result
    }

    private static func groupBlock(
        _ group: TabSidebarGroup,
        members: [TabSidebarItem],
        prefs: TabSidebarPrefs,
        query: String
    ) -> TabSidebarBlock? {
        let groupMatches = !query.isEmpty && group.name.lowercased().contains(query)
        var tabs: [TabSidebarTabBlock] = []
        for member in members {
            // A matching group name shows all of its tabs with all their panes.
            if let block = tabBlock(member, prefs: prefs, query: groupMatches ? "" : query, forceAllPanes: false) {
                tabs.append(block)
            }
        }
        guard !tabs.isEmpty else { return nil }

        var statuses: [TabSidebarStatus] = []
        for status in [TabSidebarStatus.working, .error, .blocked, .cancelled] {
            if members.contains(where: { $0.panes.contains { $0.status == status } }) { statuses.append(status) }
        }
        var shown = group
        // Searching renders the group expanded without touching its stored state.
        if !query.isEmpty { shown.isCollapsed = false }
        return .group(TabSidebarGroupBlock(
            group: shown,
            tabs: tabs,
            statuses: statuses,
            hasBell: members.contains { $0.panes.contains(where: \.hasBell) },
            containsSelected: members.contains(where: \.isSelected)))
    }

    private static func tabBlock(
        _ tab: TabSidebarItem,
        prefs: TabSidebarPrefs,
        query: String,
        forceAllPanes: Bool
    ) -> TabSidebarTabBlock? {
        var visiblePanes = tab.panes

        if !query.isEmpty {
            let nameMatches = (tab.customName ?? "").lowercased().contains(query)
            let matching = tab.panes.filter { paneMatches($0, query: query, prefs: prefs) }
            // A tab-name match shows all of the tab's panes; otherwise only the matching ones.
            if nameMatches {
                visiblePanes = tab.panes
            } else if matching.isEmpty {
                return nil
            } else {
                visiblePanes = matching
            }
        }

        if prefs.viewAs == .tabs || tab.panes.isEmpty {
            let row = TabSidebarBlockRow(
                id: "tab", paneID: nil, content: TabSidebarRows.tabRow(tab, prefs: prefs), isSelected: tab.isSelected)
            return TabSidebarTabBlock(tab: tab, headerText: nil, rows: [row])
        }

        let focusedID = tab.focusedPane?.id
        let isSingle = tab.panes.count == 1
        let rows = visiblePanes.map { pane -> TabSidebarBlockRow in
            var content = TabSidebarRows.paneRow(pane, prefs: prefs)
            // A named tab with one pane has no header: its name is the row's title.
            if isSingle, let name = tab.customName {
                content.title = name
                content.titleIsPath = false
                content.titleUsesUIFont = true
            }
            return TabSidebarBlockRow(
                id: pane.id, paneID: pane.id, content: content,
                // Only the focused pane of the selected tab is highlighted.
                isSelected: tab.isSelected && pane.id == focusedID)
        }
        return TabSidebarTabBlock(tab: tab, headerText: tab.panes.count > 1 ? tab.headerText : nil, rows: rows)
    }

    // MARK: Names

    /// Spec: "New group color: first unused of red, orange, yellow, green, blue, purple; else blue".
    static func nextGroupColor(used: [TabSidebarGroupColor]) -> TabSidebarGroupColor {
        let order: [TabSidebarGroupColor] = [.red, .orange, .yellow, .green, .blue, .purple]
        return order.first { !used.contains($0) } ?? .blue
    }

    // MARK: Moving

    /// Puts `moving` directly before `target` (or at the end for nil).
    static func orderAfterMove(_ ids: [Int], moving: Int, before target: Int?) -> [Int] {
        var result = ids.filter { $0 != moving }
        if let target, let index = result.firstIndex(of: target) {
            result.insert(moving, at: index)
        } else {
            result.append(moving)
        }
        return result
    }

    /// Puts `moving` directly after `target`.
    static func orderAfterMove(_ ids: [Int], moving: Int, after target: Int) -> [Int] {
        var result = ids.filter { $0 != moving }
        if let index = result.firstIndex(of: target) {
            result.insert(moving, at: index + 1)
        } else {
            result.append(moving)
        }
        return result
    }

    /// Moves a group's members, as one run, before or after the block that contains `anchor`
    /// (or to the end for nil).
    static func orderAfterMoveBlock(_ ids: [Int], members: [Int], anchor: Int?, before: Bool, items: [TabSidebarItem]) -> [Int] {
        let moving = Set(members)
        let remaining = ids.filter { !moving.contains($0) }
        let remainingItems = items.filter { !moving.contains($0.id) }

        guard let anchor, let block = blocks(remainingItems).first(where: { $0.contains(anchor) }),
              let first = remaining.firstIndex(of: block.first!),
              let last = remaining.firstIndex(of: block.last!) else {
            return remaining + members
        }

        var result = remaining
        result.insert(contentsOf: members, at: before ? first : last + 1)
        return result
    }
}
