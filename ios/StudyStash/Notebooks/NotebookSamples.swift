#if DEBUG
import CoreText
import PencilKit
import UIKit

/// A notebook of a lecture's notes in a student's hand, for pictures (`-show notebook`): three pages, on narrow
/// ruled, grid and Cornell paper, with lines of notes, a boxed formula, a highlighted line, a graph and an answer in
/// red. The writing is real PencilKit ink: each word traced from a handwriting face's outlines with a fine pen.
/// `-notebook-colour cream|dark` puts it on that paper. Made afresh each launch; never sent anywhere unless the
/// notebook is closed with Done (the demo library takes it).
@MainActor
enum NotebookSamples {
    static let id = UUID(uuidString: "0B5E55ED-0000-4000-8000-00000000A11C")!

    static func make() -> UUID {
        let store = NotebookStore.shared
        if let old = store.notebook(id) { store.delete(old) }
        let colour = DebugLaunch.value("-notebook-colour").flatMap(Notebook.PaperColour.init(rawValue:)) ?? .white
        let papers: [Notebook.Paper] = [.narrow, .grid, .cornell]
        let pages = papers.map { Notebook.Page(Notebook.Template(paper: $0, colour: colour)) }
        let n = Notebook(id: id, title: "Calculus II notes, 14 Oct", className: "Calculus II", lectureID: nil, lectureTitle: nil,
                         pages: pages, template: Notebook.Template(paper: .narrow, colour: colour))
        store.save(n)
        let dark = colour == .dark
        let pen = dark ? UIColor(hex: "#EDEFF2") : UIColor(hex: "#1E2A47")
        let red = dark ? UIColor(hex: "#FF8A7A") : UIColor(hex: "#C23A2E")
        store.setDrawing(PKDrawing(strokes: lined(pen: pen, red: red)), n, pages[0])
        store.setDrawing(PKDrawing(strokes: grid(pen: pen, red: red)), n, pages[1])
        store.setDrawing(PKDrawing(strokes: cornell(pen: pen, red: red)), n, pages[2])
        return id
    }

    private static func line(_ k: Int) -> CGFloat { PaperDrawing.top + CGFloat(k) * PaperDrawing.spacing(.narrow) - 3 }

    // MARK: the pages

    private static func lined(pen: UIColor, red: UIColor) -> [PKStroke] {
        var h = Hand(ink: pen, seed: 7)
        let title = h.write("Integration by parts", x: 70, y: 60, size: 27)
        h.underline(from: 68, to: title + 4, y: 67)
        h.write("Mon 14 Oct", x: 478, y: 60, size: 15)
        h.write("Comes from the product rule:", x: 70, y: line(2), size: 16)
        h.write("(uv)' = u'v + uv'", x: 104, y: line(3), size: 16)
        // The formula, boxed.
        var x = h.integral(x: 116, y: line(5) + 1, height: 30)
        x = h.write("u dv  =  uv  -", x: x + 4, y: line(5), size: 19)
        x = h.integral(x: x + 8, y: line(5) + 1, height: 30)
        x = h.write("v du", x: x + 4, y: line(5), size: 19)
        h.box(CGRect(x: 100, y: line(5) - 27, width: x - 100 + 14, height: 36))
        h.write("Choose u with LIATE:", x: 70, y: line(7), size: 16)
        let end = h.measure("Log, Inverse trig, Algebraic, Trig, Exp", size: 16)
        h.highlight(from: 86, to: 92 + end, y: line(8) - 5, colour: UIColor(hex: "#FFE15C"))
        h.write("Log, Inverse trig, Algebraic, Trig, Exp", x: 90, y: line(8), size: 16)
        x = h.write("ex.", x: 70, y: line(10), size: 16)
        x = h.integral(x: x + 12, y: line(10) + 1, height: 24)
        x = h.write("x e", x: x + 3, y: line(10), size: 16)
        x = h.write("x", x: x + 1, y: line(10) - 8, size: 11)
        h.write("dx", x: x + 5, y: line(10), size: 16)
        x = h.write("u = x", x: 104, y: line(11), size: 16)
        x = h.write("dv = e", x: x + 34, y: line(11), size: 16)
        x = h.write("x", x: x + 1, y: line(11) - 8, size: 11)
        h.write("dx", x: x + 5, y: line(11), size: 16)
        x = h.write("du = dx", x: 104, y: line(12), size: 16)
        x = h.write("v = e", x: x + 22, y: line(12), size: 16)
        h.write("x", x: x + 1, y: line(12) - 8, size: 11)
        var r = Hand(ink: red, seed: 11)
        r.arrow(from: CGPoint(x: 72, y: line(14) - 5), to: CGPoint(x: 98, y: line(14) - 5))
        x = r.write("= x e", x: 106, y: line(14), size: 17)
        x = r.write("x", x: x + 1, y: line(14) - 8, size: 11)
        x = r.write("- e", x: x + 6, y: line(14), size: 17)
        x = r.write("x", x: x + 1, y: line(14) - 8, size: 11)
        r.write("+ C", x: x + 6, y: line(14), size: 17)
        x = h.write("Check: differentiate it back", x: 70, y: line(16), size: 16)
        h.tick(at: CGPoint(x: x + 10, y: line(16) - 4))
        h.write("Tabular method when u is a polynomial (p. 412)", x: 70, y: line(18), size: 16)
        return h.strokes + r.strokes
    }

