import AppKit
import SwiftUI

// Rows, tab headers and their parts. Every number is in TabSidebarMetrics (the design spec).

/// Everything about a row that comes from the model rather than its own data. The list computes it
/// so that an unchanged row is not re-rendered when something unrelated changes.
struct TabSidebarRowState: Equatable {
    var isEditing = false
    var showsFocusRing = false
    /// The row (or its whole block) is the source of the drag in progress.
    var isDragSource = false
    var isDragging = false
    var menuOpen = false
    var flash = false
}

// MARK: - Row

struct TabSidebarRowView: View, Equatable {
    let model: TabSidebarModel
    let palette: TabSidebarPalette
    let tab: TabSidebarItem
    let row: TabSidebarBlockRow
    /// The surface the row sits on: the sidebar, or a group's tint.
    let base: TabSidebarRGB
    let state: TabSidebarRowState
    let query: String
    let density: TabSidebarPrefs.Density
    let viewAs: TabSidebarPrefs.ViewAs
    let isPinnedContext: Bool
    let positionLabel: String?

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var draft = ""

    static func == (a: Self, b: Self) -> Bool {
        a.tab == b.tab && a.row == b.row && a.palette == b.palette && a.base == b.base && a.state == b.state
            && a.query == b.query && a.density == b.density && a.viewAs == b.viewAs
            && a.isPinnedContext == b.isPinnedContext && a.positionLabel == b.positionLabel
    }

    private var content: TabSidebarRowContent { row.content }
    private var key: String { TabSidebarFocusKey.row(tab: tab.id, pane: row.paneID).stringKey }
    private var isRelaxed: Bool { density == .expanded }
    private var isExpandedLayout: Bool { !content.summary.isEmpty }

    private var minHeight: CGFloat {
        guard isRelaxed else { return TabSidebarMetrics.rowMinHeightOneLine }
        let hasDetail = !content.subtitles.isEmpty || isExpandedLayout
        return hasDetail ? TabSidebarMetrics.relaxedMinHeightTwoLines : TabSidebarMetrics.relaxedMinHeight
    }

    var body: some View {
        HStack(alignment: isExpandedLayout ? .top : .center, spacing: TabSidebarMetrics.rowIconGap) {
            tile
            VStack(alignment: .leading, spacing: TabSidebarMetrics.subtitleGapAbove) {
                titleLine
                detailLines
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, isRelaxed ? TabSidebarMetrics.relaxedPaddingVertical : TabSidebarMetrics.rowPaddingVertical)
        .padding(.horizontal, isRelaxed ? TabSidebarMetrics.relaxedPaddingHorizontal : TabSidebarMetrics.rowPaddingHorizontal)
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius).fill(fill.color))
        .overlay(border)
        .overlay(alignment: .leading) { colorRail }
        .overlay(alignment: .topTrailing) { pill }
        .contentShape(Rectangle())
        .opacity(state.isDragSource ? TabSidebarMetrics.sourceOpacity : 1)
        .animation(TabSidebarMotion.hover, value: isHovering)
        .animation(TabSidebarMotion.selection, value: row.isSelected)
        .sidebarSurface(
            source: .tab(tab.id), frameKind: .tabBlock(tab.id), ghost: ghostInfo,
            onPress: { isPressed = $0 }, onClick: clicked, onRight: showMenu,
            onMiddle: { model.close(tab.id) }, onHover: hoverChanged)
        .padding(.vertical, isRelaxed ? TabSidebarMetrics.relaxedRowMargin : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(row.isSelected ? "selected" : "")
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(row.isSelected ? [.isButton, .isSelected] : .isButton)
        .modifier(RowAccessibilityActions(model: model, tab: tab, paneID: row.paneID, showMenu: showMenu))
    }

    // MARK: Tile

    private var tile: some View {
        TabSidebarTile(
            palette: palette, base: base, rowFill: fill,
            isClaude: content.isClaude, status: content.hasExited ? nil : content.status,
            tabColor: tab.group == nil ? tab.color : .none, exited: content.hasExited,
            animating: model.isAnimating, size: isRelaxed ? TabSidebarMetrics.relaxedTile : TabSidebarMetrics.tile)
    }

    // MARK: Text

    private var titleColor: Color {
        (content.hasExited ? palette.text3 : palette.text).color
    }

    @ViewBuilder
    private var titleLine: some View {
        if state.isEditing && editsOnThisRow {
            RenameField(
                palette: palette, initial: tab.name(model.prefs), isGroup: false,
                onCommit: { model.commitRename(tab: tab.id, to: $0) }, onCancel: model.cancelRename)
        } else {
            highlight(content.title)
                .font(titleFont)
                .foregroundColor(titleColor)
                .lineLimit(1)
                .truncationMode(content.titleIsPath ? .head : .tail)
                .reportFrame(.rowTitle(key), to: model.geometry)
        }
    }

