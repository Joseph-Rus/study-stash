import SwiftUI

// Syft Notes' pixel s, Joey's "Pixel Sift": the mark, its three splash screens and its four loaders, drawn from the same
// cells as the phone web app (web/src/ui/syftCells.ts) and moved by the same keyframes, easings, durations and delays
// as his motion reference (syft-motion.html). Each keyframe track below is the reference's CSS, read the way a browser
// reads it: a value at each offset, the timing function applied between each pair. A splash plays once and holds (the
// reference loops it for show); a loader loops. Reduce Motion: the finished s, still (a loader breathes; a splash only
// fades). Colours: SyftPalette (Theme.swift). Geometry in the reference's units: a cell 6.6 square, corners 1.8, on a
// pitch of 8, the grid 6 × 7 (48 × 56).

// MARK: - The cells

enum SyftCells {
    static let cell = 6.6
    static let radius = 1.8
    static let pitch = 8.0
    static let gridWidth = 48.0
    static let gridHeight = 56.0

    /// The 24 cells' corners in path order, p0 → p23: from the top right tip, across the top, down the left, across the
    /// middle, down the right, along the bottom to the bottom left tip.
    static let path: [(x: Double, y: Double)] = [
        (40, 8), (40, 0), (32, 0), (24, 0), (16, 0), (8, 0), (0, 8), (8, 8), (0, 16), (8, 16), (8, 24), (16, 24),
        (24, 24), (32, 24), (32, 32), (40, 32), (32, 40), (40, 40), (32, 48), (24, 48), (16, 48), (8, 48), (0, 48), (0, 40),
    ]

    /// Every slot of the grid: the mesh behind the s.
    static let mesh: [(x: Double, y: Double)] = (0..<42).map { (Double($0 % 6) * 8, Double($0 / 6) * 8) }

    enum Look: Sendable {
        /// The motion board's Sorted / Night (S1, L1) and the dark tile: the bottom row mustard.
        case sorted
        /// The logo board's white tile: the bottom row ink.
        case light
        /// S2: each stroke its own colour, the middle one ink.
        case segments
        /// S3 and Odd One Out: every cell ink (paper on a dark page).
        case ink
    }

    static func colour(_ look: Look, _ i: Int) -> Color {
        switch look {
        case .sorted, .light:
            if i <= 7 { return Color(syft: SyftPalette.lilac) }
            if i <= 13 { return Color(syft: SyftPalette.sky) }
            if i <= 17 || i == 23 { return Color(syft: SyftPalette.coral) }
            return Color(syft: look == .sorted ? SyftPalette.mustard : SyftPalette.ink)
        case .segments:
            if i <= 5 { return Color(syft: SyftPalette.lilac) }
            if i <= 9 { return Color(syft: SyftPalette.sky) }
            if i <= 13 { return Color(syft: SyftPalette.ink) }
            if i <= 17 { return Color(syft: SyftPalette.coral) }
            return Color(syft: SyftPalette.mustard)
        case .ink:
            return Color(syft: SyftPalette.cell)
        }
    }

    /// A loose bit: its centre in the grid's units, its turn and its colour.
    struct Bit {
        var x: Double, y: Double, turn: Double, colour: UIColor
        /// From the logo board's centres, in pitches from the middle of the top left cell.
        init(_ col: Double, _ row: Double, _ turn: Double, _ colour: UIColor) {
            x = cell / 2 + col * pitch
            y = cell / 2 + row * pitch
            self.turn = turn
            self.colour = colour
        }
    }

    /// The white tile's six bits tumbling above the s: coral, lilac, sky, mustard, lilac, ink.
    static let bitsAbove: [Bit] = [
        Bit(0.3, -1.5, 20, SyftPalette.coral), Bit(1.0, -1.7, -30, SyftPalette.lilac), Bit(1.5, -2.6, 15, SyftPalette.sky),
        Bit(2.6, -2.1, -25, SyftPalette.mustard), Bit(3.8, -2.3, 35, SyftPalette.lilac), Bit(4.8, -1.9, -20, SyftPalette.ink),
    ]
    /// The dark tile's three bits falling out under it: coral, sky, lilac.
    static let bitsBelow: [Bit] = [Bit(1.0, 7.6, 20, SyftPalette.coral), Bit(2.8, 8.5, 20, SyftPalette.sky), Bit(4.3, 7.4, 20, SyftPalette.lilac)]
    /// The light mesh's (P6) three: coral, sky, mustard.
    static let bitsBelowSegments: [Bit] = [Bit(1.0, 7.6, 20, SyftPalette.coral), Bit(2.8, 8.5, 20, SyftPalette.sky), Bit(4.3, 7.4, 20, SyftPalette.mustard)]

    /// Odd One Out and S3's start: the p1 cell up and right of its slot, turned.
    static let pop = (dx: 10.0, dy: -14.0, turn: 25.0)
    /// S3's three coral ticks over the p1 slot, in the grid's units.
    static let ticks: [(Double, Double, Double, Double)] = [(43.3, -4, 43.3, -8), (48.3, -2.5, 51.3, -5.5), (38.3, -2.5, 35.3, -5.5)]
}

// MARK: - Keyframes, as CSS reads them

