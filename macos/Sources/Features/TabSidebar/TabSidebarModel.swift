import AppKit
import Combine
import SwiftUI

/// What the user is renaming.
enum TabSidebarEditTarget: Equatable {
    case tab(Int)
    case group(String)
}

/// The keyboard cursor: a row (a pane, or the single row of a tab) or a group header.
enum TabSidebarFocusKey: Equatable, Hashable {
    case row(tab: Int, pane: String?)
    case group(String)

    var stringKey: String {
        switch self {
        case .row(let tab, let pane): return "row:\(tab):\(pane ?? "tab")"
        case .group(let id): return "group:\(id)"
        }
    }
}

/// Per-tab sidebar state that survives window restoration (spec part 2B, section 5).
struct TabSidebarMeta: Equatable, Codable {
    var isPinned: Bool = false
    /// The tab's own color; it shows only while the tab is loose.
    var color: TabSidebarGroupColor = .none
    var group: TabSidebarGroup?

    init() {}

    // Tolerant decoding so state saved by an older build still restores.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPinned = (try? c.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        color = (try? c.decodeIfPresent(TabSidebarGroupColor.self, forKey: .color)) ?? .none
        group = try? c.decodeIfPresent(TabSidebarGroup.self, forKey: .group)
    }

    /// A new tab opens in its neighbor's container: the same group, or pinned if that one is.
    var inheritedByNewTab: TabSidebarMeta {
        var copy = TabSidebarMeta()
        copy.isPinned = isPinned
        copy.group = group
        return copy
    }
}

