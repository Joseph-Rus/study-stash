import SwiftUI

/// The library's front screen: what's next (the next class on the calendar, the next things due), the newest
/// lectures, and every class as a tile. + records, imports a voice memo, or adds files.
struct LibraryTab: View {
    @Environment(AppModel.self) private var app
    @State private var path: NavigationPath = DebugLaunch.route.map { NavigationPath([$0]) } ?? NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            if let api = app.api {
                LibraryHome(api: api, path: $path).routes()
            }
        }
    }
}

private struct LibraryHome: View {
    @Environment(AppModel.self) private var app
    let api: APIClient
    @Binding var path: NavigationPath

    @State private var library: Resource<LibraryOverview>
    @State private var recent: Resource<[LectureSummary]>
    @State private var due: Resource<DueList>
    @State private var upcoming: Resource<Upcoming>

    init(api: APIClient, path: Binding<NavigationPath>) {
        self.api = api
        _path = path
        _library = State(initialValue: Resource("library") { try await api.library() })
        _recent = State(initialValue: Resource("recent") { try await api.lectures(limit: 8) })
        _due = State(initialValue: Resource("due") { try await api.due() })
        _upcoming = State(initialValue: Resource("upcoming") { try await api.upcoming() })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if library.stale || recent.stale { OfflineNote().frame(maxWidth: .infinity) }
                if let writing = library.value?.writing, writing > 0 {
                    Label("Writing notes for \(writing) lecture\(writing == 1 ? "" : "s")…", systemImage: "sparkles")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)
                        .padding(.horizontal, 4)
                }
                OnThisPhone()
                nextUp
                recentSection
                NotebookShelf()
                classesSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(.paper)
        .navigationTitle("Library")
        .navigationSubtitle(app.libraryName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { app.record(for: nil) } label: { Label("Record a lecture", systemImage: "mic.fill") }
                    Button { app.incoming = .handwriting(className: nil, lecture: nil) } label: { Label("Write notes", systemImage: "pencil.and.scribble") }
                    Button { app.incoming = .files([], className: nil, lecture: nil) } label: { Label("Add files or scan pages", systemImage: "doc.viewfinder") }
                    Button { app.incoming = .audio(nil) } label: { Label("Import a recording", systemImage: "waveform") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable { await loadAll() }
        .task { await loadAll() }
        .onChange(of: library.value?.classes) { _, _ in if let v = library.value { app.learn(v) } }
    }

    private func loadAll() async {
        async let a: Void = library.load()
        async let b: Void = recent.load()
        async let c: Void = due.load()
        async let d: Void = upcoming.load()
        _ = await (a, b, c, d)
        if let v = library.value { app.learn(v) }
    }

    // MARK: next up

    /// The next class on the calendar today and the next three things due, side by side as a card.
    @ViewBuilder private var nextUp: some View {
        let nextEvent = upcoming.value?.events.first { e in
            guard let end = Format.parse(e.end) else { return false }
            return end > .now && Format.daysBetween(.now, Format.parse(e.start) ?? .now) <= 1
        }
        let dueItems = (due.value?.groups ?? [])
            .filter { ["overdue", "week", "later"].contains($0.key) }
            .flatMap { g in g.items.map { (item: $0, overdue: g.key == "overdue") } }
            .prefix(3)

        if nextEvent != nil || !dueItems.isEmpty {
            SectionHeading(title: "Up next")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if let e = nextEvent {
                        HStack(spacing: 12) {
                            VStack(spacing: 0) {
                                Text(Format.parse(e.start).map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.red).textCase(.uppercase)
                                Text(Format.parse(e.start).map { $0.formatted(.dateTime.day()) } ?? "")
                                    .font(.title2.weight(.semibold))
                            }
                            .frame(width: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).font(.headline).lineLimit(1)
                                Text([Format.dayLabel(Format.parse(e.start) ?? .now), Format.timeRange(e.start, e.end, allDay: e.allDay), e.location]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            ClassDot(color: app.color(ofEvent: e))
                        }
                        .padding(14)
                        if !dueItems.isEmpty { Divider().padding(.leading, 70) }
                    }
                    ForEach(Array(dueItems.enumerated()), id: \.offset) { i, entry in
                        Button {
                            path.append(Route.assignment(class: entry.item.class, id: entry.item.id))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(for: entry.item.kind))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(app.color(of: entry.item.class))
                                    .frame(width: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.item.name).font(.body.weight(.medium)).lineLimit(1)
                                    Text(Format.dueWhen(entry.item.due))
                                        .font(.subheadline)
                                        .foregroundStyle(entry.overdue ? .red : .secondary)
                                        .fontWeight(entry.overdue ? .semibold : .regular)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if i < dueItems.count - 1 { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }

    // MARK: recent lectures

    @ViewBuilder private var recentSection: some View {
        if let lectures = recent.value, !lectures.isEmpty {
            SectionHeading(title: "Recent lectures")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(lectures.enumerated()), id: \.element.id) { i, l in
                        NavigationLink(value: Route.lecture(l.id)) {
                            LectureCard(lecture: l, color: app.color(of: l.class))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if i < lectures.count - 1 { Divider().padding(.leading, 30) }
                    }
                }
            }
        } else if recent.value == nil, recent.error == nil {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    // MARK: classes

    @ViewBuilder private var classesSection: some View {
        Loaded(resource: library, failure: "Couldn't load your classes") { overview in
            if overview.classes.isEmpty && overview.unsorted == 0 {
                ContentUnavailableView("Nothing here yet", systemImage: "books.vertical",
                                       description: Text("Record a lecture with Study Stash on your computer, and it shows up here with notes."))
            } else {
                SectionHeading(title: "Classes")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                    ForEach(overview.classes) { c in
                        NavigationLink(value: Route.classDetail(c.name)) {
                            ClassTile(name: c.name, code: c.code, lectures: c.lectures, color: ClassColor.of(c.color))
                        }
                        .buttonStyle(.plain)
                    }
                    if overview.unsorted > 0 {
                        NavigationLink(value: Route.classDetail("Unsorted")) {
                            ClassTile(name: "Unsorted", code: nil, lectures: overview.unsorted, color: .gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "quiz": "checkmark.circle"
        case "discussion": "bubble.left.and.bubble.right"
        case "todo": "circle"
        default: "doc.text"
        }
    }
}

/// A class as a tile: its colour washed across the top, the name in serif, its course code and how many lectures.
struct ClassTile: View {
    var name: String
    var code: String?
    var lectures: Int
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: name == "Unsorted" ? "tray" : "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                Text("\(lectures)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(color.opacity(0.14), in: .capsule)
            }
            Spacer(minLength: 18)
            Text(name)
                .font(.headlineSerif)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(code?.isEmpty == false ? code! : "\(lectures) lecture\(lectures == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.card)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
        .contentShape(.rect(cornerRadius: 22))
    }
}

/// Recordings made on this phone that aren't in the library yet: sending, waiting for it, or refused, each with a
/// way to send again or delete.
struct OnThisPhone: View {
    @Environment(AppModel.self) private var app
    @State private var store = RecordingStore.shared

    var body: some View {
        let list = store.unsent.filter { $0.state != .recording }
        if !list.isEmpty {
            SectionHeading(title: "On this phone")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 12) {
                            Image(systemName: r.state == .failed ? "exclamationmark.triangle.fill" : r.state == .sending ? "arrow.up.circle" : "tray.and.arrow.up")
                                .foregroundStyle(r.state == .failed ? .orange : .accentColor)
                                .symbolEffect(.pulse, isActive: r.state == .sending)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                                Text(r.state == .sending ? "Sending…" : r.error ?? "Waiting to reach your library")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Menu {
                                Button("Send now", systemImage: "arrow.up") { if let api = app.api { Task { await store.send(r.id, api: api) } } }
                                if let audio = store.audioURL(r), FileManager.default.fileExists(atPath: audio.path) {
                                    ShareLink(item: audio) { Label("Share the audio", systemImage: "waveform") }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.delete(r) }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if i < list.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
            }
        }
    }
}

/// The notebooks written (or brought in from GoodNotes) on this phone, newest first; a tap opens one.
struct NotebookShelf: View {
    @State private var store = NotebookStore.shared
    @State private var open: UUID?

    var body: some View {
        if !store.notebooks.isEmpty {
            SectionHeading(title: "Notebooks")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.notebooks) { n in
                        Button { open = n.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Group {
                                    if let image = store.thumbnail(n, width: 220) { Image(uiImage: image).resizable().scaledToFill() } else { Color.white }
                                }
                                .frame(width: 110, height: 142)
                                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                Text(n.title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 110, alignment: .leading)
                                Text(n.needsSaving ? "Not saved to library" : "In \(n.className ?? "library")")
                                    .font(.caption2).foregroundStyle(n.needsSaving ? .orange : .secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .fullScreenCover(item: Binding(get: { open.map(IdentifiedUUID.init) }, set: { open = $0?.id })) { NotebookEditor(id: $0.id) }
        }
    }
}

struct IdentifiedUUID: Identifiable { var id: UUID }
