import AppKit
import SwiftUI

/// The sidebar's menus: native `NSMenu`s with the spec's items, order, disabled rules and
/// shortcuts (spec part 1, section 4). Share Session, Cloud Agent and Worktree Config are Warp
/// cloud features with no counterpart here, so they are not listed.
enum TabSidebarMenus {
    // MARK: Tab menu

    /// Right-click / "⋮" menu for a tab, and for one of its panes when `pane` is given.
    static func tabMenu(_ model: TabSidebarModel, tab id: Int, pane paneID: String? = nil) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let item = model.item(id) else { return menu }
        let isPinned = item.isPinned || (item.group?.isPinned ?? false)

        // A pane row adds the pane's own actions on top.
        if let paneID {
            let panes = model.paneCount(id)
            let isMax = model.isMaximized(id)
            let maximize = menu.add(isMax ? "Restore Pane" : "Maximize Pane") { model.toggleMaximize(tab: id, pane: paneID) }
            maximize.setKey("\r", [.command, .shift])
            maximize.isEnabled = panes > 1
            menu.add("Minimize Pane") { model.minimize(tab: id, pane: paneID) }.isEnabled = panes > 1 && !isMax

            let moveTo = NSMenu()
            moveTo.autoenablesItems = false
            moveTo.add("New Tab") { model.movePane(tab: id, pane: paneID, to: .newTab) }
            moveTo.add("New Window") { model.movePane(tab: id, pane: paneID, to: .newWindow) }
            let others = model.items.filter { $0.id != id }
            if !others.isEmpty { moveTo.addSeparator() }
            for other in others {
                moveTo.add(other.name(model.prefs)) { model.movePane(tab: id, pane: paneID, to: .tab(other.id)) }
            }
            if !model.groups.isEmpty { moveTo.addSeparator() }
            for group in model.groups {
                let entry = moveTo.add("New Tab in \(group.name)") { model.movePane(tab: id, pane: paneID, to: .group(group.id)) }
                entry.image = dotImage(color: model.palette.groupBase(group.color).nsColor)
            }
            let move = NSMenuItem(title: "Move Pane to…", action: nil, keyEquivalent: "")
            move.submenu = moveTo
            move.isEnabled = panes > 1
            menu.addItem(move)

            menu.addSeparator()
            menu.add("Split Right") { model.split(tab: id, pane: paneID, .right) }
            menu.add("Split Down") { model.split(tab: id, pane: paneID, .down) }

            menu.addSeparator()
            menu.add("Close Other Panes") { model.closeOtherPanes(tab: id, pane: paneID) }.isEnabled = panes > 1
            menu.add(panes > 1 ? "Close Pane" : "Close Tab") {
                if panes > 1 { model.close(id, pane: paneID) } else { model.close(id) }
            }
            menu.addSeparator()
        }

        menu.add(isPinned ? "Unpin Tab" : "Pin Tab") { model.togglePinned(id) }
        menu.add("New Group with Tab") { model.newGroup(with: id) }

        let moveTo = NSMenu()
        moveTo.autoenablesItems = false
        let otherGroups = model.groups.filter { $0.id != item.group?.id }
        for group in otherGroups {
            let entry = moveTo.add(group.name) { model.moveToGroup(id, group: group.id) }
            entry.image = dotImage(color: model.palette.groupBase(group.color).nsColor)
        }
        if !otherGroups.isEmpty { moveTo.addSeparator() }
        let remove = moveTo.add("Remove from Group") { model.removeFromGroup(id) }
        remove.isEnabled = item.group != nil
        menu.addSubmenu("Move to Group", moveTo)

        menu.addSeparator()
        menu.add("Copy Pane Title") { model.copyPaneTitle(id, pane: paneID) }
        menu.add("Copy Working Directory") { model.copyWorkingDirectory(id, pane: paneID) }

        menu.addSeparator()
        menu.add("Rename Tab") { model.beginRename(tab: id) }
        menu.add("Reset Tab Name") { model.resetName(id) }.isEnabled = item.hasCustomName

        menu.addSeparator()
        let down = menu.add("Move Tab Down") { model.move(.tab(id), down: true) }
        down.setKey(NSDownArrowFunctionKey, [.option])
        down.isEnabled = model.canMove(.tab(id), down: true)
        let up = menu.add("Move Tab Up") { model.move(.tab(id), down: false) }
        up.setKey(NSUpArrowFunctionKey, [.option])
        up.isEnabled = model.canMove(.tab(id), down: false)

