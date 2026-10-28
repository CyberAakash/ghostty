import Foundation

// Pure operations on the ordered list of tabs. `items` is the real tab order; each item carries
// its pinned flag and group. Every function returns a new list, and the model writes the result
// back to the windows. The rules are the design spec's: part 2A section 5 (groups and tabs) and
// part 2B section 1 (drag and drop).

enum TabSidebarOps {
    // MARK: Helpers

    static func index(of tab: Int, in items: [TabSidebarItem]) -> Int? { items.firstIndex { $0.id == tab } }

    static func members(of group: String, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        items.filter { $0.group?.id == group && !$0.isPinned }
    }

    /// The index just after the last item of the pinned section (0 when nothing is pinned).
    static func endOfPinned(_ items: [TabSidebarItem]) -> Int {
        var last = -1
        for (i, item) in items.enumerated() where item.isPinned || (item.group?.isPinned ?? false) { last = i }
        return last + 1
    }

    /// Items in the order of `ids` (anything missing keeps its relative position at the end).
    static func reordered(_ items: [TabSidebarItem], to ids: [Int]) -> [TabSidebarItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var out = ids.compactMap { byID[$0] }
        let placed = Set(ids)
        out += items.filter { !placed.contains($0.id) }
        return out
    }

    /// Normalizes the list the way the sidebar lays it out: groups contiguous, pinned blocks first.
    static func normalized(_ items: [TabSidebarItem]) -> [TabSidebarItem] {
        reordered(items, to: TabSidebarLayout.desiredOrder(items))
    }

    /// Groups that lost all members vanish by themselves (a group exists only through members), but a
    /// pinned flag on a tab that is also in a group is meaningless, so keep the two exclusive.
    private static func cleaned(_ items: [TabSidebarItem]) -> [TabSidebarItem] {
        items.map { item in
            var copy = item
            if copy.isPinned { copy.group = nil }
            return copy
        }
    }

    // MARK: Pin and unpin

    /// Pin Tab: leaves its group and goes to the end of Pinned.
    static func pinTab(_ id: Int, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        guard var tab = items.first(where: { $0.id == id }), !tab.isPinned else { return items }
        var rest = items.filter { $0.id != id }
        tab.isPinned = true
        tab.group = nil
        rest.insert(tab, at: endOfPinned(rest))
        return normalized(cleaned(rest))
    }

    /// Unpin Tab: goes to the top of the main list, loose.
    static func unpinTab(_ id: Int, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        guard var tab = items.first(where: { $0.id == id }) else { return items }
        var rest = items.filter { $0.id != id }
        tab.isPinned = false
        tab.group = nil
        rest.insert(tab, at: endOfPinned(rest))
        return normalized(rest)
    }

    /// Pin Group: the whole group goes to the end of Pinned.
    static func pinGroup(_ group: String, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        let run = members(of: group, in: items).map { item -> TabSidebarItem in
            var copy = item
            copy.group?.isPinned = true
            return copy
        }
        guard !run.isEmpty else { return items }
        var rest = items.filter { $0.group?.id != group || $0.isPinned }
        rest.insert(contentsOf: run, at: endOfPinned(rest))
        return normalized(rest)
    }

    /// Unpin Group: to the top of the main list.
    static func unpinGroup(_ group: String, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        let run = members(of: group, in: items).map { item -> TabSidebarItem in
            var copy = item
            copy.group?.isPinned = false
            return copy
        }
        guard !run.isEmpty else { return items }
        var rest = items.filter { $0.group?.id != group || $0.isPinned }
        rest.insert(contentsOf: run, at: endOfPinned(rest))
        return normalized(rest)
    }

    // MARK: Groups

