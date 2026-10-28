import AppKit
import SwiftUI

// A group: one container with a tinted body, a 1 pt border, a 3 pt color rail, a header and its tabs
// (spec part 1, 2.3). Collapsed, only the header remains.

private final class PendingToggle { var work: DispatchWorkItem? }

struct TabSidebarGroupView: View, Equatable {
    let model: TabSidebarModel
    let palette: TabSidebarPalette
    let block: TabSidebarGroupBlock
    let query: String
    let density: TabSidebarPrefs.Density
    let viewAs: TabSidebarPrefs.ViewAs
    let drag: TabSidebarDragState?
    let editing: TabSidebarEditTarget?
    let focusKey: TabSidebarFocusKey?
    let showsFocusRing: Bool
    let menuOwner: String?
    let flashID: String?
    let collapsedTabs: Set<Int>

    static func == (a: Self, b: Self) -> Bool {
        a.block == b.block && a.palette == b.palette && a.query == b.query && a.density == b.density
            && a.viewAs == b.viewAs && a.drag == b.drag && a.editing == b.editing && a.focusKey == b.focusKey
            && a.showsFocusRing == b.showsFocusRing && a.menuOwner == b.menuOwner && a.flashID == b.flashID
            && a.collapsedTabs == b.collapsedTabs
    }

    private var group: TabSidebarGroup { block.group }
    private var tint: TabSidebarRGB { palette.groupTint(group.color) }
    private var isDragSource: Bool { drag?.sourceGroup == group.id }

    private var isIntoTarget: Bool {
        if case .groupHeader(group.id, true)? = drag?.target, drag?.verdict == .valid { return true }
        return false
    }

    private var isInvalidTarget: Bool {
        if case .invalid(let id)? = drag?.verdict { return id == group.id }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            TabSidebarGroupHeader(
                model: model, palette: palette, block: block, tint: tint,
                state: headerState)
                .equatable()

            CollapsibleBody(isCollapsed: group.isCollapsed) {
                VStack(alignment: .leading, spacing: TabSidebarMetrics.groupBodyGap) {
                    ForEach(block.tabs) { tab in
                        TabSidebarTabBlockView(
                            model: model, palette: palette, block: tab, base: tint,
                            isCollapsed: collapsedTabs.contains(tab.id), query: query, density: density, viewAs: viewAs,
                            isPinnedContext: group.isPinned, drag: drag, editing: editing, focusKey: focusKey,
                            showsFocusRing: showsFocusRing, menuOwner: menuOwner, isFlashing: flashID == "tab:\(tab.id)")
                            .equatable()
                    }
                    Color.clear
                        .frame(height: TabSidebarMetrics.groupBottomStrip)
                        .reportFrame(.groupBottom(group.id), to: model.geometry)
                }
            }
        }
        .padding(.leading, TabSidebarMetrics.groupPaddingLeading)
        .padding(.trailing, TabSidebarMetrics.groupPaddingTrailing)
        .background(
            RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius)
                .fill((isIntoTarget ? palette.groupIntoFill(group.color) : tint).color))
        .overlay(rail)
        .overlay(containerBorder)
        .overlay(flash)
        .overlay(alignment: .top) { line(before: true) }
        .overlay(alignment: .bottom) { line(before: false) }
        .opacity(isDragSource ? TabSidebarMetrics.sourceOpacity : 1)
        .padding(.vertical, TabSidebarMetrics.groupMarginVertical)
        .reportFrame(.groupContainer(group.id), to: model.geometry)
        .id(block.id)
    }

    // MARK: Chrome

    /// The 3 pt rail, with the container's rounded corners on its leading side.
    @ViewBuilder
    private var rail: some View {
        if group.color != .none { railBar }
    }

    private var railBar: some View {
        HStack(spacing: 0) {
            Rectangle().fill(palette.groupBase(group.color).color).frame(width: TabSidebarMetrics.groupRail)
            Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var containerBorder: some View {
        if isInvalidTarget {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius).strokeBorder(palette.error.color, lineWidth: 1.5)
        } else if isIntoTarget {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius).strokeBorder(palette.accent.color, lineWidth: 1.5)
        } else {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius)
                .strokeBorder(palette.groupBorder(group.color).color, lineWidth: TabSidebarMetrics.groupBorder)
        }
    }

    @ViewBuilder
    private var flash: some View {
        RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius)
            .fill(palette.settleFlash().color)
            .opacity(flashID == "group:\(group.id)" ? 1 : 0)
            .animation(flashID == "group:\(group.id)" ? nil : TabSidebarMotion.flash, value: flashID)
            .allowsHitTesting(false)
    }

    /// The insertion line above or below the whole container.
    @ViewBuilder
    private func line(before: Bool) -> some View {
        if let target = drag?.target, drag?.verdict == .valid {
            let show: Bool = {
                switch target {
                case .groupHeader(group.id, false): return before
                case .groupBlock(group.id, let after): return before == !after
                case .groupBottom(group.id): return !before
                default: return false
                }
            }()
            if show {
                TabSidebarInsertionLine(palette: palette)
                    .offset(y: before ? -(TabSidebarMetrics.dropLine + TabSidebarMetrics.groupMarginVertical / 2)
                                      : TabSidebarMetrics.dropLine + TabSidebarMetrics.groupMarginVertical / 2)
            }
        }
    }

    private var headerState: TabSidebarRowState {
        var state = TabSidebarRowState()
        state.isEditing = editing == .group(group.id)
        state.showsFocusRing = showsFocusRing && focusKey == .group(group.id)
        state.isDragSource = isDragSource
        state.isDragging = drag != nil
        state.menuOpen = menuOwner == TabSidebarFocusKey.group(group.id).stringKey
        return state
    }
}

