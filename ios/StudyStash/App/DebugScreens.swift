#if DEBUG
import PencilKit
import SwiftUI
import UIKit

/// A screen a debug build opens straight away with `-show <name>`, for pictures in the simulator (see ios/DESIGN.md).
enum DebugScreen: Identifiable, Hashable {
    case record, uses, addFiles, importAudio, goodnotes, handwriting, notebook, widgets
    case ask(AskScope)
    /// The shared pieces of the look, page 1–4 (`components`, `components:2`, …), to set beside the desktop's.
    case components(Int)
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
        case "components": self = .components(parts.count > 1 ? Int(parts[1]) ?? 1 : 1)
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
        case .study, .notebook, .widgets, .components: true
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

    /// A notebook of three pages of handwriting (narrow ruled, grid, Cornell notes), kept on this phone (the Home
    /// tab's shelf shows it from then on): `NotebookSamples`.
    static func notebook() -> UUID { NotebookSamples.make() }

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

#if DEBUG
/// Every shared piece of the look in its states, a page at a time (`-show components:<1-4>`): what ios/DESIGN.md
/// describes, drawn by the app itself, to compare with the desktop's pictures.
struct ComponentGallery: View {
    @Environment(AppModel.self) private var app
    var page: Int
    @State private var text = ""
    @State private var tab = 0
    @State private var seg = 0
    @State private var only = true

