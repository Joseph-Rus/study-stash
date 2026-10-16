import SwiftUI

// Ask, as the desktop's ask bar and answer card have it (MacAiAskBar, MacAiAnswer, AiByline): the question typed into
// the Ask bar at the foot of the page ("Ask anything about your notes", its scope "All notes" beside it as a menu);
// each answer in ink in the notes' type, who answered under it, and From: the lectures it used, each with its class's
// swatch and the minute, opening the lecture at that minute. The Ask tab keeps its questions; a page's Ask sheet is
// about that page.

/// One question and what came back: the answer as it was written, the lectures it drew on, or why there's none.
struct AskTurn: Codable, Identifiable, Hashable, Sendable {
    struct Source: Codable, Hashable, Sendable {
        var id: String?
        var title: String
        var `class`: String?
        var date: String?
        var at: Double?
        /// Where in the notes it came from ("Key points") when it isn't a moment in the recording.
        var section: String?
        /// Every moment in this lecture the answer drew on, earliest first.
        var moments: [Double]?

        var times: [Double] { moments ?? at.map { [$0] } ?? [] }
    }
    enum State: String, Codable, Sendable { case asking, done, failed }

    var id = UUID()
    var question: String
    /// What it was asked about, in words ("Calculus II"); nil for everything.
    var scope: String?
    /// What it was asked about, to ask it again.
    var asked: AskScope?
    var answer = ""
    var sources: [Source] = []
    var state: State = .asking
    var problem: String?
    var engine: String?
    /// "This answer came from Ollama. Claude didn't respond in time."
    var note: String?

    /// One source a lecture, however many of its sections the answer drew on, in the order they came; a lecture's
    /// moments gathered, earliest first.
    static func merged(_ sources: [AskSource]) -> [Source] {
        var out: [Source] = []
        for s in sources {
            if let id = s.id, let i = out.firstIndex(where: { $0.id == id }) {
                if let at = s.at, !(out[i].moments ?? []).contains(where: { Int($0) == Int(at) }) {
                    out[i].moments = ((out[i].moments ?? []) + [at]).sorted()
                    out[i].at = out[i].moments?.first
                }
                continue
            }
            out.append(.init(id: s.id, title: s.title, class: s.class, date: s.date, at: s.at,
                             section: s.section.isEmpty ? nil : s.section, moments: s.at.map { [$0] }))
        }
        return out
    }
}

/// What Ask is about: everything, one class, or one lecture (and the class it's in, when it's known).
enum AskScope: Hashable, Codable, Sendable {
    case everything
    case `class`(String)
    case lecture(id: String, title: String, class: String? = nil)

    /// The scope's name in the Ask bar and its menu: "All notes", "Calculus II", "This lecture".
    func label(noun: String = Nouns.lecture) -> String {
        switch self {
        case .everything: "All notes"
        case .class(let c): c
        case .lecture: "This \(noun)"
        }
    }

    /// The Ask bar's words: "Ask anything about your notes", "Ask about Machine Learning", "Ask about this lecture".
    func placeholder(noun: String = Nouns.lecture) -> String {
        switch self {
        case .everything: "Ask anything about your notes"
        case .class(let c): "Ask about \(c)"
        case .lecture: "Ask about this \(noun)"
        }
    }