// MARK: - Header

struct TabSidebarGroupHeader: View, Equatable {
    let model: TabSidebarModel
    let palette: TabSidebarPalette
    let block: TabSidebarGroupBlock
    let tint: TabSidebarRGB
    let state: TabSidebarRowState

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var pending = PendingToggle()

    static func == (a: Self, b: Self) -> Bool {
        a.block == b.block && a.palette == b.palette && a.state == b.state
    }

    private var group: TabSidebarGroup { block.group }
    private var key: String { TabSidebarFocusKey.group(group.id).stringKey }
    private var showsSelectedFill: Bool { group.isCollapsed && block.containsSelected }

    var body: some View {
        HStack(spacing: TabSidebarMetrics.groupHeaderGap) {
            chevron
            TabSidebarIconView(
                icon: .groupPanes, size: TabSidebarMetrics.groupHeaderIcon,
                color: (group.color == .none ? palette.text2 : palette.groupBase(group.color)).color)
                .animation(TabSidebarMotion.swatch, value: group.color)

            name

            if group.isPinned {
                TabSidebarIconView(icon: .pin, size: TabSidebarMetrics.sectionPinIcon, color: palette.text3.color, stroke: 1.75)
                    .accessibilityHidden(true)
            }

            countPill
            if group.isCollapsed { collapsedIndicators }

            Spacer(minLength: 0)

            if (isHovering || state.menuOpen) && !state.isDragging {
                HStack(spacing: 0) {
                    TabSidebarHeaderButton(
                        palette: palette, icon: .ellipsisVertical, help: "Group Options", action: showMenu)
                    TabSidebarHeaderButton(
                        palette: palette, icon: .close, help: "Close Group", stroke: 1.75,
                        anchoredAction: { model.confirmCloseGroup(group.id, anchor: $0) })
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, TabSidebarMetrics.groupHeaderPaddingHorizontal)
        .frame(height: TabSidebarMetrics.groupHeaderHeight)
        .background(headerFill)
        .overlay(focusRing)
        .contentShape(Rectangle())
        .animation(TabSidebarMotion.pill, value: isHovering)
        .sidebarSurface(
            source: .group(group.id), frameKind: .groupContainer(group.id), ghost: ghostInfo,
            onPress: { isPressed = $0 }, onClick: clicked, onRight: showMenu,
            onHover: { inside, top in
                isHovering = inside
                guard !state.isDragging, model.editing == nil else { return }
                if inside {
                    TabSidebarHoverCard.shared.rowEntered(
                        .group(block, prefs: model.prefs), rowTop: top, window: model.window,
                        palette: palette, enabled: model.prefs.showDetailsOnHover && model.menuOwner == nil)
                } else {
                    TabSidebarHoverCard.shared.rowExited()
                }
            })
        .reportFrame(.groupHeader(group.id), to: model.geometry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), group, \(group.color.localizedName.lowercased()), \(block.tabs.count) \(block.tabs.count == 1 ? "tab" : "tabs")")
        .accessibilityValue(group.isCollapsed ? "collapsed" : "expanded")
        .accessibilityHint(group.isCollapsed ? "Double-tap to expand" : "Double-tap to collapse")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: group.isCollapsed ? "Expand" : "Collapse") { model.toggleCollapsed(group.id) }
        .accessibilityAction(named: "Rename Group") { model.beginRename(group: group.id) }
        .accessibilityAction(named: "New Tab in Group") { model.newTab(inGroup: group.id) }
        .accessibilityAction(named: group.isPinned ? "Unpin Group" : "Pin Group") { model.toggleGroupPinned(group.id) }
        .accessibilityAction(named: "Ungroup Tabs") { model.ungroup(group.id) }
        .accessibilityAction(named: "Close Tabs in Group") { model.closeTabs(inGroup: group.id) }
        .accessibilityAction(named: "Show Menu", showMenu)
    }

    // MARK: Pieces

    private var chevron: some View {
        TabSidebarDisclosure(
            palette: palette, isCollapsed: group.isCollapsed,
            label: group.isCollapsed ? "Expand group" : "Collapse group") { model.toggleCollapsed(group.id) }
    }

    @ViewBuilder
    private var name: some View {
        if state.isEditing {
            RenameField(
                palette: palette, initial: group.name, isGroup: true,
                onCommit: { model.commitRename(group: group.id, to: $0) }, onCancel: model.cancelRename)
        } else {
            Text(group.name)
                .font(.system(size: TabSidebarMetrics.groupHeaderFont, weight: .semibold))
                .foregroundColor(palette.text.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .reportFrame(.groupName(group.id), to: model.geometry)
        }
    }

    private var countPill: some View {
        Text("\(block.tabs.count)")
            .font(.system(size: TabSidebarMetrics.countFont, weight: .medium).monospacedDigit())
            .foregroundColor(palette.text2.color)
            .padding(.horizontal, TabSidebarMetrics.countPaddingHorizontal)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.countRadius).fill(palette.groupCountPill(group.color).color))
            .fixedSize()
    }

