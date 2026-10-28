import AppKit
import SwiftUI

// The view-options panel (spec part 1, 2.8): a custom opaque panel anchored under the sliders
// button. It is a non-activating child panel so it can be wider than a narrow sidebar and never takes
// keyboard focus from the terminal.

final class TabSidebarOptionsPanel {
    static let shared = TabSidebarOptionsPanel()

    private static let shadowInset: CGFloat = 24

    private var panel: OptionsPanel?
    private var monitors: [Any] = []
    private weak var model: TabSidebarModel?
    private weak var anchor: NSView?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle(model: TabSidebarModel, anchor: NSView, alignRight: Bool = false) {
        if isOpen { close() } else { open(model: model, anchor: anchor, alignRight: alignRight) }
    }

    func open(model: TabSidebarModel, anchor button: NSView, alignRight: Bool = false) {
        guard let window = model.window else { return }
        self.model = model
        self.anchor = button
        TabSidebarHoverCard.shared.hideNow()

        let settings = TabSidebarSettings.shared
        let host = NSHostingView(rootView: OptionsRoot(model: model, settings: settings))
        let size = host.fittingSize

        let panel = self.panel ?? OptionsPanel()
        self.panel = panel
        panel.contentView = host

        // x = button left - 8 (at least 8 from the window edge), y = just under the button + 6.
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let inset = Self.shadowInset
        var x = buttonRect.minX - TabSidebarMetrics.optionsAnchorInset - inset
        if alignRight { x = buttonRect.maxX - size.width + inset }
        x = max(x, window.frame.minX + TabSidebarMetrics.optionsAnchorInset - inset)
        let top = buttonRect.minY - TabSidebarMetrics.optionsAnchorGap + inset
        let frame = NSRect(x: x, y: top - size.height, width: size.width, height: size.height)

        let reduced = TabSidebarMotion.reduced
        panel.setFrame(frame.offsetBy(dx: 0, dy: reduced ? 0 : 4), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.10 : 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            panel.animator().alphaValue = 1
            if !reduced { panel.animator().setFrame(frame, display: true) }
        }
        model.isOptionsOpen = true
        installMonitors(window: window)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        model?.isOptionsOpen = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            if panel?.alphaValue == 0 { panel?.orderOut(nil) }
        })
    }

    /// Clicking outside (other than on the sliders button itself, which toggles) or pressing Esc closes it.
    private func installMonitors(window: NSWindow) {
        let mouse = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window === panel { return event }
            if let button = self.anchor, event.window === window {
                let rect = button.convert(button.bounds, to: nil)
                if rect.contains(event.locationInWindow) { return event }
            }
            self.close()
            return event
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.close()
                return nil
            }
            return event
        }
        monitors = [mouse, keys].compactMap { $0 }
    }
}