    var className: String? {
        switch self {
        case .everything: nil
        case .class(let c): c
        case .lecture(_, _, let c): c
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
        // `-ask-new` (debug): start with nothing asked, for pictures of the empty page.
        let fresh = DebugLaunch.flag("-ask-new")
        let saved = fresh ? [] : saveKey.flatMap { UserDefaults.standard.data(forKey: $0) }.flatMap { try? JSONDecoder().decode([AskTurn].self, from: $0) } ?? []
        // A question stopped by the app closing is marked as such, not left asking forever.
        turns = saved.map { var t = $0; if t.state == .asking { t.state = .failed; t.problem = "Stopped before it was answered." }; return t }
    }

    var busy: Bool { turns.contains { $0.state == .asking } }

    /// The AI that answered last ("Claude"), to say who's being asked next.
    var lastEngine: String? { turns.last { $0.engine?.isEmpty == false }?.engine }

    private func save() {
        guard let saveKey, let data = try? JSONEncoder().encode(Array(turns.suffix(30))) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    func clear() { turns = []; save() }

    func ask(_ text: String, scope: AskScope, label: String?, api: APIClient) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        let turn = AskTurn(question: q, scope: scope == .everything ? nil : label, asked: scope)
        turns.append(turn)
        // `-ask-waiting` (debug): leave it asking, for a picture of an answer on its way.
        if DebugLaunch.flag("-ask-waiting") { return }
        let i = turns.count - 1
        func update(_ change: (inout AskTurn) -> Void) { if turns.indices.contains(i), turns[i].id == turn.id { change(&turns[i]) } }

        var lecture: String?, cls: String?
        switch scope {
        case .everything: break
        case .class(let c): cls = c
        case .lecture(let id, _, _): lecture = id
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
                        if reply.fellBack { $0.note = "This answer came from \(reply.engineName). \(reply.why)".trimmingCharacters(in: .whitespaces) }
                        $0.state = .done
                    }
                case .error(_, let detail):
                    update { $0.state = .failed; $0.problem = detail.isEmpty ? "The library couldn't answer that." : detail }
                }
            }
            update {
                guard $0.state == .asking else { return }
                $0.state = $0.answer.isEmpty ? .failed : .done
                if $0.answer.isEmpty { $0.problem = "No answer came back." }
            }
        } catch {
            update {
                $0.state = .failed
                $0.problem = $0.answer.isEmpty
                    ? (error as? APIError)?.detail ?? "Your library isn't answering. Check it's on and connected."
                    : "Your library stopped answering partway through. Check it's on and connected."
            }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        save()
    }

    /// A question that failed, asked again in its own place.
    func retry(_ turn: AskTurn, scope: AskScope, label: String?, api: APIClient) async {
        turns.removeAll { $0.id == turn.id }
        await ask(turn.question, scope: turn.asked ?? scope, label: turn.scope ?? label, api: api)
    }
}


/// Where a lecture an answer came from opens: at the moment it drew on, on the Transcript.
/// FLOWS: after the core merge, `Route.lecture(id, at: at)`.
func askLectureRoute(_ id: String, at: Double?) -> Route { .lecture(id) }

/// The Ask tab: answers from your own notes and lectures, about everything or one class.
struct AskTab: View {
    @State private var conversation = AskConversation(saveKey: "ask.history")
    @State private var scope: AskScope = .everything
    @State private var confirmClear = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            AskThread(conversation: conversation, scope: $scope, base: .everything, isTab: true) { source, at in
                // FLOWS: after the core merge, `app.go(askLectureRoute(id, at: at))`: the lecture on Home's stack, at
                // the minute, on its Transcript. Until then it opens here.
                if let id = source.id { path.append(askLectureRoute(id, at: at)) }
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !conversation.turns.isEmpty && !conversation.busy {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { confirmClear = true } label: { Text("Clear").textStyle(.nav) }
                            .accessibilityLabel("Clear your questions and answers")
                    }
                }
            }
            .confirmationDialog("Clear your questions and answers?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear", role: .destructive) { withAnimation { conversation.clear() } }
            } message: {
                Text("They're kept only on this phone, so they can't come back.")
            }
            .routes()
        }
    }
}