    private var titleSize: CGFloat { isRelaxed ? TabSidebarMetrics.relaxedTitleFont : TabSidebarMetrics.titleFont }

    private var titleFont: Font {
        let weight: Font.Weight = content.hasBell ? .semibold : .regular
        if content.titleUsesUIFont {
            return .system(size: titleSize, weight: .medium)
        }
        return .system(size: titleSize, weight: weight, design: .monospaced)
    }

    /// The rename field lives on the tab header when the tab shows one; otherwise on its row.
    private var editsOnThisRow: Bool {
        viewAs == .tabs || !tab.showsHeader
    }

    @ViewBuilder
    private var detailLines: some View {
        if !content.summary.isEmpty {
            ForEach(Array(content.summary.enumerated()), id: \.offset) { _, line in
                summaryLine(line)
            }
            if content.moreCount > 0 {
                Text("+ \(content.moreCount) more")
                    .font(.system(size: TabSidebarMetrics.subtitleFont))
                    .foregroundColor(palette.text3.color)
                    .padding(.leading, TabSidebarMetrics.moreLeading)
                    .frame(height: TabSidebarMetrics.subtitleLine, alignment: .leading)
            }
        } else {
            ForEach(Array(content.subtitles.enumerated()), id: \.offset) { _, subtitle in
                subtitleLine(subtitle)
            }
        }
    }

    private func subtitleLine(_ subtitle: TabSidebarSubtitle) -> some View {
        HStack(spacing: TabSidebarMetrics.subtitleIconGap) {
            TabSidebarIconView(
                icon: icon(for: subtitle.kind), size: TabSidebarMetrics.subtitleIcon, color: palette.text3.color)
            highlight(subtitle.text)
                .font(.system(size: TabSidebarMetrics.subtitleFont))
                .foregroundColor(palette.text2.color)
                .lineLimit(1)
                .truncationMode(TabSidebarRowContent.isPath(subtitle.text) ? .head : .tail)
            if let diff = subtitle.diff {
                Spacer(minLength: 4)
                TabSidebarDiffBadge(palette: palette, base: fill, stats: diff)
            }
        }
        .frame(height: TabSidebarMetrics.subtitleLine)
    }

    private func icon(for kind: TabSidebarSubtitle.Kind) -> TabSidebarIcon {
        switch kind {
        case .branch: return .branch
        case .directory: return .folder
        case .changes: return .diffChanges
        }
    }

    private func summaryLine(_ line: TabSidebarSummaryLine) -> some View {
        HStack(spacing: TabSidebarMetrics.summaryGap) {
            TabSidebarIconView(
                icon: line.isClaude ? .claude : .terminal, size: TabSidebarMetrics.summaryGlyph,
                color: line.isClaude ? palette.claude.color : palette.text3.color)
                .frame(width: TabSidebarMetrics.summaryGlyphSlot)
            highlight(line.title)
                .font(.system(size: TabSidebarMetrics.summaryFont, design: .monospaced))
                .foregroundColor(palette.text2.color)
                .lineLimit(1)
                .truncationMode(line.titleIsPath ? .head : .tail)
            if let status = line.status {
                TabSidebarStatusBadge(
                    palette: palette, status: status, size: TabSidebarMetrics.summaryBadge,
                    rowFill: fill, ring: false, animating: model.isAnimating)
            }
        }
        .frame(height: TabSidebarMetrics.subtitleLine)
    }

