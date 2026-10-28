import AppKit
import SwiftUI

// Pointer handling for the list, done in AppKit. A row, tab header or group header is a "surface":
// an invisible view that only reports where it is and what a click, a drag, a right click, a middle
// click or a hover on it should do. The sidebar's host view owns the mouse: it finds the surface under
// the pointer and runs one press / drag / click state machine, so a click and a drag never both fire,
// nothing depends on SwiftUI gesture arbitration, and it can be driven by plain NSEvents in tests.
//
// Buttons drawn on top of a surface (close, more, chevron, +) are "controls": the host view leaves
// events on them to SwiftUI.

// MARK: - Registry

final class TabSidebarPointerRegistry {
    private let surfaces = NSHashTable<TabSidebarSurface>.weakObjects()
    private let controls = NSHashTable<TabSidebarControlMarker>.weakObjects()

    func add(_ surface: TabSidebarSurface) { surfaces.add(surface) }
    func remove(_ surface: TabSidebarSurface) { surfaces.remove(surface) }
    func add(_ control: TabSidebarControlMarker) { controls.add(control) }
    func remove(_ control: TabSidebarControlMarker) { controls.remove(control) }

    /// The smallest active surface under a window point (y up), inside the list's viewport.
    func surface(at point: CGPoint, viewport: NSView?) -> TabSidebarSurface? {
        if let viewport, viewport.window != nil, !viewport.convert(viewport.bounds, to: nil).contains(point) {
            return nil
        }
        var best: (TabSidebarSurface, CGFloat)?
        for surface in surfaces.allObjects where surface.isActive && surface.window != nil {
            let rect = surface.convert(surface.bounds, to: nil)
            guard rect.contains(point) else { continue }
            let area = rect.width * rect.height
            if best == nil || area < best!.1 { best = (surface, area) }
        }
        return best?.0
    }

    func isOverControl(_ point: CGPoint) -> Bool {
        controls.allObjects.contains { control in
            control.window != nil && control.convert(control.bounds, to: nil).contains(point)
        }
    }
}

// MARK: - Surface

final class TabSidebarSurface: NSView {
    var registry: TabSidebarPointerRegistry? {
        didSet {
            if oldValue !== registry { oldValue?.remove(self); if window != nil { registry?.add(self) } }
        }
    }
    var isActive = true
    /// What a drag of this surface carries; nil when it cannot be dragged.
    var source: TabSidebarOps.Source?
    /// The block whose frame defines the grab offset.
    var frameKind: TabSidebarGeometry.Kind?
    var ghost: () -> TabSidebarGhostModel.Info = { .init(title: "", isClaude: false, paneCount: nil, group: nil, width: 200) }
    var onPress: (Bool) -> Void = { _ in }
    var onClick: (_ clickCount: Int, _ windowPoint: CGPoint) -> Void = { _, _ in }
    var onRight: () -> Void = {}
    var onMiddle: () -> Void = {}
    /// `inside`, and the surface's top edge in screen coordinates.
    var onHover: (Bool, CGFloat) -> Void = { _, _ in }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { registry?.add(self) } else { registry?.remove(self) }
    }

    var screenTop: CGFloat {
        guard let window else { return 0 }
        return window.convertToScreen(convert(bounds, to: nil)).maxY
    }
}

struct TabSidebarSurfaceRepresentable: NSViewRepresentable {
    let registry: TabSidebarPointerRegistry
    let isActive: Bool
    let source: TabSidebarOps.Source?
    let frameKind: TabSidebarGeometry.Kind?
    let ghost: () -> TabSidebarGhostModel.Info
    let onPress: (Bool) -> Void
    let onClick: (Int, CGPoint) -> Void
    let onRight: () -> Void
    let onMiddle: () -> Void
    let onHover: (Bool, CGFloat) -> Void

    func makeNSView(context: Context) -> TabSidebarSurface {
        let view = TabSidebarSurface()
        update(view)
        return view
    }

    func updateNSView(_ view: TabSidebarSurface, context: Context) { update(view) }

