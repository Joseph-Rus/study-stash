import SwiftUI

/// One question and what came back: the answer as it was written, the lectures it drew on, or why there's none.
struct AskTurn: Codable, Identifiable, Hashable, Sendable {
    struct Source: Codable, Hashable, Sendable {
        var id: String?
        var title: String
        var `class`: String?
        var date: String?
        var at: Double?
    }
    enum State: String, Codable, Sendable { case asking, done, failed }

    var id = UUID()
    var question: String
    var scope: String?
    var answer = ""
    var sources: [Source] = []
    var state: State = .asking
    var problem: String?
    var engine: String?

    /// One source a lecture, however many of its sections the answer drew on, in the order they came.
    static func merged(_ sources: [AskSource]) -> [Source] {
        var out: [Source] = []
        for s in sources {
            if let id = s.id, out.contains(where: { $0.id == id }) { continue }
            out.append(.init(id: s.id, title: s.title, class: s.class, date: s.date, at: s.at))
        }
        return out
    }
}

/// What Ask is about: everything, one class, or one lecture.
enum AskScope: Hashable {
    case everything
    case `class`(String)
    case lecture(id: String, title: String)

    var label: String {
        switch self {
        case .everything: "All classes"
        case .class(let c): c
        case .lecture(_, let t): t
        }
    }
}

/// A conversation with the library's AI: questions, answers streaming in, and their sources.
@MainActor @Observable
final class AskConversation {
    var turns: [AskTurn]
    @ObservationIgnored private let saveKey: String?

    init(saveKey: String?) {
        self.saveKey = saveKey
        let saved = saveKey.flatMap { UserDefaults.standard.data(forKey: $0) }.flatMap { try? JSONDecoder().decode([AskTurn].self, from: $0) } ?? []
        // A question stopped by the app closing is marked as such, not left asking forever.
        turns = saved.map { var t = $0; if t.state == .asking { t.state = .failed; t.problem = "Stopped before it was answered." }; return t }
    }

    var busy: Bool { turns.contains { $0.state == .asking } }

    private func save() {
        guard let saveKey, let data = try? JSONEncoder().encode(Array(turns.suffix(30))) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    func clear() { turns = []; save() }

    func ask(_ text: String, scope: AskScope, api: APIClient) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        let turn = AskTurn(question: q, scope: scope == .everything ? nil : scope.label)
        turns.append(turn)
        let i = turns.count - 1
        func update(_ change: (inout AskTurn) -> Void) { if turns.indices.contains(i), turns[i].id == turn.id { change(&turns[i]) } }

        var lecture: String?, cls: String?
        switch scope {
        case .everything: break
        case .class(let c): cls = c
        case .lecture(let id, _): lecture = id
        }
        do {
            for try await event in try await api.ask(q, lecture: lecture, class: cls) {
                switch event {
                case .text(let t): update { $0.answer += t }
                case .answer(let t): update { $0.answer = t }
                case .done(let reply):
                    update {
                        if !reply.answer.isEmpty { $0.answer = reply.answer }
                        $0.sources = AskTurn.merged(reply.sources)
                        $0.engine = reply.engineName
                        $0.state = .done
                    }
                case .error(_, let detail):
                    update { $0.state = .failed; $0.problem = detail.isEmpty ? "The library couldn't answer that." : detail }
                }
            }
            update { if $0.state == .asking { $0.state = $0.answer.isEmpty ? .failed : .done; if $0.answer.isEmpty { $0.problem = "No answer came back." } } }
        } catch {
            update { $0.state = .failed; $0.problem = (error as? APIError)?.detail ?? "Couldn't reach your library." }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        save()
    }
}

/// The Ask tab: answers from your own notes and lectures, about everything or one class.
struct AskTab: View {
    @Environment(AppModel.self) private var app
    @State private var conversation = AskConversation(saveKey: "ask.history")
    @State private var scope: AskScope = .everything

    var body: some View {
        NavigationStack(path: app.stack(.ask)) {
            AskThread(conversation: conversation, scope: $scope, chooseScope: true)
                .navigationTitle("Ask")
                .toolbar {
                    if !conversation.turns.isEmpty {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Clear", systemImage: "trash") { withAnimation { conversation.clear() } }
                        }
                    }
                }
                .routes()
        }
    }
}

