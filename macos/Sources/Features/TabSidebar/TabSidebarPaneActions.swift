import AppKit

// What the row menu does to a pane: maximize, minimize, split, move, close the others. The sidebar
// reads and edits the same split tree as the terminal, so these are ordinary tree operations.

extension TabSidebarModel {
    enum PaneDestination {
        case newTab
        case newWindow
        case tab(Int)
        case group(String)
    }

    private func paneContext(_ id: Int, _ paneID: String?) -> (controller: TerminalController, surface: Ghostty.SurfaceView)? {
        guard let controller = controller(for: id) else { return nil }
        let surface = controller.surfaceTree.first { $0.id.uuidString == paneID } ?? controller.focusedSurface
            ?? controller.surfaceTree.first { _ in true }
        guard let surface else { return nil }
        return (controller, surface)
    }

    func paneCount(_ id: Int) -> Int { controller(for: id)?.surfaceTree.count ?? 1 }

    func isMaximized(_ id: Int) -> Bool { controller(for: id)?.surfaceTree.zoomed != nil }

    /// Maximize hides every other pane of the tab; doing it again restores them.
    func toggleMaximize(tab id: Int, pane paneID: String?) {
        guard let (controller, surface) = paneContext(id, paneID), controller.surfaceTree.isSplit else { return }
        select(id, pane: paneID)
        guard let node = controller.surfaceTree.root?.node(view: surface) else { return }
        if controller.surfaceTree.zoomed != nil {
            controller.surfaceTree = SplitTree(root: controller.surfaceTree.root, zoomed: nil)
        } else {
            controller.surfaceTree = SplitTree(root: controller.surfaceTree.root, zoomed: node)
        }
        DispatchQueue.main.async { Ghostty.moveFocus(to: surface) }
    }

    /// Minimize puts another pane in front: this pane is hidden until the tab is restored.
    func minimize(tab id: Int, pane paneID: String?) {
        guard let (controller, surface) = paneContext(id, paneID), controller.surfaceTree.isSplit,
              let node = controller.surfaceTree.root?.node(view: surface),
              let other = controller.surfaceTree.focusTarget(for: .next, from: node),
              let otherNode = controller.surfaceTree.root?.node(view: other) else { return }
        select(id)
        controller.surfaceTree = SplitTree(root: controller.surfaceTree.root, zoomed: otherNode)
        DispatchQueue.main.async { Ghostty.moveFocus(to: other) }
    }

    func split(tab id: Int, pane paneID: String?, _ direction: SplitTree<Ghostty.SurfaceView>.NewDirection) {
        guard let (controller, surface) = paneContext(id, paneID) else { return }
        select(id, pane: paneID)
        controller.focusedSurface = surface
        switch direction {
        case .right: controller.splitRight(self)
        case .left: controller.splitLeft(self)
        case .down: controller.splitDown(self)
        case .up: controller.splitUp(self)
        }
    }

    func closeOtherPanes(tab id: Int, pane paneID: String?) {
        guard let (controller, surface) = paneContext(id, paneID), controller.surfaceTree.isSplit,
              let node = controller.surfaceTree.root?.node(view: surface) else { return }
        select(id)
        controller.replaceSurfaceTree(
            SplitTree(root: node, zoomed: nil), moveFocusTo: surface, undoAction: "Close Other Panes")
    }

    /// Moves a pane to a new tab, a new window, another tab (as a split) or a group (as a new tab in it).
    func movePane(tab id: Int, pane paneID: String?, to destination: PaneDestination) {
        guard let (source, surface) = paneContext(id, paneID), source.surfaceTree.isSplit,
              let node = source.surfaceTree.root?.node(view: surface), let ghostty else { return }

        func detach() {
            let next = source.surfaceTree.focusTarget(for: .next, from: node)
                ?? source.surfaceTree.focusTarget(for: .previous, from: node)
            source.replaceSurfaceTree(source.surfaceTree.removing(node), moveFocusTo: next, undoAction: "Move Pane")
        }

        switch destination {
        case .newWindow:
            detach()
            _ = TerminalController.newWindow(ghostty, tree: SplitTree(view: surface))

        case .newTab, .group:
            detach()
            let created = TerminalController.newWindow(ghostty, tree: SplitTree(view: surface))
            if let parent = source.window, let child = created.window {
                parent.addTabbedWindow(child, ordered: .above)
                child.makeKeyAndOrderFront(nil)
            }
            if case .group(let groupID) = destination, let newID = created.window?.windowNumber {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.requestRefresh(immediately: true)
                    DispatchQueue.main.async { self.moveToGroup(newID, group: groupID) }
                }
            }

        case .tab(let targetID):
            guard let target = controller(for: targetID), target !== source,
                  let anchor = target.focusedSurface ?? target.surfaceTree.first(where: { _ in true }),
                  let moved = try? target.surfaceTree.inserting(view: surface, at: anchor, direction: .right) else { return }
            detach()
            target.replaceSurfaceTree(moved, moveFocusTo: surface, undoAction: "Move Pane")
            select(targetID)
        }
    }
}