    static func dismantleNSView(_ view: TabSidebarSurface, coordinator: ()) {
        view.registry?.remove(view)
    }

    private func update(_ view: TabSidebarSurface) {
        view.registry = registry
        view.isActive = isActive
        view.source = source
        view.frameKind = frameKind
        view.ghost = ghost
        view.onPress = onPress
        view.onClick = onClick
        view.onRight = onRight
        view.onMiddle = onMiddle
        view.onHover = onHover
    }
}

private struct SurfaceActiveKey: EnvironmentKey { static let defaultValue = true }
private struct PointerRegistryKey: EnvironmentKey { static let defaultValue: TabSidebarPointerRegistry? = nil }

extension EnvironmentValues {
    /// False for surfaces inside a collapsed group: they are laid out but cannot be reached.
    var sidebarSurfaceActive: Bool {
        get { self[SurfaceActiveKey.self] }
        set { self[SurfaceActiveKey.self] = newValue }
    }

    var sidebarPointerRegistry: TabSidebarPointerRegistry? {
        get { self[PointerRegistryKey.self] }
        set { self[PointerRegistryKey.self] = newValue }
    }
}

private struct SurfaceModifier: ViewModifier {
    @Environment(\.sidebarSurfaceActive) private var isActive
    @Environment(\.sidebarPointerRegistry) private var registry
    let source: TabSidebarOps.Source?
    let frameKind: TabSidebarGeometry.Kind?
    let ghost: () -> TabSidebarGhostModel.Info
    let onPress: (Bool) -> Void
    let onClick: (Int, CGPoint) -> Void
    let onRight: () -> Void
    let onMiddle: () -> Void
    let onHover: (Bool, CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            Group {
                if let registry {
                    TabSidebarSurfaceRepresentable(
                        registry: registry, isActive: isActive, source: source, frameKind: frameKind, ghost: ghost,
                        onPress: onPress, onClick: onClick, onRight: onRight, onMiddle: onMiddle, onHover: onHover)
                }
            })
    }
}

extension View {
    func sidebarSurface(
        source: TabSidebarOps.Source?,
        frameKind: TabSidebarGeometry.Kind?,
        ghost: @escaping () -> TabSidebarGhostModel.Info,
        onPress: @escaping (Bool) -> Void,
        onClick: @escaping (_ clickCount: Int, _ windowPoint: CGPoint) -> Void,
        onRight: @escaping () -> Void,
        onMiddle: @escaping () -> Void = {},
        onHover: @escaping (_ inside: Bool, _ screenTop: CGFloat) -> Void
    ) -> some View {
        modifier(SurfaceModifier(
            source: source, frameKind: frameKind, ghost: ghost, onPress: onPress, onClick: onClick,
            onRight: onRight, onMiddle: onMiddle, onHover: onHover))
    }
}

// MARK: - Controls

final class TabSidebarControlMarker: NSView {
    var registry: TabSidebarPointerRegistry? {
        didSet {
            if oldValue !== registry { oldValue?.remove(self); if window != nil { registry?.add(self) } }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { registry?.add(self) } else { registry?.remove(self) }
    }
}

private struct ControlRepresentable: NSViewRepresentable {
    let registry: TabSidebarPointerRegistry

    func makeNSView(context: Context) -> TabSidebarControlMarker {
        let view = TabSidebarControlMarker()
        view.registry = registry
        return view
    }

    func updateNSView(_ view: TabSidebarControlMarker, context: Context) { view.registry = registry }

    static func dismantleNSView(_ view: TabSidebarControlMarker, coordinator: ()) {
        view.registry?.remove(view)
    }
}

private struct ControlModifier: ViewModifier {
    @Environment(\.sidebarPointerRegistry) private var registry

    func body(content: Content) -> some View {
        content.background(Group { if let registry { ControlRepresentable(registry: registry) } })
    }
}

extension View {
    /// Marks a button that sits on top of a surface, so the host view leaves its clicks to SwiftUI.
    func sidebarControl() -> some View { modifier(ControlModifier()) }
}

// MARK: - Host view

/// The sidebar's hosting view. It owns the mouse for the list (see the top of this file).
final class TabSidebarHostView: NonDraggableHostingView<TabSidebarView> {
    private struct Press {
        let surface: TabSidebarSurface
        let start: CGPoint
        let clickCount: Int
        var isDragging = false
    }

