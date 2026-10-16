import SwiftUI
import UIKit

// One typeface, Atkinson Hyperlegible Next (the desktop's own TTFs, in Resources/Fonts, registered in project.yml),
// with weight carrying the hierarchy and every figure one width (tabular), as on the desktop. Each style is the
// desktop's (tokens.css `--text-*` and Styles.axaml) at the same size, and grows with Dynamic Type beside the iOS
// style named for it. Page titles are smaller on a phone than on a computer or an iPad (`compact`). Also compiled
// into the widget extension.

/// The app's text styles, by the desktop's names. `.textStyle(.lede)` on a view sets the font, the line height and
/// the letter spacing; `Font.app(.lede)` is the font alone.
enum AppText: CaseIterable, Sendable {
    /// A page's title: Home's date, "Due", a class's name. 800, 40/44 (34/38 on a phone), tight.
    case date
    /// A note's title on its page. 800, 32 (28 on a phone).
    case docTitle
    /// A section's heading: "Up next", "Notes", "Lectures". 800, 17/24.
    case h2
    /// A lecture's or an event's title in a list. 700, 17/22.
    case title
    /// Anything else. 400, 15/22.
    case body
    /// The sentence under a page's title, and empty states. 400, 16/24 (in ink-muted).
    case lede
    /// A lecture's summary in a list (two lines), what the AI wrote. 400, 14.5/22 (in ink-muted).
    case summary
    /// A sidebar's or a list's row. 500, 15/20 (700 when chosen).
    case nav
    /// A class's name in a list of classes. 400, 14/20.
    case className
    /// An assignment's name in the calendar. 700, 14/19.
    case due
    /// Day names, counts, a menu's group labels, a rail's dates. 500, 13/18.
    case meta
    /// Times, "Recorded", a footer. 500, 12/16.
    case micro
    /// A day's number in the week. 800, 22/26.
    case dayNum
    /// When, beside a row: "Today", "Sat 10 Oct", "1:45 PM". 700, 14/18 (in ink-muted).
    case when
    /// A note's folder under its title (the highlight), "Unsorted". 600, 13.5/18.
    case folder
    /// How long, at a row's end: "52 min". 500, 14/18 (in ink-subtle).
    case length
    /// A group's label: "This week", "Classes". 700, 13/18 (in ink-subtle).
    case group
    /// A heading in a class page's rail: "Due", "On Canvas". 800, 15/24.
    case railTitle
    /// A pill's words: Record, Attach. 700, 15.
    case button
    /// A small pill's, a picker's, a link's words: "All notes", "See these on the calendar". 700, 14.
    case buttonSmall
    /// Where a note is filed and when: "Lecture, Monday 12 October at 9:30 AM, 52 min". 500, 14/18.
    case crumb
    /// Notes | Transcript. 700, 15.
    case tab
    /// The line over a note that says whose words are whose. 500, 12/16.
    case legend

    struct Spec: Sendable {
        var size: CGFloat
        var weight: Font.Weight
        var lineHeight: CGFloat
        /// Letter spacing, in ems.
        var tracking: CGFloat = 0
        var relativeTo: Font.TextStyle
        /// The size on a phone, where it differs.
        var compactSize: CGFloat?
        var compactLineHeight: CGFloat?
    }

    var spec: Spec {
        switch self {
        case .date: Spec(size: 40, weight: .heavy, lineHeight: 44, tracking: -0.025, relativeTo: .largeTitle, compactSize: 34, compactLineHeight: 38)
        case .docTitle: Spec(size: 32, weight: .heavy, lineHeight: 40, tracking: -0.02, relativeTo: .title, compactSize: 28, compactLineHeight: 34)
        case .h2: Spec(size: 17, weight: .heavy, lineHeight: 24, tracking: -0.01, relativeTo: .headline)
        case .title: Spec(size: 17, weight: .bold, lineHeight: 22, tracking: -0.01, relativeTo: .headline)
        case .body: Spec(size: 15, weight: .regular, lineHeight: 22, relativeTo: .body)
        case .lede: Spec(size: 16, weight: .regular, lineHeight: 24, relativeTo: .body)
        case .summary: Spec(size: 14.5, weight: .regular, lineHeight: 22, relativeTo: .subheadline)
        case .nav: Spec(size: 15, weight: .medium, lineHeight: 20, relativeTo: .body)
        case .className: Spec(size: 14, weight: .regular, lineHeight: 20, relativeTo: .subheadline)
        case .due: Spec(size: 14, weight: .bold, lineHeight: 19, relativeTo: .subheadline)
        case .meta: Spec(size: 13, weight: .medium, lineHeight: 18, relativeTo: .footnote)
        case .micro: Spec(size: 12, weight: .medium, lineHeight: 16, relativeTo: .caption)
        case .dayNum: Spec(size: 22, weight: .heavy, lineHeight: 26, tracking: -0.02, relativeTo: .title2)
        case .when: Spec(size: 14, weight: .bold, lineHeight: 18, relativeTo: .subheadline)
        case .folder: Spec(size: 13.5, weight: .semibold, lineHeight: 18, relativeTo: .footnote)
        case .length: Spec(size: 14, weight: .medium, lineHeight: 18, relativeTo: .subheadline)
        case .group: Spec(size: 13, weight: .bold, lineHeight: 18, relativeTo: .footnote)
        case .railTitle: Spec(size: 15, weight: .heavy, lineHeight: 24, tracking: -0.01, relativeTo: .subheadline)
        case .button: Spec(size: 15, weight: .bold, lineHeight: 20, relativeTo: .body)
        case .buttonSmall: Spec(size: 14, weight: .bold, lineHeight: 18, relativeTo: .subheadline)
        case .crumb: Spec(size: 14, weight: .medium, lineHeight: 18, relativeTo: .subheadline)
        case .tab: Spec(size: 15, weight: .bold, lineHeight: 20, relativeTo: .body)
        case .legend: Spec(size: 12, weight: .medium, lineHeight: 16, relativeTo: .caption)
        }
    }
}