    /// Spec 2A section 3: the first occurrence of the query is marked.
    private func highlight(_ text: String) -> Text {
        let needle = TabSidebarLayout.normalized(query)
        guard !needle.isEmpty, let range = text.range(of: needle, options: .caseInsensitive) else { return Text(text) }
        var attributed = AttributedString(text)
        if let lower = AttributedString.Index(range.lowerBound, within: attributed),
           let upper = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[lower..<upper].backgroundColor = palette.highlight(over: fill).color
        }
        return Text(attributed)
    }

    // MARK: Trailing indicators

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: TabSidebarMetrics.trailingIndicatorGap) {
            if content.hasExited {
                Text("Exited")
                    .font(.system(size: 11))
                    .foregroundColor(palette.text3.color)
            }
            if content.hasBell {
                TabSidebarIconView(icon: .bell, size: TabSidebarMetrics.trailingBell, color: palette.blocked.color)
                    .help("Bell")
            }
            if tab.isPinned && tab.group == nil && !(isHovering || state.menuOpen) {
                TabSidebarIconView(icon: .pin, size: 10, color: palette.text3.color, stroke: 1.75)
                    .accessibilityHidden(true)
            }
            if let chip = content.branchChip {
                HStack(spacing: 3) {
                    TabSidebarIconView(icon: .branch, size: TabSidebarMetrics.subtitleIcon, color: palette.text3.color)
                    Text(chip)
                        .font(.system(size: TabSidebarMetrics.diffFont))
                        .foregroundColor(palette.text2.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, TabSidebarMetrics.diffPaddingHorizontal)
                .frame(height: 16)
                .frame(maxWidth: TabSidebarMetrics.branchChipMaxWidth)
                .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.diffRadius).fill(palette.diffBadgeFill(over: fill).color))
                .fixedSize(horizontal: true, vertical: false)
            }
            if let count = content.paneCount {
                HStack(spacing: 3) {
                    TabSidebarIconView(icon: .groupPanes, size: 11, color: palette.text3.color)
                    Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundColor(palette.text3.color)
                }
            }
        }
        .padding(.top, isExpandedLayout ? 2 : 0)
    }

    // MARK: Fills

    private var fill: TabSidebarRGB {
        if row.isSelected { return isHovering ? palette.selectedHover(over: base) : palette.selected(over: base) }
        if isPressed { return palette.pressed(over: base) }
        if isHovering && !state.isDragging { return palette.hover(over: base) }
        return base
    }

    @ViewBuilder
    private var border: some View {
        if state.showsFocusRing {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
                .strokeBorder(palette.accent.color, lineWidth: TabSidebarMetrics.keyboardFocusRing)
        } else if row.isSelected {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
                .strokeBorder(palette.selectedBorder(over: base).color, lineWidth: TabSidebarMetrics.selectedBorder)
        }
    }

    /// A colored loose tab carries a 3 pt rail down its left edge, like a group does.
    @ViewBuilder
    private var colorRail: some View {
        if tab.group == nil, tab.color != .none {
            Rectangle()
                .fill(palette.groupBase(tab.color).color)
                .frame(width: TabSidebarMetrics.groupRail)
                .clipShape(RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius))
                .allowsHitTesting(false)
        }
    }

    // MARK: Pill

    @ViewBuilder
    private var pill: some View {
        if (isHovering || state.menuOpen) && !state.isDragging {
            let inGroup = tab.group != nil
            let inPinnedGroup = tab.group?.isPinned == true
            if !inPinnedGroup {
            TabSidebarPill(
                palette: palette,
                showsMenu: !inGroup,
                showsClose: !(tab.isPinned && tab.group == nil),
                showsUnpin: tab.isPinned && tab.group == nil,
                closeHelp: row.paneID != nil && tab.panes.count > 1 && viewAs == .panes ? "Close Pane" : "Close Tab",
                menuHelp: "Pane Options",
                onMenu: showMenu,
                onClose: closePressed,
                onUnpin: { model.togglePinned(tab.id) })
                .padding(.top, isRelaxed ? TabSidebarMetrics.pillTopRelaxed : TabSidebarMetrics.pillTop)
                .padding(.trailing, isRelaxed ? TabSidebarMetrics.pillTrailingRelaxed : TabSidebarMetrics.pillTrailing)
                .transition(.opacity)
            }
        }
    }

    // MARK: Actions

    private func clicked(_ count: Int, _ windowPoint: CGPoint) {
        model.select(tab.id, pane: row.paneID)
        if count >= 2, model.geometry.contains(.rowTitle(key), windowPoint: windowPoint) {
            model.beginRename(tab: tab.id)
        }
    }

    private func closePressed() {
        if let paneID = row.paneID, viewAs == .panes, tab.panes.count > 1 {
            model.close(tab.id, pane: paneID)
        } else {
            model.close(tab.id)
        }
    }

    private func showMenu() {
        let menu = TabSidebarMenus.tabMenu(model, tab: tab.id, pane: row.paneID ?? tab.focusedPane?.id)
        TabSidebarMenus.popUp(menu, owner: key, model: model)
    }

    private func hoverChanged(_ inside: Bool, _ screenTop: CGFloat) {
        isHovering = inside
        guard !state.isDragging, model.editing == nil else { return }
        if inside {
            let card: TabSidebarCardContent
            if viewAs == .tabs {
                card = .tab(tab, prefs: model.prefs)
            } else if let pane = tab.panes.first(where: { $0.id == row.paneID }) {
                card = .pane(pane, in: tab, prefs: model.prefs)
            } else {
                return
            }
            TabSidebarHoverCard.shared.rowEntered(
                card, rowTop: screenTop, window: model.window, palette: palette,
                enabled: model.prefs.showDetailsOnHover && model.menuOwner == nil)
        } else {
            TabSidebarHoverCard.shared.rowExited()
        }
    }

    private func ghostInfo() -> TabSidebarGhostModel.Info {
        let pane = tab.panes.first { $0.id == row.paneID }
        let title = tab.customName ?? pane?.title(model.prefs) ?? content.title
        return .init(
            title: title, isClaude: content.isClaude,
            paneCount: tab.panes.count > 1 ? tab.panes.count : nil, group: nil,
            width: min(TabSidebarMetrics.ghostMaxWidth, model.geometry.view(.tabBlock(tab.id))?.bounds.width ?? 260))
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        var parts = [content.title, content.isClaude ? "Claude Code" : "terminal"]
        if let status = content.status, !content.hasExited { parts.append(status.word.lowercased()) }
        if let branch = tab.panes.first(where: { $0.id == row.paneID })?.branch { parts.append("branch \(branch)") }
        if let diff = tab.focusedPane?.diff { parts.append("\(diff.added) lines added, \(diff.removed) removed") }
        if let group = tab.group { parts.append("in \(group.name)") }
        if let position = positionLabel { parts.append(position) }
        if content.hasBell { parts.append("bell") }
        if content.hasExited { parts.append("process exited") }
        return parts.joined(separator: ", ")
    }

    private var accessibilityHint: String {
        let pane = tab.panes.first { $0.id == row.paneID } ?? tab.focusedPane
        return [pane?.cwd, pane?.kindName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func isHoveringBinding() -> Bool { isHovering }
}

private struct RowAccessibilityActions: ViewModifier {
    let model: TabSidebarModel
    let tab: TabSidebarItem
    let paneID: String?
    let showMenu: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Select") { model.select(tab.id, pane: paneID) }
            .accessibilityAction(named: "Rename Tab") { model.beginRename(tab: tab.id) }
            .accessibilityAction(named: "Close Tab") { model.close(tab.id) }
            .accessibilityAction(named: tab.isPinned ? "Unpin Tab" : "Pin Tab") { model.togglePinned(tab.id) }
            .accessibilityAction(named: "Move Up") { model.move(.tab(tab.id), down: false) }
            .accessibilityAction(named: "Move Down") { model.move(.tab(tab.id), down: true) }
            .accessibilityAction(named: "Show Menu", showMenu)
    }
}