    /// New Group with Tab. The group sits where the tab was if the tab was loose; if the tab was in
    /// another group, directly after that group, in the same section.
    static func newGroup(
        with tab: Int, id: String, name: String, color: TabSidebarGroupColor, in items: [TabSidebarItem]
    ) -> [TabSidebarItem] {
        guard let current = items.first(where: { $0.id == tab }) else { return items }
        var work = items

        // Leave the old group first, landing right after it.
        if current.group != nil && !current.isPinned {
            work = removeFromGroup(tab, in: work)
        }

        guard let at = index(of: tab, in: work) else { return items }
        let isPinnedSection = work[at].isPinned
        work[at].group = TabSidebarGroup(id: id, name: name, color: color, isCollapsed: false, isPinned: false)
        if isPinnedSection {
            // A pinned tab that gets grouped becomes a pinned group.
            work[at].isPinned = false
            work[at].group?.isPinned = true
        }
        return normalized(work)
    }

    /// New Tab Group (+ menu): the new tab goes to the end of the main list, in its own group.
    static func newTabGroup(
        tab: TabSidebarItem, id: String, name: String, color: TabSidebarGroupColor, in items: [TabSidebarItem]
    ) -> [TabSidebarItem] {
        var created = tab
        created.isPinned = false
        created.group = TabSidebarGroup(id: id, name: name, color: color, isCollapsed: false, isPinned: false)
        return normalized(items.filter { $0.id != tab.id } + [created])
    }

    /// Ungroup Tabs: the group's tabs stay where they are, loose.
    static func ungroup(_ group: String, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        let pinned = items.first(where: { $0.group?.id == group })?.group?.isPinned ?? false
        return normalized(items.map { item in
            guard item.group?.id == group else { return item }
            var copy = item
            copy.group = nil
            // Members of a pinned group stay in the pinned section as loose pinned tabs.
            copy.isPinned = pinned
            return copy
        })
    }

    /// Joins `group`, appended at the end of it.
    static func moveToGroup(_ tab: Int, group: String, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        guard let source = items.first(where: { $0.id == tab }),
              let anchor = members(of: group, in: items).last(where: { $0.id != tab }) ?? members(of: group, in: items).first,
              let attrs = anchor.group else { return items }
        var moved = source
        moved.isPinned = false
        moved.group = attrs
        var rest = items.filter { $0.id != tab }
        guard let at = rest.lastIndex(where: { $0.group?.id == group && !$0.isPinned }) else { return items }
        rest.insert(moved, at: at + 1)
        return normalized(rest)
    }

    /// Remove from Group (also ⌥←): the tab lands directly after its group, loose.
    static func removeFromGroup(_ tab: Int, in items: [TabSidebarItem]) -> [TabSidebarItem] {
        guard let source = items.first(where: { $0.id == tab }), let group = source.group else { return items }
        var moved = source
        moved.group = nil
        moved.isPinned = group.isPinned
        var rest = items.filter { $0.id != tab }
        let lastMember = rest.lastIndex(where: { $0.group?.id == group.id && !$0.isPinned })
        rest.insert(moved, at: (lastMember ?? (index(of: tab, in: items) ?? 0) - 1) + 1)
        return normalized(rest)
    }

    /// ⌥→: a loose tab whose previous sibling is a group is appended to that group.
    static func moveIntoPreviousGroup(_ tab: Int, in items: [TabSidebarItem]) -> (items: [TabSidebarItem], group: String)? {
        guard let source = items.first(where: { $0.id == tab }), source.group == nil else { return nil }
        let blocks = TabSidebarLayout.blocks(items)
        guard let bi = blocks.firstIndex(where: { $0 == [tab] }), bi > 0,
              let previous = items.first(where: { $0.id == blocks[bi - 1].first }),
              let group = previous.group else { return nil }
        // Same section only: a pinned tab does not join an unpinned group and vice versa.
        guard source.isPinned == group.isPinned || (source.isPinned && group.isPinned) else { return nil }
        return (moveToGroup(tab, group: group.id, in: items), group.id)
    }

    // MARK: Moving up and down

    /// The blocks of one container: a group's tabs, the pinned section, or the main list.
    private static func container(of target: MoveTarget, in items: [TabSidebarItem]) -> [[Int]]? {
        switch target {
        case .tab(let id):
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            if let group = item.group, !item.isPinned {
                return members(of: group.id, in: items).map { [$0.id] }
            }
            return sectionBlocks(pinned: item.isPinned, in: items)
        case .group(let id):
            guard let first = members(of: id, in: items).first, let group = first.group else { return nil }
            return sectionBlocks(pinned: group.isPinned, in: items)
        }
    }