    /// A collapsed group still tells you what is inside: up to five overlapping dots, one per tab, colored
    /// by that tab's most urgent status (or Claude / terminal), then "+N" and the bell.
    private var collapsedIndicators: some View {
        let shown = Array(block.tabs.prefix(TabSidebarMetrics.collapsedDotLimit))
        let extra = block.tabs.count - shown.count
        return HStack(spacing: TabSidebarMetrics.collapsedIndicatorGap) {
            HStack(spacing: -TabSidebarMetrics.collapsedDotOverlap) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, tab in
                    Circle()
                        .fill(dotColor(tab).color)
                        .frame(width: TabSidebarMetrics.collapsedDot, height: TabSidebarMetrics.collapsedDot)
                        .overlay(Circle().strokeBorder(tint.color, lineWidth: 1.5))
                        .zIndex(Double(shown.count - index))
                }
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: TabSidebarMetrics.countFont, weight: .medium).monospacedDigit())
                    .foregroundColor(palette.text2.color)
            }
            if block.hasBell {
                TabSidebarIconView(
                    icon: .bell, size: TabSidebarMetrics.collapsedBell, color: palette.blocked.color, stroke: 1.75)
            }
        }
    }

    private func dotColor(_ tab: TabSidebarTabBlock) -> TabSidebarRGB {
        let order: [TabSidebarStatus] = [.error, .blocked, .working, .done, .cancelled]
        let statuses = tab.tab.panes.compactMap(\.status)
        if let status = order.first(where: statuses.contains) {
            switch status {
            case .error: return palette.error
            case .blocked: return palette.blocked
            case .working: return palette.working
            case .done: return palette.done
            case .cancelled: return palette.cancelled
            }
        }
        return tab.tab.panes.contains(where: \.isClaude) ? palette.claude : palette.text3
    }

    private var headerFill: some View {
        RoundedRectangle(cornerRadius: TabSidebarMetrics.groupHeaderRadius)
            .fill(showsSelectedFill ? palette.selected(over: tint).color : .clear)
            .padding(.vertical, 1)
    }

    @ViewBuilder
    private var focusRing: some View {
        if state.showsFocusRing {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.groupHeaderRadius)
                .strokeBorder(palette.accent.color, lineWidth: TabSidebarMetrics.keyboardFocusRing)
        }
    }

    // MARK: Actions

    /// Chevron: handled by its own button. Name: a single click toggles after 250 ms unless a second
    /// click arrives, which renames. Anywhere else: toggles at once.
    private func clicked(_ count: Int, _ windowPoint: CGPoint) {
        model.setFocus(.group(group.id), ring: false)
        let onName = model.geometry.contains(.groupName(group.id), windowPoint: windowPoint)

        if onName {
            pending.work?.cancel()
            if count >= 2 {
                model.beginRename(group: group.id)
            } else {
                let work = DispatchWorkItem { model.toggleCollapsed(group.id) }
                pending.work = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        } else {
            model.toggleCollapsed(group.id)
        }
    }

    private func showMenu() {
        TabSidebarMenus.popUp(TabSidebarMenus.groupMenu(model, group: group.id), owner: key, model: model)
    }

    private func topOnScreen() -> CGFloat {
        guard let view = model.geometry.view(.groupHeader(group.id)), let window = view.window else { return 0 }
        return window.convertToScreen(view.convert(view.bounds, to: nil)).maxY
    }

    private func ghostInfo() -> TabSidebarGhostModel.Info {
        .init(
            title: group.name, isClaude: false, paneCount: nil,
            group: (group.color, block.tabs.count),
            width: min(TabSidebarMetrics.ghostMaxWidth, model.geometry.view(.groupContainer(group.id))?.bounds.width ?? 260))
    }
}

