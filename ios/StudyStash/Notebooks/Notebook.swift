import Foundation
import Observation
import PDFKit
import PencilKit
import UIKit

/// A handwritten notebook on this phone: pages of ink (PencilKit), each on plain, lined or grid paper or over a PDF
/// page (one imported from GoodNotes keeps its PDFs). Saved to the library as a PDF in a class (and a lecture),
/// where it's read, handwriting too, for notes and Ask; saved again, it replaces the copy there.
struct Notebook: Codable, Identifiable, Hashable, Sendable {
    enum Paper: String, Codable, CaseIterable, Sendable { case plain, lined, grid, dotted }

    struct Page: Codable, Hashable, Identifiable, Sendable {
        var id = UUID()
        var width: Double
        var height: Double
        var paper: Paper = .lined
        /// A PDF beside the notebook, and its page (from 1), drawn under the ink instead of the paper.
        var pdf: String?
        var pdfPage: Int = 1

        var size: CGSize { CGSize(width: width, height: height) }
    }

    var id = UUID()
    var title: String
    var className: String?
    var lectureID: String?
    var lectureTitle: String?
    var pages: [Page]
    var created = Date.now
    var updated = Date.now
    /// The copy in the library, so saving again replaces it.
    var attachmentID: String?
    var savedAt: Date?
    var importedFrom: String?

    /// US Letter at 72 points an inch, the paper a new page is.
    static let letter = CGSize(width: 612, height: 792)

    static func blank(title: String, className: String?, lecture: (id: String, title: String)?, paper: Paper = .lined) -> Notebook {
        Notebook(title: title, className: className, lectureID: lecture?.id, lectureTitle: lecture?.title,
                 pages: [Page(width: letter.width, height: letter.height, paper: paper)])
    }

    var needsSaving: Bool { savedAt.map { $0 < updated } ?? true }
}

/// The notebooks on this phone: Application Support/Notebooks/<id>/ holds notebook.json, each page's ink
/// (<page id>.drawing) and the PDFs pages are drawn over.
@MainActor @Observable
final class NotebookStore {
    static let shared = NotebookStore()

    private(set) var notebooks: [Notebook] = []
    let folder: URL

    init(folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Notebooks")) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        notebooks = dirs.compactMap { try? JSONDecoder.iso.decode(Notebook.self, from: Data(contentsOf: $0.appending(path: "notebook.json"))) }
            .sorted { $0.updated > $1.updated }
    }

    func dir(_ n: Notebook) -> URL { folder.appending(path: n.id.uuidString) }

    func save(_ n: Notebook) {
        try? FileManager.default.createDirectory(at: dir(n), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.iso.encode(n) { try? data.write(to: dir(n).appending(path: "notebook.json"), options: .atomic) }
        if let i = notebooks.firstIndex(where: { $0.id == n.id }) { notebooks[i] = n } else { notebooks.insert(n, at: 0) }
        notebooks.sort { $0.updated > $1.updated }
    }

    func delete(_ n: Notebook) {
        try? FileManager.default.removeItem(at: dir(n))
        notebooks.removeAll { $0.id == n.id }
    }

    func drawing(_ n: Notebook, _ page: Notebook.Page) -> PKDrawing {
        (try? Data(contentsOf: dir(n).appending(path: "\(page.id.uuidString).drawing"))).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
    }

    func setDrawing(_ d: PKDrawing, _ n: Notebook, _ page: Notebook.Page) {
        try? FileManager.default.createDirectory(at: dir(n), withIntermediateDirectories: true)
        try? d.dataRepresentation().write(to: dir(n).appending(path: "\(page.id.uuidString).drawing"), options: .atomic)
    }

    func pdf(_ n: Notebook, _ page: Notebook.Page) -> PDFPage? {
        guard let name = page.pdf, let doc = pdfCache[dir(n).appending(path: name)] ?? PDFDocument(url: dir(n).appending(path: name)) else { return nil }
        pdfCache[dir(n).appending(path: name)] = doc
        return doc.page(at: max(0, page.pdfPage - 1))
    }

    @ObservationIgnored private var pdfCache: [URL: PDFDocument] = [:]

    // MARK: rendering

    /// The page as it looks: its paper or PDF, then the ink.
    func render(_ n: Notebook, _ page: Notebook.Page, in ctx: CGContext, includeInk: Bool = true) {
        let rect = CGRect(origin: .zero, size: page.size)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        if let pdfPage = pdf(n, page) {
            ctx.saveGState()
            let box = pdfPage.bounds(for: .mediaBox)
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: rect.width / box.width, y: -rect.height / box.height)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            pdfPage.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        } else {
            PaperDrawing.draw(page.paper, in: rect, ctx: ctx)
        }
        if includeInk {
            // PencilKit lightens dark ink for dark mode; a page is always paper.
            var ink = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent { ink = drawing(n, page).image(from: rect, scale: 2) }
            UIGraphicsPushContext(ctx)
            ink.draw(in: rect)
            UIGraphicsPopContext()
        }
    }

