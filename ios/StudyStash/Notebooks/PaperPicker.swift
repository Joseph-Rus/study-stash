import SwiftUI
import UniformTypeIdentifiers

/// A paper as it's printed, small: drawn by the same code as the page itself, at the page's proportions.
struct PaperPreview: View {
    var template: Notebook.Template
    var width: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let size = template.size.size
        Image(uiImage: Self.image(template, width: width, screen: displayScale))
            .resizable()
            .frame(width: width, height: (width * size.height / size.width).rounded())
            .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor static func image(_ t: Notebook.Template, width: CGFloat, screen: CGFloat) -> UIImage {
        let key = "\(t.paper)|\(t.colour)|\(t.size)|\(width)|\(screen)"
        if let image = cache[key] { return image }
        let page = t.size.size
        let scale = width / page.width
        let format = UIGraphicsImageRendererFormat()
        format.scale = screen
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: (page.height * scale).rounded()), format: format).image { r in
            r.cgContext.scaleBy(x: scale, y: scale)
            PaperDrawing.draw(t.paper, colour: t.colour, in: CGRect(origin: .zero, size: page), ctx: r.cgContext,
                              hairline: 0.9 / (scale * screen))
        }
        cache[key] = image
        return image
    }
}

/// Choosing paper: the rulings as small pages, the paper's colour, and its size.
struct PaperPicker: View {
    @Binding var template: Notebook.Template
    /// Pages across.
    var columns = 3
    var tileWidth: CGFloat = 84
    var showsSize = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                GroupLabel("Paper")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns),
                          alignment: .leading, spacing: 18) {
                    ForEach(Notebook.Paper.allCases, id: \.self) { paper in tile(paper) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                GroupLabel("Colour")
                HStack(spacing: 14) {
                    ForEach(Notebook.PaperColour.allCases, id: \.self) { colour in swatch(colour) }
                }
            }
            if showsSize {
                VStack(alignment: .leading, spacing: 12) {
                    GroupLabel("Size")
                    Segmented(selection: $template.size, options: Notebook.PageSize.allCases.map { ($0, $0.name) })
                        .frame(maxWidth: 320)
                }
            }
        }
    }

    private func tile(_ paper: Notebook.Paper) -> some View {
        let chosen = template.paper == paper
        var t = template
        t.paper = paper
        return Button { template.paper = paper } label: {
            VStack(spacing: 8) {
                PaperPreview(template: t, width: tileWidth)
                    .clipShape(.rect(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.line, lineWidth: 1))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(chosen ? Color.ink : .clear, lineWidth: 2))
                Text(paper.name)
                    .textStyle(.meta)
                    .fontWeight(chosen ? .bold : .medium)
                    .foregroundStyle(chosen ? Color.ink : .inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paper.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("paper.\(paper.rawValue)")
    }

    private func swatch(_ colour: Notebook.PaperColour) -> some View {
        let chosen = template.colour == colour
        return Button { template.colour = colour } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: PaperDrawing.inks(colour).ground))
                    .frame(width: 22, height: 22)
                    // Firmer than a hairline, so dark paper shows on a dark sheet.
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.inkSubtle.opacity(0.45), lineWidth: 1))
                Text(colour.name)
                    .textStyle(.buttonSmall)
                    .foregroundStyle(chosen ? Color.ink : .inkMuted)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 36)
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(chosen ? Color.ink : .line, lineWidth: chosen ? 2 : 1))
            .contentShape(.rect(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(colour.name) paper")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("paper.colour.\(colour.rawValue)")
    }
}

/// The paper a new notebook was last made with, so the next one starts there.
enum LastTemplate {
    static let key = "notebook.template"

    static var value: Notebook.Template {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let t = try? JSONDecoder().decode(Notebook.Template.self, from: data) else { return .standard }
            return t
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}

/// Making a notebook: its title, where it's filed, and its paper, shown as the page it'll be. Create starts writing;
/// a PDF (slides, a handout) can be the pages instead.
struct NewNotebookView: View {
    @Environment(AppModel.self) private var app
    var className: String?
    var lecture: (id: String, title: String)?
    /// Beside a lecture or the recorder: no bar of its own, and nothing to cancel.
    var embedded = false
    var created: (Notebook) -> Void
    var cancel: () -> Void
    @State private var title: String
    @State private var template = LastTemplate.value
    @State private var importing = false
    @State private var problem: String?
    @State private var width: CGFloat = 0
    @State private var store = NotebookStore.shared

    init(className: String?, lecture: (id: String, title: String)?, embedded: Bool = false,
         created: @escaping (Notebook) -> Void, cancel: @escaping () -> Void) {
        self.className = className
        self.lecture = lecture
        self.embedded = embedded
        self.created = created
        self.cancel = cancel
        let day = Format.date(.now)
        _title = State(initialValue: lecture.map { "Notes, \($0.title)" } ?? className.map { "\($0) notes, \(day)" } ?? "Notes, \(day)")
    }

