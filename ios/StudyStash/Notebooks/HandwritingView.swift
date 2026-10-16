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
            if let id {
                NotebookEditor(id: id, embedded: embedded) { self.id = nil }
            } else {
                Color.surface
            }
        }
        .task(id: id) {
            if id != nil { return }
            if let lecture, let existing = store.notebooks.first(where: { $0.lectureID == lecture.id }) {
                id = existing.id
                return
            }
            let day = Format.date(.now)
            let title = lecture.map { "Notes, \($0.title)" } ?? className.map { "\($0) notes, \(day)" } ?? "Notes, \(day)"
            let n = Notebook.blank(title: title, className: className, lecture: lecture)
            store.save(n)
            id = n.id
        }
    }
}

/// One notebook, a page at a time: the ink over its paper (or PDF) on the grey desk, Apple's pens, pages added and
/// turned. Done (the chevron) saves it to the library when anything changed and says so ("Saved to Calculus II.", or,
/// offline, that it's kept here and sent later); a notebook closed with nothing written in it is let go. There's no
/// Save button.
struct NotebookEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let id: UUID
    var embedded = false
    /// Beside a lecture, after Delete notebook: the page beside starts a fresh one.
    var onDeleted: (() -> Void)?
    @State private var store = NotebookStore.shared
    @State private var index = 0
    @State private var closing = false
    @State private var message: String?
    @State private var renaming = false
    @State private var confirmingDelete = false

    private var notebook: Notebook? { store.notebooks.first { $0.id == id } }
    private var pageCount: Int { notebook?.pages.count ?? 1 }

    var body: some View {
        Group {
            if embedded {
                // Beside a lecture: inside its navigation, so a bar of its own rather than a second NavigationStack.
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(notebook?.title ?? "Notes").textStyle(.title).foregroundStyle(.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        pageTurner(compact: true)
                        Menu { menuItems } label: { Label("More", icon: "more_horiz") }
                            .buttonStyle(.icon)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
                    .background(.surface)
                    .overlay(alignment: .bottom) { Rule() }
                    pages
                }
            } else {
                NavigationStack {
                    pages
                        .overlay(alignment: .top) {
                            pageTurner(compact: false)
                                .padding(.horizontal, 6)
                                .frame(height: 40)
                                .background(.surface, in: .capsule)
                                .lifted(.float, in: Capsule())
                                .padding(.top, 10)
                        }
                        .navigationTitle(notebook?.title ?? "Notes")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { toolbar }
                }
            }
        }
        .task {
            // Anything kept on this phone while the library couldn't be reached goes now.
            if let api = app.api { await store.sendWaiting(api: api) }
        }
        // Closed some other way (beside a lecture, or the app going elsewhere): saved all the same, quietly.
        .onDisappear { saveQuietly() }
    }

    private var pages: some View {
        ZStack(alignment: .bottom) {
            Color.canvas.ignoresSafeArea()
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
        }
        .overlay(alignment: .bottom) {
            // Above Apple's pens, which sit along the foot of a phone.
            if let message {
                Toast(message)
                    .padding(.horizontal, 20)
                    .padding(.bottom, sizeClass == .regular ? 24 : 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: message)
        .alert("Rename notebook", isPresented: $renaming) {
            TextField("Title", text: Binding(get: { notebook?.title ?? "" }, set: { t in
                guard var n = notebook else { return }
                n.title = t; n.updated = .now; store.save(n)
            }))
            Button("Done") {}
        }
        .confirmationDialog("Delete this notebook from this phone?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete notebook", role: .destructive) { deleteNotebook() }
        } message: {
            Text(notebook?.savedAt == nil ? "It hasn't been saved to your library, so it'll be gone." : "The copy saved to your library stays there.")
        }
    }

    /// ‹ Page 2 of 3 › (or + on the last page, to add one).
    private func pageTurner(compact: Bool) -> some View {
        HStack(spacing: 2) {
            Button { withAnimation { index -= 1 } } label: { Label("Previous page", icon: "chevron_left") }
                .buttonStyle(.icon)
                .disabled(index == 0)
                .opacity(index == 0 ? 0.35 : 1)
            Text(compact ? "\(index + 1) of \(pageCount)" : "Page \(index + 1) of \(pageCount)")
                .textStyle(.meta).foregroundStyle(.inkMuted)
                .padding(.horizontal, 4)
                .accessibilityLabel("Page \(index + 1) of \(pageCount)")
            if index + 1 < pageCount {
                Button { withAnimation { index += 1 } } label: { Label("Next page", icon: "chevron_right") }
                    .buttonStyle(.icon)
            } else {
                Button { addPage() } label: { Label("Add a page", icon: "page_add") }
                    .buttonStyle(.icon)
            }
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button { renaming = true } label: { Label("Rename", icon: "edit") }
        Menu {
            ForEach(Notebook.Paper.allCases, id: \.self) { p in
                Button { setPaper(p) } label: {
                    if currentPaper == p { Label(p.rawValue.capitalized, icon: "check") } else { Text(p.rawValue.capitalized) }
                }
            }
        } label: { Label("Paper", icon: "description") }
        Button { addPage() } label: { Label("Add a page", icon: "page_add") }
        Button(role: .destructive) { deletePage() } label: { Label("Delete this page", icon: "page_remove") }
            .disabled(pageCount < 2)
        Divider()
        if let n = notebook {
            ShareLink(item: PDFExport(data: store.pdfData(n), name: n.title), preview: SharePreview(n.title)) {
                Label("Share as PDF", icon: "ios_share")
            }
        }
        Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete notebook", icon: "delete") }
    }

    private var currentPaper: Notebook.Paper? {
        guard let n = notebook, n.pages.indices.contains(index), n.pages[index].pdf == nil else { return nil }
        return n.pages[index].paper
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { Task { await close() } } label: {
                if closing { ProgressView().tint(.inkSubtle) } else { Label("Done", icon: "expand_more") }
            }
            .disabled(closing)
            .accessibilityLabel("Done")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu { menuItems } label: { Label("More", icon: "more_horiz") }
        }
    }

    // MARK: Pages

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

    private func deleteNotebook() {
        guard let n = notebook else { return }
        store.delete(n)
        if embedded { onDeleted?() } else { dismiss() }
    }

    // MARK: Saving

    /// Where it's saved, in words: its class, else its lecture, else the library.
    private func place(_ n: Notebook) -> String { n.className ?? n.lectureTitle ?? app.libraryName }

    /// Done: save to the library if anything changed, say so, then close. A notebook with nothing in it, never saved,
    /// is let go instead.
    private func close() async {
        guard let n = notebook else { dismiss(); return }
        if n.savedAt == nil, store.isBlank(n) {
            store.delete(n)
            dismiss()
            return
        }
        guard n.needsSaving, let api = app.api else { dismiss(); return }
        closing = true
        let outcome = await store.send(n.id, api: api, waitingAtMost: .seconds(6))
        switch outcome {
        case .saved:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "Saved to \(place(n))."
        case .kept: message = "Saved on this phone. It's sent when your library can be reached."
        case .stillSending: message = "Saving to \(place(n)). It carries on after this closes."
        }
        try? await Task.sleep(for: .seconds(outcome == .saved ? 1.2 : 2.4))
        dismiss()
    }

    private func saveQuietly() {
        guard !closing, let n = notebook else { return }
        if n.savedAt == nil, store.isBlank(n) {
            store.delete(n)
            return
        }
        if n.needsSaving, let api = app.api {
            let store = store
            Task { _ = await store.send(n.id, api: api, waitingAtMost: .seconds(120)) }
        }
    }
}