    /// The whole notebook as one PDF, a page each.
    func pdfData(_ n: Notebook) -> Data {
        let first = n.pages.first?.size ?? Notebook.letter
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first))
        return renderer.pdfData { r in
            for page in n.pages {
                r.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                render(n, page, in: r.cgContext)
            }
        }
    }

    func thumbnail(_ n: Notebook, width: CGFloat = 240) -> UIImage? {
        guard let page = n.pages.first else { return nil }
        let scale = width / page.size.width
        let size = CGSize(width: width, height: page.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { r in
            r.cgContext.scaleBy(x: scale, y: scale)
            render(n, page, in: r.cgContext)
        }
    }

    /// Save it to the library: the PDF into its class (and lecture), replacing the copy saved before.
    func upload(_ id: UUID, api: APIClient) async throws {
        guard var n = notebooks.first(where: { $0.id == id }) else { return }
        let name = n.title.replacingOccurrences(of: "/", with: "-") + ".pdf"
        let added = try await api.upload(files: [(name, "application/pdf", pdfData(n))], class: n.className, lecture: n.lectureID)
        if let old = n.attachmentID, old != added.first?.id { try? await api.deleteAttachment(old) }
        n.attachmentID = added.first?.id
        n.savedAt = .now
        save(n)
    }

    // MARK: GoodNotes

    /// A GoodNotes notebook, as one of these: each page's size and PDF kept, its strokes as PencilKit ink.
    func importGoodNotes(_ g: GoodNotesNotebook, className: String?, lecture: (id: String, title: String)?) -> Notebook {
        var n = Notebook(title: g.title, className: className, lectureID: lecture?.id, lectureTitle: lecture?.title, pages: [],
                         importedFrom: "GoodNotes")
        try? FileManager.default.createDirectory(at: dir(n), withIntermediateDirectories: true)
        var pdfNames: [Data: String] = [:]
        for gp in g.pages {
            var page = Notebook.Page(width: gp.size.width, height: gp.size.height, paper: .plain)
            if let bg = gp.background {
                let name = pdfNames[bg.pdf] ?? "background-\(pdfNames.count + 1).pdf"
                if pdfNames[bg.pdf] == nil {
                    try? bg.pdf.write(to: dir(n).appending(path: name))
                    pdfNames[bg.pdf] = name
                }
                page.pdf = name
                page.pdfPage = bg.page
            }
            setDrawing(Self.drawing(from: gp.strokes), n, page)
            n.pages.append(page)
        }
        save(n)
        return n
    }

    nonisolated static func drawing(from strokes: [GoodNotesNotebook.Stroke]) -> PKDrawing {
        var out: [PKStroke] = []
        for s in strokes {
            let color = UIColor(red: s.color.r, green: s.color.g, blue: s.color.b, alpha: s.highlighter ? min(s.color.a, 0.35) : s.color.a)
            let inkType: PKInk.InkType = s.highlighter ? .marker : .pen
            let ink = PKInk(inkType, color: color)
            for path in s.paths {
                var t: TimeInterval = 0
                let points = path.map { p -> PKStrokePoint in
                    defer { t += 0.008 }
                    // GoodNotes keeps a pen's half-width (its nib's radius). PencilKit draws nothing at all for a stroke
                    // made in code narrower than about 2.4 (whatever validWidthRange says), so a fine pen comes in at 2.5.
                    let w = max(p.width * 2, 2.5)
                    return PKStrokePoint(location: p.point, timeOffset: t, size: CGSize(width: w, height: w),
                                         opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                // A dot: one point, drawn as a short stroke so it shows.
                let all = points.count == 1 ? [points[0], PKStrokePoint(location: CGPoint(x: points[0].location.x + 0.3, y: points[0].location.y),
                                                                           timeOffset: 0.01, size: points[0].size, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)] : points
                out.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: all, creationDate: .now)))
            }
        }
        return PKDrawing(strokes: out)
    }
}

/// Plain, lined, grid and dotted paper, drawn in a page's own units.
enum PaperDrawing {
    static func draw(_ paper: Notebook.Paper, in rect: CGRect, ctx: CGContext) {
        let line = UIColor(red: 0.72, green: 0.8, blue: 0.9, alpha: 0.55).cgColor
        let step: CGFloat = paper == .lined ? 26 : 18
        ctx.saveGState()
        switch paper {
        case .plain: break
        case .lined:
            ctx.setStrokeColor(line)
            ctx.setLineWidth(0.6)
            var y = rect.minY + 72
            while y < rect.maxY - 24 { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
            ctx.strokePath()
            ctx.setStrokeColor(UIColor(red: 0.95, green: 0.55, blue: 0.55, alpha: 0.5).cgColor)
            ctx.move(to: CGPoint(x: rect.minX + 60, y: rect.minY)); ctx.addLine(to: CGPoint(x: rect.minX + 60, y: rect.maxY))
            ctx.strokePath()
        case .grid:
            ctx.setStrokeColor(line)
            ctx.setLineWidth(0.4)
            var x = rect.minX + step
            while x < rect.maxX { ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
            var y = rect.minY + step
            while y < rect.maxY { ctx.move(to: CGPoint(x: rect.minX, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
            ctx.strokePath()
        case .dotted:
            ctx.setFillColor(UIColor(white: 0.6, alpha: 0.7).cgColor)
            var y = rect.minY + step
            while y < rect.maxY {
                var x = rect.minX + step
                while x < rect.maxX { ctx.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)); x += step }
                y += step
            }
        }
        ctx.restoreGState()
    }
}
