import AppKit
import SwiftUI

// Pieces for the hidden sidebar: the 6 pt hover strip on the window's left edge, the holder of the
// overlay sidebar that slides in over the terminal, and the toggle shown in the title bar.

/// A view that only reports the pointer entering and leaving. It never takes clicks.
class TabSidebarHoverTracker: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    private var tracking: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

final class TabSidebarEdgeStrip: TabSidebarHoverTracker {}

/// Holds the overlay sidebar. Unlike the strip it must take clicks, so its tracking area sits on a
/// subview-free background and `hitTest` is left alone.
final class TabSidebarOverlayHolder: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// The title-bar toggle shown while the sidebar is hidden.
struct TabSidebarShowButton: View {
    let palette: TabSidebarPalette
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            TabSidebarIconView(
                icon: .sidebarToggle, size: 16, color: (isHovering ? palette.text : palette.text2).color)
                .frame(width: TabSidebarMetrics.toolbarButton, height: TabSidebarMetrics.toolbarButton)
                .background(
                    RoundedRectangle(cornerRadius: TabSidebarMetrics.toolbarButtonRadius)
                        .fill(isHovering ? palette.hover(over: palette.sidebar).color : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Show Tab Sidebar (⌘\\)")
        .accessibilityLabel("Show tab sidebar")
        .padding(.horizontal, 6)
    }
}

/// "Maximized — click to restore": a 24 pt banner at the top of the terminal while a pane hides the others.
struct TabSidebarZoomBanner: View {
    let palette: TabSidebarPalette
    let hiddenCount: Int
    let restore: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: restore) {
            HStack(spacing: 8) {
                TabSidebarIconView(icon: .groupPanes, size: 12, color: palette.accent.color)
                Text("Maximized — click to restore")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.text.color)
                Text("\(hiddenCount) hidden · ⇧⌘↩")
                    .font(.system(size: 11))
                    .foregroundColor(palette.text3.color)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(isHovering ? palette.selected(over: palette.sidebar).color : palette.popover.color)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Maximized pane, click to restore")
    }
}
