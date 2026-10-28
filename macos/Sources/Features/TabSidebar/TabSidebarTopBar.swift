import AppKit
import Combine
import SwiftUI

// The custom top bar that replaces the macOS title bar (design: Part C). It is as tall as the unified
// compact title bar so the traffic lights sit centered in it, and it is a window drag area. The
// buttons and the title are the only things on it.

final class TabSidebarTopBar: NSView {
    static let height: CGFloat = 38

    private let leftHost: NSHostingView<TabSidebarTopBarLeft>
    private let rightHost: NSHostingView<TabSidebarTopBarRight>
    private let titleField = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private var leftLeading: NSLayoutConstraint?
    private var palette: TabSidebarPalette
    private var observers: [Any] = []
    private var titleObservation: NSKeyValueObservation?

    /// Called by the bar's buttons; the container owns what they do.
    var onToggleSidebar: () -> Void = {}
    var onSplitMenu: (NSView) -> Void = { _ in }

    init(background: NSColor) {
        palette = TabSidebarPalette(terminal: TabSidebarRGB(background))
        leftHost = NSHostingView(rootView: TabSidebarTopBarLeft(palette: palette, toggle: {}))
        rightHost = NSHostingView(rootView: TabSidebarTopBarRight(palette: palette, split: { _ in }))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = background.cgColor

        for host in [leftHost, rightHost] as [NSView] {
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
        }
        // The bar sits in the title bar's area; its buttons must not be pushed down by that inset.
        leftHost.sizingOptions = [.intrinsicContentSize]
        rightHost.sizingOptions = [.intrinsicContentSize]
        if #available(macOS 13.3, *) {
            leftHost.safeAreaRegions = []
            rightHost.safeAreaRegions = []
        }

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isSelectable = false
        addSubview(titleField)

        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        addSubview(hairline)

        let leading = leftHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TabSidebarMetrics.topBarToggleX)
        leftLeading = leading
        NSLayoutConstraint.activate([
            leading,
            leftHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightHost.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 114),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -114),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: TabSidebarMetrics.hairline),
        ])
        applyPalette()
        rebuildButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Appearance

    func setBackground(_ color: NSColor) {
        palette = TabSidebarPalette(terminal: TabSidebarRGB(color))
        layer?.backgroundColor = color.cgColor
        applyPalette()
        rebuildButtons()
    }

    private func applyPalette() {
        hairline.layer?.backgroundColor = palette.hairline.nsColor.cgColor
        refreshTitle()
    }

    private func rebuildButtons() {
        leftHost.rootView = TabSidebarTopBarLeft(palette: palette, toggle: { [weak self] in self?.onToggleSidebar() })
        rightHost.rootView = TabSidebarTopBarRight(
            palette: palette,
            split: { [weak self] in self?.onSplitMenu($0) })
    }

    // MARK: Window state

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        titleObservation = nil
        guard let window else { return }

        titleObservation = window.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshTitle() }
        }
        let center = NotificationCenter.default
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                     NSWindow.didEnterFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateTogglePosition()
            })
        }
        // The working directory changes without the title changing.
        observers.append(center.addObserver(forName: .tabSidebarNeedsRefresh, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTitle()
        })
        updateTogglePosition()
        refreshTitle()
    }

    /// Native traffic lights take x 14..70; in full screen they are gone and the toggle moves to x = 14.
    private func updateTogglePosition() {
        let fullScreen = window?.styleMask.contains(.fullScreen) ?? false
        leftLeading?.constant = fullScreen ? TabSidebarMetrics.topBarPadding : TabSidebarMetrics.topBarToggleX
    }

    private func refreshTitle() {
        guard let window else { return }
        let controller = window.windowController as? TerminalController
        let title = window.title.isEmpty ? "Ghostty" : window.title
        var directory = controller?.focusedSurface?.pwd ?? ""
        if !directory.isEmpty {
            directory = (directory as NSString).abbreviatingWithTildeInPath
        }

        let text = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.text2.nsColor])
        if !directory.isEmpty, directory != title {
            text.append(NSAttributedString(
                string: "  ·  \(directory)",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.text3.nsColor]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        titleField.attributedStringValue = text
    }

    // MARK: Window dragging

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Contents

struct TabSidebarTopBarLeft: View {
    let palette: TabSidebarPalette
    let toggle: () -> Void
    @ObservedObject private var settings = TabSidebarSettings.shared

    var body: some View {
        TabSidebarToolbarButton(
            palette: palette, icon: .sidebarToggle,
            help: settings.isVisible ? "Hide Tab Sidebar (⌘\\)" : "Show Tab Sidebar (⌘\\)",
            label: settings.isVisible ? "Hide tab sidebar" : "Show tab sidebar",
            isOn: settings.isVisible, size: TabSidebarMetrics.topBarButton, iconSize: 16, action: toggle)
            .padding(.vertical, 4)
    }
}

struct TabSidebarTopBarRight: View {
    let palette: TabSidebarPalette
    let split: (NSView) -> Void

    var body: some View {
        HStack(spacing: 4) {
            TabSidebarAnchoredButton(palette: palette, icon: .newGroup, help: "Split", label: "Split menu", action: split)
        }
        .padding(.trailing, TabSidebarMetrics.topBarPadding - 4)
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }
}

/// A toolbar button that hands its own NSView to the action, so menus and panels can anchor to it.
struct TabSidebarAnchoredButton: View {
    let palette: TabSidebarPalette
    let icon: TabSidebarIcon
    let help: String
    let label: String
    let action: (NSView) -> Void
    var rightAction: ((NSView) -> Void)?
    var size: CGFloat = TabSidebarMetrics.topBarButton
    @State private var anchor = AnchorBox()

    var body: some View {
        TabSidebarToolbarButton(
            palette: palette, icon: icon, help: help, label: label, isOn: false,
            size: size, iconSize: 14) {
            if let view = anchor.view { action(view) }
        }
        .background(AnchorView(box: anchor))
        .overlay(RightClickCatcher { if let view = anchor.view { rightAction?(view) } }.allowsHitTesting(rightAction != nil))
    }
}

/// Reports right clicks (and control-clicks) on the view it overlays, and lets everything else through.
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: () -> Void = {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isRight = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isRight ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }
    }
}

final class AnchorBox { weak var view: NSView? }

struct AnchorView: NSViewRepresentable {
    let box: AnchorBox
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}
