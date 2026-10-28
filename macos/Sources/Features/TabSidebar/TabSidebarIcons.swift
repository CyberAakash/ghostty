import SwiftUI

// The sidebar's custom icon set. The drawings are the design's SVG sources, copied verbatim:
// every icon lives on a 16 x 16 grid and is stroked with round caps and joins. Like the design's
// `I(name, size, stroke)` wrapper, the stroke width is in grid units, so it scales with the icon.

// MARK: - SVG path parsing

enum TabSidebarSVG {
    /// Parses the subset of SVG path syntax the icons use (M L H V C S Q A Z, absolute and relative).
    static func path(_ d: String) -> Path {
        var parser = Parser(Array(d.unicodeScalars))
        return parser.parse()
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        init(_ scalars: [Unicode.Scalar]) { s = scalars }

        mutating func parse() -> Path {
            var command: Character = " "
            while true {
                skipSeparators()
                guard i < s.count else { break }
                if let c = letter(s[i]) {
                    command = c
                    i += 1
                    if command == "z" || command == "Z" {
                        path.closeSubpath()
                        current = start
                        lastCubicControl = nil
                        lastQuadControl = nil
                        continue
                    }
                }
                guard command != " " else { break }
                guard run(command) else { break }
                // After the first pair of a moveto, further pairs are implicit linetos.
                if command == "M" { command = "L" } else if command == "m" { command = "l" }
            }
            return path
        }

        func letter(_ u: Unicode.Scalar) -> Character? {
            let c = Character(u)
            return "MmLlHhVvCcSsQqAaZz".contains(c) ? c : nil
        }

        mutating func skipSeparators() {
            while i < s.count, s[i] == " " || s[i] == "," || s[i] == "\n" || s[i] == "\t" { i += 1 }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            guard i < s.count else { return nil }
            var j = i
            var text = ""
            if s[j] == "-" || s[j] == "+" { text.unicodeScalars.append(s[j]); j += 1 }
            var sawDot = false
            var sawDigit = false
            while j < s.count {
                let u = s[j]
                if u.properties.numericType != nil, u.value >= 48, u.value <= 57 {
                    text.unicodeScalars.append(u); sawDigit = true; j += 1
                } else if u == ".", !sawDot {
                    text.unicodeScalars.append(u); sawDot = true; j += 1
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(text) else { return nil }
            i = j
            return CGFloat(value)
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < s.count, s[i] == "0" || s[i] == "1" else { return nil }
            defer { i += 1 }
            return s[i] == "1"
        }

        mutating func pair() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        /// Executes one set of arguments for `command`. Returns false when no arguments remain.
        mutating func run(_ command: Character) -> Bool {
            let relative = command.isLowercase
            let base = relative ? current : .zero

            switch command {
            case "M", "m":
                guard let p = pair() else { return false }
                let point = CGPoint(x: base.x + p.x, y: base.y + p.y)
                path.move(to: point)
                current = point
                start = point
                lastCubicControl = nil; lastQuadControl = nil

            case "L", "l":
                guard let p = pair() else { return false }
                let point = CGPoint(x: base.x + p.x, y: base.y + p.y)
                path.addLine(to: point)
                current = point
                lastCubicControl = nil; lastQuadControl = nil

            case "H", "h":
                guard let x = number() else { return false }
                let point = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: point)
                current = point
                lastCubicControl = nil; lastQuadControl = nil

            case "V", "v":
                guard let y = number() else { return false }
                let point = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: point)
                current = point
                lastCubicControl = nil; lastQuadControl = nil

            case "C", "c":
                guard let a = pair(), let b = pair(), let p = pair() else { return false }
                let c1 = CGPoint(x: base.x + a.x, y: base.y + a.y)
                let c2 = CGPoint(x: base.x + b.x, y: base.y + b.y)
                let end = CGPoint(x: base.x + p.x, y: base.y + p.y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2; lastQuadControl = nil

            case "S", "s":
                guard let b = pair(), let p = pair() else { return false }
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = CGPoint(x: base.x + b.x, y: base.y + b.y)
                let end = CGPoint(x: base.x + p.x, y: base.y + p.y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
                lastCubicControl = c2; lastQuadControl = nil

            case "Q", "q":
                guard let a = pair(), let p = pair() else { return false }
                let c = CGPoint(x: base.x + a.x, y: base.y + a.y)
                let end = CGPoint(x: base.x + p.x, y: base.y + p.y)
                path.addQuadCurve(to: end, control: c)
                current = end
                lastQuadControl = c; lastCubicControl = nil

            case "A", "a":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = flag(), let sweep = flag(), let p = pair() else { return false }
                let end = CGPoint(x: base.x + p.x, y: base.y + p.y)
                TabSidebarSVG.addArc(
                    to: &path, from: current, to: end, rx: rx, ry: ry,
                    rotation: rotation, large: large, sweep: sweep)
                current = end
                lastCubicControl = nil; lastQuadControl = nil

            default:
                return false
            }
            return true
        }
    }

    /// SVG elliptical arc to cubic Béziers (SVG 1.1, appendix F.6.5: endpoint to center
    /// parameterization, then one curve per quarter turn).
    static func addArc(
        to path: inout Path, from p0: CGPoint, to p1: CGPoint,
        rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool
    ) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 || p0 == p1 {
            path.addLine(to: p1)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Scale the radii up if they cannot span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let root = lambda.squareRoot()
            rx *= root
            ry *= root
        }

        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coefficient = denominator == 0 ? 0 : (max(0, numerator / denominator)).squareRoot()
        if large == sweep { coefficient = -coefficient }
        let cxp = coefficient * (rx * y1p / ry)
        let cyp = coefficient * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            var a = acos(max(-1, min(1, dot / length)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)

        func point(_ angle: CGFloat) -> CGPoint {
            let x = rx * cos(angle), y = ry * sin(angle)
            return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
        }
        func derivative(_ angle: CGFloat) -> CGPoint {
            let x = -rx * sin(angle), y = ry * cos(angle)
            return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
        }

        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            let pa = point(a), pb = point(b)
            let da = derivative(a), db = derivative(b)
            path.addCurve(
                to: pb,
                control1: CGPoint(x: pa.x + t * da.x, y: pa.y + t * da.y),
                control2: CGPoint(x: pb.x - t * db.x, y: pb.y - t * db.y))
            a = b
        }
    }
}

// MARK: - Icon definitions

/// One drawn element of an icon.
struct TabSidebarIconPart {
    enum Shape {
        case path(String)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat)
        case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, rx: CGFloat)
    }

    var shape: Shape
    var filled = false
    var stroked = true
    var strokeWidth: CGFloat?
    var strokeOpacity: Double = 1
    var dash: [CGFloat] = []

    static func path(_ d: String, width: CGFloat? = nil, opacity: Double = 1, dash: [CGFloat] = []) -> Self {
        .init(shape: .path(d), strokeWidth: width, strokeOpacity: opacity, dash: dash)
    }
    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, width: CGFloat? = nil, opacity: Double = 1) -> Self {
        .init(shape: .circle(cx: cx, cy: cy, r: r), strokeWidth: width, strokeOpacity: opacity)
    }
    static func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Self {
        .init(shape: .circle(cx: cx, cy: cy, r: r), filled: true, stroked: false)
    }
    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rx: CGFloat = 0, dash: [CGFloat] = []) -> Self {
        .init(shape: .rect(x: x, y: y, w: w, h: h, rx: rx), dash: dash)
    }
    static func filledRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, rx: CGFloat = 0) -> Self {
        .init(shape: .rect(x: x, y: y, w: w, h: h, rx: rx), filled: true, stroked: false)
    }
}