/// CSS's cubic-bezier(x1, y1, x2, y2).
struct SyftEasing: Sendable {
    let x1, y1, x2, y2: Double
    static let linear = SyftEasing(x1: 0, y1: 0, x2: 1, y2: 1)
    static let ease = SyftEasing(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeOut = SyftEasing(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = SyftEasing(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static func bezier(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> SyftEasing { SyftEasing(x1: a, y1: b, x2: c, y2: d) }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return x }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            let u = 1 - t
            let bx = 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
            if abs(bx - x) < 1e-7 { break }
            if bx < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        let u = 1 - t
        return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
    }
}

/// One property's keyframes: (offset 0…1, value), eased between each pair by the animation's timing function.
struct SyftTrack: Sendable {
    let keys: [(Double, Double)]
    init(_ keys: [(Double, Double)]) { self.keys = keys }

    func value(_ p: Double, _ easing: SyftEasing) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if p <= first.0 { return first.1 }
        if p >= last.0 { return last.1 }
        for i in 1..<keys.count where p <= keys[i].0 {
            let a = keys[i - 1], b = keys[i]
            return a.1 + (b.1 - a.1) * easing((p - a.0) / (b.0 - a.0))
        }
        return last.1
    }
}

/// An animation's clock: how far through its keyframes it is `t` seconds after it began. Before its delay, its first
/// keyframe (CSS's backwards fill); once, it holds its last (forwards); repeating, it goes round.
struct SyftTiming: Sendable {
    var duration: Double
    var delay: Double = 0
    var easing: SyftEasing
    var repeats = false

    func progress(_ t: Double) -> Double {
        let local = t - delay
        if local <= 0 { return 0 }
        if repeats { return local.truncatingRemainder(dividingBy: duration) / duration }
        return min(1, local / duration)
    }
}

// MARK: - Drawing

/// Draws cells in a box of the reference's units fitted into a canvas.
struct SyftStage {
    /// The canvas point of the units' (0, 0).
    var origin: CGPoint
    /// Points per unit.
    var unit: CGFloat

    /// `box` (x, y, width, height in units) fitted into `size`, centred.
    init(box: (Double, Double, Double, Double), in size: CGSize) {
        let (x, y, w, h) = (CGFloat(box.0), CGFloat(box.1), CGFloat(box.2), CGFloat(box.3))
        let k: CGFloat = min(size.width / w, size.height / h)
        unit = k
        origin = CGPoint(x: (size.width - w * k) / 2 - x * k, y: (size.height - h * k) / 2 - y * k)
    }

    init(origin: CGPoint, unit: CGFloat) {
        self.origin = origin
        self.unit = unit
    }

    /// A cell (or bit) with its top left at (x, y), moved about its own centre.
    func cell(_ gc: GraphicsContext, x: Double, y: Double, size: Double = SyftCells.cell, radius: Double = SyftCells.radius,
              colour: Color, dx: Double = 0, dy: Double = 0, turn: Double = 0, scale: Double = 1, opacity: Double = 1) {
        guard opacity > 0.001, scale > 0.001 else { return }
        var g = gc
        g.opacity *= opacity
        g.translateBy(x: origin.x + (x + size / 2 + dx) * unit, y: origin.y + (y + size / 2 + dy) * unit)
        if turn != 0 { g.rotate(by: .degrees(turn)) }
        if scale != 1 { g.scaleBy(x: scale, y: scale) }
        let s = size * unit
        g.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: radius * unit, style: .circular),
               with: .color(colour))
    }

    func ticks(_ gc: GraphicsContext, dx: Double = 0, dy: Double = 0, opacity: Double = 1) {
        guard opacity > 0.001 else { return }
        var g = gc
        g.opacity *= opacity
        var p = Path()
        for (x1, y1, x2, y2) in SyftCells.ticks {
            p.move(to: CGPoint(x: origin.x + (x1 + dx) * unit, y: origin.y + (y1 + dy) * unit))
            p.addLine(to: CGPoint(x: origin.x + (x2 + dx) * unit, y: origin.y + (y2 + dy) * unit))
        }
        g.stroke(p, with: .color(Color(syft: SyftPalette.coral)), style: StrokeStyle(lineWidth: 1.2 * unit, lineCap: .round))
    }
}

// MARK: - The mark

/// The static pixel s, `height` points tall: the white tile's look on a light page and the dark tile's (with its mesh)
/// on a dark one, unless given a `look`; `oddOneOut`, its top right cell popped out in coral (empty pages, problems);
/// `mesh` with the automatic look, the light mesh (P6) or the night one (P3); `tile`, on a circle (an avatar) or the
/// app icon's rounded square. Bits from 48 points tall, unless told.
struct SyftMark: View {
    enum Tile { case circle, square }

    var height: CGFloat = 96
    var look: SyftCells.Look?
    var mesh: Bool?
    var bits: Bool?
    var oddOneOut = false
    var tile: Tile?
    var label: String?
    @Environment(\.colorScheme) private var scheme

    init(height: CGFloat = 96, look: SyftCells.Look? = nil, mesh: Bool? = nil, bits: Bool? = nil, oddOneOut: Bool = false,
         tile: Tile? = nil, label: String? = nil) {
        self.height = height
        self.look = look
        self.mesh = mesh
        self.bits = bits
        self.oddOneOut = oddOneOut
        self.tile = tile
        self.label = label
    }

