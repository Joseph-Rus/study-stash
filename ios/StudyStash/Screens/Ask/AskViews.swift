import SwiftUI

// Ask, as the desktop's ask bar and answer card have it (MacAiAskBar, MacAiAnswer, AiByline, AiChatsMenu): the question
// typed into the Ask bar at the foot of the page ("Ask anything about your notes", its scope "All notes" beside it);
// each answer in ink in the notes' type as it's written, who answered under it, and the lectures it used, each opening
// at its moment. What's happening while there are no words yet is said: "Asking your laptop…", "Reading your notes…".
// The conversation is kept by the library as a chat: Chats lists them (the computer's too), New chat starts another.

/// Where a lecture an answer came from opens: at the moment it drew on, on the Transcript.
func askLectureRoute(_ id: String, at: Double?) -> Route { .lecture(id, at: at) }

/// The Ask tab: answers from your own notes and lectures, about everything or one class.
struct AskTab: View {
    @Environment(AppModel.self) private var app
    @State private var conversation = AskConversation(saveKey: "ask.history", place: .home)
    @State private var scope: AskScope = .everything

    var body: some View {
        NavigationStack(path: app.stack(.ask)) {
            AskThread(conversation: conversation, scope: $scope, base: .everything, isTab: true) { source, at in
                // The lecture on Home's stack, at the minute, on its Transcript.
                if let id = source.id { app.go(askLectureRoute(id, at: at), tab: .home) }
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.large)
            .routes()
        }
    }
}

/// Ask about one lecture or class, from its page's Ask bar. `question` is sent as it opens ("Ask how to start this").
/// Nothing is opened inside it: a lecture an answer came from closes the sheet, then opens at its minute on the page
/// underneath. A lecture's own page can take that itself with `onMoment` (its Transcript at that time). What's asked
/// here is kept as the lecture's (or the class's) chat, as on the computer.
struct AskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: AskConversation
    @State private var scope: AskScope
    /// Where it was opened (a lecture's class found, when it wasn't given).
    @State private var base: AskScope
    private let question: String?
    private let onMoment: ((_ lecture: String, _ at: Double?) -> Void)?

    init(scope: AskScope, question: String? = nil, onMoment: ((_ lecture: String, _ at: Double?) -> Void)? = nil) {
        let known = scope.inClass(scope.lectureClassSaved)
        _scope = State(initialValue: known)
        _base = State(initialValue: known)
        _conversation = State(initialValue: AskConversation(saveKey: nil, place: known.place))
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
                    app.go(askLectureRoute(id, at: at), tab: app.tab)
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
        .task {
            // A lecture's class, when it wasn't given and nothing saved says: the library's.
            guard case let .lecture(id, _, nil) = base, let l = try? await app.api?.lecture(id),
                  let cls = l.class, !cls.isEmpty, cls != "Unsorted" else { return }
            if scope == base { scope = base.inClass(cls) }
            base = base.inClass(cls)
        }
    }
}

