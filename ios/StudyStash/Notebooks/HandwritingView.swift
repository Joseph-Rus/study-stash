import PencilKit
import SwiftUI

/// Write notes for a class or lecture: the notebook already kept for it, or a new one.
struct HandwritingView: View {
    var className: String?
    var lecture: (id: String, title: String)?
    /// Beside a lecture on an iPad, not a screen of its own: no Done, it's closed from the lecture.
    var embedded = false
    @State private var store = NotebookStore.shared
    @State private var id: UUID?

    var body: some View {
        Group {
            if let id { NotebookEditor(id: id, embedded: embedded) } else { Color.paper }
        }
        .task {
            if id != nil { return }
            if let lecture, let existing = store.notebooks.first(where: { $0.lectureID == lecture.id }) {
                id = existing.id
                return
            }
            let title = lecture.map { "Notes, \($0.title)" } ?? className.map { "\($0) notes, \(Date.now.formatted(.dateTime.month(.abbreviated).day()))" }
                ?? "Notes, \(Date.now.formatted(.dateTime.month(.abbreviated).day()))"
            let n = Notebook.blank(title: title, className: className, lecture: lecture)
            store.save(n)
            id = n.id
        }
    }
}

/// One notebook, a page at a time: the ink over its paper (or PDF), Apple's pens, pages added and turned, and saving
/// it to the library.
struct NotebookEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    var embedded = false
    @State private var store = NotebookStore.shared
    @State private var index = 0
    @State private var saving = false
    @State private var saved: String?
    @State private var renaming = false
    @State private var confirmingDelete = false

    private var notebook: Notebook? { store.notebooks.first { $0.id == id } }

    var body: some View {
        if embedded {
            // Beside a lecture: inside its navigation, so a bar of its own rather than a second NavigationStack.
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text(notebook?.title ?? "Notes").font(.headline).lineLimit(1)
                    Spacer()
                    Button("Previous page", systemImage: "chevron.left") { withAnimation { index -= 1 } }.disabled(index == 0).labelStyle(.iconOnly)
                    Text("\(index + 1)/\(notebook?.pages.count ?? 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    if index + 1 < (notebook?.pages.count ?? 1) {
                        Button("Next page", systemImage: "chevron.right") { withAnimation { index += 1 } }.labelStyle(.iconOnly)
                    } else {
                        Button("Add a page", systemImage: "plus") { addPage() }.labelStyle(.iconOnly)
                    }
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Image(systemName: notebook?.needsSaving == false ? "checkmark.icloud" : "icloud.and.arrow.up") }
                    }
                    .accessibilityLabel("Save to library")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
                pages
            }
        } else {
            NavigationStack {
                pages
                    .navigationTitle(notebook?.title ?? "Notes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar }
            }
        }
    }

    private var pages: some View {
            ZStack(alignment: .bottom) {
                Color(white: 0.9).ignoresSafeArea()
                if let n = notebook, n.pages.indices.contains(index) {
                    PageCanvas(notebook: n, page: n.pages[index], store: store) { drawing in
                        store.setDrawing(drawing, n, n.pages[index])
                        var changed = n
                        changed.updated = .now
                        store.save(changed)
                    }
                    .id(n.pages[index].id)
                    .ignoresSafeArea(edges: .bottom)
                }
                if let saved {
                    Label(saved, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .alert("Title", isPresented: $renaming) {
                TextField("Title", text: Binding(get: { notebook?.title ?? "" }, set: { t in
                    guard var n = notebook else { return }
                    n.title = t; n.updated = .now; store.save(n)
                }))
                Button("Done") {}
            }
            .confirmationDialog("Delete this notebook from this phone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let n = notebook { store.delete(n) }; dismiss() }
            } message: {
                Text("A copy saved to your library stays there.")
            }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if !embedded {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done", systemImage: "chevron.down") { dismiss() }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                Task { await save() }
            } label: {
                if saving { ProgressView() } else { Label("Save to library", systemImage: notebook?.needsSaving == false ? "checkmark.icloud" : "icloud.and.arrow.up") }
            }
            .disabled(saving)
            Menu {
                Button("Rename", systemImage: "pencil") { renaming = true }
                Menu {
                    ForEach(Notebook.Paper.allCases, id: \.self) { p in
                        Button(p.rawValue.capitalized) { setPaper(p) }
                    }
                } label: { Label("Paper", systemImage: "doc.plaintext") }
                Button("Add a page", systemImage: "plus.rectangle.portrait") { addPage() }
                Button("Delete this page", systemImage: "minus.rectangle.portrait", role: .destructive) { deletePage() }
                    .disabled((notebook?.pages.count ?? 0) < 2)
                Divider()
                if let n = notebook {
                    ShareLink(item: PDFExport(data: store.pdfData(n), name: n.title), preview: SharePreview(n.title)) {
                        Label("Share as PDF", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Delete notebook", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: { Image(systemName: "ellipsis") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Previous page", systemImage: "chevron.left") { withAnimation { index -= 1 } }.disabled(index == 0)
            Spacer()
            Text("Page \(index + 1) of \(notebook?.pages.count ?? 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            if index + 1 < (notebook?.pages.count ?? 1) {
                Button("Next page", systemImage: "chevron.right") { withAnimation { index += 1 } }
            } else {
                Button("Add a page", systemImage: "plus") { addPage() }
            }
        }
    }

    private func addPage() {
        guard var n = notebook else { return }
        let last = n.pages.last
        n.pages.append(Notebook.Page(width: last?.width ?? Notebook.letter.width, height: last?.height ?? Notebook.letter.height,
                                     paper: last?.pdf == nil ? (last?.paper ?? .lined) : .lined))
        n.updated = .now
        store.save(n)
        withAnimation { index = n.pages.count - 1 }
    }

    private func deletePage() {
        guard var n = notebook, n.pages.count > 1 else { return }
        n.pages.remove(at: index)
        n.updated = .now
        store.save(n)
        index = min(index, n.pages.count - 1)
    }

    private func setPaper(_ p: Notebook.Paper) {
        guard var n = notebook else { return }
        n.pages[index].paper = p
        n.pages[index].pdf = nil
        n.updated = .now
        store.save(n)
    }

    private func save() async {
        guard let api = app.api else { return }
        saving = true
        defer { saving = false }
        do {
            try await store.upload(id, api: api)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { saved = "Saved to \(notebook?.lectureTitle ?? notebook?.className ?? app.libraryName)" }
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { saved = nil }
        } catch {
            withAnimation { saved = (error as? APIError)?.detail ?? "Couldn't save it. Try again." }
        }
    }
}

/// A PDF to share, named for its notebook.
struct PDFExport: Transferable {
    var data: Data
    var name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }.suggestedFileName { $0.name + ".pdf" }
    }
}

/// One page: PencilKit's canvas, the page's paper or PDF under the ink, zoomed to fit the width.
private struct PageCanvas: UIViewRepresentable {
    var notebook: Notebook
    var page: Notebook.Page
    var store: NotebookStore
    var changed: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = store.drawing(notebook, page)
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentSize = page.size
        canvas.minimumZoomScale = 0.3
        canvas.maximumZoomScale = 5
        canvas.delegate = context.coordinator
        canvas.alwaysBounceVertical = true
        canvas.overrideUserInterfaceStyle = .light

        let paper = UIImageView(image: UIGraphicsImageRenderer(size: page.size).image { r in
            store.render(notebook, page, in: r.cgContext, includeInk: false)
        })
        paper.layer.shadowColor = UIColor.black.cgColor
        paper.layer.shadowOpacity = 0.12
        paper.layer.shadowRadius = 6
        canvas.insertSubview(paper, at: 0)
        context.coordinator.paper = paper
        context.coordinator.pageSize = page.size

        let picker = PKToolPicker()
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            context.coordinator.fit(canvas)
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.changed = changed
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var changed: (PKDrawing) -> Void
        var paper: UIImageView?
        var picker: PKToolPicker?
        var pageSize: CGSize = .zero
        private var fitted = false

        init(changed: @escaping (PKDrawing) -> Void) { self.changed = changed }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) { changed(canvas.drawing) }

        func fit(_ canvas: PKCanvasView) {
            guard canvas.bounds.width > 0, !fitted else { return }
            fitted = true
            let scale = canvas.bounds.width / pageSize.width
            canvas.minimumZoomScale = min(scale, canvas.bounds.height / pageSize.height) * 0.9
            canvas.setZoomScale(scale, animated: false)
            scrollViewDidZoom(canvas)
        }

        func scrollViewDidZoom(_ scroll: UIScrollView) {
            let s = scroll.zoomScale
            paper?.frame = CGRect(origin: .zero, size: CGSize(width: pageSize.width * s, height: pageSize.height * s))
            scroll.contentSize = CGSize(width: pageSize.width * s, height: pageSize.height * s)
        }
    }
}
