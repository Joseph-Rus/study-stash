import PDFKit
import PencilKit
import SwiftUI

/// A GoodNotes notebook (shared from GoodNotes: Share, then Export, then GoodNotes; or chosen in Attach) brought in as
/// a notebook here: every page, its PDF and its ink, which stays ink (keep writing on it), then saved to the library
/// for notes and Ask. It shows the notebook's first page as it'll look, how much is in it, and where it'll go.
struct GoodNotesImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let url: URL
    /// Where it goes: the class (and lecture) Attach was opened for; from GoodNotes' share sheet, chosen here.
    @State private var className: String?
    var lecture: (id: String, title: String)?

    @State private var book: GoodNotesNotebook?
    @State private var cover: UIImage?
    @State private var problem: String?
    @State private var working = false
    @State private var opened: UUID?

    /// From GoodNotes' share sheet: it suggests the class on the calendar now (Unsorted if none).
    private let suggestsPlace: Bool

    init(url: URL) {
        self.url = url
        suggestsPlace = true
    }

    /// From Attach: where Attach was opened for (nil is Unsorted).
    init(url: URL, className: String?, lecture: (id: String, title: String)?) {
        self.url = url
        _className = State(initialValue: className)
        self.lecture = lecture
        suggestsPlace = false
    }

    var body: some View {
        if let opened {
            // Brought in: it opens over the whole screen, as every notebook does, and this sheet gives way.
            Color.surface.task { app.incoming = .notebook(opened) }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let book {
                            ready(book)
                        } else if let problem {
                            EmptyState(title: "Couldn't read this notebook", detail: problem)
                        } else {
                            HStack(spacing: 10) {
                                StudyLoader(.page, color: .inkSubtle)
                                Text("Reading the notebook…").textStyle(.lede).foregroundStyle(.inkMuted)
                            }
                            .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, Space.pageCompact)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .page()
                .foregroundStyle(.ink)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Text("Cancel").textStyle(.nav) }
                    }
                }
                .navigationDestination(isPresented: $choosingPlace) {
                    FolderChoiceList(title: "Attach to", selection: $className)
                }
            }
            .task {
                if suggestsPlace, className == nil { className = app.classNow(app.upcoming) }
                await read()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-import-local"), let book {
                    opened = NotebookStore.shared.importGoodNotes(book, className: nil, lecture: nil).id
                }
                #endif
            }
        }
    }

    @State private var choosingPlace = false

    @ViewBuilder private func ready(_ book: GoodNotesNotebook) -> some View {
        let strokes = book.pages.reduce(0) { $0 + $1.strokes.count }
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let cover { Image(uiImage: cover).resizable().scaledToFit() } else { Color.white }
            }
            .frame(width: 104)
            .aspectRatio(book.pages.first.map { $0.size.width / max(1, $0.size.height) } ?? 0.77, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 4))
            .lifted(.today, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("The notebook's first page")
            VStack(alignment: .leading, spacing: 6) {
                Text("From GoodNotes").textStyle(.meta).foregroundStyle(.inkMuted)
                Text(book.title).textStyle(.docTitle).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(count(book.pages.count, "page") + ", " + (strokes == 0 ? "no ink yet" : count(strokes, "stroke") + " of ink"))
                    .textStyle(.meta).foregroundStyle(.inkSubtle)
            }
        }
        .padding(.top, 8)

        Text("Your ink comes in as ink: keep writing on it here. Saved to your library, it's read for notes and Ask.")
            .textStyle(.lede).foregroundStyle(.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)

        if let lecture {
            Panel(padding: 0) {
                HStack(spacing: 12) {
                    Text("Attach to").textStyle(.nav).foregroundStyle(.inkMuted)
                    Spacer(minLength: 8)
                    Text(lecture.title).textStyle(.nav).fontWeight(.semibold).foregroundStyle(.ink).lineLimit(1)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            .padding(.top, 20)
        } else {
            Panel(padding: 0) {
                Button { choosingPlace = true } label: { PlaceRow(label: "Attach to", className: className) }
                    .buttonStyle(AttachRowStyle())
            }
            .padding(.top, 20)
        }

        Button { Task { await bringIn() } } label: {
            HStack(spacing: 8) {
                if working { StudyLoader(.inline, color: .surface) }
                Text(working ? "Bringing it in…" : "Import")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pill(ink: true))
        .disabled(working)
        .padding(.top, 16)
    }

    private func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n.formatted()) \(noun)s"
    }

    private func read() async {
        let url = url
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let book = try await Task.detached(priority: .userInitiated) { () throws -> GoodNotesNotebook in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try GoodNotesNotebook(data: Data(contentsOf: url), title: title)
            }.value
            self.book = book
            if let first = book.pages.first { cover = Self.picture(first, width: 208) }
        } catch {
            problem = (error as? GoodNotesError)?.words
                ?? "That isn't a GoodNotes notebook Egghead Notes can read. In GoodNotes, try Share, then Export, then PDF instead, and attach the PDF."
        }
    }

    /// A page as it'll look here: white paper, its PDF if it has one, then its ink.
    private static func picture(_ page: GoodNotesNotebook.Page, width: CGFloat) -> UIImage {
        let rect = CGRect(origin: .zero, size: page.size)
        let scale = width / max(1, page.size.width)
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: page.size.height * scale)).image { r in
            let ctx = r.cgContext
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(rect)
            if let bg = page.background, let doc = PDFDocument(data: bg.pdf), let pdf = doc.page(at: max(0, bg.page - 1)) {
                let box = pdf.bounds(for: .mediaBox)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: rect.height)
                ctx.scaleBy(x: rect.width / box.width, y: -rect.height / box.height)
                ctx.translateBy(x: -box.minX, y: -box.minY)
                pdf.draw(with: .mediaBox, to: ctx)
                ctx.restoreGState()
            }
            var ink = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = NotebookStore.drawing(from: page.strokes).image(from: rect, scale: 2 * scale)
            }
            UIGraphicsPushContext(ctx)
            ink.draw(in: rect)
            UIGraphicsPopContext()
        }
    }

    private func bringIn() async {
        guard let book else { return }
        working = true
        defer { working = false }
        let n = NotebookStore.shared.importGoodNotes(book, className: className, lecture: lecture)
        if let api = app.api { try? await NotebookStore.shared.upload(n.id, api: api) }
        opened = n.id
    }
}
