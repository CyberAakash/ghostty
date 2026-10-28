import AppKit
import Combine
import SwiftUI

/// Use this container to achieve a glass effect at the window level.
/// Modifying `NSThemeFrame` can sometimes be unpredictable.
class TerminalViewContainer: NSView {
    private let terminalView: NSView
    private let clearTerminalSafeArea: () -> Void

    /// Background color applied with glass effect
    private(set) var glassEffectView: NSView?
    private var derivedConfig: DerivedConfig?

    // MARK: Tab sidebar (fork)

    /// The sidebar's model while the sidebar is shown, nil otherwise. Hiding the sidebar tears
    /// the whole view down so it costs nothing.
    private(set) var sidebarModel: TabSidebarModel?
    private var sidebarHost: NSView?
    private var sidebarHandle: NSView?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var terminalLeadingConstraint: NSLayoutConstraint?
    private var sidebarCancellables: Set<AnyCancellable> = []
    private var edgeStrip: NSView?
    private var overlayView: NSView?
    private var overlayModel: TabSidebarModel?
    private var overlayLeading: NSLayoutConstraint?
    private var overlayHideWork: DispatchWorkItem?
    private var overlayShowWork: DispatchWorkItem?
    private var overlayEscMonitor: Any?
    private(set) var topBar: TabSidebarTopBar?
    private var zoomBanner: NSView?
    private var zoomCancellable: AnyCancellable?
    private var terminalTopConstraint: NSLayoutConstraint?
    /// Backs the top bar's options panel and menus while the sidebar itself is hidden.
    private var chromeModel: TabSidebarModel?
    private var sidebarBackground = NSColor.windowBackgroundColor

    var windowThemeFrameView: NSView? {
        window?.contentView?.superview
    }

    var windowCornerRadius: CGFloat? {
        guard let window, window.responds(to: Selector(("_cornerRadius"))) else {
            return nil
        }

        return window.value(forKey: "_cornerRadius") as? CGFloat
    }

    init<Root: View>(@ViewBuilder rootView: () -> Root) {
        let host = NSHostingView(rootView: rootView())
        self.terminalView = host
        self.clearTerminalSafeArea = {
            // The custom top bar is laid out above the terminal, so the title bar inset must not count twice.
            if #available(macOS 13.3, *) { host.safeAreaRegions = [] }
        }
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The initial content size to use as a fallback before the SwiftUI
    /// view hierarchy has completed layout (i.e. before @FocusedValue
    /// propagates `lastFocusedSurface`). Once the hosting view reports
    /// a valid intrinsic size, this fallback is no longer used.
    var initialContentSize: NSSize?

    override var intrinsicContentSize: NSSize {
        let hostingSize = terminalView.intrinsicContentSize
        // The hosting view returns a valid size once SwiftUI has laid out
        // with the correct idealWidth/idealHeight. Before that (when
        // @FocusedValue hasn't propagated), it returns a tiny default.
        // Fall back to initialContentSize in that case.
        if let initialContentSize,
           hostingSize.width < initialContentSize.width || hostingSize.height < initialContentSize.height {
            return initialContentSize
        }
        return hostingSize
    }

    private func setup() {
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        let leading = terminalView.leadingAnchor.constraint(equalTo: leadingAnchor)
        terminalLeadingConstraint = leading
        let top = terminalView.topAnchor.constraint(equalTo: topAnchor)
        terminalTopConstraint = top
        NSLayoutConstraint.activate([
            top,
            leading,
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGlassEffectIfNeeded()
        updateGlassEffectTopInsetIfNeeded()
        installTopBarIfNeeded()
        observeSidebarSettings()
    }

    override func layout() {
        super.layout()
        updateGlassEffectTopInsetIfNeeded()
    }

    func ghosttyConfigDidChange(_ config: Ghostty.Config, preferredBackgroundColor: NSColor?) {
        let terminalColor = preferredBackgroundColor ?? NSColor(config.backgroundColor)
        sidebarBackground = terminalColor
        sidebarModel?.setTerminalBackground(terminalColor)
        topBar?.setBackground(terminalColor)

        let newValue = DerivedConfig(config: config, preferredBackgroundColor: preferredBackgroundColor, cornerRadius: windowCornerRadius)
        guard newValue != derivedConfig else { return }
        derivedConfig = newValue

        // Attach the glass effect synchronously if missing to prevent flicker when a new tab appears.
        // Existing updates remain deferred, as they can occur during SwiftUI rendering.
        if glassEffectView == nil {
            updateGlassEffectIfNeeded()
        } else {
            DispatchQueue.main.async(execute: updateGlassEffectIfNeeded)
        }
    }
}

// MARK: - Tab sidebar

extension TerminalViewContainer {
    fileprivate func observeSidebarSettings() {
        sidebarCancellables.removeAll()
        guard window != nil else {
            removeSidebar()
            return
        }

        let settings = TabSidebarSettings.shared
        settings.$isVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                if visible {
                    self?.leaveHiddenMode()
                    self?.installSidebar()
                } else {
                    self?.removeSidebar()
                    self?.enterHiddenMode()
                }
            }
            .store(in: &sidebarCancellables)

        settings.$width
            .removeDuplicates()
            .sink { [weak self] width in
                guard let self, self.sidebarHost != nil else { return }
                self.sidebarWidthConstraint?.constant = width
                self.terminalLeadingConstraint?.constant = width
            }
            .store(in: &sidebarCancellables)
    }

    fileprivate func installSidebar() {
        guard sidebarHost == nil, let window else { return }

        let model = TabSidebarModel(window: window)
        model.setTerminalBackground(sidebarBackground)
        let host = TabSidebarHostView(model: model)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)

        let width = TabSidebarSettings.shared.width
        let widthConstraint = host.widthAnchor.constraint(equalToConstant: width)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: contentTopAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
        ])