/// Ask about one lecture or class, from its screen.
struct AskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var conversation = AskConversation(saveKey: nil)
    @State var scope: AskScope

    var body: some View {
        NavigationStack {
            AskThread(conversation: conversation, scope: $scope, chooseScope: false)
                .navigationTitle(scope.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", systemImage: "xmark") { dismiss() } } }
                .routes()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct AskThread: View {
    @Environment(AppModel.self) private var app
    var conversation: AskConversation
    @Binding var scope: AskScope
    var chooseScope: Bool

    @State private var question = ""
    @State private var classes: [ClassInfo] = ResponseCache.shared.read("library", as: LibraryOverview.self)?.classes ?? []
    @State private var noAI = false
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        switch scope {
        case .lecture: ["Summarize this lecture in 5 bullets", "What's most likely to be on the exam?", "Quiz me on this lecture"]
        default: ["What did we cover this week?", "Explain the hardest idea from my last lecture", "Quiz me on my most recent notes"]
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if noAI {
                        ContentUnavailableView("Asking isn't set up yet", systemImage: "sparkles",
                                               description: Text("Choose an AI in Study Stash's Settings → AI on your computer, then ask here."))
                    } else if conversation.turns.isEmpty {
                        start
                    }
                    ForEach(conversation.turns) { turn in
                        TurnView(turn: turn).id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.surface)
            .onChange(of: conversation.turns.last?.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: conversation.turns.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { if !noAI { composer } }
        .task {
            guard let api = app.api else { return }
            if let lib = try? await api.library() { classes = lib.classes; noAI = !lib.ask }
            if chooseScope, let q = DebugLaunch.value("-ask"), conversation.turns.last?.question != q { send(q) }
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(Color.accentColor.gradient).symbolEffect(.breathe)
                Text("Ask about your notes").font(.app(.docTitle))
                Text("Answers come from what's in your library, with the lectures each one used.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        HStack {
                            Text(s).font(.callout).multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(.surfaceSunken, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if chooseScope && !classes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All classes", on: scope == .everything) { scope = .everything }
                        ForEach(classes) { c in
                            chip(c.name, on: scope == .class(c.name), hue: Highlighter(classIndex: c.color)) {
                                scope = scope == .class(c.name) ? .everything : .class(c.name)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(scope == .everything ? "Ask anything about your classes" : "Ask about \(scope.label)", text: $question, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(question) }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .onChange(of: focused) { _, f in if f, let api = app.api { Task { await api.warm() } } }
                Button { send(question) } label: {
                    Image(systemName: conversation.busy ? "ellipsis" : "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 34, height: 34)
                        .symbolEffect(.variableColor.iterative, isActive: conversation.busy)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || conversation.busy)
                .padding(5)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 6)
    }

    private func chip(_ text: String, on: Bool, hue: Highlighter? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if text != "All classes" { Swatch(hue, small: true) }
                Text(text).font(.footnote.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? Color.surface : .ink)
        .background(on ? AnyShapeStyle(Color.ink) : AnyShapeStyle(.regularMaterial), in: .capsule)
    }

    private func send(_ text: String) {
        guard let api = app.api else { return }
        let q = text
        question = ""
        Task { await conversation.ask(q, scope: scope, api: api) }
    }
}

private struct TurnView: View {
    @Environment(AppModel.self) private var app
    var turn: AskTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 48)
                Text(turn.question)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: 20, style: .continuous))
                    .textSelection(.enabled)
            }
            if let scope = turn.scope {
                Text(scope).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }

            if turn.answer.isEmpty && turn.state == .asking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading your notes…").font(.callout).foregroundStyle(.secondary)
                }
            } else if !turn.answer.isEmpty {
                MarkdownText(turn.answer)
            }
            if turn.state == .failed, let p = turn.problem {
                Label(p, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            if !turn.sources.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("From").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(Array(turn.sources.enumerated()), id: \.offset) { _, s in
                        let row = HStack(spacing: 8) {
                            Swatch(app.hue(of: s.class), small: true)
                            Text(s.title).font(.footnote.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text([s.date.flatMap(Format.parse).map { Format.shortDate($0) }, s.at.map(Format.clock)]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.surfaceSunken, in: .rect(cornerRadius: 12, style: .continuous))
                        if let id = s.id {
                            NavigationLink(value: Route.lecture(id)) { row }.buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                }
            }
        }
    }
}

/// Markdown from the AI: headings, lists and paragraphs as blocks, bold, italics, code and links inline.
struct MarkdownText: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let s): inline(s).font(.app(.title)).padding(.top, 4)
                case .bullet(let s, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tint)
                        inline(s)
                    }
                    .padding(.leading, CGFloat(depth) * 16)
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(.tint).monospacedDigit()
                        inline(s)
                    }
                case .paragraph(let s): inline(s)
                }
            }
        }
        .font(.body)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        return Text(a)
    }

    enum Block { case heading(String), bullet(String, Int), numbered(Int, String), paragraph(String) }

    nonisolated static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        for raw in text.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let m = line.firstMatch(of: /^#{1,6}\s+(.*)$/) { flush(); out.append(.heading(String(m.1))) }
            else if let m = line.firstMatch(of: /^[-*•]\s+(.*)$/) { flush(); out.append(.bullet(String(m.1), indent / 2)) }
            else if let m = line.firstMatch(of: /^(\d+)[.)]\s+(.*)$/) { flush(); out.append(.numbered(Int(m.1) ?? 1, String(m.2))) }
            else { para.append(line) }
        }
        flush()
        return out
    }
}
