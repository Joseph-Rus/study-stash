import SwiftUI

/// Search everything: lectures, the passages that matched (in notes or what was said), and classes.
struct SearchTab: View {
    @State private var query = DebugLaunch.value("-search") ?? ""

    var body: some View {
        NavigationStack {
            SearchResultsView(query: query, live: true)
                .searchable(text: $query, prompt: "Lectures, topics, what was said")
                .routes()
        }
    }
}

struct SearchResultsView: View {
    @Environment(AppModel.self) private var app
    var query: String
    var live = false

    @State private var results: SearchResults?
    @State private var problem: String?
    @State private var searching = false

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass",
                                       description: Text("Find a lecture by title or topic, or anything that was said in class."))
                    .listRowBackground(Color.clear)
            } else if let r = results {
                if r.lectures.isEmpty && r.passages.isEmpty && r.classes.isEmpty {
                    ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                }
                if !r.classes.isEmpty {
                    Section(app.words.classes) {
                        ForEach(r.classes) { c in
                            NavigationLink(value: Route.classDetail(c.name)) {
                                Label { Text(c.name) } icon: { ClassDot(color: ClassColor.of(c.color), size: 12) }
                            }
                        }
                    }
                }
                if !r.lectures.isEmpty {
                    Section("Lectures") {
                        ForEach(r.lectures) { l in
                            NavigationLink(value: Route.lecture(l.id)) { LectureCard(lecture: l, color: app.color(of: l.class)) }
                        }
                    }
                }
                if !r.passages.isEmpty {
                    Section("Passages") {
                        ForEach(Array(r.passages.enumerated()), id: \.offset) { _, p in
                            NavigationLink(value: Route.lecture(p.id)) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        ClassDot(color: app.color(of: p.class), size: 7)
                                        Text(p.title ?? "Lecture").font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Spacer()
                                        Text(p.kind == "transcript" ? (p.at.map(Format.clock) ?? "Transcript") : p.section)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Text(highlighted(p.text)).font(.callout).lineLimit(4)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            } else if let problem {
                ContentUnavailableView("Couldn't search", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.paper)
        .navigationTitle(live ? "Search" : query)
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty, let api = app.api else { results = nil; return }
            if live { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            do {
                results = try await api.search(q, limit: 30)
                problem = nil
            } catch is CancellationError {
            } catch {
                problem = (error as? APIError)?.detail ?? "Something went wrong."
            }
        }
    }

    /// The passage with the words searched for picked out.
    private func highlighted(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        for word in query.split(separator: " ").map(String.init) where word.count > 1 {
            var search = a.startIndex..<a.endIndex
            while let r = a[search].range(of: word, options: .caseInsensitive) {
                a[r].backgroundColor = .yellow.opacity(0.35)
                a[r].font = .callout.weight(.semibold)
                search = r.upperBound..<a.endIndex
            }
        }
        return a
    }
}
