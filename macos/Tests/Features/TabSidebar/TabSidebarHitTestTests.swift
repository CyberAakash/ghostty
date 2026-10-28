import CoreGraphics
import Foundation
import Testing
@testable import Ghostty

struct TabSidebarHitTestTests {
    @Test func hitTest() {
    func check(_ condition: Bool, _ message: String) {
        #expect(condition, Comment(rawValue: message))
    }
    typealias F = TabSidebarHitTest.Frame
    func f(_ top: CGFloat, _ bottom: CGFloat) -> F { F(minX: 0, maxX: 260, top: top, bottom: bottom) }
    // list: tab 1 (0-28) gap2 | group G (30-130: header 30-58, members 2:[60-88],3:[90-118], bottom 126-130) | tab 4 (132-160); viewport 0-400; pin zone none
    let g = TabSidebarHitTest.Block(kind: .group("G"), frame: f(30, 130), header: f(30, 58), bottomStrip: f(126, 130), members: [(2, f(60, 88)), (3, f(90, 118))])
    let layout = TabSidebarHitTest.Layout(viewport: f(0, 400), blocks: [
        .init(kind: .tab(1), frame: f(0, 28)), g, .init(kind: .tab(4), frame: f(132, 160))], pinZone: nil)
    func r(_ y: CGFloat, _ s: TabSidebarOps.Source = .tab(9), x: CGFloat = 100) -> TabSidebarOps.Target? {
        TabSidebarHitTest.resolve(point: CGPoint(x: x, y: y), source: s, layout: layout)
    }
    check(r(5) == .tab(1, after: false), "top half of a tab → before")
    check(r(20) == .tab(1, after: true), "bottom half → after")
    check(r(31) == .groupHeader("G", into: false), "header top strip (first 8pt) → before group")
    check(r(37) == .groupHeader("G", into: false), "still the top strip at 7pt")
    check(r(39) == .groupHeader("G", into: true), "header body → into")
    check(r(127) == .groupBottom("G"), "bottom strip")
    check(r(62) == .tab(2, after: false) && r(85) == .tab(2, after: true), "interior member halves")
    check(r(89.9) == .tab(3, after: false), "nearest member in the gap between members (nearer 3) \(String(describing: r(89.9)))")
    check(r(29) == .tab(1, after: true), "gap between tab 1 and group: nearer to tab 1's bottom → after tab 1 \(String(describing: r(29)))")
    check(r(131) == .groupBlock("G", after: true) || r(131) == .tab(4, after: false), "gap between group and tab 4")
    check(r(131.5) == .tab(4, after: false), "gap nearer to tab 4's top → before it")
    check(r(200) == .listEnd && r(399) == .listEnd, "empty area → list end")
    check(r(-10) == .tab(1, after: false), "slightly above the list clamps to the first block")
    check(r(-30) == nil && r(430) == nil, "more than 24pt outside = no target")
    check(r(100, x: -30) == nil, "too far left")
    // group source
    check(r(40, .group("G")) == nil, "group on itself: no target")
    check(r(62, .group("G")) == nil, "group on its own tab: no target")
    check(r(10, .group("X")) == .tab(1, after: false), "group over a loose tab")
    check(r(62, .group("X")) == .groupInterior("G"), "group over another group's interior → invalid target")
    check(r(35, .group("X")) == .groupBlock("G", after: false) && r(55, .group("X")) == .groupBlock("G", after: true), "group over a header: midpoint decides")
    check(r(127, .group("X")) == .groupBottom("G"), "group over bottom strip")
    // pin zone
    let withZone = TabSidebarHitTest.Layout(viewport: f(0, 400), blocks: [.init(kind: .tab(4), frame: f(40, 68))], pinZone: f(6, 38))
    check(TabSidebarHitTest.resolve(point: CGPoint(x: 100, y: 20), source: .tab(9), layout: withZone) == .pinZone, "pin zone")
    check(TabSidebarHitTest.resolve(point: CGPoint(x: 100, y: 50), source: .tab(9), layout: withZone) == .tab(4, after: false), "tab below the pin zone")
    // empty list
    check(TabSidebarHitTest.resolve(point: CGPoint(x: 100, y: 50), source: .tab(9), layout: .init(viewport: f(0, 400), blocks: [], pinZone: nil)) == .listEnd, "empty list → end")
    }
}