enum TabSidebarIcon {
    case terminal, claude, branch, folder, pin, pinFilled, chevron, plus, search, sliders, ellipsisVertical
    case close, groupPanes, check, dragHandle, newGroup, newTab, bell, exited, sidebarToggle
    case list, grid, diffChanges, colorNone, split
    case glyphDone, glyphError, glyphCancelled, glyphBlocked, glyphWorking
    case xmarkCircleFill

    /// The design's default stroke width for this icon (grid units).
    var defaultStroke: CGFloat {
        switch self {
        case .claude: return 1.75
        case .close: return 1.75
        case .chevron: return 2
        case .check: return 2
        case .glyphDone, .glyphError, .glyphCancelled, .glyphBlocked: return 2.75
        case .glyphWorking: return 2.25
        case .colorNone: return 1.25
        default: return 1.5
        }
    }

    var parts: [TabSidebarIconPart] {
        switch self {
        case .terminal:
            return [.path("M4.5 5.5 7 8l-2.5 2.5M8.5 10.5h3")]
        case .claude:
            return [.path("M8 2.75v10.5M2.75 8h10.5M4.3 4.3l7.4 7.4M11.7 4.3l-7.4 7.4")]
        case .branch:
            return [.circle(5, 3.75, 1.5), .circle(5, 12.25, 1.5), .circle(11, 5.25, 1.5),
                    .path("M5 5.25v5.5M11 6.75c0 2.75-6 1.75-6 4")]
        case .folder:
            return [.path("M2.5 4.75c0-.7.55-1.25 1.25-1.25h2.6l1.4 1.75h4.5c.7 0 1.25.55 1.25 1.25v5.25c0 .7-.55 1.25-1.25 1.25h-8.5c-.7 0-1.25-.55-1.25-1.25z")]
        case .pin:
            return [.path("M5.75 2.75h4.5M6.75 2.75v3.5L4.5 9h7L9.25 6.25v-3.5M8 9v4.25")]
        case .pinFilled:
            var head = TabSidebarIconPart.path("M5.75 2.75h4.5M6.75 2.75v3.5L4.5 9h7L9.25 6.25v-3.5")
            head.filled = true
            return [head, .path("M8 9v4.25")]
        case .chevron:
            return [.path("M6 3.75 10.25 8 6 12.25")]
        case .plus:
            return [.path("M8 3.25v9.5M3.25 8h9.5")]
        case .search:
            return [.circle(7, 7, 4.25), .path("M10.25 10.25l3 3")]
        case .sliders:
            return [.path("M2.5 5h5.25M12.25 5h1.25M2.5 11h1.25M8.25 11h5.25"), .circle(10, 5, 2), .circle(6, 11, 2)]
        case .ellipsisVertical:
            return [.dot(8, 3.5, 1.3), .dot(8, 8, 1.3), .dot(8, 12.5, 1.3)]
        case .close:
            return [.path("M4.5 4.5l7 7M11.5 4.5l-7 7")]
        case .groupPanes:
            return [.rect(2.5, 5.5, 8.5, 7.5, rx: 1.75), .path("M5.25 3h6.5c.97 0 1.75.78 1.75 1.75v6")]
        case .check:
            return [.path("M3.75 8.25 6.6 11 12.25 5")]
        case .dragHandle:
            return [.dot(6, 4, 1.1), .dot(10, 4, 1.1), .dot(6, 8, 1.1), .dot(10, 8, 1.1), .dot(6, 12, 1.1), .dot(10, 12, 1.1)]
        case .newGroup:
            return [.path("M5 2.75h6.75c.97 0 1.75.78 1.75 1.75v6.75"), .rect(2.25, 5, 8.75, 8.75, rx: 1.75),
                    .path("M6.625 7.25v4.25M4.5 9.375h4.25")]
        case .newTab:
            return [.rect(2.25, 2.75, 11.5, 10.5, rx: 2), .path("M8 5.75v4.5M5.75 8h4.5")]
        case .bell:
            return [.path("M4.25 10.75V7.5a3.75 3.75 0 0 1 7.5 0v3.25l1 1.25h-9.5z"), .path("M6.75 13.75h2.5")]
        case .exited:
            return [.circle(8, 8, 5.75), .filledRect(6, 6, 4, 4, rx: 0.75)]
        case .sidebarToggle:
            return [.rect(2, 3, 12, 10, rx: 2), .path("M6 3v10")]
        case .list:
            return [.path("M3 4.5h10M3 8h10M3 11.5h10")]
        case .grid:
            return [.rect(2.75, 2.75, 4.25, 4.25, rx: 1), .rect(9, 2.75, 4.25, 4.25, rx: 1),
                    .rect(2.75, 9, 4.25, 4.25, rx: 1), .rect(9, 9, 4.25, 4.25, rx: 1)]
        case .diffChanges:
            return [.path("M5.5 3v6M2.5 6h6M8.5 12.5h5")]
        case .split:
            return [.rect(2.25, 3, 11.5, 10, rx: 2), .path("M8 3v10")]
        case .colorNone:
            return [.circle(8, 8, 5)]
        case .glyphDone:
            return [.path("M3.75 8.25 6.6 11 12.25 5")]
        case .glyphError:
            return [.path("M8 4v4.75"), .dot(8, 11.75, 1.1)]
        case .glyphCancelled:
            return [.path("M4.5 8h7")]
        case .glyphBlocked:
            return [.path("M6.25 5v6M9.75 5v6")]
        case .glyphWorking:
            return [.path("M8 3a5 5 0 0 1 5 5")]
        case .xmarkCircleFill:
            // The circle is filled; the cross is drawn by the caller in the field color.
            return [.init(shape: .circle(cx: 8, cy: 8, r: 6), filled: true, stroked: false)]
        }
    }

