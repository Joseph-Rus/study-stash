import SwiftUI

/// What Study Stash is for: school brings classes, Canvas and what's due; anything else gets folders, and notes
/// written for it. The library keeps it, so every computer and phone goes by it.
struct UsesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onboarding = false

    struct Kind: Identifiable { var id: String; var title: String; var about: String; var symbol: String }
    static let kinds: [Kind] = [
        .init(id: "student", title: "School", about: "Lectures, classes, Canvas and what's due", symbol: "graduationcap.fill"),
        .init(id: "work", title: "Work", about: "Meetings, calls and projects", symbol: "briefcase.fill"),
        .init(id: "research", title: "Research", about: "Interviews, seminars and reading groups", symbol: "flask.fill"),
        .init(id: "creative", title: "Creative", about: "Critiques, studio time and ideas", symbol: "paintpalette.fill"),
        .init(id: "personal", title: "Personal", about: "Talks, podcasts, notes to self", symbol: "person.fill"),
    ]

    @State private var picked: Set<String> = []
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if onboarding {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What will you use Study Stash for?").font(.app(.docTitle))
                            Text("Pick any that fit. School brings in classes, Canvas and what's due; anything else gets folders.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                    VStack(spacing: 10) {
                        ForEach(Self.kinds) { k in
                            let on = picked.contains(k.id)
                            Button {
                                withAnimation(.snappy) { if on { picked.remove(k.id) } else { picked.insert(k.id) } }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: k.symbol)
                                        .font(.title3)
                                        .foregroundStyle(on ? .white : Color.accentColor)
                                        .frame(width: 44, height: 44)
                                        .background(on ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.accentColor.opacity(0.12)), in: .rect(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(k.title).font(.headline)
                                        Text(k.about).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(on ? Color.accentColor : .secondary)
                                }
                                .padding(14)
                                .background(.surfaceSunken, in: .rect(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(.surface)
            .navigationTitle(onboarding ? "" : "What it's for")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onboarding {
                    ToolbarItem(placement: .cancellationAction) { Button("Later") { app.askedUses = true; dismiss(); Task { await Reminders.setUp() } } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            saving = true
                            await app.setUses(Self.kinds.map(\.id).filter(picked.contains))
                            saving = false
                            dismiss()
                            if onboarding { await Reminders.setUp() }
                        }
                    } label: { if saving { ProgressView() } else { Text("Done").bold() } }
                    .disabled(picked.isEmpty || saving)
                }
            }
        }
        .onAppear { picked = Set(app.uses ?? []) }
        .interactiveDismissDisabled(onboarding)
    }
}