    private let model: TabSidebarModel
    private var press: Press?
    private weak var hovered: TabSidebarSurface?
    private var tracking: NSTrackingArea?

    init(model: TabSidebarModel) {
        self.model = model
        super.init(rootView: TabSidebarView(model: model))
    }

    @MainActor required init(rootView: TabSidebarView) { fatalError("use init(model:)") }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var registry: TabSidebarPointerRegistry { model.pointerRegistry }
    private var viewport: NSView? { model.geometry.view(.viewport) }

    // MARK: Mouse buttons

    /// The first click on an inactive window already selects, drags and closes, as in the terminal.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        guard model.editing == nil, !registry.isOverControl(point),
              let surface = registry.surface(at: point, viewport: viewport) else {
            return super.mouseDown(with: event)
        }
        if event.modifierFlags.contains(.control) {
            surface.onRight()
            return
        }
        TabSidebarHoverCard.shared.hideNow()
        press = Press(surface: surface, start: point, clickCount: max(1, event.clickCount))
        surface.onPress(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = press else { return super.mouseDragged(with: event) }
        let point = event.locationInWindow
        guard let pointer = model.sidebarPoint(forWindow: point) else { return }

        if current.isDragging {
            model.dragController.update(pointer: pointer)
            return
        }
        let moved = hypot(point.x - current.start.x, point.y - current.start.y)
        guard moved >= TabSidebarMetrics.dragThreshold else { return }
        guard let source = current.surface.source, !model.isSearching else { return }

        current.surface.onPress(false)
        var grab = CGSize.zero
        if let kind = current.surface.frameKind, let view = model.geometry.view(kind) {
            let rect = view.convert(view.bounds, to: nil)
            grab = CGSize(width: current.start.x - rect.minX, height: min(rect.maxY - current.start.y, 30))
        }
        model.dragController.begin(source: source, info: current.surface.ghost(), grab: grab, pointer: pointer)
        // The drag may be refused (no window, searching): then this press is over.
        if model.dragController.isActive {
            current.isDragging = true
            press = current
        } else {
            press = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = press else { return super.mouseUp(with: event) }
        press = nil
        if current.isDragging {
            model.dragController.end()
            updateHover(at: event.locationInWindow)
            return
        }
        current.surface.onPress(false)
        let point = event.locationInWindow
        guard hypot(point.x - current.start.x, point.y - current.start.y) < TabSidebarMetrics.dragThreshold else { return }
        current.surface.onClick(current.clickCount, point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = event.locationInWindow
        guard model.editing == nil, let surface = registry.surface(at: point, viewport: viewport) else {
            return super.rightMouseDown(with: event)
        }
        TabSidebarHoverCard.shared.hideNow()
        surface.onRight()
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, model.editing == nil,
              let surface = registry.surface(at: event.locationInWindow, viewport: viewport) else {
            return super.otherMouseUp(with: event)
        }
        surface.onMiddle()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        // Rows move under a resting pointer.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.updateHover(at: window.mouseLocationOutsideOfEventStream)
        }
    }

    func updateHover(at point: CGPoint) {
        guard press?.isDragging != true, model.drag == nil else { return setHovered(nil) }
        setHovered(registry.surface(at: point, viewport: viewport))
    }

    private func setHovered(_ surface: TabSidebarSurface?) {
        guard hovered !== surface else { return }
        let old = hovered
        hovered = surface
        old?.onHover(false, 0)
        surface?.onHover(true, surface?.screenTop ?? 0)
    }
}

/// Whether a window-space point (y up) lies inside the registered view for `kind`.
extension TabSidebarGeometry {
    func contains(_ kind: Kind, windowPoint: CGPoint) -> Bool {
        guard let view = view(kind), view.window != nil else { return false }
        return view.convert(view.bounds, to: nil).contains(windowPoint)
    }
}
