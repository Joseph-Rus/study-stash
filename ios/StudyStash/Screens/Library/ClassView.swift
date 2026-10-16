import QuickLook
import SwiftUI

/// One class: its lectures under "This week", "Last week" and the months before, and the files added to it.
struct ClassView: View {
    @Environment(AppModel.self) private var app
    let name: String

    @State private var lectures: Resource<[LectureSummary]>?
    @State private var files: Resource<[Attachment]>?
    @State private var library: Resource<LibraryOverview>?

    var body: some View {
        let color = app.color(of: name)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header(color)
                if let lectures {
                    Loaded(resource: lectures, failure: "Couldn't load this class") { list in
                        if list.isEmpty {
                            ContentUnavailableView("No lectures yet", systemImage: "mic",
                                                   description: Text("Lectures recorded for \(name) show up here."))
                        }
                        ForEach(Format.grouped(list) { Format.lectureGroup($0.date) }, id: \.label) { group in
                            SectionHeading(title: group.label)
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { i, l in
                                        NavigationLink(value: Route.lecture(l.id)) {
                                            LectureCard(lecture: l, color: color, showClass: false)
                                                .padding(.horizontal, 14).padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        if i < group.items.count - 1 { Divider().padding(.leading, 30) }
                                    }
                                }
                            }
                        }
                    }
                }
                if let files = files?.value, !files.isEmpty {
                    SectionHeading(title: "Files")
                    AttachmentList(files: files)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(.paper)
        .titleOnScroll(name)
        .refreshable { await load() }
        .task {
            guard let api = app.api else { return }
            if lectures == nil {
                lectures = Resource("class:\(name)") { try await api.lectures(class: name, limit: 500) }
                files = Resource("class:\(name):files") { try await api.attachments(class: name) }
                library = Resource("library") { try await api.library() }
            }
            await load()
        }
    }

    private func load() async {
        async let a: Void = lectures?.load() ?? ()
        async let b: Void = files?.load() ?? ()
        _ = await (a, b)
    }

    private func header(_ color: Color) -> some View {
        let info = library?.value?.classes.first { $0.name == name }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClassDot(color: color, size: 12)
                if let code = info?.code, !code.isEmpty {
                    Text(code).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
            }
            Text(name).font(.display).lineLimit(3)
            if let d = info?.description, !d.isEmpty {
                Text(d).font(.callout).foregroundStyle(.secondary)
            }
            if let n = info?.lectures ?? lectures?.value?.count {
                Text("\(n) lecture\(n == 1 ? "" : "s")").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

/// Files added to a class or lecture, each opening in Quick Look.
struct AttachmentList: View {
    @Environment(AppModel.self) private var app
    var files: [Attachment]
    @State private var preview: URL?
    @State private var opening: String?

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { i, f in
                    Button { Task { await open(f) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(f.type))
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 36, height: 36)
                                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).font(.body).lineLimit(1)
                                Text(f.reading ? "Reading your handwriting…" : "\(Format.fileSize(f.size)) · \(Format.ago(f.added))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if opening == f.id { ProgressView() }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if i < files.count - 1 { Divider().padding(.leading, 62) }
                }
            }
        }
        .quickLookPreview($preview)
    }

    private func symbol(_ type: String) -> String {
        if type.hasPrefix("image/") { return "photo" }
        if type.contains("pdf") { return "doc.richtext" }
        if type.hasPrefix("audio/") { return "waveform" }
        if type.contains("presentation") || type.contains("powerpoint") { return "rectangle.on.rectangle" }
        return "doc"
    }

    /// Download it (with the pairing cookie) to a temporary file Quick Look can show.
    private func open(_ f: Attachment) async {
        guard let api = app.api else { return }
        opening = f.id
        defer { opening = nil }
        do {
            let (data, _) = try await AppModel.session.data(from: api.attachmentURL(f.id))
            let dir = FileManager.default.temporaryDirectory.appending(path: f.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appending(path: f.name)
            try data.write(to: file)
            preview = file
        } catch {}
    }
}