    private static func grid(pen: UIColor, red: UIColor) -> [PKStroke] {
        var h = Hand(ink: pen, seed: 3)
        let title = h.write("Area between curves", x: 36, y: 58, size: 26)
        h.underline(from: 34, to: title + 4, y: 65)
        // Axes on the grid's lines, y = x and y = x² over [0, 1.4].
        let o = CGPoint(x: 108, y: 396), unit: CGFloat = 216
        h.arrow(from: CGPoint(x: o.x - 18, y: o.y), to: CGPoint(x: o.x + unit * 1.55, y: o.y))
        h.arrow(from: CGPoint(x: o.x, y: o.y + 18), to: CGPoint(x: o.x, y: o.y - unit * 1.2))
        h.write("x", x: o.x + unit * 1.55 + 6, y: o.y + 5, size: 15)
        h.write("y", x: o.x - 5, y: o.y - unit * 1.2 - 8, size: 15)
        var hatch = Hand(ink: UIColor(hex: "#A6E3A1"), seed: 5)
        for i in 1..<12 {
            let t = CGFloat(i) / 12
            hatch.marker(from: CGPoint(x: o.x + t * unit, y: o.y - t * t * unit), to: CGPoint(x: o.x + t * unit, y: o.y - t * unit), width: 9)
        }
        h.curve((0...25).map { i in let t = CGFloat(i) / 20; return CGPoint(x: o.x + t * unit, y: o.y - t * unit) })
        h.curve((0...22).map { i in let t = CGFloat(i) / 20; return CGPoint(x: o.x + t * unit, y: o.y - t * t * unit) })
        h.write("y = x", x: o.x + unit * 1.27, y: o.y - unit * 1.2, size: 15)
        h.write("y = x²", x: o.x + unit * 1.12, y: o.y - unit * 1.22 + 4 - 40, size: 15)
        h.dot(at: CGPoint(x: o.x + unit, y: o.y - unit))
        h.write("(1, 1)", x: o.x + unit + 12, y: o.y - unit + 16, size: 14)
        h.write("1", x: o.x + unit - 4, y: o.y + 18, size: 14)
        // The area, boxed, and the answer.
        var x = h.write("A =", x: 54, y: 486, size: 19)
        x = h.integral(x: x + 12, y: 487, height: 32)
        h.write("1", x: x - 2, y: 466, size: 10)
        h.write("0", x: x - 8, y: 496, size: 10)
        x = h.write("(x - x²) dx", x: x + 8, y: 486, size: 19)
        h.box(CGRect(x: 40, y: 458, width: x - 40 + 14, height: 40))
        var r = Hand(ink: red, seed: 9)
        r.write("= 1/2 - 1/3 = 1/6", x: 72, y: 540, size: 19)
        h.write("Top curve minus bottom curve, between where they cross.", x: 54, y: 594, size: 15)
        return hatch.strokes + h.strokes + r.strokes
    }

