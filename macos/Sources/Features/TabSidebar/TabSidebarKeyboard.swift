import AppKit
import SwiftUI

// Keyboard (spec part 2B, section 3). The list is one focusable element with a focus cursor that is
// separate from the selection: arrows never switch tabs, Space does. A mouse click moves the
// cursor but hides the ring; the terminal keeps keyboard input until the sidebar is focused on
// purpose (from the search field, ⇧⌘A).

/// An invisible view that becomes first responder when the list is focused and receives its keys.
struct TabSidebarKeyCatcher: NSViewRepresentable {
    let model: TabSidebarModel

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.model = model
        model.registerKeyView(view)
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) { view.model = model }

    final class KeyView: NSView {
        weak var model: TabSidebarModel?

        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func becomeFirstResponder() -> Bool {
            model?.listFocusChanged(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            model?.listFocusChanged(false)
            return true
        }

        override func keyDown(with event: NSEvent) {
            if model?.handleKeyDown(event) != true { super.keyDown(with: event) }
        }
    }
}

extension TabSidebarModel {
    // MARK: Focus stops

    /// Every visible row and group header, in order. Tabs inside collapsed groups are skipped, and
    /// tab headers are not stops (their tab's row is).
    var focusStops: [TabSidebarFocusKey] {
        var stops: [TabSidebarFocusKey] = []
        func add(_ tab: TabSidebarTabBlock) {
            // A folded multi-pane tab shows only its header, which is not a stop.
            if collapsedTabs.contains(tab.tab.id), tab.headerText != nil { return }
            for row in tab.rows { stops.append(.row(tab: tab.tab.id, pane: row.paneID)) }
        }
        for (section, blocks) in [("pinned", list.pinned), ("open", list.main)] where !isSectionCollapsed(section) {
            for block in blocks {
                switch block {
                case .tab(let tab): add(tab)
                case .group(let group):
                    stops.append(.group(group.group.id))
                    if !group.group.isCollapsed { group.tabs.forEach(add) }
                }
            }
        }
        return stops
    }

    private func scrollTarget(for key: TabSidebarFocusKey) -> String {
        switch key {
        case .row(let tab, _): return "tab:\(tab)"
        case .group(let id): return "group:\(id)"
        }
    }

    func moveFocus(to key: TabSidebarFocusKey) {
        setFocus(key, ring: true)
        scrollRequest = scrollTarget(for: key)
    }

    func moveFocus(by delta: Int) {
        let stops = focusStops
        guard !stops.isEmpty else { return }
        guard let current = focusKey, let index = stops.firstIndex(of: current) else {
            moveFocus(to: stops[0])
            return
        }
        moveFocus(to: stops[min(max(index + delta, 0), stops.count - 1)])
    }

    /// Spec: "↓ in the field focuses the first result (ring on); ↩ does the same and selects it if it is a row."
    func leaveSearch(selectFirst: Bool) {
        guard let first = focusStops.first else { return }
        focusList()
        moveFocus(to: first)
        if selectFirst, case .row(let tab, let pane) = first {
            selectKeepingFocus(tab, pane: pane)
        }
    }

    func focusFirstStopIfNeeded(ring: Bool) {
        if focusKey == nil || !focusStops.contains(where: { $0 == focusKey }) {
            if let first = focusStops.first { setFocus(first, ring: ring) }
        } else {
            setFocus(focusKey, ring: ring)
        }
    }

    // MARK: Keys

    /// Returns true when the key was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        TabSidebarHoverCard.shared.hideNow()