/// Ask about one lecture or class, from its page's Ask bar. `question` is sent as it opens ("Ask how to start this").
/// Nothing is opened inside it: a lecture an answer came from closes the sheet, then opens at its minute on the page
/// underneath. A lecture's own page can take that itself with `onMoment` (its Transcript at that time).
struct AskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var conversation = AskConversation(saveKey: nil)
    @State private var scope: AskScope
    private let base: AskScope
    private let question: String?
    private let onMoment: ((_ lecture: String, _ at: Double?) -> Void)?

    init(scope: AskScope, question: String? = nil, onMoment: ((_ lecture: String, _ at: Double?) -> Void)? = nil) {
        _scope = State(initialValue: scope)
        base = scope
        self.question = question
        self.onMoment = onMoment
    }

    var body: some View {
        NavigationStack {
            AskThread(conversation: conversation, scope: $scope, base: base, isTab: false, firstQuestion: question) { source, at in
                guard let id = source.id else { return }
                dismiss()
                if let onMoment {
                    onMoment(id, at)
                } else {
                    // FLOWS: after the core merge, `app.go(askLectureRoute(id, at: at), tab: <the tab underneath>)`.
                    _ = id
                }
            }
            .navigationTitle(scope.placeholder(noun: app.noun(of: scope.className)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("Done").textStyle(.button) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The page both share: what to ask (or the questions asked and their answers), and the Ask bar at its foot.
private struct AskThread: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    var conversation: AskConversation
    @Binding var scope: AskScope
    /// Where it was opened: the scopes the bar offers follow from it (a lecture: it, its class, all notes).
    var base: AskScope
    /// The Ask tab (its history kept), not a sheet.
    var isTab: Bool
    var firstQuestion: String?
    /// A lecture an answer came from, tapped: at the moment it drew on.
    var open: (AskTurn.Source, Double?) -> Void

    @State private var question = ""
    @State private var classes: [ClassInfo] = ResponseCache.shared.read("library", as: LibraryOverview.self)?.classes ?? []
    @State private var latest: LectureSummary? = ResponseCache.shared.read("recent", as: [LectureSummary].self)?.first
    @State private var noAI = false
    @State private var picking = false
    @State private var warmed = false

    private var pad: CGFloat { sizeClass == .regular ? Space.pageRegular : Space.pageCompact }

    /// The noun of what's asked about ("lecture", "meeting").
    private var noun: String { app.noun(of: scope.className) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if noAI {
                        EmptyState(title: "Asking isn't set up yet",
                                   detail: "On your computer, open Settings, then Your AI, and choose one.")
                    } else if conversation.turns.isEmpty {
                        start
                    }
                    ForEach(Array(conversation.turns.enumerated()), id: \.element.id) { i, turn in
                        TurnView(turn: turn, asking: conversation.lastEngine, inScope: base, open: open) { retry(turn) }
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, pad)
                .padding(.bottom, 16)
                .frame(maxWidth: 760 + 2 * pad)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .page()
            .onChange(of: conversation.turns.last?.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: conversation.turns.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { if !noAI { composer } }
        .foregroundStyle(.ink)
        .task {
            guard let api = app.api else { return }
            if let lib = try? await api.library() { classes = lib.classes; noAI = !lib.ask }
            if let q = firstQuestion, conversation.turns.isEmpty { send(q) }
            #if DEBUG
            // `-ask "<question>"`: asked on the Ask tab, or in the sheet `-show ask…` opens.
            let sheet = DebugLaunch.value("-show")?.hasPrefix("ask") == true
            if let q = DebugLaunch.value("-ask"), isTab != sheet, conversation.turns.last?.question != q { send(q) }
            // `-ask-scopes`: the scope's menu open, for pictures.
            if DebugLaunch.flag("-ask-scopes"), isTab != sheet { try? await Task.sleep(for: .seconds(1)); picking = true }
            #endif
            if latest == nil { latest = try? await api.lectures(limit: 1).first }
        }
    }

    // MARK: before anything's asked

    private var lede: String {
        let plural = noun + "s"
        return switch base {
        case .everything: "Answers come from your notes and \(app.words.lectures), with the \(app.words.lecture) and the minute each one used."
        case .class(let c): "Answers come from your \(c) notes and \(plural), with the \(noun) and the minute each one used."
        case .lecture: "Answers come from this \(noun)'s notes and what was said in it, with the minute each one used."
        }
    }

    /// Three questions worth asking, from what's in the library: its latest class, its last lecture, what's due.
    private var suggestions: [String] {
        let school = app.forSchool
        switch scope {
        case .lecture:
            return ["Summarize this \(noun) in five points", "Quiz me on this \(noun)",
                    school ? "What's most likely to be on the exam?" : "What was decided, and who's doing what?"]
        case .class(let c):
            return ["What did we cover in \(c) this week?", "Quiz me on my last \(c) \(noun)",
                    school ? "What's due next in \(c), and which \(noun)s help?" : "What's still to do, and who's doing it?"]
        case .everything:
            let recent = latest?.class.flatMap { $0.isEmpty || $0 == "Unsorted" ? nil : $0 } ?? classes.first?.name
            return [recent.map { "What did we cover in \($0) this week?" } ?? "What did we cover this week?",
                    "Quiz me on my last \(app.words.lecture)",
                    school ? "What's due next, and which \(app.words.lectures) help?" : "What's still to do, and who's doing it?"]
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lede).textStyle(.lede).foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isTab ? 0 : 12)
                .padding(.bottom, 20)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                if i > 0 { Rule() }
                Button { send(s) } label: {
                    HStack(spacing: 12) {
                        Text(s).textStyle(.nav).foregroundStyle(.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Icon("chevron_right", size: 16).foregroundStyle(.inkSubtle)
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.row)
                .accessibilityHint("Asks it")
            }
        }
    }

    // MARK: the Ask bar

    /// The scopes the bar offers here, as the desktop's: a lecture, its folder by name, all notes; a folder and all
    /// notes; or all notes and each folder.
    private var choices: [AskScope] {
        switch base {
        case .lecture(_, _, let c): [base] + (c.map { [.class($0)] } ?? []) + [.everything]
        case .class: [base, .everything]
        case .everything: [.everything] + classes.map { .class($0.name) }
        }
    }

    private var composer: some View {
        AskBar(placeholder: scope.placeholder(noun: noun), text: $question,
               scope: choices.count > 1 ? scope.label(noun: noun) : nil,
               busy: conversation.busy, onScope: { picking = true }) { send(question) }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                ScopeMenu(choices: choices, chosen: scope, noun: noun) { picked in
                    scope = picked
                    picking = false
                }
                .presentationCompactAdaptation(.popover)
            }
            .onChange(of: question) { old, new in
                // The AI that will answer gets ready once a question's begun, as on the computer.
                if old.isEmpty, !new.isEmpty, !warmed, let api = app.api { warmed = true; Task { await api.warm() } }
            }
            .padding(.horizontal, sizeClass == .regular ? pad : 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: 760 + 2 * pad)
            .frame(maxWidth: .infinity)
    }

    private func send(_ text: String) {
        guard let api = app.api, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let q = text, s = scope, label = scope.label(noun: noun)
        question = ""
        Task { await conversation.ask(q, scope: s, label: label, api: api) }
    }

    private func retry(_ turn: AskTurn) {
        guard let api = app.api else { return }
        let s = scope, label = scope.label(noun: noun)
        Task { await conversation.retry(turn, scope: s, label: label, api: api) }
    }
}

/// The scope's menu over the Ask bar, as the desktop's: each choice by name, a folder with its swatch, a check by the
/// one asked about now.
private struct ScopeMenu: View {
    @Environment(AppModel.self) private var app
    var choices: [AskScope]
    var chosen: AskScope
    var noun: String
    var pick: (AskScope) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GroupLabel("Ask about").padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                ForEach(choices, id: \.self) { c in
                    Button { pick(c) } label: {
                        HStack(spacing: 10) {
                            if case .class(let cls) = c { Swatch(app.hue(of: cls)) }
                            Text(c.label(noun: noun)).textStyle(.nav).fontWeight(c == chosen ? .bold : .medium)
                                .foregroundStyle(.ink).lineLimit(1)
                            Spacer(minLength: 16)
                            if c == chosen { Icon("check", size: 16).foregroundStyle(.ink) }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(MenuRowStyle())
                    .accessibilityAddTraits(c == chosen ? [.isSelected] : [])
                }
            }
            .padding(6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 260, maxHeight: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A menu's row: the wash while it's pressed, the control's corners.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.hover : .clear, in: .rect(cornerRadius: Radius.control))
    }
}

/// One question and its answer: the question on the right, a plain line on the sunken grey (no bubble colour); the
/// answer in ink in the notes' type; who answered (the desktop's byline); then From, the lectures it used, each with
/// its class's swatch and the minute, opening there.
private struct TurnView: View {
    @Environment(AppModel.self) private var app
    var turn: AskTurn
    /// Who's being asked, to say so while waiting ("Asking Claude…").
    var asking: String?
    /// Where the thread is: a class's own Ask doesn't name the class on every question.
    var inScope: AskScope
    var open: (AskTurn.Source, Double?) -> Void
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .trailing, spacing: 6) {
                Text(turn.question).textStyle(.body).foregroundStyle(.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.surfaceSunken, in: .rect(cornerRadius: Radius.panel))
                if case .class(let c)? = turn.asked, inScope != turn.asked {
                    Highlight(c, hue: app.hue(of: c))
                }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You asked: \(turn.question)")

            if turn.answer.isEmpty && turn.state == .asking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.inkSubtle)
                    Text(asking.map { "Asking \($0)…" } ?? "Reading your notes…").textStyle(.meta).foregroundStyle(.inkMuted)
                }
                .padding(.vertical, 4)
            } else if !turn.answer.isEmpty {
                MarkdownText(turn.answer)
            }

            if turn.state == .failed, let p = turn.problem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon("warning", size: 16).foregroundStyle(.inkSubtle)
                    Text(p).textStyle(.body).foregroundStyle(.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Button("Ask again", action: retry).buttonStyle(.textLink)
            }

            if turn.state == .done, let engine = turn.engine, !engine.isEmpty {
                Text(engine).textStyle(.micro).foregroundStyle(.inkSubtle)
                    .accessibilityLabel("Answered by \(engine)")
            }
            if let note = turn.note {
                Text(note).textStyle(.micro).foregroundStyle(.inkSubtle).fixedSize(horizontal: false, vertical: true)
            }

            let sources = turn.sources.filter { $0.id != nil }
            if turn.state == .done, !sources.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    GroupLabel("From").padding(.bottom, 2)
                    ForEach(Array(sources.enumerated()), id: \.offset) { i, s in
                        if i > 0 { Rule() }
                        SourceRow(source: s) { open(s, s.times.first) }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A lecture an answer came from: its class's swatch, its title, "Thu 15 Oct · 3:42". The row opens it at that minute.
private struct SourceRow: View {
    @Environment(AppModel.self) private var app
    var source: AskTurn.Source
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Swatch(app.hue(of: source.class))
                Text(title).textStyle(.nav).foregroundStyle(.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 12)
                Text(meta).textStyle(.meta).foregroundStyle(.inkSubtle).monospacedDigit().lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .combine)
        .accessibilityHint(source.times.isEmpty ? "Opens it" : "Opens it at \(Format.clock(source.times[0]))")
    }

    private var title: String {
        if !source.title.isEmpty { return source.title }
        return Nouns.untitled(folder: source.class, date: source.date)
    }

    /// "Thu 15 Oct · 3:42": the day, then the minute (or the part of the notes) it used.
    private var meta: String {
        let day = Format.parse(source.date).map { Format.date($0) }
        let at = source.times.first.map(Format.clock) ?? source.section
        return [day, at].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Markdown from the AI, in the notes' type: headings, lists and paragraphs as blocks, bold, italics, code and links
/// inline, maths as plain characters. Ink on the page; bullets and numbers in the subtle ink.
struct MarkdownText: View {
    var text: String
    var style: AppText = .body
    init(_ text: String, style: AppText = .body) {
        self.text = text
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { i, block in
                switch block {
                case .heading(let s):
                    inline(s).textStyle(.title).padding(.top, i == 0 ? 0 : 6).accessibilityAddTraits(.isHeader)
                case .bullet(let s, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(.inkSubtle)
                        inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4 + CGFloat(depth) * 18)
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(.inkSubtle).monospacedDigit()
                        inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 2)
                case .paragraph(let s):
                    inline(s).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textStyle(style)
        .foregroundStyle(.ink)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> Text {
        var a = (try? AttributedString(markdown: PlainMath.inline(s), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        // Code in the app's own type on the wash, never a system monospace.
        let code = a.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for r in code {
            a[r].inlinePresentationIntent?.remove(.code)
            a[r].backgroundColor = .hover
        }
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
