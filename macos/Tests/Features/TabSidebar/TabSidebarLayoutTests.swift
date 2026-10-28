import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

struct TabSidebarLayoutTests {
    @Test func layout() {
    func check(_ condition: Bool, _ message: String) {
        #expect(condition, Comment(rawValue: message))
    }

    func pane(_ id: String, _ title: String, cwd: String = "", branch: String? = nil, diff: TabSidebarDiffStats? = nil, focused: Bool = false, bell: Bool = false, exited: Bool = false) -> TabSidebarPane {
        TabSidebarPane(id: id, rawTitle: title, cwd: cwd, cwdDisplay: cwd.replacingOccurrences(of: "/Users/me", with: "~"), branch: branch, diff: diff, isFocused: focused, hasBell: bell, hasExited: exited)
    }
    func tab(_ id: Int, _ panes: [TabSidebarPane], name: String? = nil, sel: Bool = false, pinned: Bool = false, group: TabSidebarGroup? = nil) -> TabSidebarItem {
        TabSidebarItem(id: id, customName: name, panes: panes, color: .none, isSelected: sel, isPinned: pinned, group: group, position: id)
    }
    func group(_ id: String, _ name: String, color: TabSidebarGroupColor = .blue, collapsed: Bool = false, pinned: Bool = false) -> TabSidebarGroup {
        TabSidebarGroup(id: id, name: name, color: color, isCollapsed: collapsed, isPinned: pinned)
    }
    let P = TabSidebarPrefs()
    func ids(_ list: TabSidebarList) -> (pinned: [String], main: [String]) { (list.pinned.map(\.id), list.main.map(\.id)) }

    // ---- defaults match the spec
    check(P.viewAs == .panes && P.tabItem == .focusedSession && P.density == .compact && P.paneTitle == .command && P.showBranch && P.showDirectory && P.showDetailsOnHover, "spec defaults")

    // ---- claude detection and titles (spec 4.2)
    let claude = pane("c", "✳ Voice agentic OS feasibility", cwd: "/Users/me/research")
    check(claude.isClaude && claude.status == .done, "claude idle = done")
    check(pane("c", "⠂ Working", cwd: "/x").status == .working, "claude working")
    check(claude.title(P) == "Voice agentic OS feasibility", "claude title as conversation \(claude.title(P))")
    check(pane("c", "✳", cwd: "/x").title(P) == "Claude Code", "claude title fallback")
    let term = pane("t", "kubectl get pods", cwd: "/Users/me/infra", branch: "main")
    check(term.title(P) == "kubectl get pods", "terminal command title")
    check(pane("t", "", cwd: "/Users/me/infra").title(P) == "~/infra", "terminal empty command falls back to cwd")
    var dirP = P; dirP.paneTitle = .directory
    check(term.title(dirP) == "~/infra", "title as directory")
    var brP = P; brP.paneTitle = .branch
    check(term.title(brP) == "main", "title as branch")
    check(pane("t", "zsh", cwd: "/Users/me/infra").title(brP) == "~/infra", "branch title falls back to cwd")

    // ---- subtitles: Compact has none (the branch is a chip at the end of the row), Relaxed shows all
    let tp = pane("t", "kubectl get pods", cwd: "/Users/me/infra", branch: "main", diff: .init(added: 142, removed: 38))
    let compact = TabSidebarRows.subtitles(for: tp, title: tp.title(P), prefs: P)
    check(compact.isEmpty && TabSidebarRows.branchChip(for: tp, prefs: P) == "main", "compact: no subtitle lines, branch chip \(compact)")
    var exP = P; exP.density = .expanded
    let expanded = TabSidebarRows.subtitles(for: tp, title: tp.title(exP), prefs: exP)
    check(expanded.map(\.kind) == [.branch, .directory] && expanded[0].diff == .init(added: 142, removed: 38), "expanded: branch(+diff) then dir \(expanded)")
    let noBranch = pane("t", "zsh", cwd: "/Users/me/x", diff: .init(added: 1, removed: 2))
    let ch = TabSidebarRows.subtitles(for: noBranch, title: "zsh", prefs: exP)
    check(ch.first?.kind == .changes && ch.first?.diff == .init(added: 1, removed: 2), "changes line when diff but no branch \(ch)")
    check(TabSidebarRows.subtitles(for: noBranch, title: "zsh", prefs: P).isEmpty && TabSidebarRows.branchChip(for: noBranch, prefs: P) == nil, "compact without a branch: a single plain line")
    var exDir = exP; exDir.paneTitle = .directory
    var exBr = exP; exBr.paneTitle = .branch
    check(TabSidebarRows.subtitles(for: tp, title: tp.title(exDir), prefs: exDir).map(\.kind) == [.branch], "title=directory hides the directory line")
    check(TabSidebarRows.subtitles(for: tp, title: tp.title(exBr), prefs: exBr).map(\.kind) == [.changes, .directory], "title=branch: no branch line, the diff moves to a Changes line")
    var offP = exP; offP.showBranch = false
    check(TabSidebarRows.subtitles(for: tp, title: "x", prefs: offP).map(\.kind) == [.changes, .directory], "branch toggle off")
    let dupDir = pane("t", "~/infra", cwd: "/Users/me/infra")
    check(TabSidebarRows.subtitles(for: dupDir, title: "~/infra", prefs: exP).isEmpty, "directory equal to title is not repeated")

    // ---- rows: path titles head-truncate
    check(TabSidebarRows.paneRow(dupDir, prefs: P).titleIsPath, "path title flagged")
    check(!TabSidebarRows.paneRow(term, prefs: P).titleIsPath, "command not a path")

    // ---- tabs view
    let multi = tab(1, [pane("a", "vim", cwd: "/Users/me/a", branch: "main", focused: true), pane("b", "✳ Chat", cwd: "/Users/me/b"), pane("c", "zsh", cwd: "/Users/me/c"), pane("d", "top", cwd: "/Users/me/d")], name: "coucou")
    var tabsP = P; tabsP.viewAs = .tabs
    let focusedRow = TabSidebarRows.tabRow(multi, prefs: tabsP)
    check(focusedRow.title == "coucou" && focusedRow.titleUsesUIFont && focusedRow.paneCount == 4, "tabs/focused named tab, pane count")
    var sumP = tabsP; sumP.tabItem = .summary
    let sumRow = TabSidebarRows.tabRow(multi, prefs: sumP)
    check(sumRow.summary.count == 3 && sumRow.moreCount == 1 && sumRow.paneCount == nil && sumRow.subtitles.isEmpty, "summary: 3 lines + 1 more")
    let single = tab(2, [pane("x", "zsh", cwd: "/Users/me/x", branch: "main", focused: true)])
    check(TabSidebarRows.tabRow(single, prefs: sumP).summary.isEmpty, "summary only for multi-pane tabs")
    check(TabSidebarRows.tabRow(single, prefs: tabsP).title == "zsh" && !TabSidebarRows.tabRow(single, prefs: tabsP).titleUsesUIFont, "unnamed tab uses pane title in mono")

    // ---- headers (spec 4.1)
    check(tab(1, [pane("a", "zsh", cwd: "/Users/me/proj", focused: true)]).showsHeader == false, "single unnamed pane: no header")
    check(multi.showsHeader && multi.headerText == "coucou", "named: header")
    check(tab(3, [pane("a", "zsh", cwd: "/Users/me/proj", focused: true), pane("b", "zsh", cwd: "/x")]).headerText == "proj", "multi unnamed: header from cwd component")

    // ---- ordering: pinned first, groups at first member, physical order kept
    let G = group("g1", "Infra")
    let items = [tab(1, [pane("a", "a", focused: true)]), tab(2, [pane("b", "b", focused: true)], group: G), tab(3, [pane("c", "c", focused: true)]), tab(4, [pane("d", "d", focused: true)], group: G), tab(5, [pane("e", "e", focused: true)], pinned: true)]
    check(TabSidebarLayout.desiredOrder(items) == [5, 1, 2, 4, 3], "order \(TabSidebarLayout.desiredOrder(items))")
    let pg = group("g2", "Pinned", pinned: true)
    let items2 = [tab(1, [pane("a", "a", focused: true)]), tab(2, [pane("b", "b", focused: true)], group: pg), tab(3, [pane("c", "c", focused: true)], pinned: true), tab(4, [pane("d", "d", focused: true)], group: pg)]
    check(TabSidebarLayout.desiredOrder(items2) == [2, 4, 3, 1], "pinned group + pinned tab keep physical order \(TabSidebarLayout.desiredOrder(items2))")

    // ---- list structure
    let list = TabSidebarLayout.list(items: items, prefs: P)
    check(list.pinned.map(\.id) == ["tab:5"] && list.main.map(\.id) == ["tab:1", "group:g1", "tab:3"], "list blocks \(ids(list))")
    if case .group(let gb) = list.main[1] { check(gb.tabs.map(\.id) == [2, 4], "group members") } else { check(false, "group block") }

    // ---- group indicators when collapsed
    let busy = tab(2, [pane("b", "⠂ Busy", focused: true, bell: true)], group: group("g3", "Report", collapsed: true))
    let gl = TabSidebarLayout.list(items: [busy], prefs: P)
    if case .group(let gb) = gl.main[0] { check(gb.statuses == [.working] && gb.hasBell && gb.group.isCollapsed, "collapsed indicators") } else { check(false, "collapsed group block") }

    // ---- panes view: only the focused pane of the selected tab is highlighted
    let selTab = tab(1, [pane("a", "a", focused: true), pane("b", "b")], sel: true)
    if case .tab(let tb) = TabSidebarLayout.list(items: [selTab], prefs: P).main[0] { check(tb.rows.map(\.isSelected) == [true, false] && tb.headerText != nil, "panes selection + header") } else { check(false, "tab block") }
    if case .tab(let tb) = TabSidebarLayout.list(items: [selTab], prefs: tabsP).main[0] { check(tb.rows.count == 1 && tb.rows[0].isSelected && tb.headerText == nil, "tabs view selection") } else { check(false, "tab block 2") }

    // ---- search (spec 2A section 3)
    let sItems = [
      tab(1, [pane("a", "kubectl get pods", cwd: "/Users/me/infra", branch: "main", focused: true), pane("b", "zsh", cwd: "/Users/me/web", branch: "feature/login")], name: "Deploy", group: group("g", "Work")),
      tab(2, [pane("c", "vim notes", cwd: "/Users/me/notes", focused: true)]),
    ]
    func foundTabs(_ q: String, _ p: TabSidebarPrefs = P) -> [String] {
        let l = TabSidebarLayout.list(items: sItems, prefs: p, query: q)
        var out: [String] = []
        for block in l.pinned + l.main {
            switch block {
            case .tab(let t): out.append("t\(t.id)[\(t.rows.count)]")
            case .group(let g): out.append("g\(g.group.name)(" + g.tabs.map { "t\($0.id)[\($0.rows.count)]" }.joined(separator: ",") + ")")
            }
        }
        return out
    }
    check(foundTabs("WORK") == ["gWork(t1[2])"], "group name match shows all tabs/panes \(foundTabs("WORK"))")
    check(foundTabs("deploy") == ["gWork(t1[2])"], "tab name match shows all panes")
    check(foundTabs("login") == ["gWork(t1[1])"], "pane match lists only matching panes \(foundTabs("login"))")
    check(foundTabs("notes") == ["t2[1]"], "cwd match")
    check(foundTabs("kube pods") == [], "no tokenizing: 'kube pods' is not a substring")
    check(foundTabs("zzz").isEmpty && TabSidebarLayout.list(items: sItems, prefs: P, query: "zzz").isEmptyResult, "empty result flag")
    var collapsedItems = sItems; collapsedItems[0].group?.isCollapsed = true
    let cl = TabSidebarLayout.list(items: collapsedItems, prefs: P, query: "login")
    if case .group(let g) = cl.main[0] { check(!g.group.isCollapsed, "search renders collapsed groups expanded") } else { check(false, "collapsed search group") }
    check(foundTabs("") == ["gWork(t1[2])", "t2[1]"], "empty query shows everything \(foundTabs(""))")

    // ---- group color: first unused
    check(TabSidebarLayout.nextGroupColor(used: []) == .red && TabSidebarLayout.nextGroupColor(used: [.red, .orange]) == .yellow && TabSidebarLayout.nextGroupColor(used: [.red,.orange,.yellow,.green,.blue,.purple]) == .blue, "next group color")

    // ---- moving
    check(TabSidebarLayout.orderAfterMove([1,2,3,4], moving: 4, before: 2) == [1,4,2,3], "before")
    check(TabSidebarLayout.orderAfterMove([1,2,3,4], moving: 1, after: 3) == [2,3,1,4], "after")
    check(TabSidebarLayout.orderAfterMove([1,2,3,4], moving: 1, before: nil) == [2,3,4,1], "end")
    let flat = [tab(1, [pane("a","a")]), tab(2, [pane("b","b")], group: G), tab(3, [pane("c","c")]), tab(4, [pane("d","d")], group: G), tab(5, [pane("e","e")])]
    check(TabSidebarLayout.orderAfterMoveBlock([1,2,3,4,5], members: [2,4], anchor: 1, before: true, items: flat) == [2,4,1,3,5], "group before tab")
    check(TabSidebarLayout.orderAfterMoveBlock([1,2,3,4,5], members: [2,4], anchor: 5, before: false, items: flat) == [1,3,5,2,4], "group after tab")
    check(GitDiffStats.parse(" 3 files changed, 12 insertions(+), 4 deletions(-)\n") == TabSidebarDiffStats(added: 12, removed: 4), "diff parse")

    // ---- prefs decode tolerance
    let old = try! JSONDecoder().decode(TabSidebarPrefs.self, from: "{\"viewAs\":\"tabs\",\"density\":\"weird\"}".data(using: .utf8)!)
    check(old.viewAs == .tabs && old.density == .compact && old.showBranch, "tolerant prefs decode")
    }
}
