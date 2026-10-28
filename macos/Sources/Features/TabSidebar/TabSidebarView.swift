import AppKit
import SwiftUI

struct TabSidebarView: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject private var settings = TabSidebarSettings.shared

    var body: some View {
        let palette = model.palette
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                TabSidebarControlBar(model: model, settings: settings)
                Rectangle().fill(palette.hairline.color).frame(height: TabSidebarMetrics.hairline)
                TabSidebarListView(model: model, settings: settings)
            }

            TabSidebarGhostView(model: model, ghost: model.ghost)

            // The 1 pt hairline on the sidebar's trailing edge.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle().fill(palette.hairline.color).frame(width: TabSidebarMetrics.hairline)
            }
            .allowsHitTesting(false)
        }
        .coordinateSpace(name: "sidebar")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.sidebar.color)
        .background(TabSidebarKeyCatcher(model: model))
        .environment(\.sidebarPalette, palette)
        .environment(\.sidebarPointerRegistry, model.pointerRegistry)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs, \(model.tabCount) \(model.tabCount == 1 ? "tab" : "tabs")")
    }
}

// MARK: - Control bar

struct TabSidebarControlBar: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject var settings: TabSidebarSettings

    var body: some View {
        HStack(spacing: TabSidebarMetrics.controlBarGap) {
            TabSidebarSearchField(model: model, width: settings.width)
            TabSidebarAnchoredButton(
                palette: model.palette, icon: .sliders, help: "View Options", label: "View options",
                action: { TabSidebarOptionsPanel.shared.toggle(model: model, anchor: $0, alignRight: true) },
                size: TabSidebarMetrics.toolbarButton)
            TabSidebarAnchoredButton(
                palette: model.palette, icon: .plus, help: "New", label: "New",
                action: { TabSidebarMenus.popUp(TabSidebarMenus.newMenu(model), owner: "plus", model: model, anchor: $0) },
                size: TabSidebarMetrics.toolbarButton)
        }
        .padding(.horizontal, TabSidebarMetrics.controlBarPadding)
        .frame(height: TabSidebarMetrics.controlBarHeight)
        .overlay(RightClickCatcher {
            TabSidebarMenus.popUp(TabSidebarMenus.newMenu(model), owner: "plus", model: model)
        })
    }
}

/// 26 x 26 toolbar button: hover, pressed and "open" states.
struct TabSidebarToolbarButton: View {
    let palette: TabSidebarPalette
    let icon: TabSidebarIcon
    let help: String
    let label: String
    let isOn: Bool
    var size: CGFloat = TabSidebarMetrics.toolbarButton
    var iconSize: CGFloat = TabSidebarMetrics.toolbarIcon
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    private var fill: TabSidebarRGB {
        if isOn { return palette.selected(over: palette.sidebar) }
        if isPressed { return palette.pressed(over: palette.sidebar) }
        if isHovering { return palette.hover(over: palette.sidebar) }
        return palette.sidebar
    }

    var body: some View {
        TabSidebarIconView(
            icon: icon, size: iconSize,
            color: (isHovering || isOn ? palette.text : palette.text2).color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.toolbarButtonRadius).fill(fill.color))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(TabSidebarMotion.hover, value: isHovering)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { value in
                        isPressed = false
                        if abs(value.translation.width) < 4, abs(value.translation.height) < 4 { action() }
                    })
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

// MARK: - Search field

struct TabSidebarSearchField: View {
    @ObservedObject var model: TabSidebarModel
    let width: CGFloat
    @State private var isFocused = false

    private var palette: TabSidebarPalette { model.palette }