    /// The knockout cross of `xmarkCircleFill`.
    static let xmarkKnockout = "M5.9 5.9l4.2 4.2M10.1 5.9l-4.2 4.2"
}

// MARK: - Drawing

/// Draws one icon at `size` points, tinted with `color`.
struct TabSidebarIconView: View {
    let icon: TabSidebarIcon
    var size: CGFloat = 14
    var color: Color = .primary
    var stroke: CGFloat?
    /// Only for `xmarkCircleFill`: the color of the cross cut out of the circle.
    var knockout: Color = .clear

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 16
            let width = (stroke ?? icon.defaultStroke) * scale
            let transform = CGAffineTransform(scaleX: scale, y: scale)

            func draw(_ part: TabSidebarIconPart, in context: GraphicsContext) {
                var path: Path
                switch part.shape {
                case .path(let d): path = TabSidebarSVG.path(d)
                case .circle(let cx, let cy, let r): path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                case .rect(let x, let y, let w, let h, let rx):
                    path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
                }
                path = path.applying(transform)

                if part.filled { context.fill(path, with: .color(color)) }
                if part.stroked {
                    let style = StrokeStyle(
                        lineWidth: (part.strokeWidth ?? (stroke ?? icon.defaultStroke)) * scale,
                        lineCap: .round, lineJoin: .round, dash: part.dash.map { $0 * scale })
                    context.stroke(path, with: .color(color.opacity(part.strokeOpacity)), style: style)
                }
            }