/// The disclosure chevron of a group or a multi-pane tab: always visible, its own hover and pressed fill,
/// a 140 ms turn. `box` is the glyph's box; the clickable area is larger.
struct TabSidebarDisclosure: View {
    let palette: TabSidebarPalette
    let isCollapsed: Bool
    var box: CGFloat = TabSidebarMetrics.chevronBox
    var hit = CGSize(width: TabSidebarMetrics.chevronHitWidth, height: TabSidebarMetrics.groupHeaderHeight)
    var label = "Toggle"
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        TabSidebarIconView(
            icon: .chevron, size: TabSidebarMetrics.chevronGlyph,
            color: (isHovering ? palette.text : palette.text2).color)
            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
            .animation(TabSidebarMotion.chevron, value: isCollapsed)
            .frame(width: box, height: box)
            .background(
                RoundedRectangle(cornerRadius: TabSidebarMetrics.chevronRadius)
                    .fill(palette.ink.color.opacity(isPressed ? 0.14 : isHovering ? 0.10 : 0)))
            .frame(width: max(hit.width, box), height: max(hit.height, box))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { value in
                        isPressed = false
                        if abs(value.translation.width) < 4, abs(value.translation.height) < 4 { action() }
                    })
            .sidebarControl()
            .help(label)
            .accessibilityHidden(true)
    }
}

// MARK: - Collapsing body

/// Clips its content to zero height when collapsed and animates between the two. The content is kept
/// at its natural size inside the clip, so it is not re-laid out while the height changes.
struct CollapsibleBody<Content: View>: View {
    let isCollapsed: Bool
    @ViewBuilder var content: () -> Content
    @State private var natural: CGFloat?

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
                })
            .onPreferenceChange(HeightKey.self) { height in
                // Layout reports 0 before it has measured anything; that is not a real height.
                if height > 0 { natural = height }
            }
            .frame(height: isCollapsed ? 0 : natural, alignment: .top)
            .clipped()
            .opacity(isCollapsed ? 0 : 1)
            .allowsHitTesting(!isCollapsed)
            .environment(\.sidebarSurfaceActive, !isCollapsed)
            .animation(TabSidebarMotion.groupToggle, value: isCollapsed)
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
