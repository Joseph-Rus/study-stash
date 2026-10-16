import SwiftUI
import WidgetKit

/// Every widget, the Lock Screen's and the Live Activity's views at their real sizes, in one screen the app can show
/// (debug builds: launch with `-demo -show widgets`), so they can be pictured in the simulator, which can't put a
/// widget on its Home Screen headless. `-gallery home|large|lock|island` picks the page (home by default). They show
/// the demo library's week (`Glance.sample`). Compiled into the app and the widget extension both.
struct WidgetGallery: View {
    enum Page: String { case home, large, lock, island }
    var page: Page = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gallery"), args.indices.contains(i + 1) else { return .home }
        return Page(rawValue: args[i + 1]) ?? .home
    }()
    private let now = Date.now

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch page {
                case .home: home
                case .large: large
                case .lock: lock
                case .island: island
                }
            }
            .padding(.horizontal, 19)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(page == .lock || page == .island ? Self.wallpaper : Color.canvas)
        .foregroundStyle(.ink)
    }

    /// The Lock Screen's wallpaper, in the gallery: flat, dark.
    static let wallpaper = Color.resolved(Palette.canvas, dark: true)

    private var sample: Glance { .sample(at: now) }
    /// The same week with the first class gone: the next is this afternoon's, and another after it.
    private var later: Glance {
        var g = sample
        g.events.removeFirst()
        return g
    }
    /// A quiet day: nothing on, nothing due.
    private var quiet: Glance {
        var g = sample
        g.events = []
        g.due = []
        g.toHandIn = 0
        return g
    }

    // MARK: pages

    @ViewBuilder private var home: some View {
        Caption("Small: a class about to start; a later one")
        HStack(spacing: 24) {
            Stage(.systemSmall) { UpNextView(glance: sample, now: now, family: .systemSmall) }
            Stage(.systemSmall) { UpNextView(glance: later, now: now, family: .systemSmall) }
        }
        Caption("Medium: a class on now, and what's due")
        Stage(.systemMedium) { UpNextView(glance: sample, now: now.addingTimeInterval(20 * 60), family: .systemMedium) }
        Caption("Medium: a later class")
        Stage(.systemMedium) { UpNextView(glance: later, now: now, family: .systemMedium) }
        Caption("Small: a quiet day; before the app has said anything")
        HStack(spacing: 24) {
            Stage(.systemSmall) { UpNextView(glance: quiet, now: now, family: .systemSmall) }
            Stage(.systemSmall) { UpNextView(glance: nil, now: now, family: .systemSmall) }
        }
    }

    @ViewBuilder private var large: some View {
        Caption("Large: Home, in a widget")
        Stage(.systemLarge) { UpNextView(glance: sample, now: now, family: .systemLarge) }
        Caption("Medium: a quiet day")
        Stage(.systemMedium) { UpNextView(glance: quiet, now: now, family: .systemMedium) }
    }

    @ViewBuilder private var lock: some View {
        // The Lock Screen draws its widgets in one colour over the wallpaper.
        VStack(spacing: 6) {
            UpNextInline(glance: sample, now: now)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 257, height: 22)
            Text("9:41").font(.system(size: 92, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 10) {
                UpNextCircular(glance: sample, now: now, gallery: true).frame(width: 72, height: 72)
                UpNextRectangular(glance: sample, now: now).frame(width: 172, height: 72)
                UpNextCircular(glance: quiet, now: now, gallery: true).frame(width: 72, height: 72)
            }
            UpNextRectangular(glance: later, now: now).frame(width: 172, height: 72)
        }
        .foregroundStyle(.white)
        .environment(\.widgetFullColor, false)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity)

        Spacer(minLength: 4)
        Caption("Recording, paused, saving", onWallpaper: true)
        LiveBanner(attributes: Self.recording, state: Self.state(paused: false))
        LiveBanner(attributes: Self.untitled, state: Self.state(paused: true))
        LiveBanner(attributes: Self.recording, state: Self.state(paused: true, finishing: true))
    }

    @ViewBuilder private var island: some View {
        Caption("Dynamic Island: closed, and the minimal one", onWallpaper: true)
        HStack(spacing: 14) {
            IslandCompact(state: Self.state(paused: false))
            Circle().fill(.black).frame(width: 37, height: 37)
                .overlay { RecordingIsland.CompactLeading(state: Self.state(paused: false)).padding(.leading, -4) }
        }
        IslandCompact(state: Self.state(paused: true))
        Caption("Dynamic Island: open", onWallpaper: true)
        IslandExpanded(attributes: Self.recording, state: Self.state(paused: false))
        IslandExpanded(attributes: Self.untitled, state: Self.state(paused: true))
    }

    // MARK: the recording's samples

    static let recording = RecordingAttributes(title: "Integration by parts", className: "Calculus II", highlighter: "yellow")
    static let untitled = RecordingAttributes(title: "Recording, Fri 16 Oct at 9:41 AM", className: nil, highlighter: nil)
    static func state(paused: Bool, finishing: Bool = false) -> RecordingAttributes.ContentState {
        RecordingAttributes.ContentState(countingFrom: .now.addingTimeInterval(-724), paused: paused, elapsed: 724, finishing: finishing)
    }
}

// MARK: - The stages

/// A widget at its real size on an iPhone 17 Pro, on the page's colour, with the system's margins and corners.
private struct Stage<Content: View>: View {
    var family: WidgetFamily
    @ViewBuilder var content: Content

    init(_ family: WidgetFamily, @ViewBuilder content: () -> Content) {
        self.family = family
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.widgetFullColor, true)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(.surface, in: .rect(cornerRadius: 24, style: .continuous))
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
    }

    private var size: CGSize {
        switch family {
        case .systemMedium: CGSize(width: 364, height: 170)
        case .systemLarge: CGSize(width: 364, height: 382)
        default: CGSize(width: 170, height: 170)
        }
    }
}

/// What a stage shows, small and quiet above it.
private struct Caption: View {
    var text: String
    var onWallpaper = false
    init(_ text: String, onWallpaper: Bool = false) {
        self.text = text
        self.onWallpaper = onWallpaper
    }
    var body: some View {
        Text(text).textStyle(.micro)
            .foregroundStyle(onWallpaper ? Color.white.opacity(0.7) : Color.inkSubtle)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Live Activity on the Lock Screen: a banner the system rounds, on the page's colour.
private struct LiveBanner: View {
    var attributes: RecordingAttributes
    var state: RecordingAttributes.ContentState
    var body: some View {
        RecordingLockScreenView(attributes: attributes, state: state)
            .frame(width: 364)
            .background(.surface, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// The island closed: the dot one side of the camera, the time the other.
private struct IslandCompact: View {
    var state: RecordingAttributes.ContentState
    var body: some View {
        HStack(spacing: 0) {
            RecordingIsland.CompactLeading(state: state).frame(width: 44, alignment: .leading)
            Color.clear.frame(width: 126)
            RecordingIsland.CompactTrailing(state: state).frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 37)
        .background(.black, in: .capsule)
        .environment(\.colorScheme, .dark)
    }
}

/// The island open: what it's doing and the time beside the camera, what's recording and the buttons under them.
private struct IslandExpanded: View {
    var attributes: RecordingAttributes
    var state: RecordingAttributes.ContentState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                RecordingIsland.Leading(state: state).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 126)
                RecordingIsland.Trailing(state: state).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 37)
            RecordingIsland.Bottom(attributes: attributes, state: state)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: 371)
        .background(.black, in: .rect(cornerRadius: 44, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
