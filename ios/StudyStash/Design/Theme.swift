import SwiftUI
import UIKit

// The Semester look's tokens: the desktop's (engine/src/StudyStash.App/Skin.cs, `Palette`, light and dark), by the same
// names, so a colour here is the colour there. Black, grey and white; a class's highlighter; and two reds, one for
// recording and one for late. There is no accent: the app's tint is ink. Also compiled into the widget extension.

extension Color {
    /// A colour that's one thing in light and another in dark ("#rrggbb", or with alpha "#rrggbbaa").
    init(light: String, dark: String) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    convenience init(light: String, dark: String) {
        let l = UIColor(hex: light), d = UIColor(hex: dark)
        self.init { $0.userInterfaceStyle == .dark ? d : l }
    }

    /// "#rrggbb" or "#rrggbbaa".
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(s, radix: 16) ?? 0
        let a = s.count == 8 ? CGFloat(v & 0xff) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(red: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255, blue: CGFloat(rgb & 0xff) / 255, alpha: a)
    }
}

/// The desktop's `Palette` (Skin.cs), light then dark.
enum Palette {
    static let canvas = UIColor(light: "#E9EBEE", dark: "#0E0F11")
    static let surface = UIColor(light: "#FFFFFF", dark: "#191A1D")
    static let surfaceSunken = UIColor(light: "#F5F6F7", dark: "#202226")
    static let surfaceToday = UIColor(light: "#FFFFFF", dark: "#2A2C31")
    static let line = UIColor(light: "#DDE0E4", dark: "#2D3035")
    // Skin.cs: Hover 0x1F/0x29 and Press 0x33/0x42 of rgb(127, 127, 127).
    static let hover = UIColor(light: "#7F7F7F1F", dark: "#7F7F7F29")
    static let press = UIColor(light: "#7F7F7F33", dark: "#7F7F7F42")
    static let ink = UIColor(light: "#1D1F23", dark: "#ECEEF1")
    static let inkMuted = UIColor(light: "#565C66", dark: "#A4A9B1")
    static let inkSubtle = UIColor(light: "#626973", dark: "#8D939C")
    static let record = UIColor(light: "#D42A1A", dark: "#FF5A47")
    static let onRecord = UIColor(light: "#FFFFFF", dark: "#1A0603")
    static let late = UIColor(light: "#B3261E", dark: "#FF8A80")
    static let focus = UIColor(light: "#1D1F23", dark: "#ECEEF1")
}

extension ShapeStyle where Self == Color {
    /// The desk behind everything: an iPad's sidebar sits straight on it.
    static var canvas: Color { Color(uiColor: Palette.canvas) }
    /// The page: every screen's background, the Ask bar, a chosen row's chip.
    static var surface: Color { Color(uiColor: Palette.surface) }
    /// A grouped box on the page (a settings group, the calendar's grid).
    static var surfaceSunken: Color { Color(uiColor: Palette.surfaceSunken) }
    /// Today's cell, lifted out of the sunken grid.
    static var surfaceToday: Color { Color(uiColor: Palette.surfaceToday) }
    /// Hairlines and 1-point outlines.
    static var line: Color { Color(uiColor: Palette.line) }
    /// The wash under a finger (a pressed row), and the highlight of a note with no folder.
    static var hover: Color { Color(uiColor: Palette.hover) }
    static var press: Color { Color(uiColor: Palette.press) }
    /// Titles and anything you act on: the app's tint.
    static var ink: Color { Color(uiColor: Palette.ink) }
    /// Summaries, dates, what the AI wrote.
    static var inkMuted: Color { Color(uiColor: Palette.inkMuted) }
    /// Counts, times, placeholders.
    static var inkSubtle: Color { Color(uiColor: Palette.inkSubtle) }
    /// The record dot, the live meter and a recording's outline. Nothing else.
    static var record: Color { Color(uiColor: Palette.record) }
    /// What sits on the record dot.
    static var onRecord: Color { Color(uiColor: Palette.onRecord) }
    /// "Missing" and "Was due…". Nothing else.
    static var late: Color { Color(uiColor: Palette.late) }
    /// A 2-point focus ring.
    static var focus: Color { Color(uiColor: Palette.focus) }
}

/// A class's colour: one highlighter each, shown only as a small swatch, a highlight behind the class's name and the
/// underline under a class page's title (never a dot, a bar, a status or a filled area). The highlighter is the shade
/// behind ink text (deep in dark, so the text stays light); the swatch has nothing on it (brighter in dark).
enum Highlighter: String, CaseIterable, Sendable, Hashable {
    case yellow, green, pink, blue, orange, violet, teal, lime

    /// The order classes take them as they're added, by their place in the library (the library's `color` for a
    /// class): the desktop's `Skin.ClassHues`, so a class is the same colour on the phone as on the computer.
    static let classOrder: [Highlighter] = [.yellow, .green, .orange, .pink, .blue, .teal, .violet, .lime]