        menu.addSeparator()
        let close = menu.add("Close Tab") { model.close(id) }
        close.setKey("w", [.command])
        let others = menu.add("Close Other Tabs") { model.closeOthers(than: id) }
        others.setKey("w", [.command, .option])
        others.isEnabled = model.canCloseOthers(id)
        let below = menu.add("Close Tabs Below") { model.closeBelow(id) }
        below.isEnabled = model.canCloseBelow(id)

        menu.addSeparator()
        menu.add("Save as New Config…") { model.saveAsConfig(id) }

        menu.addSeparator()
        menu.addSwatches(
            selected: item.group != nil && !item.isPinned ? item.group!.color : item.color,
            palette: model.palette
        ) { model.setTabColor(id, $0) }
        return menu
    }

    // MARK: "+" menu

    static func newMenu(_ model: TabSidebarModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.add("Agent") { model.newTab(command: "claude", directory: nil) }
        let terminal = menu.add("Terminal") { model.newTab() }
        terminal.setKey("t", [.command])

        let configs = TabConfigStore.load()
        if !configs.isEmpty {
            menu.addSeparator()
            for config in configs { menu.add(config.name) { model.open(config) } }
        }

        menu.addSeparator()
        menu.add("New Tab Config…") { model.editTabConfigs() }
        menu.add("New Tab Group") { model.newTabGroup() }

        menu.addSeparator()
        let reopen = menu.add("Reopen Closed Session") { model.reopenClosedTab() }
        reopen.setKey("t", [.command, .shift])
        reopen.isEnabled = model.canReopenClosedTab
        return menu
    }

    // MARK: Group menu

    static func groupMenu(_ model: TabSidebarModel, group id: String) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        guard let group = model.group(id) else { return menu }

        menu.add("Rename Group") { model.beginRename(group: id) }
        menu.add("New Tab in Group") { model.newTab(inGroup: id) }
        menu.add(group.isCollapsed ? "Expand Group" : "Collapse Group") { model.toggleCollapsed(id) }
        menu.add(group.isPinned ? "Unpin Group" : "Pin Group") { model.toggleGroupPinned(id) }

        menu.addSeparator()
        menu.add("Ungroup Tabs") { model.ungroup(id) }
        menu.add("Move Group Up") { model.move(.group(id), down: false) }.isEnabled = model.canMove(.group(id), down: false)
        menu.add("Move Group Down") { model.move(.group(id), down: true) }.isEnabled = model.canMove(.group(id), down: true)

        menu.addSeparator()
        menu.addSwatches(selected: group.color, palette: model.palette) { model.setGroupColor(id, $0) }

        menu.addSeparator()
        menu.add("Close Group") { model.confirmCloseGroup(id) }
        return menu
    }

    // MARK: Showing

    /// Shows a menu at the pointer, marking `owner` so its pill stays visible while it is open.
    static func popUp(_ menu: NSMenu, owner: String?, model: TabSidebarModel) {
        TabSidebarHoverCard.shared.hideNow()
        model.menuOpened(for: owner)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        model.menuOpened(for: nil)
    }

    /// Shows a menu under a button, marking `owner` while it is open.
    static func popUp(_ menu: NSMenu, owner: String?, model: TabSidebarModel, anchor: NSView) {
        TabSidebarHoverCard.shared.hideNow()
        model.menuOpened(for: owner)
        if let window = anchor.window {
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY - 4), in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        model.menuOpened(for: nil)
    }

    /// The top bar's split button: new panes next to the focused one.
    static func splitMenu(_ model: TabSidebarModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let controller = model.window?.windowController as? TerminalController
        menu.add("Split Right") { controller?.splitRight(menu) }
        menu.add("Split Down") { controller?.splitDown(menu) }
        menu.add("Split Left") { controller?.splitLeft(menu) }
        menu.add("Split Up") { controller?.splitUp(menu) }
        return menu
    }

    private static func dotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 8, height: 8)
        return NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

// MARK: - Menu helpers

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

private extension NSMenuItem {
    func setKey(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        keyEquivalent = key
        keyEquivalentModifierMask = modifiers
    }

    func setKey(_ function: Int, _ modifiers: NSEvent.ModifierFlags) {
        keyEquivalent = String(UnicodeScalar(UInt32(function))!)
        keyEquivalentModifierMask = modifiers
    }
}

private extension NSMenu {
    @discardableResult
    func add(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        addItem(item)
        return item
    }

    func addSeparator() { addItem(.separator()) }

    func addSubmenu(_ title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }

    /// The row of color circles: "None" first, then the six group colors.
    func addSwatches(selected: TabSidebarGroupColor, palette: TabSidebarPalette, onSelect: @escaping (TabSidebarGroupColor) -> Void) {
        let item = NSMenuItem()
        item.view = TabSidebarSwatchRow(selected: selected, palette: palette, onSelect: onSelect)
        addItem(item)
    }
}