    var body: some View {
        let art = Art(height: height, look: look, mesh: mesh, bits: bits, oddOneOut: oddOneOut, tile: tile, dark: scheme == .dark)
        Canvas { gc, size in art.draw(gc, size) }
            .frame(width: height * art.box.2 / art.box.3, height: height)
            .accessibilityElement()
            .accessibilityLabel(label ?? "")
            .accessibilityAddTraits(.isImage)
            .accessibilityHidden(label == nil)
    }

    /// What's drawn, and the box (in units) it covers.
    struct Art {
        var look: SyftCells.Look
        var mesh: Bool
        var bits: [SyftCells.Bit]
        var oddOneOut: Bool
        var tile: Tile?
        var box: (Double, Double, Double, Double)

        init(height: CGFloat, look: SyftCells.Look?, mesh: Bool?, bits: Bool?, oddOneOut: Bool, tile: Tile?, dark: Bool) {
            let resolved = look ?? (oddOneOut ? .ink : dark ? .sorted : mesh == true ? .segments : .light)
            self.look = resolved
            self.mesh = mesh ?? (look == nil && dark && !oddOneOut)
            self.oddOneOut = oddOneOut
            self.tile = tile
            let loose = !oddOneOut && (bits ?? (height >= 48))
            self.bits = !loose ? [] : resolved == .light ? SyftCells.bitsAbove : resolved == .segments ? SyftCells.bitsBelowSegments : SyftCells.bitsBelow
            var (x0, y0, x1, y1) = (0.0, 0.0, SyftCells.gridWidth - 1.4, SyftCells.gridHeight - 1.4)
            let reach = SyftCells.cell * 0.71
            for b in self.bits {
                x0 = min(x0, b.x - reach); x1 = max(x1, b.x + reach)
                y0 = min(y0, b.y - reach); y1 = max(y1, b.y + reach)
            }
            if oddOneOut { y0 = min(y0, -23); x1 = max(x1, 59) }
            let w = x1 - x0, h = y1 - y0
            if let tile {
                // The board's tiles leave about a fifth all round (an avatar's circle a little more).
                let side = max(w, h) / (tile == .circle ? 0.6 : 0.66)
                box = (x0 + w / 2 - side / 2, y0 + h / 2 - side / 2, side, side)
            } else {
                box = (x0 - 1, y0 - 1, w + 2, h + 2)
            }
        }

        func draw(_ gc: GraphicsContext, _ size: CGSize) {
            let stage = SyftStage(box: box, in: size)
            if let tile {
                let rect = CGRect(x: stage.origin.x + box.0 * stage.unit, y: stage.origin.y + box.1 * stage.unit,
                                  width: box.2 * stage.unit, height: box.3 * stage.unit)
                let shape = tile == .circle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: rect.width * 0.2237, style: .continuous)
                gc.fill(shape, with: .color(Color(syft: SyftPalette.tile)))
            }
            if mesh {
                for (x, y) in SyftCells.mesh { stage.cell(gc, x: x, y: y, colour: Color(syft: SyftPalette.mesh)) }
            }
            for b in bits {
                let colour = b.colour == SyftPalette.ink ? SyftPalette.base : b.colour
                stage.cell(gc, x: b.x - SyftCells.cell / 2, y: b.y - SyftCells.cell / 2, colour: Color(syft: colour), turn: b.turn)
            }
            for (i, c) in SyftCells.path.enumerated() where !(oddOneOut && i == 1) {
                stage.cell(gc, x: c.x, y: c.y, colour: SyftCells.colour(look, i))
            }
            if oddOneOut {
                let p = SyftCells.pop, c = SyftCells.path[1]
                stage.ticks(gc, dx: p.dx, dy: p.dy)
                stage.cell(gc, x: c.x, y: c.y, colour: Color(syft: SyftPalette.coral), dx: p.dx, dy: p.dy, turn: p.turn)
            }
        }
    }
}

/// "syft notes" as the logo writes it: "syft" in Archivo Black Italic, " notes" in Archivo Regular, −0.02 em.
struct SyftWordmark: View {
    var size: CGFloat = 28
    var colour: Color = .ink

    var body: some View {
        SyftWordmark.text(size: size, tracking: -0.02 * size)
            .foregroundStyle(colour)
            .accessibilityLabel("Syft Notes")
    }

    static func text(size: CGFloat, tracking: CGFloat) -> Text {
        let syft = Text("syft").font(.custom("ArchivoItalic-BlackItalic", fixedSize: size))
        let notes = Text(" notes").font(.custom("ArchivoRoman-Regular", fixedSize: size))
        return Text("\(syft)\(notes)").tracking(tracking)
    }
}

// MARK: - Splash screens

/// The whole screen while the app starts: the s assembles once and the wordmark rises (S1 Sort In on ink in the dark,
/// S2 Sieve Drop on white in the light), holds until the app is `ready` (at least 1.2 s, never more than 4 s), then
/// fades out over 250 ms and calls `onFinish`. It starts where the launch screen leaves off: the same background, and
/// the s's grid the same size in the same place (`unit`, LaunchMark in Assets.xcassets).
struct SyftSplash: View {
    enum Variant { case sortIn, sieveDrop, popBack }

    var variant: Variant
    var ready: Bool
    var minSeconds = 1.2
    var maxSeconds = 4.0
    var onFinish: () -> Void

    /// Points per unit: the grid is 48 × 56 units, 172.8 × 201.6 points, as LaunchMark is drawn.
    static let unit: CGFloat = 3.6