        switch event.keyCode {
        case 126: // up
            if command { moveToEnd(first: true) } else if option { moveFocused(down: false) } else { moveFocus(by: -1) }
            return true
        case 125: // down
            if command { moveToEnd(first: false) } else if option { moveFocused(down: true) } else { moveFocus(by: 1) }
            return true
        case 115: moveToEnd(first: true); return true // home
        case 119: moveToEnd(first: false); return true // end

        case 49: // space
            activateFocused()
            return true

        case 36, 76: // return, enter
            if control { showContextMenuForFocused() } else { renameFocused() }
            return true
        case 120: // F2
            renameFocused()
            return true

        case 123: // left
            if option { leaveGroup() } else { collapseOrFocusHeader() }
            return true
        case 124: // right
            if option { joinGroupAbove() } else { expandOrFocusFirst() }
            return true

        case 51: // delete
            if command { closeFocused(); return true }
            return false

        case 53: // esc
            setFocus(focusKey, ring: false)
            focusTerminal()
            return true

        default:
            return typeToSearch(event, flags: flags)
        }
    }

    // MARK: Actions

    private func moveToEnd(first: Bool) {
        let stops = focusStops
        if let key = first ? stops.first : stops.last { moveFocus(to: key) }
    }

    private func activateFocused() {
        switch focusKey {
        case .row(let tab, let pane)?: selectKeepingFocus(tab, pane: pane)
        case .group(let id)?: toggleCollapsed(id)
        case nil: break
        }
        setFocus(focusKey, ring: true)
    }

    private func renameFocused() {
        switch focusKey {
        case .row(let tab, _)?: beginRename(tab: tab)
        case .group(let id)?: beginRename(group: id)
        case nil: break
        }
    }

    private func showContextMenuForFocused() {
        guard let key = focusKey, let window else { return }
        let menu: NSMenu
        let anchor: NSView?
        switch key {
        case .row(let tab, let pane):
            menu = TabSidebarMenus.tabMenu(self, tab: tab, pane: prefs.viewAs == .panes ? pane : nil)
            anchor = geometry.view(.tabBlock(tab))
        case .group(let id):
            menu = TabSidebarMenus.groupMenu(self, group: id)
            anchor = geometry.view(.groupHeader(id))
        }
        menuOpened(for: key.stringKey)
        if let anchor {
            let rect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX + 24, y: rect.minY), in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        menuOpened(for: nil)
    }

    /// ←: a header collapses; a row in a group moves the cursor to its header.
    private func collapseOrFocusHeader() {
        switch focusKey {
        case .group(let id)?:
            if group(id)?.isCollapsed == false { setCollapsed(true, group: id) }
        case .row(let tab, _)?:
            if let group = item(tab)?.group, item(tab)?.isPinned == false { moveFocus(to: .group(group.id)) }
        case nil: break
        }
    }

    /// →: a collapsed header expands; an expanded one moves the cursor to its first row.
    private func expandOrFocusFirst() {
        guard case .group(let id)? = focusKey else { return }
        if group(id)?.isCollapsed == true {
            setCollapsed(false, group: id)
        } else if let first = focusStops.drop(while: { $0 != .group(id) }).dropFirst().first, first != .group(id) {
            moveFocus(to: first)
        }
    }

    private func moveFocused(down: Bool) {
        switch focusKey {
        case .row(let tab, _)?: move(.tab(tab), down: down)
        case .group(let id)?: move(.group(id), down: down)
        case nil: break
        }
        setFocus(focusKey, ring: true)
    }

    private func leaveGroup() {
        if case .row(let tab, _)? = focusKey { moveOutOfGroup(tab) }
    }

    private func joinGroupAbove() {
        if case .row(let tab, _)? = focusKey { moveIntoPreviousGroup(tab) }
    }

    /// ⌘⌫: close the focused tab; the cursor goes to the next stop, else the previous.
    private func closeFocused() {
        guard case .row(let tab, _)? = focusKey else { return }
        let stops = focusStops
        let others = stops.filter { if case .row(let t, _) = $0 { return t != tab } else { return true } }
        let index = stops.firstIndex(of: focusKey!) ?? 0
        let next = stops.dropFirst(index + 1).first(where: { others.contains($0) })
            ?? stops.prefix(index).last(where: { others.contains($0) })
        close(tab)
        if let next { setFocus(next, ring: true) }
    }

    /// A printable key with no ⌘ ⌃ ⌥ focuses the search field and types the character.
    private func typeToSearch(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.isDisjoint(with: [.command, .control, .option]),
              let characters = event.characters, let scalar = characters.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value < 0xF700, scalar.value != 0x7F else { return false }
        query += characters
        requestSearchFocus()
        return true
    }
}
