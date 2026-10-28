import AppKit

/// Menu items and actions for the sidebar, added to the View menu at launch.
final class TabSidebarMenu: NSObject {
    static let shared = TabSidebarMenu()

    func install() {
        guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu else { return }
        guard !menu.items.contains(where: { $0.action == #selector(toggleSidebar(_:)) }) else { return }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Toggle Tab Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "\\")
        toggle.keyEquivalentModifierMask = [.command]
        toggle.target = self
        menu.addItem(toggle)

        let search = NSMenuItem(title: "Search Tabs", action: #selector(searchTabs(_:)), keyEquivalent: "a")
        search.keyEquivalentModifierMask = [.command, .shift]
        search.target = self
        menu.addItem(search)

        let reopen = NSMenuItem(title: "Reopen Closed Tab", action: #selector(reopenClosedTab(_:)), keyEquivalent: "t")
        reopen.keyEquivalentModifierMask = [.command, .shift]
        reopen.target = self
        menu.addItem(reopen)
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        // Closing a tab registers an undo on its window, so "reopen" is just undo.
        (NSApp.keyWindow?.windowController as? TerminalController)?.undoManager?.undo()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        let settings = TabSidebarSettings.shared
        settings.isVisible.toggle()
        for case let window as TerminalWindow in NSApp.windows {
            window.syncNativeTabBarWithSidebar()
        }

        guard !settings.isVisible else { return }

        // Give focus back to the terminal so typing keeps working.
        if let surface = (NSApp.keyWindow?.windowController as? TerminalController)?.focusedSurface {
            Ghostty.moveFocus(to: surface)
        }
    }

    @objc func searchTabs(_ sender: Any?) {
        let settings = TabSidebarSettings.shared
        if !settings.isVisible { settings.isVisible = true }
        // The sidebar may have just been created, so focus on the next turn.
        DispatchQueue.main.async {
            let container = NSApp.keyWindow?.contentView as? TerminalViewContainer
            container?.sidebarModel?.requestSearchFocus()
        }
    }
}