/// The page both share: what to ask and the chats before (or the questions asked and their answers), Chats and New
/// chat over it, and the Ask bar at its foot.
private struct AskThread: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    var conversation: AskConversation
    @Binding var scope: AskScope
    /// Where it was opened: the scopes the bar offers follow from it (a lecture: it, its class, all notes).
    var base: AskScope
    /// The Ask tab (its conversation kept on the phone too), not a sheet.
    var isTab: Bool
    var firstQuestion: String?
    /// A lecture an answer came from, tapped: at the moment it drew on.
    var open: (AskTurn.Source, Double?) -> Void

    @State private var question = ""
    @State private var classes: [ClassInfo] = ResponseCache.shared.read("library", as: LibraryOverview.self)?.classes ?? []
    @State private var recent: [LectureSummary] = ResponseCache.shared.read("recent", as: [LectureSummary].self) ?? []
    @State private var chats: [ChatSummary] = []
    /// Chats started here, until the library's list has them.
    @State private var made: [ChatSummary] = []
    @State private var noAI = false
    @State private var picking = false
    @State private var showChats = false
    @State private var warmed = false
    /// The page follows the answer as it's written, unless the student has scrolled up to read.
    @State private var following = true
    @State private var toast: String?

    private var pad: CGFloat { sizeClass == .regular ? Space.pageRegular : Space.pageCompact }

    /// The noun of what's asked about ("lecture", "meeting").
    private var noun: String { app.noun(of: scope.className) }

    /// Over Google Drive the waiting is the laptop's; otherwise the library's.
    private var overDrive: Bool { app.isDrive || DebugLaunch.flag("-ask-drive") }

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
                        TurnView(turn: turn, last: i == conversation.turns.count - 1, inScope: base,
                                 stage: conversation.stage, overDrive: overDrive, open: open,
                                 retry: { retry(turn) }, askAgain: { askAgain(turn) })
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, pad)
                .padding(.bottom, 16)
                .frame(maxWidth: 760 + 2 * pad)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(conversation.turns.isEmpty ? .top : .bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .page()
            .onScrollPhaseChange { _, phase, context in
                // Where the student left it: at the end, the page follows what's written; scrolled up, it stays.
                guard phase == .idle else { return }
                let g = context.geometry
                following = g.contentOffset.y + g.containerSize.height >= g.contentSize.height - 80
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { old, new in
                guard following, new > old, !conversation.turns.isEmpty else { return }
                proxy.scrollTo("end", anchor: .bottom)
            }
            .onChange(of: conversation.turns.count) { _, _ in
                following = true
                withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onChange(of: conversation.chatID) { _, id in
                // Kept by the library just now: listed at once, before its copy (over Google Drive) says so.
                if let id, let title = conversation.title, !made.contains(where: { $0.id == id }) {
                    let p = base.place
                    made.insert(ChatSummary(id: id, title: String(title.prefix(80)), class: p.class ?? "", lecture: p.lecture ?? "",
                                            updated: ISO8601DateFormatter().string(from: .now), kind: "ask", scope: p.scope, turns: 1), at: 0)
                }
                Task { await loadChats() }
            }
            .safeAreaInset(edge: .bottom) {
                if !noAI {
                    composer {
                        guard $0, !conversation.turns.isEmpty else { return }
                        following = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            withAnimation(.smooth) { proxy.scrollTo("end", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.ink)
        .toolbar { chatButtons }
        .sheet(isPresented: $showChats) {
            ChatsSheet(place: base.place, current: conversation.chatID, made: made, recent: recent, overDrive: overDrive,
                       onOpen: { chat in
                           conversation.open(chat)
                           scope = base
                       },
                       onNew: { newChat() },
                       onDeleted: { id in
                           chats.removeAll { $0.id == id }
                           made.removeAll { $0.id == id }
                           if id == conversation.chatID { conversation.startOver() }
                       })
        }
        .toast($toast)
        .task {
            guard let api = app.api else { return }
            // A question it was opened with goes at once ("How should I start this?").
            if let q = firstQuestion, conversation.turns.isEmpty { send(q) }
            #if DEBUG
            if let typing = DebugLaunch.value("-ask-typing"), isTab { question = typing }
            #endif
            async let lib = try? api.library()
            async let latest = try? api.lectures(limit: 12)
            await loadChats()
            if let lib = await lib {
                classes = lib.classes
                noAI = !lib.ask
                app.learn(lib)
            }
            if let l = await latest { recent = l }
            #if DEBUG
            // `-ask "<question>"`: asked on the Ask tab, or in the sheet `-show ask…` opens.
            let sheet = DebugLaunch.value("-show")?.hasPrefix("ask") == true
            if let q = DebugLaunch.value("-ask"), isTab != sheet, conversation.turns.last?.question != q { send(q) }
            // `-ask-scopes`: the scope's menu open; `-ask-chats`: the Chats list, for pictures.
            if DebugLaunch.flag("-ask-scopes"), isTab != sheet { try? await Task.sleep(for: .seconds(1)); picking = true }
            if DebugLaunch.flag("-ask-chats"), isTab != sheet { try? await Task.sleep(for: .seconds(1)); showChats = true }
            // `-ask-open <chat id>`: that kept chat open, as if picked from Chats.
            if let id = DebugLaunch.value("-ask-open"), isTab != sheet, let c = chats.first(where: { $0.id == id }) { openChat(c) }
            #endif
        }
    }

    // MARK: Chats and New chat

    @ToolbarContentBuilder private var chatButtons: some ToolbarContent {
        ToolbarItemGroup(placement: isTab ? .topBarTrailing : .topBarLeading) {
            Button { showChats = true } label: { Image(icon: "forum") }
                .accessibilityLabel("Chats")
                .accessibilityIdentifier("ask.chats")
            Button { newChat() } label: { Image(icon: "add") }
                .accessibilityLabel("New chat")
                .accessibilityIdentifier("ask.new")
                .disabled(conversation.turns.isEmpty)
        }
    }

    private func newChat() {
        withAnimation(.smooth) { conversation.startOver() }
        scope = base
        question = ""
    }

    /// The chats kept where this was opened: all of them on the Ask tab, a class's or a lecture's in its sheet.
    private func loadChats() async {
        guard let api = app.api, let all = try? await api.askChats() else { return }
        made.removeAll { m in all.contains { $0.id == m.id } }
        chats = ChatsSheet.kept(all + made, at: base.place)
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

    /// Questions worth asking, from the student's own classes and lectures: the latest class, the last lecture by its
    /// title, what's due.
    private var suggestions: [String] {
        let school = app.forSchool
        switch scope {
        case .lecture:
            return ["Summarize this \(noun) in five points", "Quiz me on this \(noun)",
                    school ? "What's most likely to be on the exam?" : "What was decided, and who's doing what?"]
        case .class(let c):
            let last = recent.first { $0.class == c && $0.status == "done" && !($0.title ?? "").isEmpty }
            return ["What did we cover in \(c) this week?",
                    last?.title.map { "Quiz me on \($0)" } ?? "Quiz me on my last \(c) \(noun)",
                    school ? "What's due next in \(c), and which \(noun)s help?" : "What's still to do, and who's doing it?"]
        case .everything:
            let filed = recent.filter { ($0.class ?? "").isEmpty == false && $0.class != "Unsorted" }
            let latest = recent.first { $0.status == "done" && !($0.title ?? "").isEmpty }
            let cls = filed.first?.class ?? classes.first?.name
            var out = [cls.map { "What did we cover in \($0) this week?" } ?? "What did we cover this week?",
                       latest?.title.map { "Quiz me on \($0)" } ?? "Quiz me on my last \(app.words.lecture)"]
            if school { out.append("What's due next, and which \(app.words.lectures) help?") }
            if let other = filed.first(where: { $0.class != cls })?.class {
                out.append("Explain the hardest idea from \(other) simply")
            }
            return out
        }
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lede).textStyle(.lede).foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isTab ? 0 : 12)
                .padding(.bottom, 24)
            GroupLabel("Try asking").padding(.bottom, 2)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                if i > 0 { Rule() }
                Button { send(s) } label: {
                    HStack(spacing: 12) {
                        Text(s).textStyle(.nav).foregroundStyle(.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Icon("arrow_upward", size: 16).foregroundStyle(.inkSubtle)
                    }
                    .padding(.vertical, 13)
                }
                .buttonStyle(.row)
                .accessibilityHint("Asks it")
            }
            if !chats.isEmpty {
                HStack(alignment: .lastTextBaseline) {
                    GroupLabel("Recent chats")
                    Spacer()
                    Button("See all") { showChats = true }.buttonStyle(.textLink)
                }
                .padding(.top, 32)
                .padding(.bottom, 2)
                ForEach(Array(chats.prefix(3).enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rule() }
                    ChatRow(chat: c, about: ChatsSheet.whereWords(c, at: base.place, recent: recent)) { openChat(c) }
                }
            }
        }
    }

    private func openChat(_ c: ChatSummary) {
        Task {
            guard let api = app.api else { return }
            do {
                let chat = try await api.chat(c.id)
                withAnimation(.smooth) { conversation.open(chat) }
                scope = base
            } catch {
                toast = (error as? APIError)?.detail ?? "That chat couldn't be opened."
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

    private func composer(onFocus: @escaping (Bool) -> Void) -> some View {
        AskBar(placeholder: scope.placeholder(noun: noun), text: $question,
               scope: choices.count > 1 ? scope.label(noun: noun) : nil,
               busy: conversation.busy, onScope: { picking = true }, onStop: { conversation.stop() },
               focusOnAppear: DebugLaunch.value("-ask-typing") != nil && isTab, onFocus: onFocus) { send(question) }
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
        guard let api = app.api, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !conversation.busy else { return }
        question = ""
        warmed = false
        conversation.send(text, scope: scope, label: scope.label(noun: noun), api: api)
    }

    private func retry(_ turn: AskTurn) {
        guard let api = app.api else { return }
        conversation.retry(turn, scope: scope, label: scope.label(noun: noun), api: api)
    }

    /// The same question again, as a follow-up at the end of the chat.
    private func askAgain(_ turn: AskTurn) {
        guard let api = app.api, !conversation.busy else { return }
        let s = turn.asked ?? scope
        conversation.send(turn.question, scope: s, label: turn.scope ?? s.label(noun: noun), api: api)
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

/// One question and its answer: the question on the right on the sunken grey (no bubble colour); while there are no
/// words yet, what's happening, by a caret; the answer in ink in the notes' type as it's written, a caret at its end;
/// then the lectures it used, each opening at its moment, who answered, Copy and Ask again. A question with no answer
/// says why, with Try again.
private struct TurnView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var still
    var turn: AskTurn
    /// The newest turn: the one being answered, if any.
    var last: Bool
    /// Where the thread is: a class's own Ask doesn't name the class on every question.
    var inScope: AskScope
    var stage: AskStage
    var overDrive: Bool
    var open: (AskTurn.Source, Double?) -> Void
    var retry: () -> Void
    var askAgain: () -> Void

    /// How much of the answer is on screen while it's written: it arrives in pieces (over Google Drive, a sentence
    /// or so at a time) and is put on the page at a steady pace, as the desktop's does.
    @State private var shown = 0
    @State private var pacing = false
    /// No words for a while over Google Drive: said why.
    @State private var slow = false
    @State private var didCopy = false

    private var asking: Bool { turn.state == .asking }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            question

            if asking && turn.answer.isEmpty {
                waiting
            } else if !turn.answer.isEmpty {
                MarkdownText(shownAnswer, style: .lede, caret: asking || pacing)
                    .accessibilityElement(children: .combine)
            }

            if turn.state == .failed, let p = turn.problem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon("warning", size: 16).foregroundStyle(.inkSubtle)
                    Text(p).textStyle(.body).foregroundStyle(.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
                Button("Try again", action: retry)
                    .buttonStyle(.pill(small: true))
                    .accessibilityIdentifier("ask.retry")
            }

            if turn.state == .done && !pacing {
                if let note = turn.note {
                    Text(note).textStyle(.micro).foregroundStyle(.inkSubtle).fixedSize(horizontal: false, vertical: true)
                }
                let sources = turn.sources.filter { $0.id != nil }
                if !sources.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.offset) { _, s in
                            SourceLink(source: s) { open(s, s.times.first) }
                        }
                    }
                }
                footer
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            // Written while it's on screen: paced. Read back (an earlier turn, a chat opened): all at once.
            pacing = asking && !still
            shown = pacing ? 0 : turn.answer.count
        }
        .task(id: RevealStep(count: turn.answer.count, asking: asking)) { await reveal() }
        .task(id: asking && turn.answer.isEmpty ? stage : nil) {
            slow = false
            guard asking, turn.answer.isEmpty else { return }
            // (`-ask-waiting`, for pictures: at once.)
            try? await Task.sleep(for: .seconds(DebugLaunch.flag("-ask-waiting") ? 1 : 6))
            if !Task.isCancelled { slow = true }
        }
        .onChange(of: turn.state) { old, new in
            guard old == .asking, last else { return }
            AccessibilityNotification.Announcement(new == .failed ? (turn.problem ?? "No answer") : turn.stopped == true ? "Stopped" : "Answered").post()
        }
    }

    private struct RevealStep: Hashable { var count: Int; var asking: Bool }

    /// Put more of the answer on the page, a little at a time, catching up with what has arrived (in about a second;
    /// quicker once it's all in).
    private func reveal() async {
        guard pacing else { return }
        while !Task.isCancelled {
            let total = turn.answer.count
            if shown >= total {
                if !asking { pacing = false }
                return
            }
            let pending = total - shown
            shown = min(total, shown + (asking ? max(2, pending / 24) : max(8, pending / 6)))
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private var shownAnswer: String {
        guard pacing else { return turn.answer }
        return MarkdownText.showable(String(turn.answer.prefix(shown)))
    }

    private var question: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(turn.question).textStyle(.lede).foregroundStyle(.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.surfaceSunken, in: .rect(cornerRadius: 16))
            if case .class(let c)? = turn.asked, inScope != turn.asked {
                Highlight(c, hue: app.hue(of: c))
            }
        }
        .padding(.leading, 48)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You asked: \(turn.question)")
    }

    /// No words yet: what's happening, as far as the phone can see.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                WritingCaret()
                Text(stage.words(overDrive: overDrive)).textStyle(.lede).foregroundStyle(.inkMuted)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: stage)
            }
            if slow && overDrive {
                Text("Answers come through your Google Drive, so the first words take a few seconds.")
                    .textStyle(.meta).foregroundStyle(.inkSubtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
        .animation(.smooth, value: slow)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("ask.waiting")
    }

    /// Who answered (or that it was stopped), Copy and Ask again.
    private var footer: some View {
        HStack(spacing: 2) {
            if turn.stopped == true {
                Text("Stopped").textStyle(.micro).foregroundStyle(.inkSubtle)
            } else if let engine = turn.engine, !engine.isEmpty {
                Text(engine).textStyle(.micro).foregroundStyle(.inkSubtle)
                    .accessibilityLabel("Answered by \(engine)")
            }
            Spacer(minLength: 8)
            if !turn.answer.isEmpty {
                Button {
                    UIPasteboard.general.string = MarkdownText.plain(turn.answer)
                    didCopy = true
                    AccessibilityNotification.Announcement("Copied").post()
                    Task { try? await Task.sleep(for: .seconds(2)); didCopy = false }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", icon: didCopy ? "check" : "content_copy")
                }
                .buttonStyle(AnswerActionStyle())
                .accessibilityLabel(didCopy ? "Copied" : "Copy the answer")
            }
            Button(action: askAgain) { Label("Ask again", icon: "refresh") }
                .buttonStyle(AnswerActionStyle())
                .accessibilityIdentifier("ask.again")
        }
        .padding(.top, 2)
    }
}

/// Copy and Ask again under an answer: a small icon and words, muted, washed while pressed.
private struct AnswerActionStyle: ButtonStyle {
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 15
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ActionLabel(size: size))
            .textStyle(.meta)
            .foregroundStyle(configuration.isPressed ? Color.ink : .inkMuted)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(configuration.isPressed ? Color.press : .clear, in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect(cornerRadius: Radius.control))
            .opacity(enabled ? 1 : 0.4)
    }

    private struct ActionLabel: LabelStyle {
        var size: CGFloat
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon.scaleEffect(size / 24).frame(width: size, height: size)
                configuration.title
            }
        }
    }
}