        let handle = TabSidebarResizeHandle()
        handle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(handle)
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: contentTopAnchor),
            handle.bottomAnchor.constraint(equalTo: bottomAnchor),
            handle.widthAnchor.constraint(equalToConstant: 6),
            handle.centerXAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        terminalLeadingConstraint?.constant = width
        sidebarModel = model
        sidebarHost = host
        sidebarHandle = handle
        sidebarWidthConstraint = widthConstraint
    }

    // MARK: Custom top bar

    var contentTopAnchor: NSLayoutYAxisAnchor { topBar?.bottomAnchor ?? topAnchor }

    fileprivate func installTopBarIfNeeded() {
        guard topBar == nil, let window = window as? TerminalWindow, window.supportsSidebarChrome else { return }

        let bar = TabSidebarTopBar(background: sidebarBackground)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: TabSidebarTopBar.height),
        ])
        terminalTopConstraint?.isActive = false
        terminalTopConstraint = terminalView.topAnchor.constraint(equalTo: bar.bottomAnchor)
        terminalTopConstraint?.isActive = true
        clearTerminalSafeArea()
        topBar = bar
        observeZoom()

        bar.onToggleSidebar = { TabSidebarMenu.shared.toggleSidebar(nil) }
        bar.onSplitMenu = { [weak self] anchor in
            guard let self, let model = self.currentChromeModel() else { return }
            TabSidebarMenus.popUp(TabSidebarMenus.splitMenu(model), owner: "split", model: model, anchor: anchor)
        }
    }

    /// Shows the "Maximized" banner while a pane hides the others.
    private func observeZoom() {
        guard let controller = window?.windowController as? BaseTerminalController else { return }
        zoomCancellable = controller.$surfaceTree
            .map { (zoomed: $0.zoomed != nil, others: max(0, $0.count - 1)) }
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak controller] state in
                guard let self else { return }
                self.zoomBanner?.removeFromSuperview()
                self.zoomBanner = nil
                guard state.zoomed, let controller else { return }
                let palette = TabSidebarPalette(terminal: TabSidebarRGB(self.sidebarBackground))
                let banner = NSHostingView(rootView: TabSidebarZoomBanner(palette: palette, hiddenCount: state.others) {
                    controller.splitZoom(controller)
                })
                banner.translatesAutoresizingMaskIntoConstraints = false
                if #available(macOS 13.3, *) { banner.safeAreaRegions = [] }
                self.addSubview(banner, positioned: .above, relativeTo: self.terminalView)
                NSLayoutConstraint.activate([
                    banner.topAnchor.constraint(equalTo: self.contentTopAnchor),
                    banner.leadingAnchor.constraint(equalTo: self.terminalView.leadingAnchor),
                    banner.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                    banner.heightAnchor.constraint(equalToConstant: 24),
                ])
                self.zoomBanner = banner
            }
    }

    func currentChromeModel() -> TabSidebarModel? {
        if let sidebarModel { return sidebarModel }
        if let overlayModel { return overlayModel }
        guard let window else { return nil }
        if chromeModel == nil {
            let model = TabSidebarModel(window: window)
            model.setTerminalBackground(sidebarBackground)
            chromeModel = model
        }
        return chromeModel
    }

    // MARK: Hidden mode: edge reveal

    /// While the sidebar is hidden: a toggle in the title bar, and a 6 pt strip on the left edge that
    /// slides the sidebar in over the terminal (it does not push the terminal) after 120 ms.
    fileprivate func enterHiddenMode() {
        guard edgeStrip == nil else { return }

        let strip = TabSidebarEdgeStrip()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.onEnter = { [weak self] in self?.scheduleOverlay(show: true, after: 0.12) }
        strip.onExit = { [weak self] in self?.scheduleOverlay(show: false, after: 0.30) }
        addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: contentTopAnchor),
            strip.bottomAnchor.constraint(equalTo: bottomAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.widthAnchor.constraint(equalToConstant: TabSidebarMetrics.edgeStripWidth),
        ])
        edgeStrip = strip

    }

    fileprivate func leaveHiddenMode() {
        hideOverlay(animated: false)
        edgeStrip?.removeFromSuperview()
        edgeStrip = nil
    }

    private func scheduleOverlay(show: Bool, after delay: TimeInterval) {
        overlayShowWork?.cancel()
        overlayHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if show { self.showOverlay() } else { self.hideOverlayIfIdle() }
        }
        if show { overlayShowWork = work } else { overlayHideWork = work }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func showOverlay() {
        guard overlayView == nil, !TabSidebarSettings.shared.isVisible, let window else { return }
        let width = TabSidebarSettings.shared.width

        let model = TabSidebarModel(window: window)
        model.setTerminalBackground(sidebarBackground)
        let host = TabSidebarHostView(model: model)
        host.translatesAutoresizingMaskIntoConstraints = false

        let holder = TabSidebarOverlayHolder()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.wantsLayer = true
        holder.layer?.shadowColor = NSColor.black.cgColor
        holder.layer?.shadowOpacity = 0.35
        holder.layer?.shadowRadius = 14
        holder.layer?.masksToBounds = false
        holder.onEnter = { [weak self] in
            self?.overlayHideWork?.cancel()
        }
        holder.onExit = { [weak self] in self?.scheduleOverlay(show: false, after: 0.30) }
        holder.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: holder.topAnchor),
            host.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
        ])
        addSubview(holder, positioned: .above, relativeTo: nil)
        let leading = holder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TabSidebarMotion.reduced ? 0 : -width)
        NSLayoutConstraint.activate([
            holder.topAnchor.constraint(equalTo: contentTopAnchor),
            holder.bottomAnchor.constraint(equalTo: bottomAnchor),
            holder.widthAnchor.constraint(equalToConstant: width),
            leading,
        ])
        overlayView = holder
        overlayModel = model
        overlayLeading = leading
        layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = TabSidebarMotion.reduced ? 0 : 0.18
            context.allowsImplicitAnimation = true
            leading.animator().constant = 0
            layoutSubtreeIfNeeded()
        }

        overlayEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.overlayModel?.isOptionsOpen != true,
                  self?.overlayModel?.drag == nil, self?.overlayModel?.editing == nil else { return event }
            self?.hideOverlay(animated: true)
            return nil
        }
    }

    /// The overlay stays while a menu, the options panel, a drag or a rename is using it.
    private func hideOverlayIfIdle() {
        guard let model = overlayModel else { return }
        if model.menuOwner != nil || model.isOptionsOpen || model.drag != nil || model.editing != nil || model.isListFocused {
            scheduleOverlay(show: false, after: 0.30)
            return
        }
        hideOverlay(animated: true)
    }

    fileprivate func hideOverlay(animated: Bool) {
        overlayShowWork?.cancel()
        overlayHideWork?.cancel()
        if let monitor = overlayEscMonitor { NSEvent.removeMonitor(monitor) }
        overlayEscMonitor = nil
        guard let view = overlayView, let leading = overlayLeading else { return }
        overlayView = nil
        overlayModel = nil
        overlayLeading = nil
        let width = view.bounds.width
        if animated && !TabSidebarMotion.reduced {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                leading.animator().constant = -width
                layoutSubtreeIfNeeded()
            }, completionHandler: { view.removeFromSuperview() })
        } else {
            view.removeFromSuperview()
        }
    }

    fileprivate func removeSidebar() {
        sidebarHost?.removeFromSuperview()
        sidebarHandle?.removeFromSuperview()
        sidebarHost = nil
        sidebarHandle = nil
        sidebarWidthConstraint = nil
        sidebarModel = nil
        terminalLeadingConstraint?.constant = 0
    }
}

