import AppKit
import SwiftUI

// MARK: - Content (spec part 2A, section 2.3)

/// What the details card shows. Built from the sidebar's data; paths are absolute.
enum TabSidebarCardContent: Equatable {
    struct GroupTag: Equatable {
        var name: String
        var color: TabSidebarGroupColor
    }

    struct Pane: Equatable {
        var title: String
        var path: String
        var kind: String
        var isClaude: Bool
        var status: TabSidebarStatus?
        var exited: Bool
        var bell: Bool
        var branch: String?
        var diff: TabSidebarDiffStats?
        /// "Pane 2 of 3 in “coucou”" for a pane of a multi-pane tab.
        var paneLine: String?
        var group: GroupTag?
    }

    struct TabLine: Equatable {
        var isClaude: Bool
        var title: String
        var status: String?
        var isFocused: Bool
    }

    struct Tab: Equatable {
        var title: String
        var path: String
        var panes: [TabLine]
        var summary: String
        var group: GroupTag?
    }

    struct GroupLine: Equatable {
        var isClaude: Bool
        var title: String
    }

    struct Group: Equatable {
        var name: String
        var color: TabSidebarGroupColor
        var subtitle: String
        var tabs: [GroupLine]
        var totals: String?
    }

    case pane(Pane)
    case tab(Tab)
    case group(Group)

    // MARK: Builders

    static func pane(_ pane: TabSidebarPane, in tab: TabSidebarItem, prefs: TabSidebarPrefs) -> Self {
        var title = pane.title(prefs)
        // "If that title is the cwd, the absolute cwd instead."
        if title == pane.cwdDisplay, !pane.cwd.isEmpty { title = pane.cwd }

        var paneLine: String?
        if tab.panes.count > 1, let index = tab.panes.firstIndex(where: { $0.id == pane.id }) {
            paneLine = "Pane \(index + 1) of \(tab.panes.count)"
            if let name = tab.customName { paneLine! += " in “\(name)”" }
        }

        return .pane(Pane(
            title: title, path: pane.cwd, kind: pane.kindName, isClaude: pane.isClaude,
            status: pane.status, exited: pane.hasExited, bell: pane.hasBell,
            branch: pane.branch, diff: pane.diff, paneLine: paneLine,
            group: tab.group.map { GroupTag(name: $0.name, color: $0.color) }))
    }

    static func tab(_ tab: TabSidebarItem, prefs: TabSidebarPrefs) -> Self {
        guard let focused = tab.focusedPane else {
            return .tab(Tab(title: tab.name(prefs), path: "", panes: [], summary: "", group: nil))
        }
        if tab.panes.count == 1 { return pane(focused, in: tab, prefs: prefs) }

        let focusedIndex = (tab.panes.firstIndex { $0.id == focused.id } ?? 0) + 1
        return .tab(Tab(
            title: tab.customName ?? focused.title(prefs),
            path: focused.cwd,
            panes: tab.panes.map {
                TabLine(isClaude: $0.isClaude, title: $0.title(prefs), status: $0.status?.word, isFocused: $0.id == focused.id)
            },
            summary: "\(tab.panes.count) panes · focused: \(focusedIndex)",
            group: tab.group.map { GroupTag(name: $0.name, color: $0.color) }))
    }

    static func group(_ block: TabSidebarGroupBlock, prefs: TabSidebarPrefs) -> Self {
        let n = block.tabs.count
        var subtitle = "\(n) \(n == 1 ? "tab" : "tabs") · \(block.group.color.localizedName)"
        if block.group.isPinned { subtitle += " · Pinned" }
        subtitle += block.group.isCollapsed ? " · Collapsed" : " · Expanded"

        var counts: [String] = []
        for status in [TabSidebarStatus.working, .done, .error, .cancelled, .blocked] {
            let c = block.tabs.flatMap(\.tab.panes).filter { $0.status == status }.count
            if c > 0, status != .done { counts.append("\(c) \(status.word.lowercased())") }
        }
        let bells = block.tabs.flatMap(\.tab.panes).filter(\.hasBell).count
        if bells > 0 { counts.append("\(bells) bell") }

        return .group(Group(
            name: block.group.name, color: block.group.color, subtitle: subtitle,
            tabs: block.tabs.prefix(5).map { tabBlock in
                let focused = tabBlock.tab.focusedPane
                return GroupLine(isClaude: focused?.isClaude ?? false, title: tabBlock.tab.customName ?? focused?.title(prefs) ?? "Terminal")
            },
            totals: counts.isEmpty ? nil : counts.joined(separator: " · ")))
    }
}

// MARK: - Controller (spec 2.2: timing)

/// The details card beside the sidebar. One reusable panel; it ignores the mouse, never takes focus,
/// and shows after a 600 ms dwell (immediately when "warm"), then follows the pointer row to row.
final class TabSidebarHoverCard {
    static let shared = TabSidebarHoverCard()

    private static let dwell = 0.6
    private static let grace = 0.15
    private static let warmWindow = 0.4
    private static let fade = 0.12

