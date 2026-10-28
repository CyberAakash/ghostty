import AppKit
import SwiftUI

// The More and Close buttons drawn on each terminal pane (design: Part D, RD4): the same pill as a sidebar
// row. Hidden until the pointer has rested on the pane for 150 ms; it fades in over 120 ms and out over 100 ms.

struct TabSidebarPaneControls: View {
    let surfaceView: Ghostty.SurfaceView
    let isSplit: Bool

    @ObservedObject private var settings = TabSidebarSettings.shared
    @State private var isVisible = false
    @State private var menuOpen = false
    @State private var dwell: DispatchWorkItem?

    private var container: TerminalViewContainer? { surfaceView.window?.contentView as? TerminalViewContainer }
    private var enabled: Bool { isSplit || settings.prefs.paneControlsOnSinglePanes }

    var body: some View {
        // The controls are only drawn in windows that use the sidebar chrome.
        Color.clear
            .allowsHitTesting(false)
            .overlay(alignment: .topTrailing) {
                if enabled, let model = container?.currentChromeModel(), let tab = surfaceView.window?.windowNumber {
                    pill(model: model, tab: tab)
                        .padding(.top, model.isMaximized(tab) ? TabSidebarMetrics.paneControlTopMaximized : TabSidebarMetrics.paneControlTop)
                        .padding(.trailing, TabSidebarMetrics.paneControlTrailing)
                        .opacity(isVisible || menuOpen ? 1 : 0)
                        .allowsHitTesting(isVisible || menuOpen)
                        .animation(.easeInOut(duration: isVisible ? 0.12 : 0.10), value: isVisible || menuOpen)
                }
            }
            .background(HoverTracker { inside in hoverChanged(inside) })
    }

    private func pill(model: TabSidebarModel, tab: Int) -> some View {
        let paneID = surfaceView.id.uuidString
        let panes = model.paneCount(tab)
        return TabSidebarPill(
            palette: model.palette, showsClose: true,
            closeHelp: panes > 1 ? "Close Pane" : "Close Tab", menuHelp: "Pane Options",
            onMenu: {
                menuOpen = true
                TabSidebarMenus.popUp(TabSidebarMenus.tabMenu(model, tab: tab, pane: paneID), owner: nil, model: model)
                menuOpen = false
            },
            onClose: {
                if panes > 1 { model.close(tab, pane: paneID) } else { model.close(tab) }
            })
    }

    private func hoverChanged(_ inside: Bool) {
        dwell?.cancel()
        if inside {
            let work = DispatchWorkItem { isVisible = true }
            dwell = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        } else {
            isVisible = false
        }
    }
}

/// Reports whether the pointer is over the view's frame without taking any mouse events from the terminal.
private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) { view.onChange = onChange }

    final class TrackerView: NSView {
        var onChange: (Bool) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
    }
}
