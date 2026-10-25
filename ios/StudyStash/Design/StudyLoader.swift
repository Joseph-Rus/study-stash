import SwiftUI

/// The app's one loading mark, the desktop's Spinner: an arc going round a faint ring of its own colour, growing long
/// and short again as it turns. In the colour it's given (ink by default; `.inkSubtle` beside muted words, `.surface`
/// on an ink button). Reduce Motion: a still ring with a short arc. VoiceOver says "Loading" unless given words.
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

    /// The desktop's numbers (Spinner.cs).
    private static let period = 1.4, shortest = 20.0, longest = 270.0, turnSeconds = 1.8, ringOpacity = 0.15
    private static let stillAt = 1.06

    var body: some View {
        Group {
            if still {
                ring(at: Self.stillAt)
            } else {
                TimelineView(.animation) { context in
                    ring(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size.points, height: size.points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func ring(at seconds: Double) -> some View {
        let (start, sweep) = Self.pose(seconds)
        let thickness = size.thickness
        return Canvas { gc, area in
            let r = min(area.width, area.height) / 2 - thickness / 2
            let c = CGPoint(x: area.width / 2, y: area.height / 2)
            let style = StrokeStyle(lineWidth: thickness, lineCap: .round)
            gc.stroke(Path { $0.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false) },
                      with: .color(color.opacity(Self.ringOpacity)), style: style)
            gc.stroke(Path { $0.addArc(center: c, radius: r, startAngle: .degrees(start - 90),
                                       endAngle: .degrees(start - 90 + sweep), clockwise: false) },
                      with: .color(color), style: style)
        }
    }

    /// Where the arc begins (degrees clockwise from the top) and how far round it goes, `seconds` in.
    static func pose(_ seconds: Double) -> (start: Double, sweep: Double) {
        let grow = longest - shortest
        let periods = seconds / period, done = periods.rounded(.down), into = periods - done
        var back = done * grow + seconds / turnSeconds * 360
        let front: Double
        if into < 0.5 {
            front = back + shortest + grow * ease(into * 2)
        } else {
            front = back + longest
            back += grow * ease(into * 2 - 1)
        }
        let start = back.truncatingRemainder(dividingBy: 360)
        return (start < 0 ? start + 360 : start, front - back)
    }

    private static func ease(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