    private var panel: CardPanel?
    private var host: NSHostingView<CardRoot>?
    private var showTask: DispatchWorkItem?
    private var hideTask: DispatchWorkItem?
    private var lastHiddenAt = Date.distantPast
    private var shownContent: TabSidebarCardContent?
    private var palette = TabSidebarPalette(terminal: TabSidebarRGB(hex: 0x17181A))

    private var isVisible: Bool { panel?.isVisible == true && (panel?.alphaValue ?? 0) > 0 }

    /// The pointer entered a row, header or group header. `rowTop` is its top edge in screen coordinates.
    func rowEntered(
        _ content: TabSidebarCardContent, rowTop: CGFloat, window: NSWindow?, palette: TabSidebarPalette, enabled: Bool
    ) {
        hideTask?.cancel()
        showTask?.cancel()
        guard enabled, let window, window.isKeyWindow, NSEvent.pressedMouseButtons == 0 else { return }
        self.palette = palette

        let isWarm = isVisible || Date().timeIntervalSince(lastHiddenAt) < Self.warmWindow
        if isWarm {
            present(content, rowTop: rowTop, window: window, animateMove: isVisible)
            return
        }
        let task = DispatchWorkItem { [weak self] in
            self?.present(content, rowTop: rowTop, window: window, animateMove: false)
        }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: task)
    }

    /// The pointer left every row: hide after a short grace.
    func rowExited() {
        showTask?.cancel()
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.hideNow() }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.grace, execute: task)
    }

    /// Mouse down, scroll, drag, menus, rename, key presses and losing key status all hide it at once.
    func hideNow() {
        showTask?.cancel()
        hideTask?.cancel()
        guard let panel, panel.isVisible else {
            shownContent = nil
            return
        }
        lastHiddenAt = Date()
        shownContent = nil
        if TabSidebarMotion.reduced {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fade
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            if panel?.alphaValue == 0 { panel?.orderOut(nil) }
        })
    }

    /// An open card follows live title changes in place.
    func update(_ content: TabSidebarCardContent) {
        guard isVisible, shownContent != nil, shownContent != content else { return }
        shownContent = content
        host?.rootView = CardRoot(content: content, palette: palette)
        resizeKeepingTop()
    }

    private func present(_ content: TabSidebarCardContent, rowTop: CGFloat, window: NSWindow, animateMove: Bool) {
        guard window.isVisible else { return }

        let panel = self.panel ?? CardPanel()
        self.panel = panel
        let root = CardRoot(content: content, palette: palette)
        if let host {
            host.rootView = root
        } else {
            let host = NSHostingView(rootView: root)
            self.host = host
            panel.contentView = host
        }
        guard let host else { return }

        let size = host.fittingSize
        let shadow = CardRoot.shadowInset
        // x = sidebar trailing edge + 8, y = top of the row, clamped inside the window with an 8 pt margin.
        let x = window.frame.minX + TabSidebarSettings.shared.width + TabSidebarMetrics.cardOffsetX - shadow
        let margin = TabSidebarMetrics.cardWindowMargin
        var top = rowTop + shadow
        top = min(top, window.frame.maxY - margin + shadow)
        top = max(top, window.frame.minY + margin + size.height - shadow)
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

        let wasVisible = isVisible
        shownContent = content

        if !wasVisible {
            panel.setFrame(frame.offsetBy(dx: TabSidebarMotion.reduced ? 0 : -2, dy: 0), display: true)
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = TabSidebarMotion.reduced ? 0.10 : Self.fade
                panel.animator().alphaValue = 1
                if !TabSidebarMotion.reduced { panel.animator().setFrame(frame, display: true) }
                else { panel.setFrame(frame, display: true) }
            }
        } else if animateMove && !TabSidebarMotion.reduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fade
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func resizeKeepingTop() {
        guard let panel, let host else { return }
        let size = host.fittingSize
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
    }
}