    @State private var start = Date()
    @State private var leaving = false
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        let frozen = SyftSplash.frozenAt
        ZStack {
            background.ignoresSafeArea()
            if still {
                Canvas { gc, size in Self.draw(variant, gc, size, t: nil) }
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .onAppear { withAnimation(.easeOut(duration: 0.25)) { shown = true } }
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: leaving || frozen != nil)) { context in
                    let t = frozen ?? context.date.timeIntervalSince(start)
                    Canvas { gc, size in Self.draw(variant, gc, size, t: t) }
                        .ignoresSafeArea()
                }
            }
        }
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Syft Notes")
        .accessibilityAddTraits(.isImage)
        .task(id: ready) {
            guard frozen == nil, !leaving else { return }
            let elapsed = Date().timeIntervalSince(start)
            let wait = ready ? max(0, minSeconds - elapsed) : max(0, maxSeconds - elapsed)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .seconds(0.25))
            onFinish()
        }
    }

    private var background: Color {
        switch variant {
        case .sortIn: Color(syft: SyftPalette.ink)
        case .sieveDrop: Color(syft: SyftPalette.white)
        case .popBack: Color(syft: SyftPalette.paper)
        }
    }

    /// `-splash-at <seconds>` (debug builds): the splash held at that moment, for pictures.
    static let frozenAt: Double? = DebugLaunch.value("-splash-at").flatMap(Double.init)

    // The reference's 100 × 200 phone: the grid's corner at (26.7, 70), the wordmark's baseline at 152, centred at 50.
    static let gridX = 26.7, gridY = 70.0

    static func draw(_ variant: Variant, _ gc: GraphicsContext, _ size: CGSize, t: Double?) {
        let k = unit
        // The grid's middle at the screen's middle, as the launch screen has it.
        let grid = SyftStage(origin: CGPoint(x: size.width / 2 - 24 * k, y: size.height / 2 - 28 * k), unit: k)
        let phone = SyftStage(origin: CGPoint(x: grid.origin.x - gridX * k, y: grid.origin.y - gridY * k), unit: k)
        switch variant {
        case .sortIn: sortIn(gc, grid, t)
        case .sieveDrop: sieveDrop(gc, grid, phone, size, t)
        case .popBack: popBack(gc, grid, t, cells: Color(syft: SyftPalette.ink))
        }
        let words: (SyftTrack, SyftTrack, SyftTiming) = switch variant {
        case .sortIn: (Self.word(0.36, 0.46), Self.wordRise(0.36, 0.46), SyftTiming(duration: 5, easing: .easeOut))
        case .sieveDrop: (Self.word(0.40, 0.50), Self.wordRise(0.40, 0.50), SyftTiming(duration: 5, easing: .easeOut))
        case .popBack: (Self.word(0.56, 0.66), Self.wordRise(0.56, 0.66), SyftTiming(duration: 4.5, easing: .easeOut))
        }
        let p = t.map { words.2.progress($0) } ?? 1
        let colour = Color(syft: variant == .sortIn ? SyftPalette.white : SyftPalette.ink)
        drawWordmark(gc, size, phone, opacity: words.0.value(p, words.2.easing), rise: words.1.value(p, words.2.easing), colour: colour)
    }

    private static func word(_ from: Double, _ to: Double) -> SyftTrack { SyftTrack([(0, 0), (from, 0), (to, 1), (1, 1)]) }
    private static func wordRise(_ from: Double, _ to: Double) -> SyftTrack { SyftTrack([(0, 4), (from, 4), (to, 0), (1, 0)]) }

    static func drawWordmark(_ gc: GraphicsContext, _ size: CGSize, _ phone: SyftStage, opacity: Double, rise: Double, colour: Color) {
        guard opacity > 0.001 else { return }
        let k = phone.unit
        let text = gc.resolve(SyftWordmark.text(size: 13 * k, tracking: -0.3 * k).foregroundStyle(colour))
        let measured = text.measure(in: size)
        let baseline = text.firstBaseline(in: size)
        var g = gc
        g.opacity *= opacity
        let x = phone.origin.x + 50 * k - measured.width / 2
        let y = phone.origin.y + (152 + rise) * k - baseline
        g.draw(text, in: CGRect(origin: CGPoint(x: x, y: y), size: measured))
    }

    // S1 · Sort In (5 s, cubic-bezier(.22,.9,.3,1)): each cell falls in spinning from (dx, dy) with a small bounce; the
    // bottom rows land first. The dark mesh is there from the start.
    static let sortInCells: [(dx: Double, dy: Double, turn: Double, delay: Double)] = [
        (-10, -92, 70, 0.64), (8, -86, -60, 0.76), (-12, -94, 90, 0.74), (10, -90, -110, 0.78), (-8, -84, 70, 0.72),
        (12, -92, -80, 0.80), (14, -100, -100, 0.62), (-6, -88, 50, 0.66), (10, -96, 110, 0.52), (-14, -104, -80, 0.55),
        (12, -95, 60, 0.40), (-8, -112, -120, 0.44), (15, -100, 80, 0.38), (-12, -108, -50, 0.42), (-14, -100, -70, 0.30),
        (9, -118, 100, 0.27), (-10, -110, 70, 0.16), (6, -120, -110, 0.20), (8, -110, 80, 0), (-12, -120, -60, 0.05),
        (14, -105, 120, 0.02), (-6, -125, -90, 0.08), (10, -115, 45, 0.04), (12, -105, 90, 0.14),
    ]
    private static let sortInEasing = SyftEasing.bezier(0.22, 0.9, 0.3, 1)
    private static let sortInOpacity = SyftTrack([(0, 0), (0.06, 1), (0.86, 1), (1, 1)])
    private static let fallen = SyftTrack([(0, 1), (0.26, 0), (0.29, 0), (0.32, 0), (0.86, 0), (1, 0)])

    static func sortIn(_ gc: GraphicsContext, _ grid: SyftStage, _ t: Double?) {
        for (x, y) in SyftCells.mesh { grid.cell(gc, x: x, y: y, colour: Color(syft: SyftPalette.meshDark)) }
        for (i, c) in SyftCells.path.enumerated() {
            let s = sortInCells[i]
            let colour = SyftCells.colour(.sorted, i)
            guard let t else { grid.cell(gc, x: c.x, y: c.y, colour: colour); continue }
            let timing = SyftTiming(duration: 5, delay: s.delay, easing: sortInEasing)
            let p = timing.progress(t)
            let bounce = SyftTrack([(0, s.dy), (0.26, 0), (0.29, -1.5), (0.32, 0), (0.86, 0), (1, 0)])
            let f = fallen.value(p, sortInEasing)
            grid.cell(gc, x: c.x, y: c.y, colour: colour, dx: s.dx * f, dy: bounce.value(p, sortInEasing), turn: s.turn * f,
                      opacity: sortInOpacity.value(p, sortInEasing))
        }
    }

    // S2 · Sieve Drop (5 s): the light mesh fades in, six bits fall straight through, the s lights up along its path
    // (0.5 s + index × 0.05 s, cubic-bezier(.3,.7,.4,1)). The bits keep falling while it waits: sifting.
    static let sieveBits: [(x: Double, colour: UIColor, turn: Double, duration: Double, delay: Double)] = [
        (30, SyftPalette.coral, 220, 2.6, 0), (46, SyftPalette.sky, -180, 3.1, 0.7), (58, SyftPalette.lilac, 260, 2.8, 1.4),
        (70, SyftPalette.mustard, -240, 3.3, 0.3), (38, SyftPalette.ink, 200, 2.9, 2), (64, SyftPalette.coral, -200, 2.7, 2.4),
    ]
    private static let popEasing = SyftEasing.bezier(0.3, 0.7, 0.4, 1)
    private static let popOpacity = SyftTrack([(0, 0), (0.07, 1), (0.86, 1), (1, 1)])
    private static let popScale = SyftTrack([(0, 0.3), (0.07, 1.18), (0.11, 1), (0.86, 1), (1, 1)])
    private static let meshIn = SyftTrack([(0, 0), (0.08, 1), (1, 1)])

    static func sieveDrop(_ gc: GraphicsContext, _ grid: SyftStage, _ phone: SyftStage, _ size: CGSize, _ t: Double?) {
        let mesh = t.map { meshIn.value(SyftTiming(duration: 5, easing: .ease).progress($0), .ease) } ?? 1
        for (x, y) in SyftCells.mesh { grid.cell(gc, x: x, y: y, colour: Color(syft: SyftPalette.meshLight), opacity: mesh) }
        if let t {
            // The bits fall from just above the screen to below it (the reference's -10 to 230 of its 200-tall phone),
            // across the whole screen whatever its height.
            let fall = size.height / 200
            for b in sieveBits {
                let p = SyftTiming(duration: b.duration, delay: b.delay, easing: .linear, repeats: true).progress(t)
                let s = 5.6 * phone.unit
                var g = gc
                g.translateBy(x: phone.origin.x + (b.x + 2.8) * phone.unit, y: (-10 + 240 * p) * fall + s / 2)
                g.rotate(by: .degrees(b.turn * p))
                g.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s), cornerRadius: 1.6 * phone.unit, style: .circular),
                       with: .color(Color(syft: b.colour)))
            }
        }
        for (i, c) in SyftCells.path.enumerated() {
            let colour = SyftCells.colour(.segments, i)
            guard let t else { grid.cell(gc, x: c.x, y: c.y, colour: colour); continue }
            let p = SyftTiming(duration: 5, delay: 0.5 + Double(i) * 0.05, easing: popEasing).progress(t)
            grid.cell(gc, x: c.x, y: c.y, colour: colour, scale: popScale.value(p, popEasing), opacity: popOpacity.value(p, popEasing))
        }
    }

    // S3 · Pop Back (4.5 s): the ink s pops in a row at a time (0.2 s + row × 0.06 s), then the coral bit hops home into
    // the top right slot with three ticks.
    private static let inOpacity = SyftTrack([(0, 0), (0.10, 1), (0.88, 1), (1, 1)])
    private static let inScale = SyftTrack([(0, 0), (0.10, 1.12), (0.14, 1), (0.88, 1), (1, 1)])
    private static let hopEasing = SyftEasing.bezier(0.4, 0, 0.2, 1)
    private static let hopOpacity = SyftTrack([(0, 0), (0.20, 0), (0.26, 1), (0.88, 1), (1, 1)])
    private static let hopX = SyftTrack([(0, 10), (0.20, 10), (0.26, 10), (0.40, 4), (0.50, 0), (0.54, 0), (0.58, 0), (0.88, 0), (1, 0)])
    private static let hopY = SyftTrack([(0, -14), (0.20, -14), (0.26, -14), (0.40, -22), (0.50, 0), (0.54, -2.5), (0.58, 0), (0.88, 0), (1, 0)])
    private static let hopTurn = SyftTrack([(0, 25), (0.20, 25), (0.26, 25), (0.40, -12), (0.50, 0), (0.54, 0), (0.58, 0), (0.88, 0), (1, 0)])
    private static let tick = SyftTrack([(0, 0), (0.49, 0), (0.53, 1), (0.66, 0), (1, 0)])

    static func popBack(_ gc: GraphicsContext, _ grid: SyftStage, _ t: Double?, cells: Color) {
        for (i, c) in SyftCells.path.enumerated() where i != 1 {
            guard let t else { grid.cell(gc, x: c.x, y: c.y, colour: cells); continue }
            let p = SyftTiming(duration: 4.5, delay: 0.2 + c.y / 8 * 0.06, easing: popEasing).progress(t)
            grid.cell(gc, x: c.x, y: c.y, colour: cells, scale: inScale.value(p, popEasing), opacity: inOpacity.value(p, popEasing))
        }
        let home = SyftCells.path[1]
        let coral = Color(syft: SyftPalette.coral)
        guard let t else { grid.cell(gc, x: home.x, y: home.y, colour: coral); return }
        let p = SyftTiming(duration: 4.5, easing: hopEasing).progress(t)
        grid.cell(gc, x: home.x, y: home.y, colour: coral, dx: hopX.value(p, hopEasing), dy: hopY.value(p, hopEasing),
                  turn: hopTurn.value(p, hopEasing), opacity: hopOpacity.value(p, hopEasing))
        grid.ticks(gc, opacity: tick.value(SyftTiming(duration: 4.5, easing: .easeOut).progress(t), .easeOut))
    }
}