    private static func cornell(pen: UIColor, red: UIColor) -> [PKStroke] {
        var h = Hand(ink: pen, seed: 21)
        h.write("Integration by parts, practice", x: 18, y: 50, size: 22)
        h.write("Wed 16 Oct", x: 488, y: 50, size: 14)
        let c: CGFloat = 18, n: CGFloat = PaperDrawing.cueWidth + 14
        h.write("When?", x: c, y: line(1), size: 16)
        h.write("Which is u?", x: c, y: line(6), size: 16)
        h.write("Tabular?", x: c, y: line(11), size: 16)
        h.write("A product of two kinds of function", x: n, y: line(1), size: 15)
        var x = h.integral(x: n + 10, y: line(2) + 1, height: 22)
        h.write("x cos x dx", x: x + 3, y: line(2), size: 15)
        h.write("u = x,   dv = cos x dx", x: n + 14, y: line(3), size: 15)
        x = h.write("= x sin x -", x: n + 14, y: line(4), size: 15)
        x = h.integral(x: x + 8, y: line(4) + 1, height: 22)
        h.write("sin x dx", x: x + 3, y: line(4), size: 15)
        var r = Hand(ink: red, seed: 4)
        r.write("= x sin x + cos x + C", x: n + 14, y: line(5), size: 15)
        h.write("Pick u so du is simpler:", x: n, y: line(6), size: 15)
        let liate = h.measure("logs, inverse trig, algebraic,", size: 15)
        h.highlight(from: n + 10, to: n + 18 + liate, y: line(7) - 5, colour: UIColor(hex: "#FFE15C"))
        h.write("logs, inverse trig, algebraic,", x: n + 14, y: line(7), size: 15)
        h.write("trig, exponential", x: n + 14, y: line(8), size: 15)
        h.write("For x², x³ ... times sin, cos, e", x: n, y: line(11), size: 15)
        h.write("Signs alternate: + - + -", x: n + 14, y: line(12), size: 15)
        h.write("Stop when the column hits 0", x: n + 14, y: line(13), size: 15)
        let summary = 792 - PaperDrawing.summaryHeight + PaperDrawing.spacing(.cornell) + 6
        h.write("Integration by parts undoes the product rule. Choose u by LIATE,", x: 22, y: summary - 3, size: 15)
        h.write("and check an answer by differentiating it back.", x: 22, y: summary + PaperDrawing.spacing(.cornell) - 3, size: 15)
        return h.strokes + r.strokes
    }
}

/// A pen that writes words as a student would: each traced from Bradley Hand's outlines (a fine pen round the
/// letters fills them), a little crooked from word to word.
private struct Hand {
    var ink: UIColor
    var width: CGFloat = 1.15
    var strokes: [PKStroke] = []
    private var rng: UInt64

    /// PencilKit draws nothing for a stroke made in code narrower than about 2.4: the letters are traced this many
    /// times larger and scaled down, so the pen comes out fine.
    private static let k: CGFloat = 3

    init(ink: UIColor, seed: UInt64) {
        self.ink = ink
        rng = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    private mutating func random(_ spread: CGFloat) -> CGFloat {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return (CGFloat(rng % 10_000) / 5_000 - 1) * spread
    }

    private static func font(_ size: CGFloat) -> CTFont {
        for name in ["BradleyHandITCTT-Bold", "Noteworthy-Bold", "MarkerFelt-Thin"] where UIFont(name: name, size: size) != nil {
            return CTFontCreateWithName(name as CFString, size, nil)
        }
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    func measure(_ text: String, size: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): Self.font(size)]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Writes `text` with its baseline at `y` from `x`; returns where it ended.
    @discardableResult
    mutating func write(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat) -> CGFloat {
        let font = Self.font(size * Self.k)
        let space = measure(" ", size: size)
        // The pen round each letter as wide as the letter's stroke, so big writing is filled too.
        let pen = max(width, size * 0.085)
        var cursor = x
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            if word.isEmpty { cursor += space; continue }
            let s = String(word)
            let path = GlyphPath.path(s, font: font)
            let angle = random(0.014)
            let lift = random(0.7)
            let transform = CGAffineTransform(translationX: cursor, y: y + lift).rotated(by: angle).scaledBy(x: 1 / Self.k, y: 1 / Self.k)
            for contour in Self.contours(path) {
                // Font space is y up; the page's is y down.
                strokes.append(stroke(contour.map { CGPoint(x: $0.x, y: -$0.y) }, width: pen * Self.k, transform: transform))
            }
            cursor += measure(s, size: size) + space
        }
        return cursor - space
    }