// MARK: - Tab header (Panes view)

struct TabSidebarTabHeaderView: View, Equatable {
    let model: TabSidebarModel
    let palette: TabSidebarPalette
    let tab: TabSidebarItem
    let text: String
    let base: TabSidebarRGB
    let state: TabSidebarRowState
    let isCollapsed: Bool

    @State private var isHovering = false
    @State private var isPressed = false

    static func == (a: Self, b: Self) -> Bool {
        a.tab == b.tab && a.text == b.text && a.palette == b.palette && a.base == b.base && a.state == b.state
            && a.isCollapsed == b.isCollapsed
    }

    private var key: String { "header:\(tab.id)" }

    /// A colored loose tab tints its header; otherwise the glyph is quiet.
    private var accent: Color {
        if tab.group == nil, tab.color != .none { return palette.groupBase(tab.color).color }
        return palette.text2.color
    }

    private var fill: Color {
        if isPressed { return palette.pressed(over: base).color }
        if isHovering { return palette.hover(over: base).color }
        return .clear
    }

    var body: some View {
        HStack(spacing: TabSidebarMetrics.tabHeaderGap) {
            TabSidebarDisclosure(
                palette: palette, isCollapsed: isCollapsed, box: TabSidebarMetrics.tabHeaderChevronBox,
                label: isCollapsed ? "Show panes" : "Hide panes") { model.toggleTabCollapsed(tab.id) }
            TabSidebarIconView(icon: .split, size: TabSidebarMetrics.tabHeaderIcon, color: accent)
            if state.isEditing {
                RenameField(
                    palette: palette, initial: tab.name(model.prefs), isGroup: false,
                    onCommit: { model.commitRename(tab: tab.id, to: $0) }, onCancel: model.cancelRename)
            } else {
                Text(text)
                    .font(.system(size: TabSidebarMetrics.groupHeaderFont, weight: .semibold))
                    .foregroundColor(palette.text.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .reportFrame(.rowTitle(key), to: model.geometry)
            }
            Text("\(tab.panes.count)")
                .font(.system(size: TabSidebarMetrics.tabCountFont, weight: .medium).monospacedDigit())
                .foregroundColor(palette.text2.color)
                .padding(.horizontal, TabSidebarMetrics.tabCountPadding)
                .frame(height: 14)
                .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.tabCountRadius)
                    .fill(TabSidebarRGB.mix(base, palette.ink, 0.08).color))
                .fixedSize()
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            if (isHovering || state.menuOpen) && !state.isDragging {
                TabSidebarHeaderButton(palette: palette, icon: .ellipsisVertical, help: "Tab Options", action: showMenu)
            }
        }
        .padding(.leading, TabSidebarMetrics.tabHeaderPaddingLeading)
        .padding(.trailing, TabSidebarMetrics.tabHeaderPaddingTrailing)
        .frame(height: TabSidebarMetrics.tabHeaderHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius).fill(fill))
        .animation(TabSidebarMotion.hover, value: isHovering)
        .contentShape(Rectangle())
        .opacity(state.isDragSource ? TabSidebarMetrics.sourceOpacity : 1)
        .sidebarSurface(
            source: .tab(tab.id), frameKind: .tabBlock(tab.id), ghost: ghostInfo,
            onPress: { isPressed = $0 }, onClick: clicked, onRight: showMenu,
            onMiddle: { model.close(tab.id) },
            onHover: { inside, _ in
                isHovering = inside
                if inside { TabSidebarHoverCard.shared.hideNow() }
            })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), tab, \(tab.panes.count) \(tab.panes.count == 1 ? "pane" : "panes")")
        .accessibilityValue(isCollapsed ? "collapsed" : "expanded")
        .accessibilityAddTraits(.isHeader)
        .accessibilityAction(named: isCollapsed ? "Show Panes" : "Hide Panes") { model.toggleTabCollapsed(tab.id) }
        .accessibilityAction(named: "Rename Tab") { model.beginRename(tab: tab.id) }
        .accessibilityAction(named: "Show Menu", showMenu)
    }

    private func clicked(_ count: Int, _ windowPoint: CGPoint) {
        // "Single click: no action". Double-click renames the tab.
        if count >= 2 { model.beginRename(tab: tab.id) }
    }

    private func showMenu() {
        TabSidebarMenus.popUp(TabSidebarMenus.tabMenu(model, tab: tab.id), owner: key, model: model)
    }

    private func ghostInfo() -> TabSidebarGhostModel.Info {
        .init(
            title: tab.customName ?? text, isClaude: tab.focusedPane?.isClaude ?? false,
            paneCount: tab.panes.count > 1 ? tab.panes.count : nil, group: nil,
            width: min(TabSidebarMetrics.ghostMaxWidth, model.geometry.view(.tabBlock(tab.id))?.bounds.width ?? 260))
    }
}