    var body: some View {
        HStack(spacing: TabSidebarMetrics.searchInnerGap) {
            TabSidebarIconView(icon: .search, size: TabSidebarMetrics.searchIcon, color: palette.text3.color)

            TabSidebarTextField(
                text: $model.query,
                placeholder: "Search tabs…",
                font: .systemFont(ofSize: TabSidebarMetrics.searchFont),
                textColor: palette.text.nsColor,
                placeholderColor: palette.text3.nsColor,
                accentColor: palette.accent.nsColor,
                focusTick: model.focusSearchTick,
                onFocusChange: { isFocused = $0 },
                onSubmit: { model.leaveSearch(selectFirst: true) },
                onCancel: escape,
                onMoveDown: { model.leaveSearch(selectFirst: false) })
                .accessibilityLabel("Search tabs")
                .accessibilityHint("Filters by title, directory, branch, tab or group name")

            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    TabSidebarIconView(
                        icon: .xmarkCircleFill, size: 14, color: palette.text3.color, knockout: palette.field.color)
                        .frame(width: TabSidebarMetrics.clearButton, height: TabSidebarMetrics.clearButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            } else if !isFocused && width >= TabSidebarMetrics.shortcutHintMinWidth {
                Text("⇧⌘A")
                    .font(.system(size: TabSidebarMetrics.shortcutHintFont))
                    .foregroundColor(palette.text3.color)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, TabSidebarMetrics.searchPaddingLeading)
        .padding(.trailing, TabSidebarMetrics.searchPaddingTrailing)
        .frame(height: TabSidebarMetrics.searchHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.searchRadius).fill(palette.field.color))
        .background(halo)
        .overlay(border)
    }

    /// 1 pt accent stroke; the 2 pt halo is a ring behind the field, so it never covers the text.
    @ViewBuilder
    private var border: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.searchRadius)
                .strokeBorder(palette.accent.color, lineWidth: TabSidebarMetrics.focusStroke)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var halo: some View {
        if isFocused {
            RoundedRectangle(cornerRadius: TabSidebarMetrics.searchRadius + TabSidebarMetrics.focusHalo)
                .strokeBorder(palette.focusHalo().color, lineWidth: TabSidebarMetrics.focusHalo)
                .padding(-TabSidebarMetrics.focusHalo)
                .allowsHitTesting(false)
        }
    }

    /// Esc clears a non-empty query; with the query already empty, focus moves to the list.
    private func escape() {
        if model.query.isEmpty {
            model.focusList()
            model.focusFirstStopIfNeeded(ring: true)
        } else {
            model.query = ""
        }
    }
}

// MARK: - List