private final class OptionsPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = true
        collectionBehavior = [.transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct OptionsRoot: View {
    @ObservedObject var model: TabSidebarModel
    @ObservedObject var settings: TabSidebarSettings

    var body: some View {
        TabSidebarOptionsView(palette: model.palette, settings: settings)
            .padding(24) // room for the static shadow
            .fixedSize()
    }
}

// MARK: - Contents

struct TabSidebarOptionsView: View {
    let palette: TabSidebarPalette
    @ObservedObject var settings: TabSidebarSettings

    private var prefs: TabSidebarPrefs { settings.prefs }

    var body: some View {
        VStack(alignment: .leading, spacing: TabSidebarMetrics.optionsGap) {
            section("View as") {
                segmented([("Panes", nil), ("Tabs", nil)],
                          selected: prefs.viewAs == .panes ? 0 : 1) { settings.prefs.viewAs = $0 == 0 ? .panes : .tabs }
            }

            if prefs.viewAs == .tabs {
                section("Tab item") {
                    segmented([("Focused session", nil), ("Summary", nil)],
                              selected: prefs.tabItem == .focusedSession ? 0 : 1) {
                        settings.prefs.tabItem = $0 == 0 ? .focusedSession : .summary
                    }
                }
            }

            section("Density") {
                segmented([(nil, .list), (nil, .grid)], selected: prefs.density == .compact ? 0 : 1,
                          labels: ["Compact", "Relaxed"]) { settings.prefs.density = $0 == 0 ? .compact : .expanded }
            }

            section("Pane title as") {
                check("Command / Conversation", prefs.paneTitle == .command) { settings.prefs.paneTitle = .command }
                check("Working Directory", prefs.paneTitle == .directory) { settings.prefs.paneTitle = .directory }
                check("Branch", prefs.paneTitle == .branch) { settings.prefs.paneTitle = .branch }
            }

            section("Additional metadata") {
                // The one used as the title is not offered again.
                if prefs.paneTitle != .branch {
                    check("Branch", prefs.showBranch) { settings.prefs.showBranch.toggle() }
                }
                if prefs.paneTitle != .directory {
                    check("Working Directory", prefs.showDirectory) { settings.prefs.showDirectory.toggle() }
                }
            }

            Rectangle().fill(palette.popoverBorder.color).frame(height: 1)
                .padding(.horizontal, -TabSidebarMetrics.optionsPadding)
                .padding(.vertical, -4)

            check("Show details on hover", prefs.showDetailsOnHover) { settings.prefs.showDetailsOnHover.toggle() }
            check("Pane controls on single panes", prefs.paneControlsOnSinglePanes) { settings.prefs.paneControlsOnSinglePanes.toggle() }
        }
        .padding(TabSidebarMetrics.optionsPadding)
        .frame(width: TabSidebarMetrics.optionsWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.optionsRadius).fill(palette.popover.color))
        .overlay(RoundedRectangle(cornerRadius: TabSidebarMetrics.optionsRadius).strokeBorder(palette.popoverBorder.color, lineWidth: 1))
        .shadow(color: .black.opacity(palette.isDark ? 0.50 : 0.16), radius: 12, y: 8)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: TabSidebarMetrics.optionsLabelFont, weight: .semibold))
                .foregroundColor(palette.popoverText2.color)
                .frame(height: 14)
                .padding(.bottom, 6)
            content()
        }
    }

    private enum SegmentIcon { case list, grid }

    /// A segmented control: 24 pt tall, 2 pt padding and gap, radius 6 track, 4.5 pt segments.
    private func segmented(
        _ segments: [(String?, SegmentIcon?)], selected: Int, labels: [String] = [], select: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: TabSidebarMetrics.segmentedGap) {
            ForEach(segments.indices, id: \.self) { index in
                Segment(
                    palette: palette, title: segments[index].0, icon: segments[index].1.map { $0 == .list ? TabSidebarIcon.list : .grid },
                    label: labels.indices.contains(index) ? labels[index] : segments[index].0 ?? "",
                    isSelected: index == selected) { select(index) }
            }
        }
        .padding(TabSidebarMetrics.segmentedPadding)
        .frame(height: TabSidebarMetrics.segmentedHeight)
        .background(RoundedRectangle(cornerRadius: TabSidebarMetrics.segmentedRadius).fill(palette.segmentedTrack.color))
    }

    private func check(_ title: String, _ isOn: Bool, action: @escaping () -> Void) -> some View {
        CheckRow(palette: palette, title: title, isOn: isOn, action: action)
    }

    private struct Segment: View {
        let palette: TabSidebarPalette
        let title: String?
        let icon: TabSidebarIcon?
        let label: String
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Group {
                    if let icon {
                        TabSidebarIconView(icon: icon, size: 14, color: textColor)
                    } else if let title {
                        Text(title).font(.system(size: TabSidebarMetrics.segmentFont, weight: .medium)).foregroundColor(textColor)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: TabSidebarMetrics.segmentRadius)
                        .fill(isSelected ? palette.segmentedSelected.color : .clear)
                        .shadow(color: .black.opacity(isSelected ? (palette.isDark ? 0.40 : 0.12) : 0), radius: 1.5, y: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }

        private var textColor: Color {
            (isSelected || isHovering ? palette.popoverText : palette.popoverText2).color
        }
    }

    private struct CheckRow: View {
        let palette: TabSidebarPalette
        let title: String
        let isOn: Bool
        let action: () -> Void
        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: TabSidebarMetrics.checkRowGap) {
                    ZStack {
                        if isOn { TabSidebarIconView(icon: .check, size: 12, color: palette.accent.color, stroke: 2) }
                    }
                    .frame(width: 14)
                    Text(title)
                        .font(.system(size: TabSidebarMetrics.checkRowFont))
                        .foregroundColor(palette.popoverText.color)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, TabSidebarMetrics.checkRowPadding)
                .frame(height: TabSidebarMetrics.checkRowHeight)
                .background(
                    RoundedRectangle(cornerRadius: TabSidebarMetrics.checkRowRadius)
                        .fill(isHovering ? palette.popoverHover.color : .clear))
                .padding(.horizontal, -TabSidebarMetrics.checkRowPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(title)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}