    private static func sectionBlocks(pinned: Bool, in items: [TabSidebarItem]) -> [[Int]] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return TabSidebarLayout.blocks(items).filter { block in
            guard let first = block.first.flatMap({ byID[$0] }) else { return false }
            let isPinnedBlock = first.isPinned || (first.group?.isPinned ?? false)
            return isPinnedBlock == pinned
        }
    }

    enum MoveTarget: Equatable {
        case tab(Int)
        case group(String)
    }

    /// Move Tab Up / Down (⌥↑ / ⌥↓): swaps with its neighbor inside the same container. Nil at the edge.
    static func swap(_ target: MoveTarget, down: Bool, in items: [TabSidebarItem]) -> [TabSidebarItem]? {
        guard let blocks = container(of: target, in: items) else { return nil }
        let mine: [Int]
        switch target {
        case .tab(let id): mine = [id]
        case .group(let id): mine = members(of: id, in: items).map(\.id)
        }
        guard let at = blocks.firstIndex(where: { $0 == mine }) else { return nil }
        let other = down ? at + 1 : at - 1
        guard blocks.indices.contains(other) else { return nil }

        var swapped = blocks
        swapped.swapAt(at, other)

        // Rebuild the full order: the container's slots keep their place, everything else stays.
        let slots = Set(blocks.flatMap { $0 })
        var queue = swapped.flatMap { $0 }
        var order: [Int] = []
        for item in items {
            if slots.contains(item.id) { order.append(queue.removeFirst()) } else { order.append(item.id) }
        }
        return normalized(reordered(items, to: order))
    }

    /// Whether a swap is possible (for disabling menu items).
    static func canSwap(_ target: MoveTarget, down: Bool, in items: [TabSidebarItem]) -> Bool {
        swap(target, down: down, in: items) != nil
    }

    // MARK: Drag and drop

    enum Source: Equatable {
        case tab(Int)
        case group(String)
    }

    /// Where the pointer is, as the hit test sees it.
    enum Target: Equatable {
        /// Before or after a tab (loose, pinned or inside a group).
        case tab(Int, after: Bool)
        /// A group header: the top strip is "before the group", the rest is "into".
        case groupHeader(String, into: Bool)
        /// Before or after a whole group block (header midpoint, or the gap between blocks).
        case groupBlock(String, after: Bool)
        /// The strip at the bottom of a group's body.
        case groupBottom(String)
        /// Inside a group's body between its tabs: the nearest member decides.
        case groupInterior(String)
        /// The empty area at the bottom: end of the main list.
        case listEnd
        /// The pin drop zone: end of Pinned.
        case pinZone
    }

    enum Result: Equatable {
        /// No valid target here: releasing cancels, nothing is drawn.
        case none
        /// A target that is not allowed: red ring, releasing cancels.
        case invalid
        /// The list after the drop.
        case move([TabSidebarItem])
    }

    static func drop(_ source: Source, on target: Target, in items: [TabSidebarItem]) -> Result {
        switch source {
        case .tab(let id): return dropTab(id, on: target, in: items)
        case .group(let id): return dropGroup(id, on: target, in: items)
        }
    }

    private static func dropTab(_ id: Int, on target: Target, in items: [TabSidebarItem]) -> Result {
        guard let source = items.first(where: { $0.id == id }) else { return .none }
        var moved = source
        var rest = items.filter { $0.id != id }
        let insertAt: Int

        func asLoose(pinned: Bool) { moved.group = nil; moved.isPinned = pinned }
        func asMember(of group: TabSidebarGroup) { moved.isPinned = false; moved.group = group }

        switch target {
        case .tab(let other, let after):
            guard other != id, let at = rest.firstIndex(where: { $0.id == other }) else { return .none }
            let anchor = rest[at]
            if let group = anchor.group, !anchor.isPinned {
                asMember(of: group)
            } else {
                asLoose(pinned: anchor.isPinned)
            }
            insertAt = after ? at + 1 : at

        case .groupHeader(let gid, let into):
            guard let first = members(of: gid, in: rest).first, let group = first.group,
                  let firstIndex = rest.firstIndex(where: { $0.id == first.id }) else { return .none }
            if into {
                asMember(of: group)
                guard let last = rest.lastIndex(where: { $0.group?.id == gid && !$0.isPinned }) else { return .none }
                insertAt = last + 1
            } else {
                asLoose(pinned: group.isPinned)
                insertAt = firstIndex
            }

        case .groupBottom(let gid):
            guard let group = members(of: gid, in: rest).first?.group,
                  let last = rest.lastIndex(where: { $0.group?.id == gid && !$0.isPinned }) else { return .none }
            asMember(of: group)
            insertAt = last + 1

        case .groupInterior(let gid):
            // Nearest member by vertical midpoint is resolved by the hit test into .tab(...).
            guard let group = members(of: gid, in: rest).first?.group,
                  let last = rest.lastIndex(where: { $0.group?.id == gid && !$0.isPinned }) else { return .none }
            asMember(of: group)
            insertAt = last + 1

        case .groupBlock(let gid, let after):
            guard let first = members(of: gid, in: rest).first, let group = first.group,
                  let firstIndex = rest.firstIndex(where: { $0.id == first.id }),
                  let last = rest.lastIndex(where: { $0.group?.id == gid && !$0.isPinned }) else { return .none }
            asLoose(pinned: group.isPinned)
            insertAt = after ? last + 1 : firstIndex

        case .listEnd:
            asLoose(pinned: false)
            insertAt = rest.count

        case .pinZone:
            asLoose(pinned: true)
            insertAt = endOfPinned(rest)
        }

        rest.insert(moved, at: min(max(0, insertAt), rest.count))
        let result = normalized(cleaned(rest))
        return result == items ? .none : .move(result)
    }

    private static func dropGroup(_ gid: String, on target: Target, in items: [TabSidebarItem]) -> Result {
        let run = members(of: gid, in: items)
        guard let first = run.first else { return .none }
        let runIDs = Set(run.map(\.id))
        var rest = items.filter { !runIDs.contains($0.id) }
        var moving = run
        let insertAt: Int
        var pinned = first.group?.isPinned ?? false

        func blockIndex(before tab: Int) -> Int? { rest.firstIndex { $0.id == tab } }

        switch target {
        case .tab(let other, let after):
            guard !runIDs.contains(other), let at = rest.firstIndex(where: { $0.id == other }) else { return .none }
            let anchor = rest[at]
            // Groups do not nest: a tab inside another group is not a place for a group.
            if anchor.group != nil && !anchor.isPinned { return .invalid }
            pinned = anchor.isPinned
            insertAt = after ? at + 1 : at

        case .groupHeader(let other, _), .groupBlock(let other, _):
            guard other != gid, let firstOther = members(of: other, in: rest).first, let group = firstOther.group,
                  let firstIndex = rest.firstIndex(where: { $0.id == firstOther.id }),
                  let lastIndex = rest.lastIndex(where: { $0.group?.id == other && !$0.isPinned }) else { return .none }
            pinned = group.isPinned
            var after = false
            if case .groupHeader(_, let into) = target { after = into } // body of the header = after, top strip = before
            if case .groupBlock(_, let a) = target { after = a }
            insertAt = after ? lastIndex + 1 : firstIndex

        case .groupBottom(let other):
            guard other != gid, let group = members(of: other, in: rest).first?.group,
                  let lastIndex = rest.lastIndex(where: { $0.group?.id == other && !$0.isPinned }) else { return .none }
            pinned = group.isPinned
            insertAt = lastIndex + 1

        case .groupInterior(let other):
            // Another group's interior is invalid; its own interior is simply no target.
            return other == gid ? .none : .invalid

        case .listEnd:
            pinned = false
            insertAt = rest.count

        case .pinZone:
            pinned = true
            insertAt = endOfPinned(rest)
        }

        moving = moving.map { item in
            var copy = item
            copy.group?.isPinned = pinned
            return copy
        }
        rest.insert(contentsOf: moving, at: min(max(0, insertAt), rest.count))
        let result = normalized(rest)
        return result == items ? .none : .move(result)
    }
}