    var body: some View {
        NavigationStack {
            gallery
                .navigationTitle("Components")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // A bar button's words as the system draws them, and as Atkinson (for the page lanes to compare).
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { } }
                    ToolbarItem(placement: .confirmationAction) { Button { } label: { Text("Done").textStyle(.button) } }
                }
        }
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch page {
                case 2: second
                case 3: third
                case 4: icons
                default: first
                }
            }
            .padding(.horizontal, Space.pageCompact)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .page()
    }

    private var first: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Format.longDate()).textStyle(.date)
                Text("Calculus II starts in 11 minutes. Problem Set 6 is due tonight.").textStyle(.lede).foregroundStyle(.inkMuted)
            }
            HStack(spacing: 8) {
                RecordButton { }
                Button { } label: { Label("Attach", icon: "attach_file") }.buttonStyle(.pill)
            }
            HStack(spacing: 8) {
                RecordButton(state: .recording, words: "Calculus II", elapsed: "12:04", levels: [0.4, 0.9, 0.6]) { } stop: { }
                RecordButton(state: .paused, words: "Paused", elapsed: "12:04") { }
            }
            SectionHeading(title: "Up next")
            VStack(spacing: 0) {
                EventRow(event: UpcomingEvent(id: "a", title: "Calculus II", start: iso(11 * 60), end: iso(61 * 60), allDay: false, location: nil, class: "Calculus II"))
                EventRow(event: UpcomingEvent(id: "b", title: "Study group", start: iso(26 * 3600), end: iso(27 * 3600), allDay: false, location: nil, class: "Intro to Psychology"))
                EventRow(event: UpcomingEvent(id: "c", title: "Career fair", start: iso(27 * 3600), end: iso(28 * 3600), allDay: false, location: nil, class: nil), suggest: false)
            }
            HStack(alignment: .lastTextBaseline) {
                SectionHeading(title: "Notes")
                Menu { Button("All notes") { } } label: { PickerLabel("All notes") }.buttonStyle(.picker)
            }
            VStack(spacing: 0) {
                NoteRow(lecture: lecture("Integration by Parts and the LIATE Rule", "Calculus II", 0, 52, "How to integrate products by reversing the product rule, and how to choose $u$ with $x^2$ and $\\int u\\,dv$."), first: true)
                NoteRow(lecture: lecture("", "Unsorted", 2, 18, "A study group planning the week before the midterm."), onFolder: { })
                NoteRow(lecture: lecture("Memory: Encoding, Storage and Retrieval", "Intro to Psychology", 9, 74, "", status: "working"))
            }
        }
    }

    private var second: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                StudyStashLogo(size: 64)
                StudyStashLogo(size: 32)
            }
            FolderTitle("Calculus II", hue: .yellow)
            Text("MATH 162 on Canvas. Meets Monday, Wednesday and Friday at 9:00 AM.").textStyle(.lede).foregroundStyle(.inkMuted)
            GroupLabel("This week")
            NoteRow(lecture: lecture("Integration by Parts and the LIATE Rule", "Calculus II", 0, 72, "How to integrate products by reversing the product rule."), showFolder: false, first: true)
            SectionHeading(title: "Highlights")
            FlowLayout(spacing: 10) {
                ForEach(Highlighter.allCases, id: \.self) { h in Highlight(h.rawValue.capitalized, hue: h) }
                Highlight("No class", hue: nil)
                Highlight("Handed in", hue: .blue, style: .due, struck: true)
                Highlight("Pressed", hue: .pink, style: .due, outlined: true)
            }
            Highlight("A long assignment name that wraps onto a second line in the calendar", hue: .green, style: .due)
            HStack(spacing: 12) {
                ForEach(Highlighter.allCases, id: \.self) { h in Swatch(h) }
                Swatch(nil)
                Swatch(.blue, small: true)
            }
            SectionHeading(title: "Buttons", trailing: "See all") { }
            HStack(spacing: 8) {
                Button("Today") { }.buttonStyle(.pill(small: true))
                Button { } label: { Label("Pause", icon: "pause", filled: true) }.buttonStyle(.pill(small: true))
                Button { } label: { Label("Stop", icon: "stop", filled: true) }.buttonStyle(.pill(small: true, ink: true))
            }
            HStack(spacing: 12) {
                Button { } label: { Label("Open in Canvas", icon: "open_in_new") }.buttonStyle(.quiet)
                Button("See these on the calendar") { }.buttonStyle(.textLink)
            }
            HStack(spacing: 4) {
                Button { } label: { Label("Search", icon: "search") }.buttonStyle(.icon)
                Button { } label: { Label("Settings", icon: "settings") }.buttonStyle(.icon)
                Button { } label: { Label("Share", icon: "ios_share") }.buttonStyle(.icon)
                Button { } label: { Label("Delete", icon: "delete") }.buttonStyle(.icon)
            }
            Button("Pair") { }.buttonStyle(.pill(ink: true)).frame(maxWidth: .infinity)
        }
    }

    private var third: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabStrip(selection: $tab, tabs: [(0, "Notes"), (1, "Transcript")])
            HStack(spacing: 12) {
                Text("Body").textStyle(.body)
                Text("weight bold").textStyle(.body).fontWeight(.bold)
                Text("bold()").textStyle(.body).bold()
                Text("italic").textStyle(.body, italic: true)
                Text("0123 1:45").textStyle(.body)
            }
            HStack(spacing: 24) {
                StudyLoader(.inline); StudyLoader(.page); StudyLoader(.screen)
                HStack(spacing: 8) { StudyLoader(.inline, color: .inkSubtle); Text("Loading your notes").textStyle(.body).foregroundStyle(.inkMuted) }
            }
            HStack {
                Segmented(selection: $seg, options: [(0, "Month"), (1, "Week")])
                Spacer()
                Toggle("Only my notes", isOn: $only).toggleStyle(.ink)
            }
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    row("Demo library", "Connected")
                    Rule()
                    row("Syft Notes", "0.17.0")
                }
            }
            EmptyText("No lectures yet. Record one here, or attach a recording.")
            EmptyState(title: "Can't reach your library", detail: "Turn Tailscale on here and on your computer, and keep Syft Notes open.", actionTitle: "Try again") { }
            AskBar(placeholder: "Ask anything about your notes", text: $text, scope: "All notes") { }
            AskBarButton(placeholder: "Ask about this lecture", scope: "This lecture") { }
            Toast("Moved to Calculus II.", actionTitle: "Undo") { }
            Toast("Recording saved", detail: "Syft Notes is writing it down; the library files it and writes your notes.")
            OfflineNote()
            TopicChips(topics: ["Integration by parts", "LIATE", "Tabular method"])
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AppText.allCases, id: \.self) { s in Text("\(s)").textStyle(s) }
            }
        }
    }

    private var icons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 4)], alignment: .leading, spacing: 10) {
            ForEach(IconNames.all, id: \.self) { name in
                VStack(spacing: 4) {
                    Icon(name, size: 24, filled: IconNames.solid.contains(name))
                    Text(name).font(.atkinson(9, .medium)).foregroundStyle(.inkSubtle).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a).textStyle(.body); Spacer(); Text(b).textStyle(.body).foregroundStyle(.inkMuted) }.padding(14)
    }

    private func iso(_ fromNow: TimeInterval) -> String { ISO8601DateFormatter().string(from: .now.addingTimeInterval(fromNow)) }

    private func lecture(_ title: String, _ cls: String, _ daysAgo: Int, _ minutes: Int, _ summary: String, status: String = "done") -> LectureSummary {
        LectureSummary(id: UUID().uuidString, title: title, class: cls, date: DemoLibrary.day(-daysAgo, at: 16), seconds: Double(minutes * 60),
                       owner: "You", status: status, summary: summary, topics: [], hasTranscript: true)
    }
}
#endif
