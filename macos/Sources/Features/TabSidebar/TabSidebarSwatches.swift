import AppKit

// The row of color circles in the tab and group menus (design: Part D, RD3). It is an AppKit view with
// Core Animation layers because a menu runs its own event loop: SwiftUI hover and press state does not
// update there, while tracking areas and layer animations do.

final class TabSidebarSwatchRow: NSView {
    private struct Swatch {
        let color: TabSidebarGroupColor
        let container = CALayer()
        let fill = CAShapeLayer()
        let ring = CAShapeLayer()
        let mark = CAShapeLayer()
    }

    private let palette: TabSidebarPalette
    private let onSelect: (TabSidebarGroupColor) -> Void
    private var swatches: [Swatch]
    private var selected: TabSidebarGroupColor
    private var hovered: Int?
    private var pressed: Int?
    private var tracking: NSTrackingArea?
    private var closeWork: DispatchWorkItem?

    private let size = TabSidebarMetrics.swatch
    private let gap = TabSidebarMetrics.swatchGap
    private let padding = TabSidebarMetrics.swatchPadding

    init(selected: TabSidebarGroupColor, palette: TabSidebarPalette, onSelect: @escaping (TabSidebarGroupColor) -> Void) {
        self.palette = palette
        self.selected = selected
        self.onSelect = onSelect
        swatches = TabSidebarGroupColor.allCases.map { Swatch(color: $0) }
        let count = CGFloat(swatches.count)
        let width = padding.leading + count * TabSidebarMetrics.swatch + (count - 1) * TabSidebarMetrics.swatchGap + padding.trailing
        let height = padding.top + TabSidebarMetrics.swatch + padding.bottom
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        autoresizingMask = [.width]
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layers

    private func frame(at index: Int) -> CGRect {
        CGRect(x: padding.leading + CGFloat(index) * (size + gap), y: (bounds.height - size) / 2, width: size, height: size)
    }

    private func build() {
        guard let root = layer else { return }
        for (index, swatch) in swatches.enumerated() {
            let container = swatch.container
            container.bounds = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            container.position = CGPoint(x: frame(at: index).midX, y: frame(at: index).midY)
            root.addSublayer(container)

            let circle = CGPath(ellipseIn: container.bounds, transform: nil)
            swatch.fill.path = circle
            container.addSublayer(swatch.fill)

            // The selection and hover ring sits 2 pt outside the circle.
            let outer = TabSidebarMetrics.swatchRingGap + TabSidebarMetrics.swatchRing
            let ringRect = container.bounds.insetBy(dx: -outer / 2 - TabSidebarMetrics.swatchRingGap / 2, dy: -outer / 2 - TabSidebarMetrics.swatchRingGap / 2)
            swatch.ring.path = CGPath(ellipseIn: ringRect, transform: nil)
            swatch.ring.fillColor = nil
            swatch.ring.lineWidth = TabSidebarMetrics.swatchRing
            swatch.ring.opacity = 0
            container.addSublayer(swatch.ring)

            swatch.mark.fillColor = nil
            swatch.mark.lineCap = .round
            swatch.mark.lineJoin = .round
            swatch.mark.lineWidth = swatch.color == .none ? 1.25 : 2
            swatch.mark.path = markPath(for: swatch.color)
            container.addSublayer(swatch.mark)
        }
        refreshColors()
        applyState(animated: false)
    }

    /// The check, or the slash of the "None" swatch.
    private func markPath(for color: TabSidebarGroupColor) -> CGPath {
        let path = CGMutablePath()
        let c = CGPoint(x: size / 2, y: size / 2)
        if color == .none {
            path.move(to: CGPoint(x: c.x - 6, y: c.y - 6))
            path.addLine(to: CGPoint(x: c.x + 6, y: c.y + 6))
        } else {
            path.move(to: CGPoint(x: c.x - 3.5, y: c.y))
            path.addLine(to: CGPoint(x: c.x - 1, y: c.y - 2.75))
            path.addLine(to: CGPoint(x: c.x + 3.75, y: c.y + 3))
        }
        return path
    }

    private func resolve(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    private func refreshColors() {
        for swatch in swatches {
            if swatch.color == .none {
                swatch.fill.fillColor = nil
                swatch.fill.strokeColor = resolve(.secondaryLabelColor)
                swatch.fill.lineWidth = 1.5
                swatch.mark.strokeColor = resolve(.secondaryLabelColor)
            } else {
                swatch.fill.fillColor = NSColor(palette.groupBase(swatch.color).color).cgColor
                swatch.fill.strokeColor = nil
                let darkMark = palette.isDark && (swatch.color == .yellow || swatch.color == .green)
                swatch.mark.strokeColor = darkMark ? NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1).cgColor : NSColor.white.cgColor
            }
        }
        applyState(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func layout() {
        super.layout()
        for (index, swatch) in swatches.enumerated() {
            swatch.container.position = CGPoint(x: frame(at: index).midX, y: frame(at: index).midY)
        }
    }

    // MARK: State

    private func applyState(animated: Bool) {
        for (index, swatch) in swatches.enumerated() {
            let isSelected = swatch.color == selected
            let isPressed = pressed == index
            let isHover = hovered == index

            let scale = isPressed ? TabSidebarMetrics.swatchPressedScale : isHover ? TabSidebarMetrics.swatchHoverScale : 1
            let ringColor = isSelected ? NSColor.labelColor : NSColor.tertiaryLabelColor

            CATransaction.begin()
            CATransaction.setDisableActions(!animated)
            // 60 ms to press, 80 ms to grow, 120 ms for the selection to move.
            CATransaction.setAnimationDuration(isPressed ? 0.06 : isHover ? 0.08 : 0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            swatch.container.transform = CATransform3DMakeScale(scale, scale, 1)
            swatch.ring.strokeColor = resolve(ringColor)
            swatch.ring.opacity = (isSelected || isHover) ? 1 : 0
            swatch.mark.opacity = (isSelected && swatch.color != .none) || swatch.color == .none ? 1 : 0
            CATransaction.commit()
        }
    }

    // MARK: Mouse

    private func index(at point: NSPoint) -> Int? {
        swatches.indices.first { frame(at: $0).insetBy(dx: -gap / 2, dy: -padding.top / 2).contains(point) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        removeAllToolTips()
        for index in swatches.indices { addToolTip(frame(at: index), owner: self, userData: nil) }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseMoved(with event: NSEvent) {
        let new = index(at: convert(event.locationInWindow, from: nil))
        guard new != hovered else { return }
        hovered = new
        applyState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        pressed = nil
        applyState(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil))
        applyState(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        let released = index(at: convert(event.locationInWindow, from: nil))
        let began = pressed
        pressed = nil
        guard let released, released == began else {
            applyState(animated: true)
            return
        }
        let color = swatches[released].color
        selected = color
        applyState(animated: true)
        onSelect(color)
        // The ring has 120 ms to move; the menu stays open a little longer so the change is seen.
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.enclosingMenuItem?.menu?.cancelTracking() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    override var acceptsFirstResponder: Bool { false }
}

extension TabSidebarSwatchRow: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let index = index(at: point) else { return "" }
        return swatches[index].color.localizedName
    }
}
