import SwiftUI
import WidgetKit

// The look's pieces as a widget can draw them (the widget extension has the tokens, the type and the icons, not the
// app's Components.swift): a class's highlight and swatch, the record dot, and the inks. A widget is drawn ahead of
// time and can't run the app's text renderer, so the highlight is a shape behind one line of words. Compiled into the
// app too, for the widget gallery. On a tinted or clear Home Screen and on the Lock Screen the system draws a widget
// in one colour: there the highlight is a faint wash and the inks the system's own levels.

extension EnvironmentValues {
    /// The widget is drawn in its own colours (not tinted, clear or on the Lock Screen). Set by each widget's root
    /// from the system's rendering mode; the gallery sets it to show the Lock Screen's look.
    @Entry var widgetFullColor = true
}

/// The three inks, or the system's levels where the widget is drawn in one colour.
struct Inks {
    var full: Bool
    var ink: AnyShapeStyle { full ? AnyShapeStyle(Color.ink) : AnyShapeStyle(.primary) }
    var muted: AnyShapeStyle { full ? AnyShapeStyle(Color.inkMuted) : AnyShapeStyle(.secondary) }
    var subtle: AnyShapeStyle { full ? AnyShapeStyle(Color.inkSubtle) : AnyShapeStyle(.secondary) }
    /// "Was due…": the late red, only in colour.
    var late: AnyShapeStyle { full ? AnyShapeStyle(Color.late) : AnyShapeStyle(.primary) }
}

/// A highlighter's pass behind words: a box with each corner rounded its own way (the desktop's radii, in ems), as
/// the app's `Highlight` draws it.
struct MarkerSwipe: Shape {
    var em: CGFloat
    func path(in r: CGRect) -> Path {
        let tl = CGSize(width: 0.28 * em, height: 0.5 * em), tr = CGSize(width: 0.55 * em, height: 0.3 * em)
        let br = CGSize(width: 0.35 * em, height: 0.55 * em), bl = CGSize(width: 0.6 * em, height: 0.35 * em)
        let k: CGFloat = 0.5523
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl.width, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr.width, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + tr.height),
                   control1: CGPoint(x: r.maxX - tr.width * (1 - k), y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + tr.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br.height))
        p.addCurve(to: CGPoint(x: r.maxX - br.width, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - br.height * (1 - k)), control2: CGPoint(x: r.maxX - br.width * (1 - k), y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bl.width, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - bl.height),
                   control1: CGPoint(x: r.minX + bl.width * (1 - k), y: r.maxY), control2: CGPoint(x: r.minX, y: r.maxY - bl.height * (1 - k)))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl.height))
        p.addCurve(to: CGPoint(x: r.minX + tl.width, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + tl.height * (1 - k)), control2: CGPoint(x: r.minX + tl.width * (1 - k), y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// A class's name marked with its highlighter, on one line (an event's class, the class recording). Nil hue is no
/// class: the grey wash. As the app's `Highlight`: the words a little in, the swipe a little past them.
struct WidgetHighlight: View {
    var text: String
    var hue: Highlighter?
    var style: AppText
    @Environment(\.widgetFullColor) private var full
    @ScaledMetric private var em: CGFloat

    init(_ text: String, hue: Highlighter?, style: AppText = .folder) {
        self.text = text
        self.hue = hue
        self.style = style
        _em = ScaledMetric(wrappedValue: style.spec.compactSize ?? style.spec.size, relativeTo: style.spec.relativeTo)
    }

    var body: some View {
        Text(text)
            .textStyle(style)
            .lineLimit(1)
            .foregroundStyle(Inks(full: full).ink)
            .padding(.horizontal, 0.18 * em)
            .background {
                MarkerSwipe(em: em)
                    .fill(full ? hue?.highlight ?? Highlighter.none : Color.primary.opacity(0.2))
                    .padding(.horizontal, -0.1 * em)
                    .padding(.top, -0.04 * em)
                    .padding(.bottom, -0.02 * em)
                    .widgetAccentable()
            }
    }
}

/// A class's colour beside its name, as the desktop's Coming up shows it: a small mark, a touch crooked (9 × 7; not
/// small, 14 × 10). Nil is no class: the desktop's grey.
struct WidgetSwatch: View {
    var hue: Highlighter?
    var small = true
    @Environment(\.widgetFullColor) private var full

    init(_ hue: Highlighter?, small: Bool = true) {
        self.hue = hue
        self.small = small
    }

    var body: some View {
        let k: CGFloat = small ? 0.7 : 1
        UnevenRoundedRectangle(topLeadingRadius: 2 * k, bottomLeadingRadius: 5 * k, bottomTrailingRadius: 3 * k, topTrailingRadius: 4 * k)
            .fill(full ? hue?.swatch ?? Highlighter.noneSwatch : Color.primary.opacity(0.5))
            .frame(width: small ? 9 : 14, height: small ? 7 : 10)
            .rotationEffect(.degrees(-8))
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

/// The record dot, as the desktop's sidebar shows what's recording: a small red dot; paused, a red ring.
struct LiveDot: View {
    var paused = false
    var size: CGFloat = 9
    var body: some View {
        Group {
            if paused {
                Circle().strokeBorder(Color.record, lineWidth: max(1.5, size / 6))
            } else {
                Circle().fill(Color.record)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Highlighter {
    /// A highlighter by the name the Glance keeps ("yellow"), or nil.
    init?(name: String?) {
        guard let name else { return nil }
        self.init(rawValue: name)
    }
}

extension Color {
    /// A token as it is in light or dark, fixed: for what the system paints itself (a Live Activity's background).
    static func resolved(_ ui: UIColor, dark: Bool) -> Color {
        Color(uiColor: ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)))
    }
}
