import SwiftUI

/// A lecture: its class and when, its topics, then its notes, the transcript they were written from, or its files.
/// A lecture whose notes aren't written yet says so and opens on the transcript.
struct LectureView: View {
    @Environment(AppModel.self) private var app
    let id: String

    enum Pane: String, CaseIterable { case notes = "Notes", transcript = "Transcript", files = "Files" }

    @State private var lecture: Resource<Lecture>?
    @State private var notes: Resource<RenderedLecture>?
    @State private var files: Resource<[Attachment]>?
    @State private var pane: Pane = .notes
    @State private var asking = false
    @State private var studying = false

    var body: some View {
        let l = lecture?.value
        let color = app.color(of: l?.class ?? notes?.value?.class)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let lecture, l == nil {
                    Loaded(resource: lecture, failure: "Couldn't load this lecture") { _ in EmptyView() }
                }
                if let l {
                    header(l, color)
                    Picker("Show", selection: $pane.animation(.snappy)) {
                        ForEach(Pane.allCases, id: \.self) { p in
                            Text(p == .files && (files?.value?.count ?? 0) > 0 ? "Files (\(files!.value!.count))" : p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch pane {
                    case .notes: notesPane(l, color)
                    case .transcript: TranscriptView(text: l.transcript)
                    case .files:
                        if let f = files?.value, !f.isEmpty { AttachmentList(files: f) } else {
                            ContentUnavailableView("No files", systemImage: "paperclip",
                                                   description: Text("Handwritten notes, slides or photos from this lecture show up here."))
                        }
                        HStack {
                            Button { app.incoming = .handwriting(className: l.class, lecture: (l.id, l.displayTitle)) } label: {
                                Label("Write notes", systemImage: "pencil.and.scribble").frame(maxWidth: .infinity)
                            }
                            Button { app.incoming = .files([], className: l.class, lecture: (l.id, l.displayTitle)) } label: {
                                Label("Add files", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 90)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.paper)
        .titleOnScroll(l?.displayTitle ?? "", after: 170)
        .toolbar {
            if let l {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { app.incoming = .handwriting(className: l.class, lecture: (l.id, l.displayTitle)) } label: {
                            Label("Write notes", systemImage: "pencil.and.scribble")
                        }
                        Button { app.incoming = .files([], className: l.class, lecture: (l.id, l.displayTitle)) } label: {
                            Label("Add files or scan pages", systemImage: "doc.viewfinder")
                        }
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText(l)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if l != nil {
                HStack(spacing: 10) {
                    Button { studying = true } label: {
                        Label("Study", systemImage: "rectangle.on.rectangle.angled")
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                    Button { asking = true } label: {
                        Label("Ask", systemImage: "sparkles")
                            .font(.body.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .padding(.bottom, 8)
            }
        }
        .fullScreenCover(isPresented: $studying) {
            if let l { StudyView(lectureID: l.id, title: l.displayTitle) }
        }
        .sheet(isPresented: $asking) {
            if let l { AskSheet(scope: .lecture(id: l.id, title: l.displayTitle)) }
        }
        .refreshable { await load() }
        .task {
            guard let api = app.api else { return }
            if lecture == nil {
                lecture = Resource("lecture:\(id)") { try await api.lecture(id) }
                notes = Resource("lecture:\(id):rendered") { try await api.rendered(id) }
                files = Resource("lecture:\(id):files") { try await api.attachments(lecture: id) }
            }
            await load()
            #if DEBUG
            if DebugLaunch.value("-study") != nil { studying = true }
            #endif
            if let l = lecture?.value, (notes?.value?.html ?? "").isEmpty, !l.transcript.isEmpty, l.status != "done" { pane = .transcript }
        }
    }

    private func load() async {
        async let a: Void = lecture?.load() ?? ()
        async let b: Void = notes?.load() ?? ()
        async let c: Void = files?.load() ?? ()
        _ = await (a, b, c)
    }

    private func header(_ l: Lecture, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cls = l.class {
                NavigationLink(value: Route.classDetail(cls)) {
                    HStack(spacing: 6) {
                        ClassDot(color: color, size: 8)
                        Text(cls).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                    }
                }
                .buttonStyle(.plain)
            }
            Text(l.displayTitle)
                .font(.display)
                .textSelection(.enabled)
            Text([Format.lectureMeta(l.date, l.seconds), l.owner].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !l.topics.isEmpty {
                TopicChips(topics: l.topics, tint: color)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func notesPane(_ l: Lecture, _ color: Color) -> some View {
        if let html = notes?.value?.html, !html.isEmpty {
            NotesView(html: html, accent: color)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: l.status == "failed" ? "exclamationmark.triangle" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(l.status == "failed" ? .orange : color)
                    .symbolEffect(.pulse, isActive: l.status == "queued" || l.status == "working")
                Text(noNotesWords(l)).font(.callout)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
        }
    }

    /// Why there are no notes: none will be written (too short), they're being written, they failed, or none came.
    private func noNotesWords(_ l: Lecture) -> String {
        let below = l.transcript.isEmpty ? "" : " The transcript is in the next tab."
        if let why = l.noNotesWhy, !why.isEmpty { return why + below }
        if l.status == "queued" || l.status == "working" { return "Notes are being written. Pull down in a minute to see them." }
        if l.status == "failed" { return "Notes couldn't be written" + (l.error.map { ": \($0)" } ?? "") + "." }
        if let e = l.error?.trimmingCharacters(in: .whitespaces), !e.isEmpty { return e + (e.hasSuffix(".") ? "" : ".") + below }
        if !l.summary.isEmpty { return l.summary }
        return "No notes were written for this lecture." + below
    }

    private func shareText(_ l: Lecture) -> String {
        "# \(l.displayTitle)\n\(Format.lectureMeta(l.date, l.seconds))\n\n\(l.notes.isEmpty ? l.transcript : l.notes)"
    }
}

/// The transcript, a "[04:05] words" line at a time, with the times down the side.
struct TranscriptView: View {
    var text: String

    var body: some View {
        let lines = Self.lines(text)
        if text.isEmpty {
            ContentUnavailableView("No transcript", systemImage: "text.quote")
        } else if lines.isEmpty {
            Text(text).font(.body).textSelection(.enabled)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(line.stamp)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.tint)
                            .frame(width: 52, alignment: .trailing)
                        Text(line.words)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    nonisolated static func lines(_ text: String) -> [(stamp: String, words: String)] {
        text.split(separator: "\n").compactMap { raw in
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard let m = s.firstMatch(of: /^\[(\d{1,2}:\d{2}(?::\d{2})?)\]\s*(.*)$/), !m.2.isEmpty else { return nil }
            return (String(m.1), String(m.2))
        }
    }
}