    private var wide: Bool { width >= 720 }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("New notebook")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { cancel() } label: { Text("Cancel").textStyle(.nav) }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button { create() } label: { Text("Create").textStyle(.button) }
                                .accessibilityIdentifier("notebook.create.bar")
                        }
                    }
            }
        }
    }

    private var content: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 56) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Title", text: $title, axis: .vertical)
                            .textStyle(wide ? .docTitle : .h2)
                            .foregroundStyle(.ink)
                            .lineLimit(1...3)
                            .submitLabel(.done)
                            .accessibilityIdentifier("notebook.title")
                        Rule()
                        filed
                    }
                    PaperPicker(template: $template, columns: wide ? 3 : 3, tileWidth: wide ? 92 : 80)
                    VStack(alignment: .leading, spacing: 14) {
                        Button { create() } label: { Text("Create notebook").frame(maxWidth: wide ? nil : .infinity) }
                            .buttonStyle(.pill(ink: true))
                            .accessibilityIdentifier("notebook.create")
                        Button("Or write on a PDF: slides, a handout") { importing = true }
                            .buttonStyle(.textLink)
                        if let problem { Text(problem).textStyle(.meta).foregroundStyle(.inkMuted) }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 480, alignment: .leading)
                if wide {
                    // The page it'll be, big enough to see the ruling.
                    VStack(alignment: .leading, spacing: 10) {
                        PaperPreview(template: template, width: 300)
                            .lifted(.float, in: Rectangle())
                        Text(template.words).textStyle(.meta).foregroundStyle(.inkMuted)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, wide ? Space.pageRegular : Space.pageCompact)
            .padding(.top, embedded ? 20 : 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: wide ? .center : .leading)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scrollDismissesKeyboard(.interactively)
        .page()
        .foregroundStyle(.ink)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { createFromPDF(url) }
        }
        .accessibilityIdentifier("page.newNotebook")
    }

    @ViewBuilder private var filed: some View {
        if let className {
            HStack(spacing: 8) {
                Swatch(app.hue(of: className))
                Text(lecture.map { "With \($0.title), in \(className)" } ?? "In \(className)")
                    .textStyle(.meta).foregroundStyle(.inkMuted).lineLimit(2)
            }
        } else if let lecture {
            Text("With \(lecture.title)").textStyle(.meta).foregroundStyle(.inkMuted)
        } else {
            Text("Saved to your library, unsorted").textStyle(.meta).foregroundStyle(.inkMuted)
        }
    }

    private var cleanTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Notes, \(Format.date(.now))" : t
    }

    private func create() {
        LastTemplate.value = template
        let n = Notebook.blank(title: cleanTitle, className: className, lecture: lecture, template: template)
        store.save(n)
        created(n)
    }

    private func createFromPDF(_ url: URL) {
        var n = Notebook.blank(title: cleanTitle, className: className, lecture: lecture, template: template)
        store.save(n)
        guard let pages = store.pages(fromPDF: url, for: n) else {
            store.delete(n)
            problem = "That PDF couldn't be opened."
            return
        }
        n.pages = pages
        // Named for the PDF unless a title was typed.
        let suggested = lecture.map { "Notes, \($0.title)" } ?? className.map { "\($0) notes, \(Format.date(.now))" }
        if title == suggested || title.isEmpty { n.title = url.deletingPathExtension().lastPathComponent }
        n.updated = .now
        store.save(n)
        LastTemplate.value = template
        created(n)
    }
}

/// Changing the paper in a notebook: of the page showing, or of every page (pages from a PDF keep theirs). Either
/// way, pages added after come on it too.
struct PaperSheet: View {
    var page: Notebook.Page?
    var pageNumber: Int
    var apply: (Notebook.Template, _ allPages: Bool) -> Void
    var done: () -> Void
    @State private var template: Notebook.Template

    init(page: Notebook.Page?, pageNumber: Int, newPages: Notebook.Template,
         apply: @escaping (Notebook.Template, Bool) -> Void, done: @escaping () -> Void) {
        self.page = page
        self.pageNumber = pageNumber
        self.apply = apply
        self.done = done
        if let page, page.pdf == nil {
            _template = State(initialValue: Notebook.Template(paper: page.paper, colour: page.colour,
                                                              size: Notebook.PageSize(page.size) ?? newPages.size))
        } else {
            _template = State(initialValue: newPages)
        }
    }

    private var onPDF: Bool { page?.pdf != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Change the paper").textStyle(.h2).foregroundStyle(.ink)
                PaperPicker(template: $template, columns: 3, tileWidth: 76)
            }
            .padding(20)
        }
        .accessibilityIdentifier("page.paper")
        // The buttons stay in sight, however little of the sheet is up.
        .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button { apply(template, false); done() } label: { Text("Apply to page \(pageNumber)") }
                            .buttonStyle(.pill(ink: true))
                            .disabled(onPDF)
                            .opacity(onPDF ? 0.4 : 1)
                            .accessibilityIdentifier("paper.apply.page")
                        Button { apply(template, true); done() } label: { Text("Apply to all pages") }
                            .buttonStyle(.pill)
                            .accessibilityIdentifier("paper.apply.all")
                    }
                    Text(onPDF ? "This page is a PDF's page, so it keeps it. Pages added after come on this paper."
                               : "Pages added after come on this paper too.")
                        .textStyle(.meta).foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surface)
                .overlay(alignment: .top) { Rule() }
        }
        .foregroundStyle(.ink)
        .background(.surface)
    }
}