private final class CardPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the card draws its own static shadow
        ignoresMouseEvents = true // "Interactive: no"
        level = .floating
        hidesOnDeactivate = true
        collectionBehavior = [.transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Views (spec 2.6)

private struct CardRoot: View {
    /// The panel is larger than the card so the static shadow is not clipped.
    static let shadowInset: CGFloat = 24

    let content: TabSidebarCardContent
    let palette: TabSidebarPalette

    var body: some View {
        TabSidebarDetailsCard(content: content, palette: palette)
            .padding(Self.shadowInset)
            .fixedSize()
    }
}

struct TabSidebarDetailsCard: View {
    let content: TabSidebarCardContent
    let palette: TabSidebarPalette

    private var text: Color { palette.popoverText.color }
    private var text2: Color { palette.popoverText2.color }
    private var border: Color { palette.popoverBorder.color }

    var body: some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.cardLineGap) {
            switch content {
            case .pane(let pane): paneCard(pane)
            case .tab(let tab): tabCard(tab)
            case .group(let group): groupCard(group)
            }
        }
        .padding(TabSidebarMetrics.cardPadding)
        .frame(width: TabSidebarMetrics.cardWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.cardRadius).fill(palette.popover.color))
        .overlay(RoundedRectangle(cornerRadius: TabSidebarMetrics.cardRadius).strokeBorder(border, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0.50 : 0.16), radius: 12, x: 0, y: 8)
    }

    // MARK: Pane

    private func paneCard(_ pane: TabSidebarCardContent.Pane) -> some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.cardLineGap) {
            Text(pane.title)
                .font(.system(size: TabSidebarMetrics.cardTitleFont, design: .monospaced))
                .foregroundColor(text)
                .fixedSize(horizontal: false, vertical: true)
            if !pane.path.isEmpty && pane.path != pane.title {
                Text(pane.path)
                    .font(.system(size: TabSidebarMetrics.cardPathFont, design: .monospaced))
                    .foregroundColor(text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            hairline

            infoLine(icon: pane.isClaude ? .claude : .terminal, color: pane.isClaude ? palette.claude.color : text2) {
                Text(kindText(pane))
            }
            if let branch = pane.branch {
                infoLine(icon: .branch, color: text2) {
                    Text(branch)
                    if let diff = pane.diff { diffBadge(diff).padding(.leading, 4) }
                }
            }
            if let line = pane.paneLine {
                infoLine(icon: .groupPanes, color: text2) { Text(line) }
            }
            if let group = pane.group { groupLine(group) }
        }
    }

    private func kindText(_ pane: TabSidebarCardContent.Pane) -> String {
        var parts = [pane.kind]
        if let status = pane.status { parts[0] += " · \(status.word)" }
        if pane.exited { parts.append("Exited") }
        if pane.bell { parts.append("Bell") }
        return parts.joined(separator: " · ")
    }

    // MARK: Tab

    private func tabCard(_ tab: TabSidebarCardContent.Tab) -> some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.cardLineGap) {
            Text(tab.title)
                .font(.system(size: TabSidebarMetrics.cardTitleFont, weight: .semibold))
                .foregroundColor(text)
                .fixedSize(horizontal: false, vertical: true)
            if !tab.path.isEmpty {
                Text(tab.path)
                    .font(.system(size: TabSidebarMetrics.cardPathFont, design: .monospaced))
                    .foregroundColor(text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            hairline

            ForEach(Array(tab.panes.enumerated()), id: \.offset) { _, line in
                infoLine(icon: line.isClaude ? .claude : .terminal, color: line.isClaude ? palette.claude.color : text2) {
                    Text(line.title)
                        .foregroundColor(line.isFocused ? text : text2)
                        .lineLimit(1)
                    if let status = line.status {
                        Text(status.lowercased()).foregroundColor(palette.popoverText3.color)
                    }
                }
            }
            infoLine(icon: .groupPanes, color: text2) { Text(tab.summary) }
            if let group = tab.group { groupLine(group) }
        }
    }

    // MARK: Group

    private func groupCard(_ group: TabSidebarCardContent.Group) -> some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.cardLineGap) {
            HStack(spacing: 6) {
                Circle().fill(palette.groupBase(group.color).color).frame(width: 8, height: 8)
                Text(group.name)
                    .font(.system(size: TabSidebarMetrics.cardTitleFont, weight: .semibold))
                    .foregroundColor(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(group.subtitle)
                .font(.system(size: TabSidebarMetrics.cardInfoFont))
                .foregroundColor(text2)

            hairline

            ForEach(Array(group.tabs.enumerated()), id: \.offset) { _, line in
                infoLine(icon: line.isClaude ? .claude : .terminal, color: line.isClaude ? palette.claude.color : text2) {
                    Text(line.title).lineLimit(1)
                }
            }
            if let totals = group.totals {
                Text(totals)
                    .font(.system(size: TabSidebarMetrics.cardInfoFont))
                    .foregroundColor(palette.popoverText3.color)
            }
        }
    }

    // MARK: Pieces

    private var hairline: some View {
        Rectangle().fill(border).frame(height: 1)
            .padding(.horizontal, -TabSidebarMetrics.cardPadding)
            .padding(.vertical, 2)
    }

    private func infoLine<Content: View>(
        icon: TabSidebarIcon, color: Color, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            TabSidebarIconView(icon: icon, size: TabSidebarMetrics.cardInfoIcon, color: color)
            HStack(spacing: 4) { content() }
                .font(.system(size: TabSidebarMetrics.cardInfoFont))
                .foregroundColor(text2)
        }
    }

    private func groupLine(_ group: TabSidebarCardContent.GroupTag) -> some View {
        HStack(spacing: 6) {
            Circle().fill(palette.groupBase(group.color).color).frame(width: 8, height: 8)
                .frame(width: TabSidebarMetrics.cardInfoIcon)
            Text(group.name)
                .font(.system(size: TabSidebarMetrics.cardInfoFont))
                .foregroundColor(text2)
        }
    }

    private func diffBadge(_ diff: TabSidebarDiffStats) -> some View {
        HStack(spacing: 4) {
            Text("+\(diff.added)").foregroundColor(palette.done.color)
            Text("−\(diff.removed)").foregroundColor(palette.error.color)
        }
        .font(.system(size: TabSidebarMetrics.diffFont, design: .monospaced))
    }
}
