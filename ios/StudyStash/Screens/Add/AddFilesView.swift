import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// A file on its way to the library: its name, type and bytes.
struct PendingFile: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var type: String
    var data: Data

    var isImage: Bool { type.hasPrefix("image/") }

    static func from(url: URL) -> PendingFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return PendingFile(name: url.lastPathComponent, type: type, data: data)
    }
}

/// Attach: the one place anything is added to a class or a lecture, opened from Home's +, a class's Attach and a
/// lecture's Attach (and with files another app handed over). Scan pages, photos and files are gathered here and
/// added together; Import a recording and From GoodNotes go on to their own screens in this sheet, and Write notes
/// opens a notebook over the whole screen (the sheet gives way). The library reads what's added (handwriting too),
/// and its notes and Ask use it.
///
/// With no class and no lecture (Home's +, or files from another app) it asks where first: an "Attach to" row, set to
/// the class on the calendar now, else Unsorted.
struct AddFilesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State var className: String?
    var lecture: (id: String, title: String)?
    @State var files: [PendingFile] = []

    /// Opened without a place (Home's +): it shows the "Attach to" row, and "Open Calculus II" when it's done.
    private let picksPlace: Bool

    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var scanning = false
    @State private var sending = false
    @State private var problem: String?
    @State private var done: [Attachment]?
    @State private var next: Next?
    @State private var path: [Step] = []

    /// Where a row goes on to, in this same sheet.
    private enum Next { case recording, goodnotes(URL) }
    /// A step pushed inside the sheet.
    private enum Step: Hashable { case place, goodnotes }

    init(className: String? = nil, lecture: (id: String, title: String)? = nil, files: [PendingFile] = []) {
        var className = className, files = files
        #if DEBUG
        // Pictures: `-attach-home` opens it as Home's + does (no class given, nothing picked yet).
        if DebugLaunch.flag("-attach-home") { className = nil; files = [] }
        #endif
        _className = State(initialValue: className)
        self.lecture = lecture
        _files = State(initialValue: files)
        picksPlace = className == nil && lecture == nil
    }

    var body: some View {
        switch next {
        case .recording:
            // The recording lane's Import a recording, for this class; after Import it opens the lecture.
            ImportAudioView(file: nil, className: className)
        case .goodnotes(let url):
            GoodNotesImportView(url: url, className: className, lecture: lecture)
        case nil:
            chooser
        }
    }

    private var chooser: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let done { added(done) } else { choosing }
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
                    Button { dismiss() } label: { Text(done == nil ? "Cancel" : "Done").textStyle(done == nil ? .nav : .button) }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .place: FolderChoiceList(title: "Attach to", selection: $className)
                case .goodnotes: GoodNotesHowTo { url in next = .goodnotes(url) }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .presentation, .text, .item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { withAnimation(.smooth) { files += urls.compactMap(PendingFile.from(url:)) } }
            }
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { pdf in
                    if let pdf { files.append(PendingFile(name: "Scan, \(Format.day(.now)) at \(Format.time(.now)).pdf", type: "application/pdf", data: pdf)) }
                    scanning = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let type = item.supportedContentTypes.first ?? .jpeg
                            let ext = type.preferredFilenameExtension ?? "jpg"
                            withAnimation(.smooth) {
                                files.append(PendingFile(name: "Photo \(files.count + 1).\(ext)", type: type.preferredMIMEType ?? "image/jpeg", data: data))
                            }
                        }
                    }
                    photos = []
                }
            }
        }
        .task {
            // From Home: the class on the calendar now, if there is one.
            if picksPlace, className == nil { className = app.classNow(app.upcoming) }
            #if DEBUG
            // Pictures: `-attach-done` (added, as the library answers), `-attach-goodnotes` (its how-to).
            if DebugLaunch.flag("-attach-done") {
                done = files.map { Attachment(id: $0.id.uuidString, name: $0.name, class: className ?? "", lecture: nil, size: $0.data.count,
                                              type: $0.type, added: "", hasText: false, reading: $0.isImage) }
            }
            if DebugLaunch.flag("-attach-goodnotes") { path = [.goodnotes] }
            #endif
        }
    }

    /// Where it's going, in words: the lecture's title, the class, or Unsorted.
    private var place: String { lecture?.title ?? className ?? "Unsorted" }

    // MARK: Choosing

    @ViewBuilder private var choosing: some View {
        Text("Attach to \(place)")
            .textStyle(.docTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        if lecture != nil, let cls = className, !cls.isEmpty, cls != "Unsorted" {
            Highlight(cls, hue: app.hue(of: cls)).padding(.top, 6)
        }
        Text("Study Stash reads what you attach on your computer, handwriting too. Notes and Ask use what's in it.")
            .textStyle(.lede).foregroundStyle(.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

        if picksPlace {
            Panel(padding: 0) {
                NavigationLink(value: Step.place) {
                    PlaceRow(label: "Attach to", className: className)
                }
                .buttonStyle(AttachRowStyle())
            }
            .padding(.top, 20)
        }

        Panel(padding: 0) {
            VStack(spacing: 0) {
                Button { scanning = true } label: {
                    AttachRow(icon: "document_scanner", title: "Scan pages",
                              detail: VNDocumentCameraViewController.isSupported ? "Straightened and saved as a PDF" : "Needs this device's camera")
                }
                .disabled(!VNDocumentCameraViewController.isSupported)
                RowRule()
                PhotosPicker(selection: $photos, maxSelectionCount: 30, matching: .images) {
                    AttachRow(icon: "image", title: "Photos", detail: "Handwritten notes, slides, whiteboards")
                }
                RowRule()
                Button { importing = true } label: {
                    AttachRow(icon: "folder", title: "Files", detail: "PDFs, slides, documents")
                }
                RowRule()
                // A notebook is the whole screen: this sheet gives way to it.
                Button { app.incoming = .handwriting(className: className, lecture: lecture) } label: {
                    AttachRow(icon: "edit_note", title: "Write notes", detail: "A notebook for your Apple Pencil or finger")
                }
                RowRule()
                Button { next = .recording } label: {
                    AttachRow(icon: "graphic_eq", title: "Import a recording", detail: "From Voice Memos or Files")
                }
                RowRule()
                NavigationLink(value: Step.goodnotes) {
                    AttachRow(icon: "book_2", title: "From GoodNotes", detail: "Bring a notebook in as ink you can keep writing on")
                }
            }
            .buttonStyle(AttachRowStyle())
        }
        .padding(.top, picksPlace ? 12 : 20)

        if !files.isEmpty {
            GroupLabel(files.count == 1 ? "To add" : "To add, \(files.count) files")
                .padding(.top, 28)
                .padding(.bottom, 8)
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { RowRule(inset: 72) }
                        HStack(spacing: 12) {
                            Thumbnail(file: f)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).textStyle(.nav).foregroundStyle(.ink).lineLimit(1)
                                Text(Format.fileSize(f.data.count)).textStyle(.meta).foregroundStyle(.inkSubtle)
                            }
                            Spacer(minLength: 8)
                            Button { withAnimation(.smooth) { files.removeAll { $0.id == f.id } } } label: {
                                Label("Remove \(f.name)", icon: "close")
                            }
                            .buttonStyle(.icon)
                            .disabled(sending)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            if let problem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon("warning", size: 16, relativeTo: .body).foregroundStyle(.ink)
                    Text(problem).textStyle(.body).foregroundStyle(.ink).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
            }
            Button { Task { await send() } } label: {
                HStack(spacing: 8) {
                    if sending { ProgressView().tint(.surface) }
                    Text(sending ? "Adding…" : files.count == 1 ? "Add 1 file" : "Add \(files.count) files")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(ink: true))
            .disabled(sending)
            .padding(.top, 16)
        }
    }

    // MARK: Done

    @ViewBuilder private func added(_ done: [Attachment]) -> some View {
        Text(done.count == 1 ? "Added 1 file to \(place)." : "Added \(done.count) files to \(place).")
            .textStyle(.docTitle)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        Text("Study Stash reads them on your computer, handwriting too. Notes and Ask use what's in them.")
            .textStyle(.lede).foregroundStyle(.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        Panel(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(done.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { RowRule(inset: 16) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(a.name).textStyle(.nav).foregroundStyle(.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(a.reading ? "Being read" : Format.fileSize(a.size)).textStyle(.meta).foregroundStyle(.inkSubtle)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(.top, 20)
        // From Home, the class it went to is one tap away; from a class or lecture, Done (at the top) goes back to it.
        if picksPlace, let cls = className, !cls.isEmpty, cls != "Unsorted" {
            Button { openClass(cls) } label: { Text("Open \(cls)").frame(maxWidth: .infinity) }
                .buttonStyle(.pill(ink: true))
                .padding(.top, 20)
        }
    }

    /// Close the sheet and open the class's page on Home (`go` closes this sheet itself).
    private func openClass(_ cls: String) {
        app.go(.classDetail(cls), tab: .home)
    }

    private func send() async {
        guard let api = app.api, !files.isEmpty else { return }
        sending = true
        problem = nil
        defer { sending = false }
        do {
            let added = try await api.upload(files: files.map { ($0.name, $0.type, $0.data) }, class: className, lecture: lecture?.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.smooth) { done = added }
        } catch {
            problem = (error as? APIError)?.detail ?? "Couldn't add those. Try again."
        }
    }
}

// MARK: - Rows

/// One way to attach: its icon, its name, a line on what it's for, and a chevron.
private struct AttachRow: View {
    var icon: String
    var title: String
    var detail: String
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 14) {
            Icon(icon, size: 22).foregroundStyle(.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.nav).fontWeight(.semibold).foregroundStyle(.ink)
                Text(detail).textStyle(.meta).foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Icon("chevron_right", size: 16).foregroundStyle(.inkSubtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .opacity(enabled ? 1 : 0.45)
        .contentShape(.rect)
    }
}

/// "Attach to" and where: the class's swatch and name (or Unsorted's tray), and a chevron to change it.
struct PlaceRow: View {
    @Environment(AppModel.self) private var app
    var label: String
    var className: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(label).textStyle(.nav).foregroundStyle(.inkMuted)
            Spacer(minLength: 8)
            if let cls = className, !cls.isEmpty, cls != "Unsorted" {
                Swatch(app.hue(of: cls))
                Text(cls).textStyle(.nav).fontWeight(.semibold).foregroundStyle(.ink).lineLimit(1)
            } else {
                Icon("inbox", size: 16).foregroundStyle(.inkSubtle)
                Text("Unsorted").textStyle(.nav).fontWeight(.semibold).foregroundStyle(.ink)
            }
            Icon("chevron_right", size: 16).foregroundStyle(.inkSubtle)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Choose where it goes")
    }
}

/// A row in a grouped box as the button: washed while pressed, to the box's edges.
struct AttachRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.press : .clear)
    }
}

/// A hairline between rows in a grouped box, starting past the icons.
struct RowRule: View {
    var inset: CGFloat = 58
    var body: some View { Rule().padding(.leading, inset) }
}

// MARK: - Choosing a class

/// Where something goes: Unsorted, then every class under its group's name ("Classes", "Clubs", "Work"), each with
/// its swatch and how many notes it has, a tick on the one chosen. Picking one goes back. Pushed inside a sheet.
struct FolderChoiceList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var title: String
    @Binding var selection: String?
    @State private var query = ""

    private var groups: [(name: String, classes: [ClassInfo])] {
        let shown = app.classes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        var order: [String] = []
        var byGroup: [String: [ClassInfo]] = [:]
        for c in shown {
            let g = (c.group ?? "").isEmpty ? app.words.classes : c.group!
            if byGroup[g] == nil { order.append(g) }
            byGroup[g, default: []].append(c)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if query.isEmpty {
                    Panel(padding: 0) {
                        choice(nil) {
                            Icon("inbox", size: 16).foregroundStyle(.inkSubtle).frame(width: 16)
                            Text("Unsorted").textStyle(.nav).foregroundStyle(.ink)
                        }
                    }
                    .padding(.top, 8)
                }
                ForEach(groups, id: \.name) { group in
                    GroupLabel(group.name).padding(.top, 24).padding(.bottom, 8)
                    Panel(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.classes.enumerated()), id: \.element.id) { i, c in
                                if i > 0 { RowRule(inset: 44) }
                                choice(c.name) {
                                    Swatch(app.hue(of: c.name)).frame(width: 16)
                                    Text(c.name).textStyle(.nav).foregroundStyle(.ink).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text("\(c.lectures)").textStyle(.meta).foregroundStyle(.inkSubtle)
                                }
                            }
                        }
                    }
                }
                if !query.isEmpty, groups.isEmpty {
                    EmptyText("No \(app.words.cls) called \"\(query)\".").padding(.top, 16)
                }
            }
            .padding(.horizontal, Space.pageCompact)
            .padding(.bottom, 32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .page()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(SearchWhenLong(count: app.classes.count, query: $query))
    }

    private func choice<Label: View>(_ name: String?, @ViewBuilder label: () -> Label) -> some View {
        let chosen = (selection ?? "") == (name ?? "") || (name == nil && selection == "Unsorted")
        return Button {
            selection = name
            dismiss()
        } label: {
            HStack(spacing: 12) {
                label()
                Spacer(minLength: 8)
                if chosen { Icon("check", size: 18).foregroundStyle(.ink) }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(AttachRowStyle())
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// A search field over the classes only when there are enough of them to need one.
private struct SearchWhenLong: ViewModifier {
    var count: Int
    @Binding var query: String
    func body(content: Content) -> some View {
        if count > 8 {
            content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a class")
        } else {
            content
        }
    }
}

// MARK: - From GoodNotes

/// How to bring a GoodNotes notebook in: the steps in GoodNotes, or a .goodnotes file chosen here.
private struct GoodNotesHowTo: View {
    var chosen: (URL) -> Void
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("From GoodNotes").textStyle(.docTitle).accessibilityAddTraits(.isHeader)
                Text("Your notebook comes in as ink you can keep writing on here. Saved to your library, it's read for notes and Ask.")
                    .textStyle(.lede).foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                GroupLabel("In GoodNotes").padding(.top, 28).padding(.bottom, 8)
                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        step(1, "Open the notebook.")
                        step(2, "Tap Share, then Export.")
                        step(3, "Choose GoodNotes, then Study Stash.")
                    }
                }
                Text("Or, if the notebook is already in Files:")
                    .textStyle(.body).foregroundStyle(.inkMuted)
                    .padding(.top, 24)
                Button { picking = true } label: { Label("Choose a file", icon: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(.pill(ink: true))
                    .padding(.top, 12)
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
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType("app.studystash.goodnotes") ?? .zip, .zip, .data]) { result in
            if case .success(let url) = result { chosen(url) }
        }
    }

    private func step(_ n: Int, _ words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)").textStyle(.buttonSmall).foregroundStyle(.inkMuted).frame(width: 18, alignment: .leading)
            Text(words).textStyle(.lede).foregroundStyle(.ink).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// A picked file, small: the photo itself, or the icon for its kind on the sunken grey.
private struct Thumbnail: View {
    var file: PendingFile
    var body: some View {
        Group {
            if file.isImage, let image = UIImage(data: file.data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Icon(file.type.contains("pdf") ? "picture_as_pdf" : "draft", size: 22).foregroundStyle(.inkMuted)
            }
        }
        .frame(width: 44, height: 44)
        .background(.surface)
        .clipShape(.rect(cornerRadius: Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(.line))
        .accessibilityHidden(true)
    }
}

/// The camera's document scanner: pages straightened and cropped, handed back as one PDF.
struct DocumentScanner: UIViewControllerRepresentable {
    var done: (Data?) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let data = NSMutableData()
            let first = scan.imageOfPage(at: 0)
            UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: first.size), nil)
            for i in 0..<scan.pageCount {
                let page = scan.imageOfPage(at: i)
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: page.size), nil)
                page.draw(at: .zero)
            }
            UIGraphicsEndPDFContext()
            done(data as Data)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done(nil) }
    }
}