// MARK: - Tab block (a header and its rows)

struct TabSidebarTabBlockView: View, Equatable {
    let model: TabSidebarModel
    let palette: TabSidebarPalette
    let block: TabSidebarTabBlock
    let base: TabSidebarRGB
    let isCollapsed: Bool
    let query: String
    let density: TabSidebarPrefs.Density
    let viewAs: TabSidebarPrefs.ViewAs
    let isPinnedContext: Bool
    let drag: TabSidebarDragState?
    let editing: TabSidebarEditTarget?
    let focusKey: TabSidebarFocusKey?
    let showsFocusRing: Bool
    let menuOwner: String?
    let isFlashing: Bool

    static func == (a: Self, b: Self) -> Bool {
        a.block == b.block && a.palette == b.palette && a.base == b.base && a.isCollapsed == b.isCollapsed
            && a.query == b.query && a.density == b.density && a.viewAs == b.viewAs
            && a.isPinnedContext == b.isPinnedContext && a.drag == b.drag && a.editing == b.editing
            && a.focusKey == b.focusKey && a.showsFocusRing == b.showsFocusRing && a.menuOwner == b.menuOwner
            && a.isFlashing == b.isFlashing
    }

    private var tabID: Int { block.tab.id }
    private var isDragSource: Bool { drag?.sourceTab == tabID }

    var body: some View {
        let hasHeader = block.headerText != nil
        VStack(alignment: .leading, spacing: TabSidebarMetrics.blockGap) {
            if let header = block.headerText {
                TabSidebarTabHeaderView(
                    model: model, palette: palette, tab: block.tab, text: header, base: base,
                    state: headerState, isCollapsed: isCollapsed)
                    .equatable()
            }
            if !(hasHeader && isCollapsed) {
                rows(indented: hasHeader)
                    .transition(.opacity)
            }
        }
        .overlay(flash)
        .overlay(alignment: .top) { indicator(.before) }
        .overlay(alignment: .bottom) { indicator(.after) }
        .reportFrame(.tabBlock(tabID), to: model.geometry)
        .padding(.vertical, hasHeader ? TabSidebarMetrics.multiPaneMargin : 0)
        .id(block.id)
    }