/// The splash as the app starts, after the launch screen: Sort In in the dark, Sieve Drop in the light, until the
/// library's been asked whether this phone still belongs (or there's none to ask), then gone.
struct StartSplash: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @State private var shown = true

    var body: some View {
        if shown {
            SyftSplash(variant: scheme == .dark ? .sortIn : .sieveDrop, ready: app.phase != .checking) { shown = false }
        }
    }
}

/// S3 Pop Back on a page, without its screen or words: setup's welcome (the ink s pops in, its coral bit hops home),
/// played once. Ink on a light page, paper on a dark one.
struct SyftHello: View {
    var height: CGFloat = 120
    @State private var start = Date()
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var still

    /// The s and the hop above it, in the reference phone's units.
    private static let box = (22.0, 44.0, 64.0, 84.0)

    var body: some View {
        Group {
            if still || done {
                Canvas { gc, size in Self.draw(gc, size, t: nil) }
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    Canvas { gc, size in Self.draw(gc, size, t: t) }
                }
                .task {
                    try? await Task.sleep(for: .seconds(4.5))
                    done = true
                }
            }
        }
        .frame(width: height * Self.box.2 / Self.box.3, height: height)
        .accessibilityElement()
        .accessibilityLabel("Syft Notes")
        .accessibilityAddTraits(.isImage)
    }

    private static func draw(_ gc: GraphicsContext, _ size: CGSize, t: Double?) {
        let phone = SyftStage(box: box, in: size)
        let grid = SyftStage(origin: CGPoint(x: phone.origin.x + SyftSplash.gridX * phone.unit, y: phone.origin.y + SyftSplash.gridY * phone.unit),
                             unit: phone.unit)
        SyftSplash.popBack(gc, grid, t, cells: Color(syft: SyftPalette.cell))
    }
}