/// A thin strip on the sidebar's trailing edge that resizes it by dragging.
private final class TabSidebarResizeHandle: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let superview else { return }
        let x = superview.convert(event.locationInWindow, from: nil).x
        TabSidebarSettings.shared.width = TabSidebarSettings.clamp(x)
    }

    override func mouseUp(with event: NSEvent) {
        TabSidebarSettings.shared.persistWidth()
    }
}

// MARK: - BaseTerminalController + terminalViewContainer

extension BaseTerminalController {
    var terminalViewContainer: TerminalViewContainer? {
        window?.contentView as? TerminalViewContainer
    }
}

// MARK: Glass

/// An `NSView` that contains a liquid glass background effect and
/// an inactive-window tint overlay.
#if compiler(>=6.2)
@available(macOS 26.0, *)
private class TerminalGlassView: NSView, ObservableObject {
    /// We use this to apply glass effect to background colors
    ///
    struct GlassBackground: View {
        @ObservedObject var model: GlassViewModel

        var body: some View {
            model.color
                .glassEffect(
                    model.glass,
                    in: RoundedRectangle(cornerRadius: model.cornerRadius)
                )
        }
    }

    class GlassViewModel: ObservableObject {
        @Published var backgroundColor: Color = .clear
        @Published var backgroundOpacity: Double = 0
        @Published var cornerRadius: CGFloat = 0
        @Published var glass: Glass = .identity

