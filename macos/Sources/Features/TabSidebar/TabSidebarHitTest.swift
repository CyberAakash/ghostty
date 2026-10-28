import CoreGraphics

/// Maps the pointer position to a drop target. Pure geometry: the model feeds it the rectangles
/// of the laid-out blocks (in a y-down space), so the zone rules of the spec (part 2B, 1.3) can be
/// tested without any views.
enum TabSidebarHitTest {
    /// A rectangle in y-down space (`top` < `bottom`).
    struct Frame: Equatable {
        var minX: CGFloat
        var maxX: CGFloat
        var top: CGFloat
        var bottom: CGFloat

        var midY: CGFloat { (top + bottom) / 2 }
        var height: CGFloat { bottom - top }

        func containsY(_ y: CGFloat) -> Bool { y >= top && y < bottom }
        func contains(_ point: CGPoint) -> Bool {
            point.x >= minX && point.x <= maxX && containsY(point.y)
        }
    }

    struct Block: Equatable {
        enum Kind: Equatable {
            case tab(Int)
            case group(String)
        }

        var kind: Kind
        var frame: Frame
        /// Group blocks only.
        var header: Frame?
        var bottomStrip: Frame?
        /// Group blocks only: the tabs inside, in order.
        var members: [(id: Int, frame: Frame)] = []

        static func == (a: Block, b: Block) -> Bool {
            a.kind == b.kind && a.frame == b.frame && a.header == b.header && a.bottomStrip == b.bottomStrip
                && a.members.map(\.id) == b.members.map(\.id)
        }
    }

    struct Layout {
        var viewport: Frame
        /// All top-level blocks in display order (pinned first).
        var blocks: [Block]
        var pinZone: Frame?
    }

    // Constants from the spec.
    static let headerTopStrip: CGFloat = 8
    static let horizontalClamp: CGFloat = 10
    static let outsideLimit: CGFloat = 24

    static func resolve(point rawPoint: CGPoint, source: TabSidebarOps.Source, layout: Layout) -> TabSidebarOps.Target? {
        let v = layout.viewport

        // More than 24 pt outside the list on any side: no target.
        if rawPoint.x < v.minX - outsideLimit || rawPoint.x > v.maxX + outsideLimit
            || rawPoint.y < v.top - outsideLimit || rawPoint.y > v.bottom + outsideLimit {
            return nil
        }
        // Otherwise clamp into the list.
        let point = CGPoint(
            x: min(max(rawPoint.x, v.minX + horizontalClamp), v.maxX - horizontalClamp),
            y: min(max(rawPoint.y, v.top), v.bottom - 0.01))

        if let zone = layout.pinZone, zone.containsY(point.y) { return .pinZone }

        let blocks = layout.blocks
        guard let first = blocks.first, let last = blocks.last else { return .listEnd }

        // Above the first block: before it. Below the last: the empty area.
        if point.y < first.frame.top { return gapTarget(block: first, after: false, source: source) }
        if point.y >= last.frame.bottom { return .listEnd }

        for (index, block) in blocks.enumerated() {
            if block.frame.containsY(point.y) { return inside(block, at: point, source: source) }

            // In the gap between this block and the next: whichever edge is nearer.
            if index + 1 < blocks.count {
                let next = blocks[index + 1]
                if point.y >= block.frame.bottom && point.y < next.frame.top {
                    let afterThis = point.y - block.frame.bottom <= next.frame.top - point.y
                    return afterThis
                        ? gapTarget(block: block, after: true, source: source)
                        : gapTarget(block: next, after: false, source: source)
                }
            }
        }
        return .listEnd
    }

    private static func gapTarget(block: Block, after: Bool, source: TabSidebarOps.Source) -> TabSidebarOps.Target? {
        switch block.kind {
        case .tab(let id): return .tab(id, after: after)
        case .group(let id):
            if source == .group(id) { return nil }
            return .groupBlock(id, after: after)
        }
    }

    private static func inside(_ block: Block, at point: CGPoint, source: TabSidebarOps.Source) -> TabSidebarOps.Target? {
        switch block.kind {
        case .tab(let id):
            return .tab(id, after: point.y > block.frame.midY)

        case .group(let gid):
            // A group dropped on itself has no target.
            if source == .group(gid) { return nil }

            if let header = block.header, header.containsY(point.y) {
                switch source {
                case .tab:
                    return .groupHeader(gid, into: point.y - header.top >= headerTopStrip)
                case .group:
                    // Header midpoint: before or after the whole group.
                    return .groupBlock(gid, after: point.y > header.midY)
                }
            }

            if let strip = block.bottomStrip, strip.containsY(point.y) { return .groupBottom(gid) }

            // Interior: a tab goes before or after the nearest member; a group cannot nest.
            switch source {
            case .group:
                return .groupInterior(gid)
            case .tab:
                guard let nearest = block.members.min(by: { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }) else {
                    return .groupBottom(gid)
                }
                return .tab(nearest.id, after: point.y > nearest.frame.midY)
            }
        }
    }
}