// MARK: - Saving to the library

/// How a save went: in the library, kept on this phone (the library couldn't be reached), or still on its way.
enum NotebookSend: Sendable { case saved, kept, stillSending }

extension NotebookStore {
    /// Notebooks being sent right now, so one isn't sent twice at once (a second copy in the library).
    @MainActor private static var sending: Set<UUID> = []

    /// Nothing written, drawn or brought in: every page plain paper with no ink.
    func isBlank(_ n: Notebook) -> Bool {
        n.importedFrom == nil && n.pages.allSatisfy { $0.pdf == nil && drawing(n, $0).strokes.isEmpty }
    }

    /// Send a notebook to the library, waiting at most `wait` to hear how it went (it carries on after that).
    func send(_ id: UUID, api: APIClient, waitingAtMost wait: Duration) async -> NotebookSend {
        guard !Self.sending.contains(id) else { return .stillSending }
        Self.sending.insert(id)
        let upload = Task { @MainActor in
            defer { Self.sending.remove(id) }
            return (try? await self.upload(id, api: api)) != nil
        }
        return await withTaskGroup(of: NotebookSend.self) { group in
            group.addTask { await upload.value ? .saved : .kept }
            group.addTask {
                try? await Task.sleep(for: wait)
                return .stillSending
            }
            let first = await group.next() ?? .stillSending
            group.cancelAll()
            return first
        }
    }

    /// Every notebook with something in it that changed since it last reached the library (closed while it couldn't
    /// be reached), sent now. The notebook open and the library's refresh call it.
    func sendWaiting(api: APIClient) async {
        for n in notebooks where n.needsSaving && !isBlank(n) && !Self.sending.contains(n.id) {
            _ = await send(n.id, api: api, waitingAtMost: .seconds(120))
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
