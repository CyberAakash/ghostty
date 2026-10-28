import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

struct TabSidebarOpsTests {
    @Test func ops() {
    func check(_ condition: Bool, _ message: String) {
        #expect(condition, Comment(rawValue: message))
    }

    func tab(_ id: Int, group: TabSidebarGroup? = nil, pinned: Bool = false) -> TabSidebarItem {
        TabSidebarItem(id: id, customName: nil, panes: [], color: .none, isSelected: false, isPinned: pinned, group: group, position: id)
    }
    func g(_ id: String, pinned: Bool = false) -> TabSidebarGroup { .init(id: id, name: id, color: .blue, isCollapsed: false, isPinned: pinned) }
    /// Compact description: ids in order, "p" = pinned loose, "G1:" = in group, groups pinned flag "*".
    func describe(_ items: [TabSidebarItem]) -> String {
        items.map { i in
            var s = "\(i.id)"
            if i.isPinned { s += "p" }
            if let gr = i.group { s += "@\(gr.id)\(gr.isPinned ? "*" : "")" }
            return s
        }.joined(separator: " ")
    }
    // base: pinned loose 5 | pinned group P: 6,7 | main: 1, G1: 2,3, 4
    func base() -> [TabSidebarItem] {
        TabSidebarOps.normalized([tab(1), tab(2, group: g("G1")), tab(3, group: g("G1")), tab(4), tab(5, pinned: true), tab(6, group: g("P", pinned: true)), tab(7, group: g("P", pinned: true))])
    }
    check(describe(base()) == "5p 6@P* 7@P* 1 2@G1 3@G1 4", "base \(describe(base()))")

    func tabDrop(_ id: Int, _ t: TabSidebarOps.Target) -> String {
        switch TabSidebarOps.drop(.tab(id), on: t, in: base()) {
        case .move(let items): return describe(items)
        case .none: return "none"
        case .invalid: return "invalid"
        }
    }
    func groupDrop(_ id: String, _ t: TabSidebarOps.Target) -> String {
        switch TabSidebarOps.drop(.group(id), on: t, in: base()) {
        case .move(let items): return describe(items)
        case .none: return "none"
        case .invalid: return "invalid"
        }
    }

    // ---- source: loose tab
    check(tabDrop(1, .tab(4, after: true)) == "5p 6@P* 7@P* 2@G1 3@G1 4 1", "loose after loose \(tabDrop(1, .tab(4, after: true)))")
    check(tabDrop(4, .tab(1, after: false)) == "5p 6@P* 7@P* 4 1 2@G1 3@G1", "loose before loose")
    check(tabDrop(1, .tab(5, after: true)) == "5p 1p 6@P* 7@P* 2@G1 3@G1 4", "loose after pinned loose becomes pinned \(tabDrop(1, .tab(5, after: true)))")
    check(tabDrop(4, .tab(3, after: false)) == "5p 6@P* 7@P* 1 2@G1 4@G1 3@G1", "loose before tab in group joins it \(tabDrop(4, .tab(3, after: false)))")
    check(tabDrop(1, .tab(7, after: false)) == "5p 6@P* 1@P* 7@P* 2@G1 3@G1 4", "loose into pinned group follows its pinned state \(tabDrop(1, .tab(7, after: false)))")
    check(tabDrop(4, .groupHeader("G1", into: false)) == "5p 6@P* 7@P* 1 4 2@G1 3@G1", "header top strip: before group, ungrouped \(tabDrop(4, .groupHeader("G1", into: false)))")
    check(tabDrop(1, .groupHeader("G1", into: true)) == "5p 6@P* 7@P* 2@G1 3@G1 1@G1 4", "header body: into, appended \(tabDrop(1, .groupHeader("G1", into: true)))")
    check(tabDrop(4, .groupBottom("G1")) == "5p 6@P* 7@P* 1 2@G1 3@G1 4@G1", "bottom strip appends")
    check(tabDrop(1, .listEnd) == "5p 6@P* 7@P* 2@G1 3@G1 4 1", "empty area end")
    check(tabDrop(4, .listEnd) == "none", "already at the end")
    check(tabDrop(1, .pinZone) == "5p 6@P* 7@P* 1p 2@G1 3@G1 4", "pin zone: end of pinned (loose pinned) \(tabDrop(1, .pinZone))")
    check(tabDrop(4, .tab(4, after: true)) == "none", "itself")
    // ---- source: tab in a group
    check(tabDrop(2, .tab(3, after: true)) == "5p 6@P* 7@P* 1 3@G1 2@G1 4", "reorder inside group")
    check(tabDrop(2, .groupHeader("G1", into: true)) == "5p 6@P* 7@P* 1 3@G1 2@G1 4", "to the end of own group")
    check(tabDrop(3, .groupHeader("G1", into: false)) == "5p 6@P* 7@P* 1 3 2@G1 4", "leaves G1, before it \(tabDrop(3, .groupHeader("G1", into: false)))")
    check(tabDrop(2, .groupHeader("P", into: true)) == "5p 6@P* 7@P* 2@P* 1 3@G1 4", "to another group takes its pinned state \(tabDrop(2, .groupHeader("P", into: true)))")
    check(tabDrop(3, .listEnd) == "5p 6@P* 7@P* 1 2@G1 4 3", "leaves group to end")
    check(tabDrop(2, .tab(4, after: true)) == "5p 6@P* 7@P* 1 3@G1 4 2", "single member leaving then other member remains")
    // a group that loses its last member vanishes by itself
    let solo = TabSidebarOps.normalized([tab(1), tab(2, group: g("G1")), tab(3)])
    if case .move(let items) = TabSidebarOps.drop(.tab(2), on: .tab(3, after: true), in: solo) { check(describe(items) == "1 3 2" && items.allSatisfy { $0.group == nil }, "empty group disappears \(describe(items))") } else { check(false, "solo move") }
    // ---- source: tab in a pinned group leaves
    check(tabDrop(6, .tab(4, after: true)) == "5p 7@P* 1 2@G1 3@G1 4 6", "from pinned group to main loose is unpinned \(tabDrop(6, .tab(4, after: true)))")
    check(tabDrop(7, .pinZone) == "5p 6@P* 7p 1 2@G1 3@G1 4", "pinned-group tab to pin zone: \(tabDrop(7, .pinZone))")

    // ---- source: group
    check(groupDrop("G1", .tab(1, after: false)) == "5p 6@P* 7@P* 2@G1 3@G1 1 4", "group before loose tab")
    check(groupDrop("G1", .tab(4, after: true)) == "5p 6@P* 7@P* 1 4 2@G1 3@G1", "group after loose tab")
    check(groupDrop("G1", .tab(5, after: true)) == "5p 2@G1* 3@G1* 6@P* 7@P* 1 4", "group onto pinned loose tab becomes pinned \(groupDrop("G1", .tab(5, after: true)))")
    check(groupDrop("G1", .tab(7, after: false)) == "invalid", "group onto a tab inside another group")
    check(groupDrop("G1", .tab(2, after: false)) == "none" || groupDrop("G1", .tab(2, after: false)) == "invalid", "group onto own tab: no target (decision)")
    check(groupDrop("G1", .groupBlock("P", after: true)) == "5p 6@P* 7@P* 2@G1* 3@G1* 1 4", "group after pinned group takes pinned \(groupDrop("G1", .groupBlock("P", after: true)))")
    check(groupDrop("P", .groupBlock("G1", after: false)) == "5p 6@P 7@P 1 2@G1 3@G1 4" || groupDrop("P", .groupBlock("G1", after: false)) == "5p 1 6@P 7@P 2@G1 3@G1 4", "pinned group before unpinned group becomes unpinned \(groupDrop("P", .groupBlock("G1", after: false)))")
    check(groupDrop("G1", .groupInterior("P")) == "invalid", "another group's interior invalid")
    check(groupDrop("G1", .groupInterior("G1")) == "none", "own interior no target")
    check(groupDrop("G1", .groupBottom("P")) == "5p 6@P* 7@P* 2@G1* 3@G1* 1 4", "group after another group's bottom strip")
    check(groupDrop("G1", .listEnd) == "5p 6@P* 7@P* 1 4 2@G1 3@G1", "group to end of list")
    check(groupDrop("G1", .pinZone) == "5p 2@G1* 3@G1* 6@P* 7@P* 1 4" || groupDrop("G1", .pinZone) == "5p 6@P* 7@P* 2@G1* 3@G1* 1 4", "group pinned at end of pinned \(groupDrop("G1", .pinZone))")

    // ---- pin / unpin
    check(describe(TabSidebarOps.pinTab(4, in: base())) == "5p 4p 6@P* 7@P* 1 2@G1 3@G1" || describe(TabSidebarOps.pinTab(4, in: base())) == "5p 6@P* 7@P* 4p 1 2@G1 3@G1", "pin tab → end of Pinned \(describe(TabSidebarOps.pinTab(4, in: base())))")
    check(describe(TabSidebarOps.pinTab(2, in: base())).contains("2p") && !describe(TabSidebarOps.pinTab(2, in: base())).contains("2@"), "pinned tab leaves its group")
    check(describe(TabSidebarOps.unpinTab(5, in: base())) == "6@P* 7@P* 5 1 2@G1 3@G1 4", "unpin → top of main \(describe(TabSidebarOps.unpinTab(5, in: base())))")
    check(describe(TabSidebarOps.pinGroup("G1", in: base())) == "5p 6@P* 7@P* 2@G1* 3@G1* 1 4", "pin group → end of Pinned \(describe(TabSidebarOps.pinGroup("G1", in: base())))")
    check(describe(TabSidebarOps.unpinGroup("P", in: base())) == "5p 6@P 7@P 1 2@G1 3@G1 4", "unpin group → top of main \(describe(TabSidebarOps.unpinGroup("P", in: base())))")

    // ---- groups
    check(describe(TabSidebarOps.newGroup(with: 4, id: "N", name: "New Group", color: .red, in: base())) == "5p 6@P* 7@P* 1 2@G1 3@G1 4@N", "new group with loose tab stays in place")
    check(describe(TabSidebarOps.newGroup(with: 2, id: "N", name: "New Group", color: .red, in: base())) == "5p 6@P* 7@P* 1 3@G1 2@N 4", "new group from a grouped tab lands after the old group \(describe(TabSidebarOps.newGroup(with: 2, id: "N", name: "New Group", color: .red, in: base())))")
    check(describe(TabSidebarOps.ungroup("G1", in: base())) == "5p 6@P* 7@P* 1 2 3 4", "ungroup in place")
    check(describe(TabSidebarOps.removeFromGroup(2, in: base())) == "5p 6@P* 7@P* 1 3@G1 2 4", "remove from group lands after it \(describe(TabSidebarOps.removeFromGroup(2, in: base())))")
    check(describe(TabSidebarOps.moveToGroup(4, group: "G1", in: base())) == "5p 6@P* 7@P* 1 2@G1 3@G1 4@G1", "move to group appends")
    if let r = TabSidebarOps.moveIntoPreviousGroup(4, in: TabSidebarOps.normalized(base())) { check(describe(r.items).hasSuffix("4@G1") && r.group == "G1", "⌥→ joins previous group") } else { check(false, "⌥→") }
    check(TabSidebarOps.moveIntoPreviousGroup(1, in: base()) == nil, "⌥→ needs a group directly above")
    let nt = Self_newTab()
    func Self_newTab() -> [TabSidebarItem] { TabSidebarOps.newTabGroup(tab: tab(9), id: "T", name: "New Group", color: .red, in: base()) }
    check(describe(nt) == "5p 6@P* 7@P* 1 2@G1 3@G1 4 9@T", "new tab group at end of main \(describe(nt))")

    // ---- swap
    check(describe(TabSidebarOps.swap(.tab(2), down: true, in: base())!) == "5p 6@P* 7@P* 1 3@G1 2@G1 4", "swap inside group")
    check(TabSidebarOps.swap(.tab(3), down: true, in: base()) == nil, "no swap at the group edge")
    check(describe(TabSidebarOps.swap(.tab(1), down: true, in: base())!) == "5p 6@P* 7@P* 2@G1 3@G1 1 4", "loose tab swaps past a whole group \(describe(TabSidebarOps.swap(.tab(1), down: true, in: base())!))")
    check(describe(TabSidebarOps.swap(.group("G1"), down: false, in: base())!) == "5p 6@P* 7@P* 2@G1 3@G1 1 4", "group swaps up")
    check(TabSidebarOps.swap(.group("P"), down: true, in: base()) == nil, "pinned group is last in Pinned: cannot go down")
    check(describe(TabSidebarOps.swap(.group("P"), down: false, in: base())!) == "6@P* 7@P* 5p 1 2@G1 3@G1 4", "pinned group swaps up with pinned neighbor \(describe(TabSidebarOps.swap(.group("P"), down: false, in: base())!))")
    check(TabSidebarOps.swap(.tab(4), down: true, in: base()) == nil, "no swap at the end")
    check(TabSidebarOps.swap(.tab(5), down: false, in: base()) == nil, "no swap at pinned start")
    }
}