    /// The pane rows. Under a header they sit 16 pt in, beside a 1 pt guide line that runs to the middle
    /// of the last row, so a split tab reads as one unit.
    private func rows(indented: Bool) -> some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.blockGap) {
            ForEach(Array(block.rows.enumerated()), id: \.element.id) { index, row in
                TabSidebarRowView(
                    model: model, palette: palette, tab: block.tab, row: row, base: base,
                    state: rowState(for: row), query: query, density: density, viewAs: viewAs,
                    isPinnedContext: isPinnedContext,
                    positionLabel: block.rows.count > 1 ? "\(index + 1) of \(block.rows.count)" : nil)
                    .equatable()
            }
        }
        .padding(.leading, indented ? TabSidebarMetrics.paneIndent : 0)
        .background(alignment: .topLeading) {
            if indented {
                GeometryReader { proxy in
                    let last = (density == .expanded ? TabSidebarMetrics.relaxedMinHeight : TabSidebarMetrics.rowMinHeightOneLine) / 2
                    Rectangle()
                        .fill(TabSidebarRGB.mix(base, palette.ink, palette.isDark ? 0.18 : 0.16).color)
                        .frame(width: 1, height: max(0, proxy.size.height - last))
                        .offset(x: TabSidebarMetrics.paneGuideX)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private var headerState: TabSidebarRowState {
        var state = TabSidebarRowState()
        state.isEditing = editing == .tab(tabID)
        state.isDragSource = isDragSource
        state.isDragging = drag != nil
        state.menuOpen = menuOwner == "header:\(tabID)"
        return state
    }

    private func rowState(for row: TabSidebarBlockRow) -> TabSidebarRowState {
        var state = TabSidebarRowState()
        let key = TabSidebarFocusKey.row(tab: tabID, pane: row.paneID)
        state.isEditing = editing == .tab(tabID) && (viewAs == .tabs || block.headerText == nil)
        state.showsFocusRing = showsFocusRing && focusKey == key
        state.isDragSource = isDragSource
        state.isDragging = drag != nil
        state.menuOpen = menuOwner == key.stringKey
        return state
    }

    /// The settle flash: the block briefly takes the "settle" color and fades.
    @ViewBuilder
    private var flash: some View {
        RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
            .fill(palette.settleFlash().color)
            .opacity(isFlashing ? 1 : 0)
            .animation(isFlashing ? nil : TabSidebarMotion.flash, value: isFlashing)
            .allowsHitTesting(false)
    }

    private enum Edge { case before, after }

    /// The insertion line: 2 pt accent, inset 2, with a ring at its leading end, in the 2 pt gap.
    @ViewBuilder
    private func indicator(_ edge: Edge) -> some View {
        if let target = drag?.target, drag?.verdict == .valid {
            let show: Bool = {
                switch target {
                case .tab(let id, let after): return id == tabID && after == (edge == .after)
                default: return false
                }
            }()
            if show {
                TabSidebarInsertionLine(palette: palette)
                    .offset(y: edge == .before ? -TabSidebarMetrics.dropLine : TabSidebarMetrics.dropLine)
            }
        }
    }
}

// MARK: - Pieces

/// The 2 pt accent line with a ring at its leading end.
struct TabSidebarInsertionLine: View {
    let palette: TabSidebarPalette

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(palette.accent.color)
                .frame(height: TabSidebarMetrics.dropLine)
                .padding(.horizontal, TabSidebarMetrics.dropLineInset)
            Circle()
                .strokeBorder(palette.accent.color, lineWidth: 2)
                .background(Circle().fill(palette.sidebar.color))
                .frame(width: TabSidebarMetrics.dropDot, height: TabSidebarMetrics.dropDot)
                .offset(x: -2)
        }
        .frame(height: TabSidebarMetrics.dropDot)
        .allowsHitTesting(false)
    }
}

/// A 20 x 20 header or pill button (the ⋮ and + on headers).
struct TabSidebarHeaderButton: View {
    let palette: TabSidebarPalette
    let icon: TabSidebarIcon
    let help: String
    var stroke: CGFloat?
    var anchoredAction: ((NSView) -> Void)?
    var action: () -> Void = {}
    @State private var isHovering = false
    @State private var anchor = AnchorBox()

