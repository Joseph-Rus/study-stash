import UIKit

/// What UIKit draws for SwiftUI and SwiftUI can't style, in the look: the navigation bars' titles (large and inline,
/// and their subtitles), their text buttons, the tab bar's labels, segmented pickers and the search field, all in
/// Atkinson and ink. Set once, before the first screen.
@MainActor
enum SystemLook {
    static func apply() {
        let ink = Palette.ink, muted = Palette.inkMuted
        let large = AppText.date.uiFont()
        let inline = Atkinson.uiFont(size: 17, weight: .bold, relativeTo: .headline)
        let subtitle = Atkinson.uiFont(size: 13, weight: .medium, relativeTo: .footnote)
        let button = Atkinson.uiFont(size: 17, weight: .medium, relativeTo: .body)
        let done = Atkinson.uiFont(size: 17, weight: .bold, relativeTo: .body)
        // The desktop's page title is tight: -0.025 em.
        let largeAttributes: [NSAttributedString.Key: Any] = [.font: large, .foregroundColor: ink, .kern: -0.025 * large.pointSize]

        func styled(_ a: UINavigationBarAppearance) -> UINavigationBarAppearance {
            a.largeTitleTextAttributes = largeAttributes
            a.titleTextAttributes = [.font: inline, .foregroundColor: ink]
            a.subtitleTextAttributes = [.font: subtitle, .foregroundColor: muted]
            a.largeSubtitleTextAttributes = [.font: Atkinson.uiFont(size: 16, relativeTo: .body), .foregroundColor: muted]
            for b in [a.buttonAppearance, a.backButtonAppearance] {
                b.normal.titleTextAttributes = [.font: button, .foregroundColor: ink]
            }
            a.doneButtonAppearance.normal.titleTextAttributes = [.font: done, .foregroundColor: ink]
            return a
        }
        let bar = UINavigationBar.appearance()
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        bar.standardAppearance = styled(standard)
        bar.compactAppearance = styled(standard.copy())
        bar.scrollEdgeAppearance = styled(edge)
        bar.compactScrollEdgeAppearance = styled(edge.copy())
        bar.largeTitleTextAttributes = largeAttributes
        bar.titleTextAttributes = [.font: inline, .foregroundColor: ink]
        bar.tintColor = ink

        UIBarButtonItem.appearance().setTitleTextAttributes([.font: button], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: button], for: .highlighted)

        let tabLabel = Atkinson.uiFont(size: 10, weight: .medium, relativeTo: .caption2)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabLabel], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabLabel], for: .selected)
        let tabs = UITabBarAppearance()
        tabs.configureWithDefaultBackground()
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: tabLabel]
            item.selected.titleTextAttributes = [.font: tabLabel, .foregroundColor: ink]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = ink

        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.font: Atkinson.uiFont(size: 13.5, weight: .bold, relativeTo: .subheadline), .foregroundColor: muted], for: .normal)
        segmented.setTitleTextAttributes([.font: Atkinson.uiFont(size: 13.5, weight: .bold, relativeTo: .subheadline), .foregroundColor: ink], for: .selected)

        // A switch that's on is ink; its knob is the page's colour, so it shows on the light ink of dark.
        UISwitch.appearance().onTintColor = ink
        UISwitch.appearance().thumbTintColor = Palette.surface

        UISearchTextField.appearance().font = Atkinson.uiFont(size: 16, relativeTo: .body)
        UISearchTextField.appearance().textColor = ink
        UITextField.appearance().tintColor = ink
        UITextView.appearance().tintColor = ink
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = ink
    }
}
