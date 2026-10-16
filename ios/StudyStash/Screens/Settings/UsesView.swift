import SwiftUI

/// What it's for: school brings classes, Canvas and what's due; anything else gets folders, and notes written for
/// it. The library keeps it, so every computer and phone goes by it. As the desktop's setup asks it: a choice per use
/// (its icon, its name, what it brings), ringed in ink and ticked when picked (`UsesChoices`, which setup shows too).
/// From Settings it's a page that saves each tick as it's made, as the desktop's General does; as a sheet
/// (`onboarding`) it has Continue and Skip for now.
struct UsesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    var onboarding = false

    struct Kind: Identifiable {
        var id: String
        var title: String
        var about: String
        /// One of the app's icons (Lucide, the desktop's names).
        var icon: String
        @available(*, deprecated, renamed: "icon", message: "An app icon's name now (Image(icon:)), not an SF Symbol")
        var symbol: String { icon }
    }
    /// The desktop's (SetupModel's UseChoice), with its icons.
    static let kinds: [Kind] = [
        .init(id: "student", title: "School", about: "Lectures, classes, Canvas and what's due", icon: "school"),
        .init(id: "work", title: "Work", about: "Meetings, calls and projects", icon: "forum"),
        .init(id: "research", title: "Research", about: "Interviews, seminars and reading groups", icon: "travel_explore"),
        .init(id: "creative", title: "Creative", about: "Critiques, studio time and ideas", icon: "palette"),
        .init(id: "personal", title: "Personal", about: "Talks, podcasts, notes to self", icon: "headphones"),
    ]

    @State private var picked: Set<String> = []
    @State private var saving = false
    @State private var problem: String?

    var body: some View {
        if onboarding {
            NavigationStack {
                page
                    .safeAreaInset(edge: .bottom) { continueBar }
            }
            .interactiveDismissDisabled()
        } else {
            page.titleOnScroll("What it’s for", after: 30)
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(onboarding ? "What will you use Study Stash for?" : "What it’s for")
                    .textStyle(onboarding ? .docTitle : .date)
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text(onboarding
                     ? "Pick any that fit. School brings in Canvas and classes; anything else gets folders, and the notes are written for it."
                     : "Pick any that fit. Your library keeps this, so your computer and this \(device) go by it.")
                    .textStyle(.lede)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                UsesChoices(picked: $picked, keepOne: !onboarding) { if !onboarding { save() } }
                    .padding(.top, 22)

                if let problem {
                    Text(problem)
                        .font(.atkinson(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }

                if !onboarding {
                    Text("School brings in Canvas and classes, and study notes. Without it you get folders, and notes written for meetings and talks: decisions, action items, open questions.")
                        .font(.atkinson(13, relativeTo: .footnote))
                        .lineSpacing(3)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, sizeClass == .regular && !onboarding ? Space.pageRegular : Space.pageCompact)
            .padding(.top, onboarding ? 16 : 4)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: onboarding ? .center : .leading)
        }
        .scrollIndicators(.hidden)
        .page()
        .onAppear {
            let said = Set(app.uses ?? [])
            // The library goes by School until it's told otherwise (the desktop ticks it the same way).
            picked = said.isEmpty && !onboarding ? ["student"] : said
        }
    }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "phone" }

    /// Continue, ink, at the sheet's foot; Skip for now under it.
    private var continueBar: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    saving = true
                    await app.setUses(Self.kinds.map(\.id).filter(picked.contains))
                    saving = false
                    dismiss()
                    await Reminders.setUp()
                }
            } label: {
                ZStack {
                    Text("Continue").opacity(saving ? 0 : 1)
                    if saving { ProgressView().tint(.surface) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(picked.isEmpty || saving)

            Button("Skip for now") {
                app.askedUses = true
                dismiss()
                Task { await Reminders.setUp() }
            }
            .buttonStyle(.textLink)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Space.pageCompact)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.surface.ignoresSafeArea())
    }

    /// From Settings, each tick goes to the library as it's made; if it can't, the ticks go back to what's saved and
    /// the page says why.
    private func save() {
        let list = Self.kinds.map(\.id).filter(picked.contains)
        problem = nil
        Task {
            guard let api = app.api, let overview = try? await api.setUses(list) else {
                problem = "Not saved: your library can’t be reached right now. Try again when this \(device) can reach your computer."
                let said = Set(app.uses ?? [])
                picked = said.isEmpty ? ["student"] : said
                return
            }
            app.askedUses = true
            app.learn(overview)
            ResponseCache.shared.write("library", overview)
        }
    }
}

/// The uses to pick from, one box each: its icon, its name and what it brings, a tick at its end; picked, ringed in
/// ink. `keepOne` keeps the last one picked (a library is always for something). `changed` follows each tick.
struct UsesChoices: View {
    @Binding var picked: Set<String>
    var keepOne = false
    var changed: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            ForEach(UsesView.kinds) { k in
                ChoiceRow(kind: k, on: picked.contains(k.id)) { tick(k.id) }
            }
        }
    }

    private func tick(_ id: String) {
        if picked.contains(id) {
            if keepOne && picked.count == 1 { UINotificationFeedbackGenerator().notificationOccurred(.warning); return }
            picked.remove(id)
        } else {
            picked.insert(id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        changed()
    }
}

/// One use to pick: its icon, its name and what it brings, a tick at its end; picked, ringed in ink.
private struct ChoiceRow: View {
    var kind: UsesView.Kind
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(kind.icon, size: 22).foregroundStyle(on ? Color.ink : .inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.atkinson(16, .bold, relativeTo: .body)).foregroundStyle(.ink)
                    Text(kind.about).font(.atkinson(14, relativeTo: .subheadline)).foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Tick(on: on)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 72)
        }
        .buttonStyle(ChoiceStyle(on: on))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

/// A choice's box: the page's white, a hairline round it (ink and thicker when picked, grey while pressed).
private struct ChoiceStyle: ButtonStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel)
        configuration.label
            .background(.surface, in: shape)
            .overlay {
                if configuration.isPressed && !on { shape.fill(.hover) }
                shape.strokeBorder(on ? Color.ink : configuration.isPressed ? .inkSubtle : .line, lineWidth: on ? 2 : 1)
            }
            .contentShape(shape)
    }
}

/// The desktop's tick box: a grey outline, or filled with ink and a check in the page's colour.
private struct Tick: View {
    var on: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        ZStack {
            if on {
                shape.fill(.ink)
                Icon("check", size: 15).foregroundStyle(.surface)
            } else {
                shape.strokeBorder(.inkSubtle, lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}