        /// backgroundColor applied with backgroundOpacity
        var color: Color {
            backgroundColor.opacity(backgroundOpacity)
        }
    }

    private let glassEffectView: NSView
    private var topConstraint: NSLayoutConstraint!
    private let glassViewModel: GlassViewModel

    init(topOffset: CGFloat) {
        let viewModel = GlassViewModel()
        self.glassEffectView = NSHostingView(rootView: GlassBackground(model: viewModel))
        self.glassViewModel = viewModel
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false

        // Glass effect view fills this view.
        glassEffectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassEffectView)
        topConstraint = glassEffectView.topAnchor.constraint(
            equalTo: topAnchor,
            constant: topOffset
        )
        NSLayoutConstraint.activate([
            topConstraint,
            glassEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            glassEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Configures the glass, tint color, corner radius.
    func configure(
        glass: Glass,
        backgroundColor: NSColor,
        backgroundOpacity: Double,
        cornerRadius: CGFloat?,
    ) {
        glassViewModel.backgroundColor = Color(backgroundColor)
        glassViewModel.backgroundOpacity = backgroundOpacity
        glassViewModel.cornerRadius = cornerRadius ?? 0
        glassViewModel.glass = glass
    }

    /// Updates the top inset offset for both the glass effect and tint overlay.
    /// Call this when the safe area insets change (e.g., during layout).
    func updateTopInset(_ offset: CGFloat) {
        topConstraint.constant = offset
    }
}
#endif // compiler(>=6.2)

extension TerminalViewContainer {
#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func addGlassEffectViewIfNeeded() -> TerminalGlassView? {
        if let existed = glassEffectView as? TerminalGlassView {
            updateGlassEffectTopInsetIfNeeded()
            return existed
        }
        guard let themeFrameView = windowThemeFrameView else {
            return nil
        }
        let effectView = TerminalGlassView(topOffset: -themeFrameView.safeAreaInsets.top)
        addSubview(effectView, positioned: .below, relativeTo: terminalView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        glassEffectView = effectView
        return effectView
    }
#endif // compiler(>=6.2)

    private func updateGlassEffectIfNeeded() {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), let derivedConfig else {
            glassEffectView?.removeFromSuperview()
            glassEffectView = nil
            return
        }
        guard let effectView = addGlassEffectViewIfNeeded() else {
            return
        }

        effectView.configure(
            glass: derivedConfig.glass.official,
            backgroundColor: derivedConfig.backgroundColor,
            backgroundOpacity: derivedConfig.backgroundOpacity,
            cornerRadius: derivedConfig.cornerRadius,
        )
#endif // compiler(>=6.2)
    }

    private func updateGlassEffectTopInsetIfNeeded() {
#if compiler(>=6.2)
        guard
            #available(macOS 26.0, *),
            let effectView = glassEffectView as? TerminalGlassView,
            let themeFrameView = windowThemeFrameView
        else {
            return
        }
        effectView.updateTopInset(-themeFrameView.safeAreaInsets.top)
#endif // compiler(>=6.2)
    }

    struct DerivedConfig: Equatable {
        let glass: BackportGlass
        let backgroundColor: NSColor
        let backgroundOpacity: Double
        let cornerRadius: CGFloat?

        init?(config: Ghostty.Config, preferredBackgroundColor: NSColor?, cornerRadius: CGFloat?) {
            switch config.backgroundBlur {
            case .macosGlassRegular:
                glass = .regular
            case .macosGlassClear:
                glass = .clear
            default:
                return nil
            }
            self.backgroundColor = preferredBackgroundColor ?? NSColor(config.backgroundColor)
            self.backgroundOpacity = config.backgroundOpacity
            self.cornerRadius = cornerRadius
        }
    }
}
