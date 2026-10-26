import SwiftUI

// How each AI shows that it's thinking, redrawn here from shapes and text as motion, not as its logo shrunk and moved.
// docs/thinking-animations.md says what each is based on and where the numbers come from.
//
// - Claude: before any words, Claude Code's spinner (· ✢ ✳ ✶ ✻ ✽ and back, a frame each 120 ms) beside words a lighter
//   band sweeps through a letter at a time; while words arrive, the Claude apps' spark, its rays snapping short as a
//   sweep goes round clockwise and growing back, redrawn twelve times a second like a hand-drawn loop.
// - ChatGPT: its filled dot, swelling and settling; the words get its smooth "Thinking" shimmer.
// - Gemini: its four-pointed sparkle in its own colours, turning a half turn at a time with its colours drifting
//   through it; the words get a quicker shimmer.
// - Ollama: its command line's braille spinner (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏, 100 ms a frame), as dots; plain words.
//
// Reduce Motion: each holds one still frame and the words don't shimmer. VoiceOver: "Claude is thinking" and so on.

/// The answering AI thinking, as its own product shows it; three dots in the subtle ink when it isn't known yet.
/// At 20 points and over (no words yet) Claude shows Claude Code's spinner; smaller (under arriving words) its spark.
struct ThinkingMark: View {
    var engine: AskEngine?
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var still
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let s = size * scale
        Group {
            if still {
                Canvas { gc, area in Thinking.draw(engine, glyphs: size >= 20, t: nil, in: &gc, area) }
            } else {
                TimelineView(.animation) { context in
                    Canvas { gc, area in
                        Thinking.draw(engine, glyphs: size >= 20, t: context.date.timeIntervalSinceReferenceDate, in: &gc, area)
                    }
                }
            }
        }
        .frame(width: s, height: s)
        .accessibilityElement()
        .accessibilityLabel(engine.map { "\($0.name) is thinking" } ?? "Thinking")
    }
}

extension View {
    /// Words beside a ThinkingMark, shimmering the way that AI's own status words do (Claude Code's verb, ChatGPT's
    /// and Gemini's "Thinking"); still under Reduce Motion, and plain for Ollama or an AI not known yet.
    func thinkingShimmer(_ engine: AskEngine?) -> some View { modifier(ThinkingShimmerModifier(engine: engine)) }
}

private struct ThinkingShimmerModifier: ViewModifier {
    var engine: AskEngine?
    @Environment(\.accessibilityReduceMotion) private var still

    func body(content: Content) -> some View {
        if still || engine == nil || engine == .ollama {
            content
        } else {
            TimelineView(.animation) { context in
                content.textRenderer(Shimmer(engine: engine ?? .claude, t: context.date.timeIntervalSinceReferenceDate))
            }
        }
    }
}

/// A lighter band passing through the words, glyph by glyph: each glyph gets one flat shade (no gradient).
private struct Shimmer: TextRenderer {
    var engine: AskEngine
    var t: Double

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        let n = Double(glyphs.count)
        // band: half-width in glyphs; lightest: the opacity at the band's middle.
        let band: Double, lightest: Double, pos: Double
        switch engine {
        case .claude:
            // Claude Code: the lighter band moves a letter at a time, a step each 100 ms.
            band = 3; lightest = 0.45
            let steps = (n + band * 2).rounded()
            pos = (t / 0.1).rounded(.down).truncatingRemainder(dividingBy: max(steps, 1)) - band
        case .chatgpt:
            // ChatGPT's "Thinking": a smooth sweep left to right, about 2 s across.
            band = 5; lightest = 0.35
            pos = (t / 2.0).truncatingRemainder(dividingBy: 1) * (n + band * 2) - band
        case .gemini, .ollama:
            band = 4; lightest = 0.4
            pos = (t / 1.5).truncatingRemainder(dividingBy: 1) * (n + band * 2) - band
        }
        for (i, g) in glyphs.enumerated() {
            let k = max(0, 1 - abs(Double(i) - pos) / band)
            var c = ctx
            c.opacity = 1 - (1 - lightest) * k
            c.draw(g)
        }
    }
}

/// The drawings, for a square `area`; `t` nil is the still frame.
enum Thinking {
    static let claude = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let geminiColours: [Color] = [
        Color(red: 0x21 / 255, green: 0x7B / 255, blue: 0xFE / 255),
        Color(red: 0x07 / 255, green: 0x8E / 255, blue: 0xFB / 255),
        Color(red: 0xAC / 255, green: 0x87 / 255, blue: 0xEB / 255),
        Color(red: 0x21 / 255, green: 0x7B / 255, blue: 0xFE / 255),
    ]