struct TabSidebarListView: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject var settings: TabSidebarSettings

    private var palette: TabSidebarPalette { model.palette }
    private var list: TabSidebarList { model.list }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: TabSidebarMetrics.blockGap) {
                            content
                        }
                        tail
                    }
                    .padding(.top, TabSidebarMetrics.listPaddingTop)
                    .padding(.horizontal, TabSidebarMetrics.listPaddingHorizontal)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .background(Color.clear.reportFrame(.viewport, to: model.geometry))
                .transaction { transaction in
                    // Filtering never animates.
                    if model.isSearching { transaction.animation = nil }
                }
                .onChange(of: model.query) { _ in
                    proxy.scrollTo("list-top", anchor: .top)
                }
                // Scrolling moves rows out from under the card.
                .onReceive(NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification)) { _ in
                    TabSidebarHoverCard.shared.hideNow()
                }
                .onChange(of: model.scrollRequest) { id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                    model.scrollRequest = nil
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        Color.clear.frame(height: 0).id("list-top")

        let showPinned = !list.pinned.isEmpty || (model.drag != nil && !model.isSearching)
        if showPinned {
            sectionHeader(section: "pinned", icon: .pin, title: "PINNED", count: list.pinned.tabCount)
            if !model.isSectionCollapsed("pinned") {
                VStack(alignment: .leading, spacing: TabSidebarMetrics.blockGap) {
                    ForEach(Array(list.pinned.enumerated()), id: \.element.id) { index, block in
                        blockView(block, pinned: true)
                    }
                    if model.drag != nil || list.pinned.isEmpty {
                        TabSidebarPinZone(model: model, palette: palette)
                    }
                }
                .padding(TabSidebarMetrics.pinnedContainerPadding)
                .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius).fill(palette.pinnedFill.color))
                .overlay(
                    RoundedRectangle(cornerRadius: TabSidebarMetrics.groupRadius)
                        .strokeBorder(palette.hairline.color, lineWidth: 1)
                        .allowsHitTesting(false))
                .padding(.bottom, TabSidebarMetrics.pinnedSeparatorMargin)
                .transition(.opacity)
            }
            if !list.main.isEmpty {
                sectionHeader(section: "open", icon: nil, title: "OPEN TABS", count: list.main.tabCount)
            }
        }

        if !(showPinned && model.isSectionCollapsed("open")) {
            ForEach(Array(list.main.enumerated()), id: \.element.id) { index, block in
                blockView(block, pinned: false)
            }
        }

        if list.isEmptyResult { emptyState }
    }

    @ViewBuilder
    private func blockView(_ block: TabSidebarBlock, pinned: Bool) -> some View {
        let base = pinned ? palette.pinnedFill : palette.sidebar
        switch block {
        case .tab(let tab):
            TabSidebarTabBlockView(
                model: model, palette: palette, block: tab, base: base,
                isCollapsed: model.collapsedTabs.contains(tab.id),
                query: model.query, density: settings.prefs.density, viewAs: settings.prefs.viewAs,
                isPinnedContext: pinned, drag: model.drag, editing: model.editing, focusKey: model.focusKey,
                showsFocusRing: model.showsFocusRing, menuOwner: model.menuOwner,
                isFlashing: model.flashID == "tab:\(tab.id)")
                .equatable()
                .transition(.opacity)

        case .group(let group):
            TabSidebarGroupView(
                model: model, palette: palette, block: group, query: model.query,
                density: settings.prefs.density, viewAs: settings.prefs.viewAs, drag: model.drag,
                editing: model.editing, focusKey: model.focusKey, showsFocusRing: model.showsFocusRing,
                menuOwner: model.menuOwner, flashID: model.flashID, collapsedTabs: model.collapsedTabs)
                .equatable()
                .transition(.opacity)
        }
    }

    /// "Pinned 3" and "Open tabs 5": a chevron, a small caps label, an optional pin icon and the count. The
    /// whole header folds and unfolds its section.
    private func sectionHeader(section: String, icon: TabSidebarIcon?, title: String, count: Int) -> some View {
        TabSidebarSectionHeader(
            palette: palette, title: title, icon: icon, count: count,
            isCollapsed: model.isSectionCollapsed(section)) { model.toggleSectionCollapsed(section) }
    }

    // MARK: Tail and empty state

    /// The rest of the list is a drop target: dropping here sends the tab to the end of the main list.
    private var tail: some View {
        Color.clear
            .frame(minHeight: TabSidebarMetrics.listTailMinHeight)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .reportFrame(.tail, to: model.geometry)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            TabSidebarIllustrationView(
                illustration: .noResults, size: TabSidebarMetrics.emptyIllustration, color: palette.text3.color)
            Text("No tabs match “\(model.query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(.system(size: 12))
                .foregroundColor(palette.text2.color)
                .multilineTextAlignment(.center)
            Button { model.query = "" } label: {
                Text("Clear Search")
                    .font(.system(size: 12))
                    .foregroundColor(palette.text.color)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.field.color))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 12)
        .transition(.opacity.animation(TabSidebarMotion.out(0.12)?.delay(0.08)))
    }
}

// MARK: - Pin drop zone

struct TabSidebarPinZone: View {
    let model: TabSidebarModel
    let palette: TabSidebarPalette

    private var isActive: Bool {
        model.drag?.target == .pinZone && model.drag?.verdict == .valid
    }

    var body: some View {
        HStack(spacing: 6) {
            TabSidebarIconView(icon: .pin, size: 12, color: (isActive ? palette.accent : palette.text3).color)
            Text("Drag a tab here to pin")
                .font(.system(size: 11))
                .foregroundColor((isActive ? palette.accent : palette.text3).color)
        }
        .frame(maxWidth: .infinity)
        .frame(height: TabSidebarMetrics.pinZoneHeight)
        .overlay(
            RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
                .strokeBorder(
                    isActive ? palette.accent.color : palette.selectedBorder(over: palette.sidebar).color,
                    style: StrokeStyle(lineWidth: isActive ? 1.5 : 1, dash: isActive ? [] : [3, 3])))
        .padding(.vertical, 2)
        .reportFrame(.pinZone, to: model.geometry)
    }
}

// MARK: - Ghost