// MARK: - Loaders

/// A loader: L1 Path Trace (a page waiting, a recording), L2 Hopping Bits (inline and in buttons), L3 Pixel Progress
/// (imports and syncing; with `progress`, the cells it has reached), L4 Row Shuffle (pull to refresh; with `progress`,
/// dealt in as far as the pull has come). `running: false` holds it still (a paused recording). VoiceOver: "Loading".
struct SyftLoader: View {
    enum Kind { case pathTrace, hoppingBits, pixelProgress, rowShuffle }

    var kind: Kind
    var height: CGFloat
    var progress: Double?
    var running = true
    /// Path Trace on its own dark tile, as the board has it.
    var tile = false
    var label: LocalizedStringKey = "Loading"

    init(_ kind: Kind, height: CGFloat? = nil, progress: Double? = nil, running: Bool = true, tile: Bool = false,
         label: LocalizedStringKey = "Loading") {
        self.kind = kind
        self.height = height ?? (kind == .pathTrace ? 72 : kind == .pixelProgress ? 10 : kind == .rowShuffle ? 34 : 20)
        self.progress = progress
        self.running = running
        self.tile = tile
        self.label = label
    }

    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.colorScheme) private var scheme

    private var box: (Double, Double, Double, Double) {
        switch kind {
        case .pathTrace: tile ? (-26.7, -22.7, 100, 100) : (-4, -4, 54.6, 62.6)
        case .hoppingBits: (21, 28, 58, 29)
        case .pixelProgress: (9.7, 43, 80.6, 8.6)
        case .rowShuffle: (0, 12, 100, 76)
        }
    }

    /// Whether it moves by itself (not a value drawn as it is, not held).
    private var loops: Bool { running && (progress == nil || kind == .pathTrace || kind == .hoppingBits) }

    var body: some View {
        let box = box, kind = kind, progress = progress, tile = tile, dark = tile || scheme == .dark
        Group {
            if !loops {
                Canvas { gc, size in Self.draw(kind, gc, size, box: box, t: nil, progress: progress, tile: tile, dark: dark) }
            } else if still {
                // Less motion: the finished drawing, breathing.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    Canvas { gc, size in Self.draw(kind, gc, size, box: box, t: nil, progress: progress, tile: tile, dark: dark) }
                        .opacity(0.725 + 0.275 * cos(t * .pi))
                }
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    Canvas { gc, size in Self.draw(kind, gc, size, box: box, t: t, progress: progress, tile: tile, dark: dark) }
                }
            }
        }
        .frame(width: height * box.2 / box.3, height: height)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    static func draw(_ kind: Kind, _ gc: GraphicsContext, _ size: CGSize, box: (Double, Double, Double, Double), t: Double?,
                     progress: Double?, tile: Bool, dark: Bool) {
        let stage = SyftStage(box: box, in: size)
        switch kind {
        case .pathTrace: pathTrace(gc, stage, t, tile: tile, dark: dark)
        case .hoppingBits: hoppingBits(gc, stage, t)
        case .pixelProgress: pixelProgress(gc, stage, t, progress: progress, dark: dark)
        case .rowShuffle: rowShuffle(gc, stage, t, progress: progress, dark: dark)
        }
    }

    // L1 · Path Trace (2 s, linear): the empty grid, the unlit s, and a lit trail along it, each cell 0.075 s after the
    // one before. On a light page the unlit s is the light mesh's colour and there's no grid.
    private static let trace = SyftTrack([(0, 0), (0.06, 1), (0.30, 1), (0.52, 0), (1, 0)])

    static func pathTrace(_ gc: GraphicsContext, _ stage: SyftStage, _ t: Double?, tile: Bool, dark: Bool) {
        if tile {
            let k = stage.unit
            let rect = CGRect(x: stage.origin.x - 26.7 * k, y: stage.origin.y - 22.7 * k, width: 100 * k, height: 100 * k)
            gc.fill(Path(roundedRect: rect, cornerRadius: 12.3 * k, style: .circular), with: .color(Color(syft: SyftPalette.ink)))
        }
        if dark {
            for (x, y) in SyftCells.mesh { stage.cell(gc, x: x, y: y, colour: Color(syft: SyftPalette.traceMeshDark)) }
        }
        let ghost = Color(syft: dark ? SyftPalette.ghostDark : SyftPalette.meshLight)
        for (x, y) in SyftCells.path { stage.cell(gc, x: x, y: y, colour: ghost) }
        for (i, c) in SyftCells.path.enumerated() {
            let lit = t.map { trace.value(SyftTiming(duration: 2, delay: Double(i) * 0.075, easing: .linear, repeats: true).progress($0), .linear) } ?? 1
            stage.cell(gc, x: c.x, y: c.y, colour: SyftCells.colour(.sorted, i), opacity: lit)
        }
    }

    // L2 · Hopping Bits (1.2 s, ease-in-out): four 10-square bits hop and flip in a wave, 0.12 s apart.
    private static let hoppers: [(x: Double, colour: UIColor)] = [(24, SyftPalette.lilac), (38, SyftPalette.sky), (52, SyftPalette.coral), (66, SyftPalette.mustard)]
    private static let hop = SyftTrack([(0, 0), (0.30, -14), (0.60, 0), (1, 0)])
    private static let flip = SyftTrack([(0, 0), (0.30, 90), (0.60, 0), (1, 0)])

    static func hoppingBits(_ gc: GraphicsContext, _ stage: SyftStage, _ t: Double?) {
        for (i, h) in hoppers.enumerated() {
            let p = t.map { SyftTiming(duration: 1.2, delay: Double(i) * 0.12, easing: .easeInOut, repeats: true).progress($0) } ?? 0
            stage.cell(gc, x: h.x, y: 44, size: 10, radius: 2.8, colour: Color(syft: h.colour), dy: hop.value(p, .easeInOut),
                       turn: flip.value(p, .easeInOut))
        }
    }

    // L3 · Pixel Progress (3 s, ease-out): ten cells fill left to right 0.15 s apart, then wipe.
    private static let progressColours: [UIColor] = [SyftPalette.lilac, SyftPalette.lilac, SyftPalette.lilac, SyftPalette.sky, SyftPalette.sky,
                                                    SyftPalette.coral, SyftPalette.coral, SyftPalette.coral, SyftPalette.mustard, SyftPalette.mustard]
    private static let fillOpacity = SyftTrack([(0, 0), (0.06, 1), (0.78, 1), (0.88, 0), (1, 0)])
    private static let fillScale = SyftTrack([(0, 0.4), (0.06, 1), (0.78, 1), (0.88, 1), (1, 1)])

    /// How many of the ten cells a real value lights: any start lights the first, all ten only when it's done.
    static func lit(_ progress: Double) -> Int { min(10, Int((max(0, progress) * 10 - 1e-9).rounded(.up))) }

    static func pixelProgress(_ gc: GraphicsContext, _ stage: SyftStage, _ t: Double?, progress: Double?, dark: Bool) {
        let mesh = Color(syft: dark ? SyftPalette.meshDark : SyftPalette.meshLight)
        let lit = progress.map(Self.lit)
        for i in 0..<10 {
            let x = 10.7 + Double(i) * 8
            stage.cell(gc, x: x, y: 44, colour: mesh)
            let colour = Color(syft: progressColours[i])
            if let lit {
                if i < lit { stage.cell(gc, x: x, y: 44, colour: colour) }
            } else if let t {
                let p = SyftTiming(duration: 3, delay: Double(i) * 0.15, easing: .easeOut, repeats: true).progress(t)
                stage.cell(gc, x: x, y: 44, colour: colour, scale: fillScale.value(p, .easeOut), opacity: fillOpacity.value(p, .easeOut))
            } else {
                stage.cell(gc, x: x, y: 44, colour: colour)
            }
        }
    }

    // L4 · Row Shuffle (2.6 s, cubic-bezier(.5,0,.2,1)): the chunky s (12-square cells, corners 3.5, at 23, 16) deals itself
    // in a row at a time from alternate sides, 0.08 s apart, and out again. The bottom row: ink, or mustard in the dark.
    private static let rows: [(from: Double, delay: Double, colour: UIColor?, cells: [(Double, Double)])] = [
        (-1, 0, SyftPalette.coral, [(14, 0), (28, 0), (42, 0)]),
        (1, 0.08, SyftPalette.mustard, [(0, 14)]),
        (-1, 0.16, SyftPalette.sky, [(14, 28), (28, 28)]),
        (1, 0.24, SyftPalette.lilac, [(42, 42)]),
        (-1, 0.32, nil, [(0, 56), (14, 56), (28, 56)]),
    ]
    private static let shuffleEasing = SyftEasing.bezier(0.5, 0, 0.2, 1)
    private static let slide = SyftTrack([(0, -80), (0.16, 0), (0.70, 0), (0.86, 80), (1, 80)])
    private static let shown = SyftTrack([(0, 0), (0.16, 1), (0.70, 1), (0.86, 0), (1, 0)])

    static func rowShuffle(_ gc: GraphicsContext, _ stage: SyftStage, _ t: Double?, progress: Double?, dark: Bool) {
        let base = dark ? SyftPalette.mustard : SyftPalette.ink
        // Looping, it comes in with every row in place (a row is in from 16% to 70% of its loop), so a pull that ended
        // with the s dealt carries straight on.
        let inPlace = 0.16 * 2.6 + 0.32
        for (i, row) in rows.enumerated() {
            var dx = 0.0, opacity = 1.0
            if let progress {
                let f = min(1, max(0, progress * 5 - Double(i)))
                let eased = 1 - (1 - f) * (1 - f)
                dx = row.from * 80 * (1 - eased)
                opacity = f
            } else if let t {
                let p = SyftTiming(duration: 2.6, delay: row.delay - inPlace, easing: shuffleEasing, repeats: true).progress(t)
                dx = -row.from * slide.value(p, shuffleEasing)
                opacity = shown.value(p, shuffleEasing)
            }
            for (x, y) in row.cells {
                stage.cell(gc, x: 23 + x, y: 16 + y, size: 12, radius: 3.5, colour: Color(syft: row.colour ?? base), dx: dx, opacity: opacity)
            }
        }
    }
}