    /// ∫, drawn by hand: a hook, a long stroke leaning right, a hook. Returns where it ends.
    mutating func integral(x: CGFloat, y: CGFloat, height h: CGFloat) -> CGFloat {
        let top = y - h * 0.82, bottom = y + h * 0.18
        let w = h * 0.32
        let points = [CGPoint(x: x + w, y: top + 2), CGPoint(x: x + w * 0.85, y: top), CGPoint(x: x + w * 0.62, y: top + 0.5),
                      CGPoint(x: x + w * 0.52, y: top + 4), CGPoint(x: x + w * 0.48, y: (top + bottom) / 2),
                      CGPoint(x: x + w * 0.42, y: bottom - 4), CGPoint(x: x + w * 0.3, y: bottom - 0.5),
                      CGPoint(x: x + w * 0.12, y: bottom), CGPoint(x: x, y: bottom - 2)]
        line(points)
        return x + w
    }

    mutating func underline(from x0: CGFloat, to x1: CGFloat, y: CGFloat) {
        var points: [CGPoint] = []
        for x in stride(from: x0, through: x1, by: 6) {
            let wave: CGFloat = sin(x / 40) * 0.8
            let drift: CGFloat = (x - x0) * 0.004
            points.append(CGPoint(x: x, y: y + wave + drift))
        }
        line(points)
    }