    var body: some View {
        Button(action: {
            if let anchoredAction, let view = anchor.view { anchoredAction(view) } else { action() }
        }) {
            TabSidebarIconView(
                icon: icon, size: TabSidebarMetrics.headerButtonIcon,
                color: (isHovering ? palette.text : palette.text2).color, stroke: stroke)
                .frame(width: TabSidebarMetrics.headerButton, height: TabSidebarMetrics.headerButton)
                .background(
                    RoundedRectangle(cornerRadius: TabSidebarMetrics.headerButtonRadius)
                        .fill(isHovering ? palette.hover(over: palette.sidebar).color : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarControl()
        .background(AnchorView(box: anchor))
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityHidden(true)
    }
}

/// The "⋮ ✕" pill on a hovered row. Popover colors, 1 pt border, static shadow.
struct TabSidebarPill: View {
    let palette: TabSidebarPalette
    var showsMenu = true
    let showsClose: Bool
    var showsUnpin = false
    let closeHelp: String
    let menuHelp: String
    let onMenu: () -> Void
    let onClose: () -> Void
    var onUnpin: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            if showsMenu { pillButton(.ellipsisVertical, help: menuHelp, action: onMenu) }
            if showsUnpin { pillButton(.pinFilled, help: "Unpin Tab", action: onUnpin) }
            if showsClose { pillButton(.close, help: closeHelp, stroke: 1.75, action: onClose) }
        }
        .padding(.horizontal, TabSidebarMetrics.pillPadding)
        .frame(height: TabSidebarMetrics.pillHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.pillRadius).fill(palette.popover.color))
        .overlay(RoundedRectangle(cornerRadius: TabSidebarMetrics.pillRadius).strokeBorder(palette.popoverBorder.color, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0.40 : 0.12), radius: 1.5, y: 1)
    }

    private func pillButton(_ icon: TabSidebarIcon, help: String, stroke: CGFloat? = nil, action: @escaping () -> Void) -> some View {
        PillButton(palette: palette, icon: icon, help: help, stroke: stroke, action: action)
    }

    private struct PillButton: View {
        let palette: TabSidebarPalette
        let icon: TabSidebarIcon
        let help: String
        let stroke: CGFloat?
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                TabSidebarIconView(
                    icon: icon, size: TabSidebarMetrics.pillIcon,
                    color: (isHovering ? palette.popoverText : palette.popoverText2).color, stroke: stroke)
                    .frame(width: TabSidebarMetrics.pillButton, height: TabSidebarMetrics.pillButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressFillStyle(palette: palette, isHovering: isHovering))
            .sidebarControl()
            .onHover { isHovering = $0 }
            .help(help)
            .accessibilityHidden(true)
        }
    }
}

/// Hover fill, and a stronger one (+14% ink) while pressed.
private struct PressFillStyle: ButtonStyle {
    let palette: TabSidebarPalette
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(
            RoundedRectangle(cornerRadius: TabSidebarMetrics.pillButtonRadius)
                .fill(configuration.isPressed ? palette.ink.color.opacity(0.14) : isHovering ? palette.popoverHover.color : .clear))
    }
}

/// "+142 −38" in a small mono chip.
struct TabSidebarDiffBadge: View {
    let palette: TabSidebarPalette
    let base: TabSidebarRGB
    let stats: TabSidebarDiffStats

    var body: some View {
        HStack(spacing: TabSidebarMetrics.diffGap) {
            Text("+\(stats.added)").foregroundColor(palette.done.color)
            Text("−\(stats.removed)").foregroundColor(palette.error.color)
        }
        .font(.system(size: TabSidebarMetrics.diffFont, design: .monospaced))
        .padding(.horizontal, TabSidebarMetrics.diffPaddingHorizontal)
        .frame(height: TabSidebarMetrics.subtitleLine)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.diffRadius).fill(palette.diffBadgeFill(over: base).color))
    }
}

/// The 22 pt tile with the terminal or Claude glyph and an optional status badge.
struct TabSidebarTile: View {
    let palette: TabSidebarPalette
    let base: TabSidebarRGB
    let rowFill: TabSidebarRGB
    let isClaude: Bool
    let status: TabSidebarStatus?
    let tabColor: TabSidebarGroupColor
    let exited: Bool
    let animating: Bool
    var size: CGFloat = TabSidebarMetrics.tile

    private var tileFill: TabSidebarRGB {
        if isClaude { return palette.claudeTile(over: base) }
        if tabColor != .none { return palette.groupTile(tabColor) }
        return palette.tile(over: base)
    }

