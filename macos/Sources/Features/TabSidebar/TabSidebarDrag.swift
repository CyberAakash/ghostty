import AppKit
import SwiftUI

// Drag and drop (spec part 2B, section 1). SwiftUI's own drag support is not used: a custom
// gesture gives the exact ghost, indicators, hit zones, auto-scroll and spring-loading.

// MARK: - State

/// What the list needs to know while a drag is in progress. It changes only when the drop target
/// does, never per mouse move (the ghost's position lives in `TabSidebarGhostModel`).
struct TabSidebarDragState: Equatable {
    enum Verdict: Equatable {
        /// No target: releasing cancels, nothing is drawn.
        case none
        /// A target that is not allowed: red ring on `group`, releasing cancels.
        case invalid(group: String?)
        case valid
    }

    var source: TabSidebarOps.Source
    var target: TabSidebarOps.Target?
    var verdict: Verdict
    /// The collapsed group that is temporarily expanded because the pointer rests on it.
    var springGroup: String?

    var sourceTab: Int? {
        if case .tab(let id) = source { return id }
        return nil
    }
    var sourceGroup: String? {
        if case .group(let id) = source { return id }
        return nil
    }
}

/// The ghost that follows the pointer. Separate from the drag state so that moving it re-renders
/// only the ghost view.
final class TabSidebarGhostModel: ObservableObject {
    struct Info: Equatable {
        var title: String
        var isClaude: Bool
        var paneCount: Int?
        /// A group ghost shows a dot, the name and the count.
        var group: (color: TabSidebarGroupColor, count: Int)?
        var width: CGFloat

        static func == (a: Info, b: Info) -> Bool {
            a.title == b.title && a.isClaude == b.isClaude && a.paneCount == b.paneCount
                && a.group?.color == b.group?.color && a.group?.count == b.group?.count && a.width == b.width
        }
    }

    @Published var info: Info?
    /// Pointer position in the sidebar's coordinate space.
    @Published var location: CGPoint = .zero
    @Published var grabOffset: CGSize = .zero
    @Published var isInvalid = false
}

// MARK: - Geometry

/// The live frames of the laid-out blocks. Views register themselves; frames are read on demand from
/// the AppKit views so they are always right, even while the list scrolls.
final class TabSidebarGeometry {
    enum Kind: Hashable {
        case tabBlock(Int)
        case groupContainer(String)
        case groupHeader(String)
        case groupBottom(String)
        case tail
        case pinZone
        case viewport
        case optionsButton
        case plusButton
        case rowTitle(String)
        case groupName(String)
    }

    private struct Weak { weak var view: NSView? }
    private var views: [Kind: Weak] = [:]

    func register(_ kind: Kind, view: NSView) { views[kind] = Weak(view: view) }
    func unregister(_ kind: Kind, view: NSView) {
        if views[kind]?.view === view { views[kind] = nil }
    }

    func view(_ kind: Kind) -> NSView? { views[kind]?.view }

    var scrollView: NSScrollView? {
        (view(.tail) ?? view(.viewport))?.enclosingScrollView
    }

    /// A frame in the hit test's y-down space (window coordinates, flipped).
    private func frame(_ kind: Kind) -> TabSidebarHitTest.Frame? {
        guard let view = view(kind), view.window != nil else { return nil }
        let rect = view.convert(view.bounds, to: nil)
        return TabSidebarHitTest.Frame(minX: rect.minX, maxX: rect.maxX, top: -rect.maxY, bottom: -rect.minY)
    }

    /// Builds the hit-test layout for the current list. Blocks whose views are not realized (scrolled
    /// far away) are skipped; the pointer cannot be over them.
    func layout(for list: TabSidebarList) -> TabSidebarHitTest.Layout? {
        guard let viewport = frame(.viewport) else { return nil }

        var blocks: [TabSidebarHitTest.Block] = []
        for block in list.pinned + list.main {
            switch block {
            case .tab(let tab):
                guard let f = frame(.tabBlock(tab.id)) else { continue }
                blocks.append(.init(kind: .tab(tab.id), frame: f))

            case .group(let group):
                guard let container = frame(.groupContainer(group.id)) else { continue }
                var members: [(id: Int, frame: TabSidebarHitTest.Frame)] = []
                for tab in group.tabs {
                    if let f = frame(.tabBlock(tab.id)) { members.append((tab.id, f)) }
                }
                blocks.append(.init(
                    kind: .group(group.id), frame: container,
                    header: frame(.groupHeader(group.id)),
                    bottomStrip: group.group.isCollapsed ? nil : frame(.groupBottom(group.id)),
                    members: members))
            }
        }
        return TabSidebarHitTest.Layout(viewport: viewport, blocks: blocks, pinZone: frame(.pinZone))
    }
}