    /// The class at `index` in the library (its `color`).
    init(classIndex index: Int) {
        let n = Self.classOrder.count
        self = Self.classOrder[((index % n) + n) % n]
    }

    var highlight: Color { Color(uiColor: highlightUI) }
    var swatch: Color { Color(uiColor: swatchUI) }

    var highlightUI: UIColor {
        switch self {
        case .yellow: UIColor(light: "#FFE46B", dark: "#5A4C00")
        case .green: UIColor(light: "#B5EEA6", dark: "#1F4F2C")
        case .pink: UIColor(light: "#FFC2DF", dark: "#5B2244")
        case .blue: UIColor(light: "#BCDCFF", dark: "#1D4263")
        case .orange: UIColor(light: "#FFCF98", dark: "#5B380F")
        case .violet: UIColor(light: "#DACBFF", dark: "#3D2E68")
        case .teal: UIColor(light: "#A6EBE1", dark: "#134F48")
        case .lime: UIColor(light: "#E2F28C", dark: "#44500E")
        }
    }

    var swatchUI: UIColor {
        switch self {
        case .yellow: UIColor(light: "#FFE46B", dark: "#E9CF4A")
        case .green: UIColor(light: "#B5EEA6", dark: "#7FD27A")
        case .pink: UIColor(light: "#FFC2DF", dark: "#F08CBF")
        case .blue: UIColor(light: "#BCDCFF", dark: "#7DB8F2")
        case .orange: UIColor(light: "#FFCF98", dark: "#F0A95A")
        case .violet: UIColor(light: "#DACBFF", dark: "#B39CF5")
        case .teal: UIColor(light: "#A6EBE1", dark: "#62D3C3")
        case .lime: UIColor(light: "#E2F28C", dark: "#C4DC55")
        }
    }

    /// The highlight behind a name with no class (an event no class matched): the pressed-row wash, as on the desktop.
    static var none: Color { .hover }
    /// A swatch for no class: the desktop's grey.
    static let noneSwatch = Color(uiColor: UIColor(hex: "#808080"))
}

/// Corner radii, nested: a control inside today's cell inside a panel inside the page.
enum Radius {
    /// Buttons that aren't pills, rows, a picker, a segment group.
    static let control: CGFloat = 8
    /// Today's cell; a menu.
    static let day: CGFloat = 10
    static let menu: CGFloat = 10
    /// A grouped box, the calendar's grid, the Ask bar, a toast.
    static let panel: CGFloat = 12
    /// The main sheet (the iPad's page beside its sidebar).
    static let pane: CGFloat = 14
    // Record and Attach are pills: as round as they're tall (Capsule).
}

/// Space, on a 4-point base (tokens.css `--space-*`).
enum Space {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 20
    static let s6: CGFloat = 24, s8: CGFloat = 32, s10: CGFloat = 40, s14: CGFloat = 56
    /// A screen's side margin on a phone, and on an iPad's page (the desktop's 24 when narrow, 56 when wide).
    static let pageCompact: CGFloat = 20
    static let pageRegular: CGFloat = 56
}

/// The two shadows anything is lifted on (tokens.css): each is a hairline round it and a soft shadow under it.
enum Lift {
    /// Today's cell.
    case today
    /// What floats: the Ask bar, a menu, a toast, the recorder.
    case float
    /// The same, ringed in ink: the Ask bar with the caret in it.
    case floatFocus
}

extension View {
    /// Lift this on a shadow, as the desktop does (`ShadowToday`, `ShadowFloat`, `ShadowFloatFocus`): the outline is
    /// drawn round `shape`, and the shadow (`0 6 14 -8` or `0 10 30 -12`, black at 18/25% light, 60/70% dark) under it.
    func lifted<S: InsettableShape>(_ lift: Lift, in shape: S) -> some View {
        modifier(Lifted(lift: lift, shape: shape))
    }
}

private struct Lifted<S: InsettableShape>: ViewModifier {
    var lift: Lift
    var shape: S
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let (y, blur, spread, alpha): (CGFloat, CGFloat, CGFloat, Double) = switch lift {
        case .today: (6, 14, -8, dark ? 0.6 : 0.18)
        case .float, .floatFocus: (10, 30, -12, dark ? 0.7 : 0.25)
        }
        content
            .background {
                // A CSS shadow with a negative spread: the shape drawn smaller by the spread, blurred by half the blur.
                shape.inset(by: -spread).fill(.black.opacity(alpha))
                    .blur(radius: blur / 2)
                    .offset(y: y)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(lift == .floatFocus ? Color.ink : .line, lineWidth: lift == .floatFocus ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Light, dark, or as the phone is: Settings' choice (`@AppStorage("appearance")`), applied at the app's root.
enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