    private var glyphColor: Color {
        if exited { return palette.text3.color }
        if isClaude { return palette.claude.color }
        if tabColor != .none { return palette.groupBase(tabColor).color }
        return palette.glyph.color
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.tileRadius).fill(tileFill.color)
            TabSidebarIconView(
                icon: isClaude ? .claude : .terminal, size: size >= 28 ? 16 : TabSidebarMetrics.tileGlyph, color: glyphColor)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let status {
                TabSidebarStatusBadge(
                    palette: palette, status: status, size: TabSidebarMetrics.statusBadge,
                    rowFill: rowFill, ring: true, animating: animating)
                    .offset(x: -TabSidebarMetrics.statusBadgeOffset, y: -TabSidebarMetrics.statusBadgeOffset)
            }
        }
    }
}

/// A status badge: a colored disc with a glyph (or, for "working", a rotating arc on a disc the
/// color of the row). The ring is the row's own fill, which makes the badge look cut out.
struct TabSidebarStatusBadge: View {
    let palette: TabSidebarPalette
    let status: TabSidebarStatus
    let size: CGFloat
    let rowFill: TabSidebarRGB
    let ring: Bool
    let animating: Bool

    var body: some View {
        ZStack {
            switch status {
            case .working:
                Circle().fill(rowFill.color)
                SpinningArc(color: palette.working.color, size: size * 0.8, animating: animating)
            case .done: disc(palette.done, .glyphDone, palette.doneGlyph)
            case .error: disc(palette.error, .glyphError, palette.errorGlyph)
            case .cancelled: disc(palette.cancelled, .glyphCancelled, palette.cancelledGlyph)
            case .blocked: disc(palette.blocked, .glyphBlocked, palette.blockedGlyph)
            }
        }
        .frame(width: size, height: size)
        .overlay(ring ? AnyView(Circle().stroke(rowFill.color, lineWidth: TabSidebarMetrics.statusBadgeRing).padding(-TabSidebarMetrics.statusBadgeRing / 2)) : AnyView(EmptyView()))
        .help(status.word)
    }

    private func disc(_ fill: TabSidebarRGB, _ glyph: TabSidebarIcon, _ glyphColor: TabSidebarRGB) -> some View {
        ZStack {
            Circle().fill(fill.color)
            TabSidebarIconView(icon: glyph, size: size * 0.66, color: glyphColor.color)
        }
    }
}

/// The only continuous animation: a 90 degree arc turning once a second, capped at 30 fps. It
/// stops when the window is hidden, the sidebar is hidden, or Reduce Motion is on.
private struct SpinningArc: View {
    let color: Color
    let size: CGFloat
    let animating: Bool

    var body: some View {
        if animating && !TabSidebarMotion.reduced {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                arc.rotationEffect(.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
        } else {
            arc
        }
    }

    private var arc: some View {
        TabSidebarIconView(icon: .glyphWorking, size: size, color: color)
    }
}

// MARK: - Inline rename

/// The rename field (spec 2.4): 20 pt tall, field fill, 1 pt accent stroke, text selected on entry.
struct RenameField: View {
    let palette: TabSidebarPalette
    let initial: String
    let isGroup: Bool
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @State private var settled = false

    var body: some View {
        TabSidebarTextField(
            text: $text,
            font: .systemFont(ofSize: 12, weight: isGroup ? .semibold : .regular),
            textColor: palette.text.nsColor,
            placeholderColor: palette.text3.nsColor,
            selectAllOnFocus: true,
            focusOnAppear: true,
            onSubmit: { if !settled { settled = true; onCommit(text) } },
            onCancel: { if !settled { settled = true; onCancel() } },
            onBlurCommit: true)
            .padding(.horizontal, TabSidebarMetrics.renamePaddingHorizontal)
            .frame(height: TabSidebarMetrics.renameHeight)
            .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.renameRadius).fill(palette.field.color))
            .overlay(RoundedRectangle(cornerRadius: TabSidebarMetrics.renameRadius).strokeBorder(palette.accent.color, lineWidth: 1))
            .padding(.vertical, -2)
            .onAppear { text = initial }
            .accessibilityLabel(isGroup ? "Group name" : "Tab name")
    }
}

// MARK: - Close-group confirmation

/// "Close 3 tabs?": 240 wide, 14 padding, buttons 24 high and 8 apart, Close in red and the default.
struct TabSidebarCloseConfirm: View {
    let palette: TabSidebarPalette
    let count: Int
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Close \(count) tabs?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.popoverText.color)
            Text("This closes every tab in the group.")
                .font(.system(size: 12))
                .foregroundColor(palette.popoverText2.color)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Close", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .tint(palette.error.color)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 240)
        .background(palette.popover.color)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }
}