            for part in icon.parts { draw(part, in: context) }

            if icon == .xmarkCircleFill {
                let cross = TabSidebarSVG.path(TabSidebarIcon.xmarkKnockout).applying(transform)
                context.stroke(cross, with: .color(knockout), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
            }
            _ = width
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Illustrations

/// The two empty-state illustrations (64 x 64 line art, tinted by the caller).
enum TabSidebarIllustration {
    case noResults, emptySidebar

    var parts: [TabSidebarIconPart] {
        switch self {
        case .noResults:
            return [
                .rect(6, 12, 36, 12, rx: 3), .rect(9.5, 15.5, 5, 5, rx: 1.25), .path("M19 18h17"),
                .rect(6, 28, 36, 12, rx: 3, dash: [2, 3]),
                .circle(44, 43, 8.5), .path("M50.25 49.25 57 56"), .path("M41 40l6 6M47 40l-6 6"),
            ]
        case .emptySidebar:
            return [
                .rect(10, 7, 44, 50, rx: 6), .rect(15, 12, 26, 6, rx: 2), .path("M45 15h4M47 13v4"),
                .path("M10 23h44"), .rect(15, 28, 34, 10, rx: 2.5, dash: [2, 3]), .path("M32 43v8M28 47h8"),
            ]
        }
    }
}

struct TabSidebarIllustrationView: View {
    let illustration: TabSidebarIllustration
    var size: CGFloat = 64
    var color: Color = .secondary

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 64
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for part in illustration.parts {
                var path: Path
                switch part.shape {
                case .path(let d): path = TabSidebarSVG.path(d)
                case .circle(let cx, let cy, let r): path = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                case .rect(let x, let y, let w, let h, let rx):
                    path = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
                }
                context.stroke(
                    path.applying(transform), with: .color(color),
                    style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round, dash: part.dash.map { $0 * scale }))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