/// Atkinson Hyperlegible Next's faces, by weight (each its own TTF, so a weight is always the real face).
enum Atkinson {
    static let family = "Atkinson Hyperlegible Next"
    /// The type's own height (ascent and descent), in ems: a line with no extra leading.
    static let naturalLineHeight: CGFloat = 1.3

    static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: "AtkinsonHyperlegibleNext-Light"
        case .medium: "AtkinsonHyperlegibleNext-Medium"
        case .semibold: "AtkinsonHyperlegibleNext-SemiBold"
        case .bold: "AtkinsonHyperlegibleNext-Bold"
        case .heavy, .black: "AtkinsonHyperlegibleNext-ExtraBold"
        default: "AtkinsonHyperlegibleNext-Regular"
        }
    }

    static func uiFace(_ weight: UIFont.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: face(.light)
        case .medium: face(.medium)
        case .semibold: face(.semibold)
        case .bold: face(.bold)
        case .heavy, .black: face(.heavy)
        default: face(.regular)
        }
    }

    /// The face slanted 12°, as the desktop's italic hint is drawn: the family has no italic of its own, and
    /// SwiftUI's `.italic()` leaves it upright. Sized at `size` × `scale` (a Dynamic Type scale), figures tabular.
    static func oblique(size: CGFloat, weight: Font.Weight, scale: CGFloat) -> UIFont {
        let base = UIFont(name: face(weight), size: size * scale) ?? .systemFont(ofSize: size * scale)
        let slant = CGAffineTransform(a: 1, b: 0, c: tan(12 * .pi / 180), d: 1, tx: 0, ty: 0)
        let d = base.fontDescriptor.addingAttributes([
            .matrix: NSValue(cgAffineTransform: slant),
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType, UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]],
        ])
        return UIFont(descriptor: d, size: size * scale)
    }

    /// The face at `size`, growing with Dynamic Type like `style`, its figures tabular.
    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular, relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: uiFace(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
        let tabular = base.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType, UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: tabular, size: size))
    }
}

extension Font {
    /// One of the app's text styles (the font alone; `.textStyle(_:)` adds the line height and spacing). `compact`
    /// takes a phone's size for the page titles.
    static func app(_ style: AppText, compact: Bool = true) -> Font {
        let s = style.spec
        let size = compact ? s.compactSize ?? s.size : s.size
        return atkinson(size, s.weight, relativeTo: s.relativeTo)
    }

    /// Atkinson at any size and weight, growing with Dynamic Type like `relativeTo`, its figures tabular.
    static func atkinson(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {
        Font.custom(Atkinson.face(weight), size: size, relativeTo: relativeTo).monospacedDigit()
    }
}

extension View {
    /// Set one of the app's text styles on everything inside: the font, its line height (the desktop's, as extra
    /// space between lines; never tighter than the type's own) and letter spacing, all growing with Dynamic Type. Page titles take the phone's size in a
    /// compact width and the desktop's in a regular one (an iPad).
    func textStyle(_ style: AppText, italic: Bool = false) -> some View { modifier(TextStyleModifier(style: style, italic: italic)) }
}

private struct TextStyleModifier: ViewModifier {
    var style: AppText
    var italic = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        let s = style.spec
        let compact = sizeClass != .regular
        let size = compact ? s.compactSize ?? s.size : s.size
        let lineHeight = compact ? s.compactLineHeight ?? s.lineHeight : s.lineHeight
        let scale = UIFontMetrics(forTextStyle: s.relativeTo.ui)
            .scaledValue(for: 1, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))
        let natural = size * Atkinson.naturalLineHeight
        let extra = lineHeight - natural
        content
            .font(italic ? Font(Atkinson.oblique(size: size, weight: s.weight, scale: scale)) : .app(style, compact: compact))
            .tracking(s.tracking * size * scale)
            // Only ever more than the type's own height: a tighter line (the big titles' 44 on 40) cuts the letters'
            // feet off in SwiftUI, so those keep the type's own.
            .lineSpacing(max(0, extra) * scale)
    }
}

extension Font.TextStyle {
    var ui: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

extension AppText {
    /// The UIKit font, for what SwiftUI can't style (the navigation and tab bars).
    func uiFont(compact: Bool = true) -> UIFont {
        let s = spec
        let w: UIFont.Weight = switch s.weight {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy, .black: .heavy
        default: .regular
        }
        return Atkinson.uiFont(size: compact ? s.compactSize ?? s.size : s.size, weight: w, relativeTo: s.relativeTo.ui)
    }
}
