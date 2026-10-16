import SwiftUI

// The app's icons: the desktop's set (Lucide 0.469.0 outlines, a 1.5 stroke with round caps and joins, in a 24-point
// box), under the desktop's names ("home", "event_upcoming", "attach_file"), as template vector images in
// Resources/Icons.xcassets, drawn in the text's colour. Anywhere SwiftUI takes an image takes one: a tab, a toolbar
// button, a menu, a swipe action, a widget. ios/tools/icons.py makes them from the same table as the desktop's
// IconPaths.cs (ios/DESIGN.md says how to add one). No SF Symbols in the app's own UI. Also compiled into the widget
// extension, which has the catalog too.

extension Image {
    /// One of the app's icons, at its own size (24 points: right for a tab, a toolbar button, a menu, a swipe
    /// action). `filled` draws the solid one where there is one (circle, pause, play_arrow, stop, fiber_manual_record).
    init(icon name: String, filled: Bool = false) {
        self.init(filled ? "\(name)-filled" : name)
    }
}

/// An icon beside text, at the desktop's size for it (18 in a row, 16 in a button, 14 for a chevron), growing with
/// Dynamic Type: `Icon("inbox", size: 15)`. Drawn in the foreground style.
struct Icon: View {
    var name: String
    var filled = false
    @ScaledMetric private var size: CGFloat

    init(_ name: String, size: CGFloat = 18, filled: Bool = false, relativeTo style: Font.TextStyle = .body) {
        self.name = name
        self.filled = filled
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        Image(icon: name, filled: filled)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label with one of the app's icons: `Label("Due", icon: "event_upcoming")`. For a tab, a menu, a toolbar
    /// button or a swipe action (the system sizes it there).
    init(_ title: String, icon: String, filled: Bool = false) {
        self.init { Text(title) } icon: { Image(icon: icon, filled: filled) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// A button with one of the app's icons: `Button("Delete", icon: "delete", role: .destructive) { … }`.
    init(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, icon: icon) }
    }
}
