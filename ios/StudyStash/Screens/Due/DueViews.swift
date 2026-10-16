import SwiftUI

/// Everything to hand in from Canvas, overdue first, then this week, later, undated and handed in; and the
/// calendar's next few days above it.
struct DueTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack(path: app.stack(.due)) {
            if let api = app.api { DueList_(api: api).routes() }
        }
    }
}

private struct DueList_: View {
    @Environment(AppModel.self) private var app
    @State private var due: Resource<DueList>
    @State private var upcoming: Resource<Upcoming>
    @State private var showHandedIn = false

    init(api: APIClient) {
        _due = State(initialValue: Resource("due") { try await api.due() })
        _upcoming = State(initialValue: Resource("upcoming") { try await api.upcoming() })
    }

    var body: some View {
        List {
            if due.stale { OfflineNote().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            if let events = upcoming.value?.events.filter({ (Format.parse($0.end) ?? .distantPast) > .now }).prefix(6), !events.isEmpty {
                Section("Coming up") {
                    let list = Array(events)
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        EventRow(event: e, suggest: !list[..<i].contains { $0.title == e.title })
                    }
                }
            }
            if let list = due.value {
                if list.groups.allSatisfy({ $0.items.isEmpty }) {
                    ContentUnavailableView("Nothing due", systemImage: "checkmark.seal",
                                           description: Text("Link Canvas in Study Stash on your computer to see what's due here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(list.groups.filter { !$0.items.isEmpty && ($0.key != "handed_in" || showHandedIn) }, id: \.key) { g in
                    Section {
                        ForEach(g.items, id: \.self) { item in
                            NavigationLink(value: Route.assignment(class: item.class, id: item.id)) {
                                DueRow(item: item, overdue: g.key == "overdue")
                            }
                        }
                    } header: {
                        Text(g.label)
                    }
                }
                if let handed = list.groups.first(where: { $0.key == "handed_in" }), !handed.items.isEmpty {
                    Button(showHandedIn ? "Hide handed in" : "Show \(handed.items.count) handed in") { withAnimation { showHandedIn.toggle() } }
                }
            } else if let error = due.error {
                ContentUnavailableView("Couldn't load what's due", systemImage: "exclamationmark.triangle", description: Text(error.detail))
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(.surface)
        .navigationTitle("Due")
        .navigationSubtitle(due.value.map { "\($0.toHandIn) to hand in" + ($0.synced.map { " · synced \(Format.ago($0))" } ?? "") } ?? "")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        async let a: Void = due.load()
        async let b: Void = upcoming.load()
        _ = await (a, b)
    }
}

private struct DueRow: View {
    @Environment(AppModel.self) private var app
    var item: DueItem
    var overdue: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Swatch(app.hue(of: item.class)).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.dueWhen(item.due))
                        .foregroundStyle(overdue ? .red : .primary)
                        .fontWeight(overdue ? .semibold : .regular)
                        .lineLimit(1)
                    if !item.label.isEmpty {
                        Text(item.label).font(.caption2.weight(.semibold))
                            .foregroundStyle(item.missing ? .red : .secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((item.missing ? Color.red : .secondary).opacity(0.12), in: .capsule)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                Text([item.class, item.points.flatMap { $0 > 0 ? "\($0.formatted()) pts" : nil }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One assignment: when it's due, the instructions, the rubric and any comments, and a way to open it in Canvas.
struct AssignmentView: View {
    @Environment(AppModel.self) private var app
    let className: String
    let id: Int
    @State private var detail: Resource<AssignmentDetail>?
    @State private var asking = false

    var body: some View {
        ScrollView {
            if let detail {
                Loaded(resource: detail, failure: "Couldn't load this assignment") { a in content(a) }
            }
        }
        .background(.surface)
        .titleOnScroll(detail?.value?.name ?? "", after: 150)
        .toolbar {
            if let url = detail?.value.flatMap({ URL(string: $0.url) }) {
                ToolbarItem(placement: .topBarTrailing) { Link(destination: url) { Label("Open in Canvas", systemImage: "safari") } }
            }
        }
        .sheet(isPresented: $asking) { AskSheet(scope: .class(className)) }
        .refreshable { await detail?.load() }
        .task {
            guard let api = app.api else { return }
            if detail == nil { detail = Resource("assignment:\(className):\(id)") { try await api.assignment(class: className, id: id) } }
            await detail?.load()
        }
    }

    private func content(_ a: AssignmentDetail) -> some View {
        let color = app.color(of: a.class)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Swatch(app.hue(of: a.class))
                Text(a.class).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            Text(a.name).font(.app(.date))
            HStack(spacing: 10) {
                fact("calendar", Format.dueWhen(a.due), a.missing ? .red : .primary)
                if let p = a.points { fact("star", "\(p.formatted()) pts", .primary) }
                if !a.scoreText.isEmpty { fact("checkmark.seal", a.scoreText, .green) }
                else if !a.label.isEmpty { fact("circle.dashed", a.label, a.missing ? .red : .secondary) }
            }
            if let html = a.instructionsHTML, !html.isEmpty {
                NotesView(html: html, accent: color)
            } else if let md = a.instructions, !md.isEmpty {
                MarkdownText(md)
            }
            if !a.rubric.isEmpty {
                SectionHeading(title: "Rubric")
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(a.rubric.enumerated()), id: \.offset) { i, r in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.criterion).font(.body.weight(.medium))
                                    if let d = r.description, !d.isEmpty { Text(d).font(.caption).foregroundStyle(.secondary) }
                                    if let c = r.mark?.comment, !c.isEmpty { Text(c).font(.caption).foregroundStyle(.tint) }
                                }
                                Spacer()
                                Text([r.mark?.points.map { $0.formatted() }, r.points.map { $0.formatted() }].compactMap { $0 }.joined(separator: " / "))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(14)
                            if i < a.rubric.count - 1 { Divider() }
                        }
                    }
                }
            }
            if !a.comments.isEmpty {
                SectionHeading(title: "Comments")
                ForEach(Array(a.comments.enumerated()), id: \.offset) { _, c in
                    Panel {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.author).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(c.text).font(.callout)
                        }
                    }
                }
            }
            Button { asking = true } label: {
                Label("Ask how to start this", systemImage: "sparkles").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func fact(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.surfaceSunken, in: .capsule)
    }
}
