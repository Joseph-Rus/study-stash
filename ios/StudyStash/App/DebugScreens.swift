#if DEBUG
import PencilKit
import SwiftUI
import UIKit

/// A screen a debug build opens straight away with `-show <name>`, for pictures in the simulator (see ios/DESIGN.md).
enum DebugScreen: Identifiable, Hashable {
    case record, uses, addFiles, importAudio, goodnotes, handwriting, notebook, widgets
    case ask(AskScope)
    case study(id: String, quiz: Bool)

    var id: String { "\(self)" }

    /// `record`, `uses`, `add-files`, `import-audio`, `goodnotes`, `handwriting`, `notebook`, `widgets`,
    /// `ask` (the first demo lecture), `ask:lecture:<id>`, `ask:class:<name>`, `study:<lecture id>`, `quiz:<lecture id>`.
    init?(_ s: String) {
        let parts = s.split(separator: ":", maxSplits: 2).map(String.init)
        switch parts.first {
        case "record": self = .record
        case "uses": self = .uses
        case "add-files": self = .addFiles
        case "import-audio": self = .importAudio
        case "goodnotes": self = .goodnotes
        case "handwriting": self = .handwriting
        case "notebook": self = .notebook
        case "widgets": self = .widgets
        case "ask":
            if parts.count == 3, parts[1] == "class" { self = .ask(.class(parts[2])); return }
            let id = parts.count == 3 ? parts[2] : DebugSamples.lectureID
            self = .ask(.lecture(id: id, title: DebugSamples.title(of: id)))
        case "study", "quiz":
            self = .study(id: parts.count > 1 ? parts[1] : DebugSamples.lectureID, quiz: parts[0] == "quiz")
        default: return nil
        }
    }

    /// Shown by MainTabs itself (the rest go through the app's own `incoming` and recorder).
    var isCover: Bool {
        switch self {
        case .study, .notebook, .widgets: true
        default: false
        }
    }
}

/// What the debug screens show: made-up files and a notebook, made on the phone, never sent anywhere.
@MainActor
enum DebugSamples {
    nonisolated static let lectureID = "demo-calc-ibp"

    nonisolated static func title(of id: String) -> String {
        DemoLibrary.lectures.first { $0.id == id }?.title ?? id
    }

    /// A photo of handwritten notes and a few slides, as if just chosen.
    static func files() -> [PendingFile] {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).pngData { r in
            UIColor.white.setFill()
            r.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            UIColor(white: 0.85, alpha: 1).setStroke()
            for y in stride(from: 80.0, to: 800, by: 36) { r.cgContext.stroke(CGRect(x: 0, y: y, width: 600, height: 0.5)) }
            UIColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1).setStroke()
            r.cgContext.setLineWidth(3)
            for row in 0..<8 {
                let y = 104.0 + Double(row) * 36
                r.cgContext.move(to: CGPoint(x: 40, y: y))
                for x in stride(from: 40.0, to: 520 - Double(row % 3) * 90, by: 12) {
                    r.cgContext.addLine(to: CGPoint(x: x, y: y - 10 * abs(sin(x / 9))))
                }
                r.cgContext.strokePath()
            }
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 960, height: 540)).pdfData { r in
            for i in 1...3 {
                r.beginPage()
                ("Week 6, slide \(i)" as NSString).draw(at: CGPoint(x: 60, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 48, weight: .bold)])
            }
        }
        return [PendingFile(name: "Photo 1.png", type: "image/png", data: photo),
                PendingFile(name: "Week 6 slides.pdf", type: "application/pdf", data: pdf)]
    }

    /// A recording from Voice Memos, as if shared to the app (its sound isn't real: it's only shown, never imported).
    static func audio() -> PendingFile {
        PendingFile(name: "Calculus II, 14 Oct.m4a", type: "audio/mp4", data: Data(count: 2_400_000))
    }

    /// A GoodNotes notebook of one blank page: the smallest file the importer reads (a zip of the notebook's index
    /// and the page's journal).
    static func goodNotes() -> URL {
        let page = "8F0D4C1E-2B7A-4E55-9C11-6A3B0F9E7D01"
        let record = Data([0x0A, UInt8(page.utf8.count)]) + Data(page.utf8)
        let index = Data([UInt8(record.count)]) + record
        let url = FileManager.default.temporaryDirectory.appending(path: "Biology notebook.goodnotes")
        try? zip([("index.notes.pb", index), ("notes/\(page)", Data())]).write(to: url)
        return url
    }

    /// A notebook with a page of handwriting, kept on this phone (the Home tab's shelf shows it from then on).
    static func notebook() -> UUID {
        let store = NotebookStore.shared
        if let n = store.notebooks.first { return n.id }
        let n = Notebook.blank(title: "Calculus II notes, 14 Oct", className: "Calculus II", lecture: nil)
        store.save(n)
        var strokes: [PKStroke] = []
        let ink = PKInk(.pen, color: UIColor(red: 0.1, green: 0.15, blue: 0.4, alpha: 1))
        for row in 0..<6 {
            let y = 140.0 + Double(row) * 46
            let end = 520.0 - Double(row % 3) * 110
            var points: [PKStrokePoint] = []
            for (i, x) in stride(from: 60.0, to: end, by: 6).enumerated() {
                points.append(PKStrokePoint(location: CGPoint(x: x, y: y - 12 * abs(sin(x / 11))), timeOffset: Double(i) * 0.01,
                                            size: CGSize(width: 2.6, height: 2.6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
            }
            strokes.append(PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: .now)))
        }
        if let page = n.pages.first { store.setDrawing(PKDrawing(strokes: strokes), n, page) }
        return n.id
    }

    /// Stored (uncompressed) zip entries.
    private static func zip(_ entries: [(String, Data)]) -> Data {
        func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        func u32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        var out = Data(), central = Data()
        for (name, data) in entries {
            let n = Data(name.utf8)
            let offset = out.count
            // A local header, then the bytes as they are.
            for part in [u32(0x0403_4b50), u16(20), u16(0), u16(0), u16(0), u16(0), u32(0), u32(data.count), u32(data.count),
                         u16(n.count), u16(0), n, data] { out.append(part) }
            for part in [u32(0x0201_4b50), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0), u32(0), u32(data.count),
                         u32(data.count), u16(n.count), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), n] { central.append(part) }
        }
        let start = out.count
        out.append(central)
        for part in [u32(0x0605_4b50), u16(0), u16(0), u16(entries.count), u16(entries.count), u32(central.count), u32(start), u16(0)] {
            out.append(part)
        }
        return out
    }
}
#endif