/// A lecture an answer came from, as a small link: its class's swatch, its title and the moments it drew on
/// ("3:40, 21:30"). It opens the lecture at the first.
private struct SourceLink: View {
    @Environment(AppModel.self) private var app
    var source: AskTurn.Source
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Swatch(app.hue(of: source.class), small: true)
                Text(title).textStyle(.meta).foregroundStyle(.ink).lineLimit(1)
                Spacer(minLength: 8)
                if let at {
                    Text(at).textStyle(.meta).foregroundStyle(.inkSubtle).monospacedDigit().lineLimit(1).fixedSize()
                }
                Icon("arrow_outward", size: 14, relativeTo: .footnote).foregroundStyle(.inkSubtle)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(at.map { "\(title), at \($0)" } ?? title)
        .accessibilityIdentifier("ask.source")
        .accessibilityHint(source.times.isEmpty ? "Opens it" : "Opens it at \(Format.clock(source.times[0]))")
    }

    private var title: String {
        if !source.title.isEmpty { return source.title }
        return Nouns.untitled(folder: source.class, date: source.date)
    }

    /// The moments it drew on ("3:40, 21:30"), or the part of the notes ("Key points").
    private var at: String? {
        let times = source.times.prefix(3).map(Format.clock)
        return times.isEmpty ? source.section : times.joined(separator: ", ")
    }
}