/// The sidebar's state for one window. It reads the window's native tab group and performs
/// actions on it; the tabs themselves stay ordinary AppKit tabs.
///
/// Efficiency: nothing polls. A refresh is requested by events, coalesced, held to 4 per second,
/// skipped while the window is not visible, and only published if the snapshot changed.
final class TabSidebarModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var list = TabSidebarList()
    @Published private(set) var palette: TabSidebarPalette
    @Published private(set) var tabCount = 0
    @Published var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    @Published var editing: TabSidebarEditTarget?
    @Published private(set) var focusKey: TabSidebarFocusKey?
    @Published private(set) var showsFocusRing = false
    @Published var drag: TabSidebarDragState?
    @Published private(set) var flashID: String?
    /// The row whose context menu is open, so its pill stays visible.
    @Published private(set) var menuOwner: String?
    @Published private(set) var focusSearchTick = 0
    @Published private(set) var isListFocused = false
    @Published var isOptionsOpen = false
    /// Multi-pane tabs whose panes are folded away, and the folded top-level sections ("pinned", "open").
    /// Kept per window; a drag opens a folded section while it lasts.
    @Published private(set) var collapsedTabs: Set<Int> = []
    @Published private(set) var collapsedSections: Set<String> = []
    /// False while the window is hidden or minimized, so continuous animation stops.
    @Published private(set) var isAnimating = true
    /// A block id the list should scroll into view (keyboard moves).
    @Published var scrollRequest: String?
    /// While searching and nothing matched.
    var isEmptyResult: Bool { list.isEmptyResult }

    private(set) weak var window: NSWindow?

    let geometry = TabSidebarGeometry()

    let pointerRegistry = TabSidebarPointerRegistry()
    let ghost = TabSidebarGhostModel()
    lazy var dragController = TabSidebarDragController(model: self)

    // MARK: Private state

    private(set) var items: [TabSidebarItem] = []
    private var isDirty = true
    private var isRefreshScheduled = false
    private var lastRefresh = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var terminalBackground = TabSidebarRGB(hex: 0x17181A)
    private weak var keyView: NSView?

    init(window: NSWindow) {
        self.window = window
        palette = TabSidebarPalette(terminal: terminalBackground)

        let center = NotificationCenter.default
        for name in [Notification.Name.tabSidebarNeedsRefresh, .terminalWindowBellDidChangeNotification] {
            center.publisher(for: name)
                .sink { [weak self] _ in self?.requestRefresh() }
                .store(in: &cancellables)
        }

        // Hidden tabs skip refreshes, so catch up as soon as this window is shown again.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification] {
            center.publisher(for: name, object: window)
                .sink { [weak self] _ in
                    self?.isAnimating = self?.isWindowVisible ?? false
                    self?.refreshIfNeeded(force: true)
                }
                .store(in: &cancellables)
        }

        // `@Published` publishes before it stores, so hop to the next turn to read the new prefs.
        TabSidebarSettings.shared.$prefs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildList()
                self?.requestRefresh(immediately: true)
            }
            .store(in: &cancellables)

        center.publisher(for: NSWindow.didResignKeyNotification, object: window)
            .sink { [weak self] _ in
                TabSidebarHoverCard.shared.hideNow()
                self?.dragController.cancelIfActive()
            }
            .store(in: &cancellables)

        requestRefresh(immediately: true)
    }

    /// A model that shows fixed items and watches nothing. Used to render previews.
    init(previewItems: [TabSidebarItem], terminal: NSColor) {
        window = nil
        terminalBackground = TabSidebarRGB(terminal)
        palette = TabSidebarPalette(terminal: terminalBackground)
        items = previewItems
        tabCount = previewItems.count
        list = TabSidebarLayout.list(items: previewItems, prefs: TabSidebarSettings.shared.prefs)
    }

    var prefs: TabSidebarPrefs { TabSidebarSettings.shared.prefs }
    var selectedID: Int? { items.first(where: \.isSelected)?.id }
    var isSearching: Bool { !TabSidebarLayout.normalized(query).isEmpty }

    /// Called whenever the terminal's theme changes. Everything re-resolves instantly.
    func setTerminalBackground(_ color: NSColor) {
        let rgb = TabSidebarRGB(color)
        guard rgb != terminalBackground else { return }
        terminalBackground = rgb
        palette = TabSidebarPalette(terminal: rgb)
    }

    // MARK: Refresh

    /// Event-driven. Held to at most 4 refreshes per second so rapid title changes cannot spin the UI.
    func requestRefresh(immediately: Bool = false) {
        isDirty = true
        guard !isRefreshScheduled else { return }
        isRefreshScheduled = true

        let wait = immediately ? 0 : max(0, 0.25 - Date().timeIntervalSince(lastRefresh))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.isRefreshScheduled = false
            self.refreshIfNeeded()
        }
    }

    private var isWindowVisible: Bool {
        window?.occlusionState.contains(.visible) ?? false
    }

    private func refreshIfNeeded(force: Bool = false) {
        guard isDirty || force, isWindowVisible else { return }
        isDirty = false
        lastRefresh = Date()

        let snapshot = buildItems()
        if snapshot != items {
            items = snapshot
            tabCount = snapshot.count
            rebuildList()
            keepOrderConsistent()
        }
    }

    /// A tab that joined a group (a new tab inherits its neighbor's) must sit inside its block.
    private func keepOrderConsistent() {
        let wanted = TabSidebarLayout.desiredOrder(items)
        if wanted != items.map(\.id), !isSearching {
            applyOrder(wanted)
        }
    }

    func rebuildList() {
        list = TabSidebarLayout.list(items: items, prefs: prefs, query: query)
    }

    private func queryChanged() {
        TabSidebarHoverCard.shared.hideNow()
        rebuildList()
    }

    // MARK: Snapshot

    private func controllers() -> [TerminalController] {
        guard let group = window?.tabGroup else {
            return (window?.windowController as? TerminalController).map { [$0] } ?? []
        }
        return group.windows.compactMap { $0.windowController as? TerminalController }
    }

    func controller(for id: Int) -> TerminalController? {
        controllers().first { $0.window?.windowNumber == id }
    }

    var ghostty: Ghostty.App? { (NSApp.delegate as? AppDelegate)?.ghostty }

    private func buildItems() -> [TabSidebarItem] {
        let selected = window?.tabGroup?.selectedWindow ?? window
        let wantsDiff = prefs.density == .expanded

        return controllers().enumerated().compactMap { index, controller in
            guard let tabWindow = controller.window else { return nil }
            let meta = controller.sidebarMeta
            let focusedID = controller.focusedSurface?.id

            let panes: [TabSidebarPane] = controller.surfaceTree.map { surface in
                let path = surface.pwd ?? ""
                let branch = path.isEmpty ? nil : GitBranch.current(inDirectory: path)
                let diff = wantsDiff && branch != nil
                    ? GitDiffStats.shared.stats(forDirectory: path) { TabSidebarEvents.requestRefresh() }
                    : nil
                return TabSidebarPane(
                    id: surface.id.uuidString,
                    rawTitle: surface.title,
                    cwd: path,
                    cwdDisplay: path.isEmpty ? "" : (path as NSString).abbreviatingWithTildeInPath,
                    branch: branch,
                    diff: diff,
                    isFocused: surface.id == focusedID,
                    hasBell: surface.bell,
                    hasExited: surface.processExited)
            }

            return TabSidebarItem(
                id: tabWindow.windowNumber,
                customName: controller.titleOverride,
                panes: panes,
                color: meta.color,
                isSelected: tabWindow === selected,
                isPinned: meta.isPinned,
                group: meta.isPinned ? nil : meta.group,
                position: index)
        }
    }

    func item(_ id: Int) -> TabSidebarItem? { items.first { $0.id == id } }

    func group(_ id: String) -> TabSidebarGroup? { items.first(where: { $0.group?.id == id })?.group }

    var groups: [TabSidebarGroup] {
        var seen = Set<String>()
        return items.compactMap { $0.group }.filter { seen.insert($0.id).inserted }
    }

    // MARK: Writing back

    /// Writes a new list to the windows: per-tab meta, then the real tab order.
    func commit(_ new: [TabSidebarItem], flash: String? = nil, announce: String? = nil) {
        for item in new {
            guard let controller = controller(for: item.id) else { continue }
            var meta = TabSidebarMeta()
            meta.isPinned = item.isPinned
            meta.color = item.color
            meta.group = item.isPinned ? nil : item.group
            if controller.sidebarMeta != meta { controller.sidebarMeta = meta }
        }

        items = new
        tabCount = new.count
        withAnimation(TabSidebarMotion.layout) { rebuildList() }
        applyOrder(new.map(\.id))

        if let flash { flashBlock(flash) }
        if let announce { announceAccessibility(announce) }
        requestRefresh(immediately: true)
    }

    /// Same technique as Ghostty's move_tab action: never remove the selected tab (AppKit would flash
    /// a neighbor), instead re-attach every other tab around it in the desired order.
    private func applyOrder(_ desired: [Int]) {
        guard let window, let group = window.tabGroup else { return }
        let windows = group.windows
        guard windows.map(\.windowNumber) != desired else { return }

        guard let anchor = group.selectedWindow ?? windows.first,
              let anchorIndex = desired.firstIndex(of: anchor.windowNumber) else { return }

        let byNumber = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowNumber, $0) })
        let after = desired[(anchorIndex + 1)...].compactMap { byNumber[$0] }
        let before = desired[..<anchorIndex].compactMap { byNumber[$0] }

        for tab in after.reversed() {
            group.removeWindow(tab)
            anchor.addTabbedWindowSafely(tab, ordered: .above)
        }
        for tab in before {
            group.removeWindow(tab)
            anchor.addTabbedWindowSafely(tab, ordered: .below)
        }

        anchor.makeKeyAndOrderFront(nil)
        TabSidebarEvents.requestRefresh()
    }

    /// The moved block flashes the "settle" color and fades (400 ms).
    private func flashBlock(_ id: String) {
        flashID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            if self?.flashID == id { self?.flashID = nil }
        }
    }

    // MARK: Selecting

    /// A mouse click: switch to the tab, focus that pane's terminal, hide the focus ring.
    func select(_ id: Int, pane paneID: String? = nil) {
        TabSidebarHoverCard.shared.hideNow()
        showsFocusRing = false
        focusKey = .row(tab: id, pane: paneID)
        guard let controller = controller(for: id), let target = controller.window else { return }
        target.makeKeyAndOrderFront(nil)
        let surface = paneID.flatMap { pane in controller.surfaceTree.first { $0.id.uuidString == pane } }
            ?? controller.focusedSurface
        if let surface { Ghostty.moveFocus(to: surface) }
    }

    /// Space on a keyboard-focused row: switch tab and pane but keep keyboard focus in the sidebar.
    func selectKeepingFocus(_ id: Int, pane paneID: String?) {
        guard let controller = controller(for: id), let target = controller.window else { return }
        target.makeKeyAndOrderFront(nil)
        if let paneID, let surface = controller.surfaceTree.first(where: { $0.id.uuidString == paneID }) {
            controller.focusedSurface = surface
        }
        requestRefresh(immediately: true)
        DispatchQueue.main.async { [weak self] in self?.focusList() }
    }

    func focusTerminal() {
        guard let surface = (window?.windowController as? TerminalController)?.focusedSurface else { return }
        Ghostty.moveFocus(to: surface)
    }

    // MARK: Creating

    func newTab() {
        (window?.windowController as? TerminalController)?.newTab(nil)
    }

    func newWindow() {
        (window?.windowController as? TerminalController)?.newWindow(nil)
    }

    /// Opens a tab running `command` (in `directory`) next to the current one.
    @discardableResult
    func newTab(command: String?, directory: String?) -> TerminalController? {
        guard let ghostty else { return nil }
        var config = Ghostty.SurfaceConfiguration()
        if let command, !command.isEmpty { config.command = command }
        if let directory, !directory.isEmpty {
            config.workingDirectory = (directory as NSString).expandingTildeInPath
        }
        return TerminalController.newTab(ghostty, from: window, withBaseConfig: config)
    }

    func open(_ config: TabConfig) {
        newTab(command: config.command, directory: config.directory)
    }

    /// New Tab in Group: added at the end of that group, which expands.
    func newTab(inGroup id: String) {
        setCollapsed(false, group: id)
        guard let created = newTab(command: nil, directory: nil), let tab = created.window?.windowNumber else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshIfNeeded(force: true)
            self.commit(TabSidebarOps.moveToGroup(tab, group: id, in: self.items))
        }
    }

    /// New Tab Group (+ menu): one new terminal tab, in its own group, at the end of the list.
    func newTabGroup() {
        guard let created = newTab(command: nil, directory: nil), let tab = created.window?.windowNumber else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshIfNeeded(force: true)
            guard let created = self.item(tab) else { return }
            let id = UUID().uuidString
            let color = TabSidebarLayout.nextGroupColor(used: self.groups.map(\.color))
            self.commit(TabSidebarOps.newTabGroup(tab: created, id: id, name: "New Group", color: color, in: self.items))
            self.editing = .group(id)
        }
    }

    var canReopenClosedTab: Bool {
        (window?.windowController as? TerminalController)?.undoManager?.canUndo ?? false
    }

    func reopenClosedTab() {
        (window?.windowController as? TerminalController)?.undoManager?.undo()
    }

    func saveAsConfig(_ id: Int) {
        guard let item = item(id), let pane = item.focusedPane else { return }
        TabConfigStore.save(TabConfig(
            name: item.name(prefs),
            directory: pane.cwdDisplay.isEmpty ? nil : pane.cwdDisplay,
            command: nil))
    }

    func editTabConfigs() {
        NSWorkspace.shared.open(TabConfigStore.ensureFileExists())
    }

    // MARK: Closing

    func close(_ id: Int) {
        guard let controller = controller(for: id) else { return }
        // A confirmation sheet would attach to a hidden window, so bring that tab forward first.
        if controller.surfaceTree.contains(where: { $0.needsConfirmQuit }) {
            select(id)
            controller.closeTab(nil)
        } else {
            controller.closeTabImmediately()
        }
    }

    /// Closes one split; the tab itself when it is the only pane.
    func close(_ id: Int, pane paneID: String) {
        guard let controller = controller(for: id) else { return }
        guard controller.surfaceTree.count > 1,
              let surface = controller.surfaceTree.first(where: { $0.id.uuidString == paneID }) else {
            close(id)
            return
        }
        select(id)
        controller.closeSurface(surface)
    }

    func closeOthers(than id: Int) {
        guard let controller = controller(for: id) else { return }
        select(id)
        controller.closeOtherTabs(nil)
    }

    func closeBelow(_ id: Int) {
        guard let controller = controller(for: id) else { return }
        select(id)
        controller.closeTabsOnTheRight(nil)
    }

    func closeTabs(inGroup id: String) {
        for item in items where item.group?.id == id && !item.isPinned { close(item.id) }
    }

    /// Closing a group closes every tab in it, so more than one tab asks first, in a popover under the button.
    func confirmCloseGroup(_ id: String, anchor: NSView? = nil) {
        let count = items.filter { $0.group?.id == id }.count
        guard count > 1, let anchor, anchor.window != nil else { return closeTabs(inGroup: id) }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: TabSidebarCloseConfirm(
            palette: palette, count: count,
            cancel: { [weak popover] in popover?.close() },
            confirm: { [weak self, weak popover] in
                popover?.close()
                self?.closeTabs(inGroup: id)
            }))
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func canCloseOthers(_ id: Int) -> Bool {
        items.contains { $0.id != id && !$0.isPinned }
    }

    func canCloseBelow(_ id: Int) -> Bool {
        guard let at = items.firstIndex(where: { $0.id == id }) else { return false }
        return items[(at + 1)...].contains { !$0.isPinned }
    }

    // MARK: Rename and copy

    func beginRename(tab id: Int) { editing = .tab(id) }
    func beginRename(group id: String) { editing = .group(id) }

    /// Spec 5.3: trimmed; an empty tab name goes back to the automatic title; an empty group name keeps the old one.
    func commitRename(tab id: Int, to text: String) {
        defer { editing = nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        controller(for: id)?.titleOverride = trimmed.isEmpty ? nil : trimmed
        requestRefresh(immediately: true)
    }

    func commitRename(group id: String, to text: String) {
        defer { editing = nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateGroup(id) { $0.name = trimmed }
    }

    func cancelRename() { editing = nil }

    func resetName(_ id: Int) {
        controller(for: id)?.titleOverride = nil
        requestRefresh(immediately: true)
    }

    func copyPaneTitle(_ id: Int, pane paneID: String?) {
        guard let item = item(id) else { return }
        let pane = item.panes.first { $0.id == paneID } ?? item.focusedPane
        copy(pane?.title(prefs) ?? item.name(prefs))
    }

    func copyWorkingDirectory(_ id: Int, pane paneID: String?) {
        guard let item = item(id) else { return }
        let pane = item.panes.first { $0.id == paneID } ?? item.focusedPane
        copy(pane?.cwd ?? "")
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Groups and pins

    /// Runs `change` on the group's attributes for every member and commits (no reorder).
    func updateGroup(_ id: String, _ change: (inout TabSidebarGroup) -> Void) {
        var new = items
        for index in new.indices where new[index].group?.id == id {
            change(&new[index].group!)
        }
        commit(new)
    }

    func setCollapsed(_ collapsed: Bool, group id: String) {
        guard group(id)?.isCollapsed != collapsed else { return }
        withAnimation(TabSidebarMotion.groupToggle) {
            updateGroup(id) { $0.isCollapsed = collapsed }
        }
    }

    func toggleTabCollapsed(_ tab: Int) {
        withAnimation(TabSidebarMotion.groupToggle) {
            if collapsedTabs.contains(tab) { collapsedTabs.remove(tab) } else { collapsedTabs.insert(tab) }
        }
    }

    func isSectionCollapsed(_ section: String) -> Bool {
        collapsedSections.contains(section) && drag == nil && query.isEmpty
    }

    func toggleSectionCollapsed(_ section: String) {
        withAnimation(TabSidebarMotion.groupToggle) {
            if collapsedSections.contains(section) { collapsedSections.remove(section) } else { collapsedSections.insert(section) }
        }
    }

    func toggleCollapsed(_ id: String) {
        setCollapsed(!(group(id)?.isCollapsed ?? false), group: id)
    }

    func setGroupColor(_ id: String, _ color: TabSidebarGroupColor) {
        withAnimation(TabSidebarMotion.swatch) { updateGroup(id) { $0.color = color } }
    }

    /// Tab menu swatches: the group's color if grouped, otherwise the tab's own.
    func setTabColor(_ tab: Int, _ color: TabSidebarGroupColor) {
        if let group = item(tab)?.group, item(tab)?.isPinned == false {
            setGroupColor(group.id, color)
            return
        }
        var new = items
        if let index = new.firstIndex(where: { $0.id == tab }) { new[index].color = color }
        withAnimation(TabSidebarMotion.swatch) { commit(new) }
    }

    func togglePinned(_ tab: Int) {
        guard let current = item(tab) else { return }
        let new = current.isPinned || (current.group?.isPinned ?? false)
            ? TabSidebarOps.unpinTab(tab, in: items)
            : TabSidebarOps.pinTab(tab, in: items)
        commit(new, flash: "tab:\(tab)", announce: current.isPinned ? nil : "Pinned \(current.name(prefs))")
    }

    func toggleGroupPinned(_ id: String) {
        let pinned = group(id)?.isPinned ?? false
        commit(pinned ? TabSidebarOps.unpinGroup(id, in: items) : TabSidebarOps.pinGroup(id, in: items), flash: "group:\(id)")
    }

    /// New Group with Tab: expanded, first unused color, and the group name starts being edited.
    func newGroup(with tab: Int) {
        let id = UUID().uuidString
        let color = TabSidebarLayout.nextGroupColor(used: groups.map(\.color))
        commit(TabSidebarOps.newGroup(with: tab, id: id, name: "New Group", color: color, in: items), flash: "group:\(id)")
        editing = .group(id)
    }

    func moveToGroup(_ tab: Int, group id: String) {
        guard let moved = item(tab), let target = group(id) else { return }
        setCollapsed(false, group: id)
        commit(TabSidebarOps.moveToGroup(tab, group: id, in: items), flash: "tab:\(tab)",
               announce: "Moved \(moved.name(prefs)) to \(target.name)")
    }

    func removeFromGroup(_ tab: Int) {
        commit(TabSidebarOps.removeFromGroup(tab, in: items), flash: "tab:\(tab)")
    }

    func ungroup(_ id: String) {
        commit(TabSidebarOps.ungroup(id, in: items))
    }

    // MARK: Ordering

    func canMove(_ target: TabSidebarOps.MoveTarget, down: Bool) -> Bool {
        TabSidebarOps.canSwap(target, down: down, in: items)
    }

    func move(_ target: TabSidebarOps.MoveTarget, down: Bool) {
        guard let new = TabSidebarOps.swap(target, down: down, in: items) else { return }
        switch target {
        case .tab(let id): commit(new, flash: "tab:\(id)")
        case .group(let id): commit(new, flash: "group:\(id)")
        }
    }

    func moveOutOfGroup(_ tab: Int) {
        guard item(tab)?.group != nil else { return }
        removeFromGroup(tab)
    }

    func moveIntoPreviousGroup(_ tab: Int) {
        guard let result = TabSidebarOps.moveIntoPreviousGroup(tab, in: items) else { return }
        setCollapsed(false, group: result.group)
        commit(result.items, flash: "tab:\(tab)")
    }

    // MARK: Focus (keyboard cursor)

    func setFocus(_ key: TabSidebarFocusKey?, ring: Bool) {
        focusKey = key
        showsFocusRing = ring && key != nil
    }

    func registerKeyView(_ view: NSView) { keyView = view }

    /// A window point (y up) in the sidebar's SwiftUI space (origin top-left of the sidebar).
    func sidebarPoint(forWindow point: CGPoint) -> CGPoint? {
        guard let keyView, keyView.window != nil else { return nil }
        let rect = keyView.convert(keyView.bounds, to: nil)
        return CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y)
    }

    /// A point in the sidebar's SwiftUI space (origin top-left of the sidebar) as a window point (y up).
    func windowPoint(forSidebar point: CGPoint) -> CGPoint? {
        guard let keyView, keyView.window != nil else { return nil }
        let rect = keyView.convert(keyView.bounds, to: nil)
        return CGPoint(x: rect.minX + point.x, y: rect.maxY - point.y)
    }

    func focusList() {
        guard let view = keyView, let window else { return }
        window.makeFirstResponder(view)
    }

    func listFocusChanged(_ focused: Bool) {
        isListFocused = focused
        if !focused { showsFocusRing = false }
    }

    func requestSearchFocus() {
        focusSearchTick += 1
    }

    func menuOpened(for key: String?) { menuOwner = key }

    // MARK: Accessibility

    func announceAccessibility(_ text: String) {
        guard let window else { return }
        NSAccessibility.post(
            element: window, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
