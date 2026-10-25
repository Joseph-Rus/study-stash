import SwiftUI

/// The app's one loading mark: three drops drifting round each other, flowing together into one and parting again like
/// liquid. In the colour it's given (ink by default; `.inkSubtle` beside muted words,
/// `.surface` on an ink button), flat, no gradient. Reduce Motion: one still frame. VoiceOver says "Loading" unless
/// given words.
struct StudyLoader: View {
    enum Size {
        /// Beside words or inside a button: 14 points.
        case inline
        /// Where a page's content will be: 22 points.
        case page
        /// A whole screen waiting: 34 points.
        case screen

        var points: CGFloat {
            switch self {
            case .inline: 14
            case .page: 22
            case .screen: 34
            }
        }
        /// The old ring's line width, kept for callers that size things by it.
        var thickness: CGFloat {
            switch self {
            case .inline: 2
            case .page: 2.5
            case .screen: 3
            }
        }
    }

    var size: Size = .page
    var color: Color = .ink
    var label: LocalizedStringKey = "Loading"

    init(_ size: Size = .page, color: Color = .ink, label: LocalizedStringKey = "Loading") {
        self.size = size
        self.color = color
        self.label = label
    }

    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        Group {
            if still {
                drawing(at: nil)
            } else {
                TimelineView(.animation) { context in
                    drawing(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size.points, height: size.points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func drawing(at t: Double?) -> some View {
        let color = color
        return Canvas { gc, area in Self.liquid(t, color, &gc, area) }
    }

    /// Three drops drifting round each other, pulling together into one and parting again like liquid (the drops are
    /// softened and cut at half, so where they meet they flow into one flat shape).
    static func liquid(_ t: Double?, _ color: Color, _ gc: inout GraphicsContext, _ area: CGSize) {
        let t = t ?? 0.85   // still: the three drops apart
        let s = min(area.width, area.height), c = CGPoint(x: area.width / 2, y: area.height / 2)
        let drop = s * 0.145
        // How far out the drops are: together, apart, together, on a slow wave.
        let wave: Double = 0.5 - 0.5 * cos(t * 2 * .pi / 2.4)
        let apart: CGFloat = s * CGFloat(0.05 + 0.26 * wave)
        gc.addFilter(.alphaThreshold(min: 0.5, color: color))
        gc.addFilter(.blur(radius: s * 0.06))
        gc.drawLayer { layer in
            for i in 0..<3 {
                let n = Double(i)
                let wander: Double = 0.35 * sin(t * 1.3 + n * 2)
                let a: Double = t * 2 * .pi / 1.9 + n * 2 * .pi / 3 + wander
                let out: Double = 1 + 0.18 * sin(t * 2.1 + n * 1.7)
                let r: CGFloat = apart * CGFloat(out)
                let p = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
                let d: CGFloat = drop * CGFloat(1 + 0.1 * sin(t * 2.7 + n))
                layer.fill(Path(ellipseIn: CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)), with: .color(.black))
            }
        }
    }
}