/// The chip that follows the pointer during a drag.
struct TabSidebarGhostView: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject var ghost: TabSidebarGhostModel

    var body: some View {
        if let info = ghost.info {
            let palette = model.palette
            let width = max(80, info.width)
            ghostChip(info, palette: palette, width: width)
                .position(
                    x: ghost.location.x - ghost.grabOffset.width + width / 2,
                    y: ghost.location.y - ghost.grabOffset.height + TabSidebarMetrics.ghostHeight / 2)
                .allowsHitTesting(false)
                .opacity(ghost.isInvalid ? 0.6 : 1)
                .overlay(alignment: .topTrailing) { invalidBadge(palette, width: width) }
        }
    }

    private func ghostChip(_ info: TabSidebarGhostModel.Info, palette: TabSidebarPalette, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if info.paneCount != nil {
                RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
                    .fill(palette.pressed(over: palette.sidebar).color)
                    .frame(width: width, height: TabSidebarMetrics.ghostHeight)
                    .offset(x: 4, y: 4)
            }
            HStack(spacing: 8) {
                if let group = info.group {
                    Circle().fill(palette.groupBase(group.color).color).frame(width: 8, height: 8)
                    Text(info.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.text.color)
                        .lineLimit(1)
                    Text("\(group.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(palette.text2.color)
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.field.color))
                } else {
                    TabSidebarIconView(
                        icon: info.isClaude ? .claude : .terminal, size: TabSidebarMetrics.tileGlyph,
                        color: (info.isClaude ? palette.claude : palette.glyph).color)
                        .frame(width: TabSidebarMetrics.tile, height: TabSidebarMetrics.tile)
                        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.tileRadius)
                            .fill((info.isClaude ? palette.claudeTile(over: palette.sidebar) : palette.tile(over: palette.sidebar)).color))
                    Text(info.title)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(palette.text.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let count = info.paneCount {
                        Text("\(count) panes").font(.system(size: 11)).foregroundColor(palette.text2.color)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: width, height: TabSidebarMetrics.ghostHeight)
            .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius).fill(palette.selected(over: palette.sidebar).color))
            .overlay(RoundedRectangle(cornerRadius: TabSidebarMetrics.rowRadius)
                .strokeBorder(palette.selectedBorder(over: palette.sidebar).color, lineWidth: 1))
            .shadow(color: .black.opacity(palette.isDark ? 0.55 : 0.20), radius: 14, y: 10)
        }
        .frame(width: width + 4, height: TabSidebarMetrics.ghostHeight + 4, alignment: .topLeading)
    }

    @ViewBuilder
    private func invalidBadge(_ palette: TabSidebarPalette, width: CGFloat) -> some View {
        if ghost.isInvalid {
            ZStack {
                Circle().fill(palette.error.color)
                TabSidebarIconView(icon: .close, size: 10, color: .white, stroke: 2)
            }
            .frame(width: 16, height: 16)
            .position(
                x: ghost.location.x - ghost.grabOffset.width + width + 6,
                y: ghost.location.y - ghost.grabOffset.height - 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}


// MARK: - Section header

struct TabSidebarSectionHeader: View {
    let palette: TabSidebarPalette
    let title: String
    let icon: TabSidebarIcon?
    let count: Int
    let isCollapsed: Bool
    let action: () -> Void
    @State private var isHovering = false
    @State private var isPressed = false

    private var fill: Color {
        palette.ink.color.opacity(isPressed ? 0.08 : isHovering ? 0.05 : 0)
    }

    var body: some View {
        HStack(spacing: TabSidebarMetrics.sectionHeaderGap) {
            TabSidebarIconView(icon: .chevron, size: TabSidebarMetrics.chevronGlyph, color: palette.text3.color)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .animation(TabSidebarMotion.chevron, value: isCollapsed)
                .frame(width: TabSidebarMetrics.sectionChevronBox, height: TabSidebarMetrics.sectionChevronBox)
            if let icon {
                TabSidebarIconView(icon: icon, size: TabSidebarMetrics.sectionPinIcon, color: palette.text3.color, stroke: 1.75)
            }
            Text(title)
                .font(.system(size: TabSidebarMetrics.sectionFont, weight: .semibold))
                .tracking(TabSidebarMetrics.sectionTracking)
                .foregroundColor(palette.text3.color)
            Text("\(count)")
                .font(.system(size: TabSidebarMetrics.sectionFont, weight: .medium).monospacedDigit())
                .foregroundColor(palette.text3.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TabSidebarMetrics.sectionHeaderPaddingHorizontal)
        .frame(height: TabSidebarMetrics.sectionHeaderHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.sectionHeaderRadius).fill(fill))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(TabSidebarMotion.hover, value: isHovering)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { value in
                    isPressed = false
                    if abs(value.translation.width) < 4, abs(value.translation.height) < 4 { action() }
                })
        .sidebarControl()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title.capitalized), \(count) \(count == 1 ? "tab" : "tabs"), \(isCollapsed ? "collapsed" : "expanded")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
