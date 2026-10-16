import SwiftUI

/// A colour in OKLCH (lightness 0–1, chroma, hue in degrees), the space the Mac app's themes are defined in.
struct OKLCH: Hashable, Sendable {
    var l: Double, c: Double, h: Double

    /// The sRGB colour, clipped into gamut.
    var rgb: (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr), b = c * sin(hr)
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l_ * l_ * l_, M = m_ * m_ * m_, S = s_ * s_ * s_
        let lin = (
            4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S,
            -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S,
            -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        )
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return (gamma(lin.0), gamma(lin.1), gamma(lin.2))
    }

    var color: Color {
        let (r, g, b) = rgb
        return Color(.sRGB, red: r, green: g, blue: b)
    }
}

/// One of the Mac app's twenty colour themes (ColourThemes.cs): the accent's hue, chroma and lightness.
struct ColourTheme: Hashable, Sendable, Identifiable {
    var name: String
    var h: Double, c: Double, l: Double
    var id: String { name }

    /// A light accent (Chalkboard, Highlighter, Lilac, Peach, Mint): text on it is dark ink.
    var isLight: Bool { l >= 0.75 }

    /// The accent, a touch lighter in the dark the way the Mac's dark tokens are.
    var accent: Color {
        Color(UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let o = OKLCH(l: dark && !isLight ? min(l + 0.08, 0.72) : l, c: c, h: h)
            let (r, g, b) = o.rgb
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }

    static let all: [ColourTheme] = [
        .init(name: "Lagoon", h: 195, c: 0.12, l: 0.58),
        .init(name: "Library", h: 160, c: 0.1, l: 0.5),
        .init(name: "Blueprint", h: 262, c: 0.19, l: 0.55),
        .init(name: "Marmalade", h: 50, c: 0.17, l: 0.64),
        .init(name: "Plum", h: 330, c: 0.14, l: 0.52),
        .init(name: "Chalkboard", h: 95, c: 0.14, l: 0.84),
        .init(name: "Highlighter", h: 125, c: 0.21, l: 0.86),
        .init(name: "Terracotta", h: 35, c: 0.13, l: 0.58),
        .init(name: "Graphite", h: 260, c: 0.01, l: 0.42),
        .init(name: "Original red", h: 22, c: 0.19, l: 0.6),
        .init(name: "Sky", h: 235, c: 0.13, l: 0.62),
        .init(name: "Midnight", h: 275, c: 0.13, l: 0.42),
        .init(name: "Violet", h: 295, c: 0.17, l: 0.55),
        .init(name: "Lilac", h: 300, c: 0.1, l: 0.82),
        .init(name: "Bubblegum", h: 355, c: 0.17, l: 0.64),
        .init(name: "Peach", h: 55, c: 0.1, l: 0.84),
        .init(name: "Mocha", h: 55, c: 0.07, l: 0.47),
        .init(name: "Moss", h: 115, c: 0.11, l: 0.56),
        .init(name: "Clover", h: 148, c: 0.16, l: 0.6),
        .init(name: "Mint", h: 165, c: 0.11, l: 0.87),
    ]

    static let lagoon = all[0]

    /// The theme with this name (any case), or Lagoon.
    static func named(_ name: String?) -> ColourTheme {
        let n = (name ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return all.first { $0.name.lowercased() == n } ?? lagoon
    }
}

/// Each class's dot, from its place in the library (ClassColors.Palette on the Mac).
enum ClassColor {
    static let palette: [OKLCH] = [
        .init(l: 0.62, c: 0.14, h: 250),
        .init(l: 0.64, c: 0.14, h: 155),
        .init(l: 0.6, c: 0.14, h: 295),
        .init(l: 0.7, c: 0.13, h: 70),
        .init(l: 0.63, c: 0.14, h: 20),
        .init(l: 0.66, c: 0.12, h: 200),
        .init(l: 0.62, c: 0.14, h: 330),
        .init(l: 0.66, c: 0.13, h: 120),
    ]

    static func of(_ index: Int?) -> Color {
        guard let index else { return .secondary }
        let n = palette.count
        return palette[((index % n) + n) % n].color
    }
}

/// The type the app reads in: New York for what a student wrote down (titles, notes), SF for the rest.
extension Font {
    static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let titleSerif = Font.system(.title2, design: .serif, weight: .semibold)
    static let headlineSerif = Font.system(.headline, design: .serif, weight: .semibold)
}

extension ShapeStyle where Self == Color {
    /// The page behind cards: warm paper in the light, deep ink in the dark.
    static var paper: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1)
            : UIColor(red: 0.972, green: 0.968, blue: 0.957, alpha: 1) })
    }

    /// A card on the paper.
    static var card: Color {
        Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.125, green: 0.128, blue: 0.140, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 0.998, alpha: 1) })
    }
}