/// An invisible view that reports its frame to the geometry registry.
struct TabSidebarFrameReporter: NSViewRepresentable {
    let geometry: TabSidebarGeometry
    let kind: TabSidebarGeometry.Kind

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.geometry = geometry
        view.kind = kind
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        if view.kind != kind {
            view.unregister()
            view.kind = kind
        }
        view.geometry = geometry
        view.register()
    }

    static func dismantleNSView(_ view: ReporterView, coordinator: ()) { view.unregister() }

    final class ReporterView: NSView {
        var geometry: TabSidebarGeometry?
        var kind: TabSidebarGeometry.Kind?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func register() {
            guard let geometry, let kind else { return }
            geometry.register(kind, view: self)
        }

        func unregister() {
            guard let geometry, let kind else { return }
            geometry.unregister(kind, view: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { register() } else { unregister() }
        }
    }
}

extension View {
    /// Registers this view's frame under `kind`, as a background that never takes events.
    func reportFrame(_ kind: TabSidebarGeometry.Kind, to geometry: TabSidebarGeometry) -> some View {
        background(TabSidebarFrameReporter(geometry: geometry, kind: kind))
    }
}

// MARK: - Controller

final class TabSidebarDragController {
    private unowned let model: TabSidebarModel

    private(set) var isActive = false
    private var escapeMonitor: Any?
    private var scrollTimer: Timer?
    private var springWorkItem: DispatchWorkItem?
    private var springTarget: String?
    private var expandedBySpring: Set<String> = []
    private var currentItems: [TabSidebarItem]?
    /// The pointer in the sidebar's SwiftUI space, as last reported by the gesture.
    private var lastPointer: CGPoint = .zero

    init(model: TabSidebarModel) { self.model = model }

    // MARK: Lifecycle