// MARK: - Pull to refresh

extension View {
    /// Pull to refresh with the pixel s: Row Shuffle deals the s in as the page is pulled and shuffles until `action`
    /// is done (the system's spinner is hidden: StudyStashApp sets it clear).
    func syftRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View { modifier(SyftRefresh(action: action)) }
}

private struct SyftRefresh: ViewModifier {
    var action: @Sendable () async -> Void
    @State private var pull: CGFloat = 0
    @State private var refreshing = false

    func body(content: Content) -> some View {
        content
            .refreshable {
                refreshing = true
                await action()
                refreshing = false
            }
            .onScrollGeometryChange(for: CGFloat.self) { max(0, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, new in
                pull = new
            }
            .overlay(alignment: .top) {
                if refreshing || pull > 6 {
                    SyftLoader(.rowShuffle, height: 34, progress: refreshing ? nil : min(1, pull / 90))
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }
}

#if DEBUG
/// The seven moving pieces and the marks, side by side (`-show components:5`).
struct SyftGallery: View {
    @State private var round = 0
    @State private var progress = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SyftWordmark(size: 34)
            HStack(alignment: .bottom, spacing: 16) {
                SyftMark(height: 110)
                SyftMark(height: 96, oddOneOut: true)
                SyftMark(height: 96, mesh: true, bits: true)
            }
            HStack(spacing: 16) {
                SyftMark(height: 64, tile: .square)
                SyftMark(height: 56, bits: true, tile: .circle)
                SyftMark(height: 30, tile: .circle)
                SyftHello(height: 80).id(round)
            }
            HStack(spacing: 20) {
                SyftLoader(.pathTrace, height: 96, tile: true)
                SyftLoader(.pathTrace, height: 72)
                SyftLoader(.rowShuffle, height: 60)
            }
            HStack(spacing: 20) {
                SyftLoader(.hoppingBits, height: 28)
                SyftLoader(.pixelProgress, height: 12)
            }
            HStack(spacing: 12) {
                SyftLoader(.pixelProgress, height: 12, progress: progress)
                Slider(value: $progress)
            }
            Button("Play again") { round += 1 }.buttonStyle(.pill(small: true))
        }
    }
}
#endif