    mutating func box(_ r: CGRect) {
        let corners = [CGPoint(x: r.minX - 1, y: r.minY + 1), CGPoint(x: r.maxX + 1, y: r.minY - 0.5),
                       CGPoint(x: r.maxX, y: r.maxY + 1), CGPoint(x: r.minX + 0.5, y: r.maxY), CGPoint(x: r.minX - 1, y: r.minY + 3)]
        var points: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 5))
            // The corner three times, so the pen turns there.
            points += [a, a]
            for i in 0..<n { let t = CGFloat(i) / CGFloat(n); points.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }
        }
        points.append(corners.last!)
        line(points)
    }

    mutating func arrow(from a: CGPoint, to b: CGPoint) {
        let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 6))
        line((0...n).map { i in let t = CGFloat(i) / CGFloat(n); return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + sin(t * 3) * 0.5) })
        let angle = atan2(b.y - a.y, b.x - a.x), head: CGFloat = 8
        line([CGPoint(x: b.x - head * cos(angle - 0.45), y: b.y - head * sin(angle - 0.45)), b, b,
              CGPoint(x: b.x - head * cos(angle + 0.45), y: b.y - head * sin(angle + 0.45))])
    }

    mutating func tick(at p: CGPoint) {
        line([CGPoint(x: p.x, y: p.y - 2), CGPoint(x: p.x + 3, y: p.y + 2), CGPoint(x: p.x + 5, y: p.y + 4), CGPoint(x: p.x + 5, y: p.y + 4),
              CGPoint(x: p.x + 9, y: p.y - 4), CGPoint(x: p.x + 14, y: p.y - 11)])
    }

    mutating func dot(at p: CGPoint) {
        line([CGPoint(x: p.x - 1.5, y: p.y), CGPoint(x: p.x, y: p.y - 1.5), CGPoint(x: p.x + 1.5, y: p.y), CGPoint(x: p.x, y: p.y + 1.5), CGPoint(x: p.x - 1.5, y: p.y)], width: 2.6)
    }

    mutating func curve(_ points: [CGPoint]) { line(points) }

    /// A highlighter's stroke behind a line of writing.
    mutating func highlight(from x0: CGFloat, to x1: CGFloat, y: CGFloat, colour: UIColor) {
        let points = stride(from: x0, through: x1, by: 8).map { CGPoint(x: $0, y: y + random(0.6)) }
        strokes.append(Self.make(points, ink: PKInk(.marker, color: colour), width: 15, transform: .identity))
    }

    mutating func marker(from a: CGPoint, to b: CGPoint, width: CGFloat) {
        let n = max(2, Int(hypot(b.x - a.x, b.y - a.y) / 6))
        let points = (0...n).map { i in let t = CGFloat(i) / CGFloat(n); return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        strokes.append(Self.make(points, ink: PKInk(.marker, color: ink), width: width, transform: .identity))
    }

    /// A pen line through `points` (page units), as fine as the writing.
    private mutating func line(_ points: [CGPoint], width w: CGFloat? = nil) {
        let scaled = points.map { CGPoint(x: $0.x * Self.k, y: $0.y * Self.k) }
        strokes.append(stroke(scaled, width: (w ?? width) * Self.k, transform: CGAffineTransform(scaleX: 1 / Self.k, y: 1 / Self.k)))
    }

    private func stroke(_ points: [CGPoint], width: CGFloat, transform: CGAffineTransform) -> PKStroke {
        Self.make(points, ink: PKInk(.pen, color: ink), width: width, transform: transform)
    }

    private static func make(_ points: [CGPoint], ink: PKInk, width: CGFloat, transform: CGAffineTransform) -> PKStroke {
        let all = points.count == 1 ? [points[0], CGPoint(x: points[0].x + 0.3, y: points[0].y)] : points
        let controls = all.enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i) * 0.006, size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        var s = PKStroke(ink: ink, path: PKStrokePath(controlPoints: controls, creationDate: .now))
        s.transform = transform
        return s
    }

    private static func quad(_ a: CGPoint, _ c: CGPoint, _ p: CGPoint, _ t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let wa: CGFloat = u * u, wc: CGFloat = 2 * u * t, wp: CGFloat = t * t
        return CGPoint(x: wa * a.x + wc * c.x + wp * p.x, y: wa * a.y + wc * c.y + wp * p.y)
    }

    private static func cubic(_ a: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p: CGPoint, _ t: CGFloat) -> CGPoint {
        let u: CGFloat = 1 - t
        let wa: CGFloat = u * u * u, w1: CGFloat = 3 * u * u * t, w2: CGFloat = 3 * u * t * t, wp: CGFloat = t * t * t
        let x: CGFloat = wa * a.x + w1 * c1.x + w2 * c2.x + wp * p.x
        let y: CGFloat = wa * a.y + w1 * c1.y + w2 * c2.y + wp * p.y
        return CGPoint(x: x, y: y)
    }

    /// A glyph outline's closed shapes as lines of points, curves cut into short straight pieces.
    private static func contours(_ path: CGPath) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var current: [CGPoint] = []
        var last = CGPoint.zero, start = CGPoint.zero
        func flushContour() { if current.count > 1 { out.append(current) }; current = [] }
        func lineTo(_ p: CGPoint) {
            let n = max(1, Int(hypot(p.x - last.x, p.y - last.y) / 6))
            for i in 1...n { let t = CGFloat(i) / CGFloat(n); current.append(CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)) }
            last = p
        }
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                flushContour()
                last = e.points[0]; start = last
                current = [last]
            case .addLineToPoint:
                lineTo(e.points[0])
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1], a = last
                for i in 1...6 { current.append(quad(a, c, p, CGFloat(i) / 6)) }
                last = p
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2], a = last
                for i in 1...8 { current.append(cubic(a, c1, c2, p, CGFloat(i) / 8)) }
                last = p
            case .closeSubpath:
                lineTo(start)
                flushContour()
            @unknown default: break
            }
        }
        flushContour()
        return out
    }
}
#endif