    func begin(source: TabSidebarOps.Source, info: TabSidebarGhostModel.Info, grab: CGSize, pointer: CGPoint) {
        guard !isActive, !model.isSearching else { return }
        isActive = true
        TabSidebarHoverCard.shared.hideNow()
        model.ghost.info = info
        model.ghost.grabOffset = grab
        model.ghost.location = pointer
        lastPointer = pointer
        model.ghost.isInvalid = false
        model.setDrag(.init(source: source, target: nil, verdict: .none, springGroup: nil))

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.cancel()
                return nil
            }
            return event
        }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.autoScrollStep()
        }
        NSCursor.closedHand.push()
        update(pointer: pointer)
    }

    func update(pointer: CGPoint) {
        guard isActive else { return }
        model.ghost.location = pointer
        lastPointer = pointer
        hitTest()
    }

    /// Releasing the button: commit a valid drop, cancel anything else.
    func end() {
        guard isActive, let drag = model.drag else { return }
        let items = currentItems
        let valid = drag.verdict == .valid
        finish()

        if valid, let items, let source = Optional(drag.source) {
            commitDrop(source: source, target: drag.target, items: items)
        } else {
            collapseSpringGroups(except: nil)
        }
    }

    func cancel() {
        guard isActive else { return }
        finish()
        collapseSpringGroups(except: nil)
    }

    func cancelIfActive() { if isActive { cancel() } }

    private func finish() {
        isActive = false
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        scrollTimer?.invalidate()
        scrollTimer = nil
        springWorkItem?.cancel()
        springWorkItem = nil
        springTarget = nil
        currentItems = nil
        NSCursor.pop()
        model.ghost.info = nil
        model.setDrag(nil)
    }

    // MARK: Hit testing

    private func pointerInWindow() -> CGPoint? {
        guard let point = model.windowPoint(forSidebar: lastPointer) else { return nil }
        return CGPoint(x: point.x, y: -point.y) // flipped into the hit test's y-down space
    }

    private func hitTest() {
        guard let drag = model.drag, let point = pointerInWindow(), let layout = model.geometry.layout(for: model.list) else { return }

        let target = TabSidebarHitTest.resolve(point: point, source: drag.source, layout: layout)
        var verdict = TabSidebarDragState.Verdict.none
        var items: [TabSidebarItem]?

        if let target {
            switch TabSidebarOps.drop(drag.source, on: target, in: model.items) {
            case .move(let new):
                verdict = .valid
                items = new
            case .invalid:
                verdict = .invalid(group: invalidGroup(for: target))
            case .none:
                verdict = .none
            }
        }

        currentItems = items
        model.ghost.isInvalid = { if case .invalid = verdict { return true } else { return false } }()

        var next = drag
        next.target = verdict == .none ? nil : target
        next.verdict = verdict
        if next != drag { model.setDrag(next) }
        updateSpring(for: target, verdict: verdict)
    }

    private func invalidGroup(for target: TabSidebarOps.Target) -> String? {
        switch target {
        case .groupInterior(let id): return id
        case .tab(let tab, _): return model.item(tab)?.group?.id
        default: return nil
        }
    }

    // MARK: Spring-loading (spec: 600 ms over a collapsed group expands it temporarily)

    private func updateSpring(for target: TabSidebarOps.Target?, verdict: TabSidebarDragState.Verdict) {
        var wanted: String?
        if verdict == .valid, case .groupHeader(let id, true)? = target, model.group(id)?.isCollapsed == true {
            wanted = id
        }
        guard wanted != springTarget else { return }
        springWorkItem?.cancel()
        springTarget = wanted

        guard let id = wanted else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isActive, self.springTarget == id else { return }
            self.expandedBySpring.insert(id)
            self.model.setCollapsed(false, group: id)
            self.model.setSpringGroup(id)
        }
        springWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Re-collapses groups that were opened only by the drag, except the one that received the drop.
    private func collapseSpringGroups(except keep: String?) {
        for id in expandedBySpring where id != keep {
            model.setCollapsed(true, group: id)
        }
        expandedBySpring = []
        model.setSpringGroup(nil)
    }

    // MARK: Auto-scroll (band 32 pt, up to 40 pt beyond; v = min(1, depth / 32); 15 pt per frame)

    private func autoScrollStep() {
        guard isActive, let scrollView = model.geometry.scrollView, let viewport = model.geometry.view(.viewport),
              viewport.window != nil else { return }

        let rect = viewport.convert(viewport.bounds, to: nil)
        guard let pointer = model.windowPoint(forSidebar: lastPointer) else { return }
        // Window coordinates are y-up: top edge is maxY.
        let band: CGFloat = 32
        let beyond: CGFloat = 40
        var velocity: CGFloat = 0

        let intoTop = pointer.y - (rect.maxY - band) // positive inside the top band
        let intoBottom = (rect.minY + band) - pointer.y // positive inside the bottom band
        if intoTop > 0, intoTop <= band + beyond {
            velocity = -min(1, intoTop / band)
        } else if intoBottom > 0, intoBottom <= band + beyond {
            velocity = min(1, intoBottom / band)
        }
        guard velocity != 0 else { return }

        let clip = scrollView.contentView
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let maxY = max(0, documentHeight - clip.bounds.height)
        // The document view is flipped (SwiftUI), so scrolling "down" increases y.
        let flipped = scrollView.documentView?.isFlipped ?? true
        let delta = velocity * 15 * (flipped ? 1 : -1)
        var origin = clip.bounds.origin
        origin.y = min(max(0, origin.y + delta), maxY)
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        hitTest() // re-hit-test after every scroll step
    }

    // MARK: Commit

    private func commitDrop(source: TabSidebarOps.Source, target: TabSidebarOps.Target?, items: [TabSidebarItem]) {
        var keep: String?
        var flash: String
        var announcement: String?
        let prefs = model.prefs

        switch source {
        case .tab(let id):
            flash = "tab:\(id)"
            let moved = items.first { $0.id == id }
            if let group = moved?.group, !(moved?.isPinned ?? false) {
                keep = group.id
                // A collapsed group hides its tab, so flash the header instead.
                if group.isCollapsed { flash = "group:\(group.id)" }
                announcement = "Moved \(moved?.name(prefs) ?? "tab") to \(group.name)"
            } else if moved?.isPinned == true || target == .pinZone {
                announcement = "Pinned \(moved?.name(prefs) ?? "tab")"
            }
        case .group(let id):
            flash = "group:\(id)"
            announcement = "Moved \(model.group(id)?.name ?? "group")"
        }

        collapseSpringGroups(except: keep)
        model.commit(items, flash: flash, announce: announcement)
    }
}

// MARK: - Model plumbing

extension TabSidebarModel {
    func setDrag(_ state: TabSidebarDragState?) {
        let wasDragging = drag != nil
        drag = state
        if state == nil || !wasDragging { return }
    }

    func setSpringGroup(_ id: String?) {
        guard var state = drag else { return }
        if state.springGroup != id {
            state.springGroup = id
            drag = state
        }
    }
}