    static func draw(_ engine: AskEngine?, glyphs: Bool, t: Double?, in gc: inout GraphicsContext, _ area: CGSize) {
        let s = min(area.width, area.height)
        let c = CGPoint(x: area.width / 2, y: area.height / 2)
        switch engine {
        case .claude: glyphs ? claudeCode(t, &gc, c, s) : spark(t, &gc, c, s)
        case .chatgpt: chatGPTDot(t, &gc, c, s)
        case .gemini: geminiSparkle(t, &gc, c, s)
        case .ollama: braille(t, &gc, c, s)
        case nil: dots(t, &gc, c, s)
        }
    }

    // MARK: Claude Code's spinner

    /// · ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢, round again: Claude Code's glyphs, forward then back, 120 ms each.
    static let codeFrames = [0, 1, 2, 3, 4, 5, 4, 3, 2, 1]

    static func claudeCodeFrame(_ t: Double?) -> Int {
        guard let t else { return 4 }   // ✻, the one it shows when done
        return codeFrames[Int((t / 0.12).rounded(.down)) % codeFrames.count]
    }

    private static func claudeCode(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let r = s * 0.40
        let ink = GraphicsContext.Shading.color(claude)
        switch claudeCodeFrame(t) {
        case 0: // · interpunct
            gc.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.08, y: c.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: ink)
        case 1: // ✢ four teardrop spokes
            gc.fill(petals(4, c, r, width: r * 0.42, from: 0), with: ink)
        case 2: // ✳ eight spokes
            var p = Path()
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + r * 0.92 * sin(a), y: c.y - r * 0.92 * cos(a)))
            }
            gc.stroke(p, with: ink, style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round))
        case 3: // ✶ six-pointed star
            var p = Path()
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                let rr = i.isMultiple(of: 2) ? r : r * 0.5
                let pt = CGPoint(x: c.x + rr * sin(a), y: c.y - rr * cos(a))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            gc.fill(p, with: ink)
        case 4: // ✻ teardrop spokes
            gc.fill(petals(8, c, r, width: r * 0.34, from: 0), with: ink)
        default: // ✽ heavy teardrop spokes
            gc.fill(petals(8, c, r, width: r * 0.46, from: .pi / 8), with: ink)
        }
    }

    /// `count` teardrops pointing in to the centre, their round ends out at `r`.
    private static func petals(_ count: Int, _ c: CGPoint, _ r: CGFloat, width w: CGFloat, from start: Double) -> Path {
        var p = Path()
        for i in 0..<count {
            let a = start + Double(i) * 2 * .pi / Double(count)
            // Drawn pointing up, then turned.
            var drop = Path()
            let bulb = r - w / 2
            drop.move(to: CGPoint(x: 0, y: -r * 0.06))
            drop.addQuadCurve(to: CGPoint(x: -w / 2, y: -bulb), control: CGPoint(x: -w * 0.5, y: -bulb * 0.45))
            drop.addArc(center: CGPoint(x: 0, y: -bulb), radius: w / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            drop.addQuadCurve(to: CGPoint(x: 0, y: -r * 0.06), control: CGPoint(x: w * 0.5, y: -bulb * 0.45))
            drop.closeSubpath()
            p.addPath(drop, transform: CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a))
        }
        return p
    }

    // MARK: Claude's spark

    /// The spark's rays: where each points (degrees clockwise from the top) and its length, a little uneven like the mark.
    private static let rays: [(angle: Double, length: Double)] = [
        (0, 1.0), (31, 0.82), (58, 0.94), (92, 0.78), (118, 0.98), (151, 0.85),
        (181, 0.95), (209, 0.8), (241, 0.97), (268, 0.83), (300, 0.92), (331, 0.87),
    ]

    /// The spark drawn twelve times a second; a sweep goes clockwise once each 1.2 s, each ray snapping short to a
    /// third as it passes and growing back over three quarters of the turn behind it, with a slight wobble each
    /// frame as if drawn by hand.
    private static func spark(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let frame = t.map { ($0 * 12).rounded(.down) } ?? 0
        let sweep = t == nil ? nil : (frame / 12 / 1.2).truncatingRemainder(dividingBy: 1) * 360
        let r = s * 0.48, width = s * 0.1
        var p = Path()
        for (i, ray) in rays.enumerated() {
            var k = 1.0
            if let sweep {
                let behind = (sweep - ray.angle + 360).truncatingRemainder(dividingBy: 360) / 360
                let grown = min(1, behind / 0.75)
                k = 0.32 + 0.68 * (1 - pow(1 - grown, 3))
                k *= 1 + 0.04 * wobble(frame, i)
            }
            let a = (ray.angle + (t == nil ? 0 : 2.5 * wobble(frame, i + 40))) * .pi / 180
            let len = (r - width / 2) * ray.length * k
            p.move(to: CGPoint(x: c.x + width * 0.2 * sin(a), y: c.y - width * 0.2 * cos(a)))
            p.addLine(to: CGPoint(x: c.x + len * sin(a), y: c.y - len * cos(a)))
        }
        gc.stroke(p, with: .color(claude), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// A steady pseudo-random number in -1...1 for a frame and a ray.
    private static func wobble(_ frame: Double, _ i: Int) -> Double {
        let x = sin(frame * 12.9898 + Double(i) * 78.233) * 43758.5453
        return (x - x.rounded(.down)) * 2 - 1
    }

    // MARK: ChatGPT's dot

    /// The filled dot in ink (black on light, white on dark, as ChatGPT's), swelling from 80% to full and back each
    /// 1.25 s, eased in and out.
    private static func chatGPTDot(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let phase = t.map { 0.5 - 0.5 * cos($0 / 1.25 * 2 * .pi) } ?? 1
        let d = s * 0.5 * (0.8 + 0.2 * phase)
        gc.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(.ink))
    }

    // MARK: Gemini's sparkle

    /// The four-pointed sparkle (curved sides, as Gemini's), filled with its blue-to-violet colours drifting through
    /// it over 3 s; it turns a half turn each 2 s, eased in and out, and gives a little as it turns.
    private static func geminiSparkle(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let r = s * 0.46
        var turn = 0.0, swell = 1.0, drift = 0.0
        if let t {
            let half = t / 2.0, step = half.rounded(.down), within = half - step
            let eased = within < 0.5 ? 4 * within * within * within : 1 - pow(-2 * within + 2, 3) / 2
            turn = (step + eased) * .pi
            swell = 0.93 + 0.07 * cos(within * 2 * .pi)
            drift = (t / 3).truncatingRemainder(dividingBy: 1)
        }
        let rr = r * swell
        // Each side a curve from point to point, bowed in towards the centre (Gemini's mark, read off its outline).
        var star = Path()
        let k = 0.16 * rr
        star.move(to: CGPoint(x: 0, y: -rr))
        star.addQuadCurve(to: CGPoint(x: rr, y: 0), control: CGPoint(x: k, y: -k))
        star.addQuadCurve(to: CGPoint(x: 0, y: rr), control: CGPoint(x: k, y: k))
        star.addQuadCurve(to: CGPoint(x: -rr, y: 0), control: CGPoint(x: -k, y: k))
        star.addQuadCurve(to: CGPoint(x: 0, y: -rr), control: CGPoint(x: -k, y: -k))
        star.closeSubpath()
        let placed = star.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: turn))
        // Its colours at 135°, four times its size, slid along so they drift through it and come round again.
        let span = r * 4, shift = CGFloat(drift) * span * 0.75
        let start = CGPoint(x: c.x - r - shift, y: c.y - r - shift)
        let end = CGPoint(x: start.x + span, y: start.y + span)
        gc.fill(placed, with: .linearGradient(Gradient(colors: geminiColours), startPoint: start, endPoint: end))
    }

    // MARK: Ollama's braille spinner

    /// ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏, the command line's spinner (progress/spinner.go), a frame each 100 ms.
    static let brailleFrames: [UInt32] = [0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F]

    private static func braille(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let frame = t.map { Int(($0 / 0.1).rounded(.down)) % brailleFrames.count } ?? 0
        let bits = brailleFrames[frame] - 0x2800
        let gap = s * 0.26, dot = s * 0.17
        // Dots 1 2 3 down the left, 4 5 6 down the right.
        for bit in 0..<6 where bits & (1 << bit) != 0 {
            let col = CGFloat(bit / 3), row = CGFloat(bit % 3)
            let x = c.x + (col - 0.5) * gap, y = c.y + (row - 1) * gap
            gc.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)), with: .color(.ink))
        }
    }

    // MARK: Not known yet

    private static func dots(_ t: Double?, _ gc: inout GraphicsContext, _ c: CGPoint, _ s: CGFloat) {
        let d = s * 0.22, gap = s * 0.12
        for i in 0..<3 {
            // Typed out: as one expression the compiler gave up on it.
            let phase: Double = t.map { (now: Double) -> Double in
                let turn: Double = (now - Double(i) * 0.18) * 2 * Double.pi / 1.2
                return 0.5 + 0.5 * sin(turn)
            } ?? 1
            let x = c.x + CGFloat(i - 1) * (d + gap)
            var g = gc
            g.opacity = 0.35 + 0.65 * phase
            g.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(.inkSubtle))
        }
    }
}
